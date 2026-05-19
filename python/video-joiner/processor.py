#!/usr/bin/env python3

import os
import re
import yaml
import argparse
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

def log(level, msg):
    print(f"[{level}] {msg}")

def load_config(path):
    try:
        with open(path) as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        raise RuntimeError(f"Config file not found: {path}")
    except Exception as e:
        raise RuntimeError(f"Failed to load config: {e}")


def build_regex(fmt):
    try:
        tokens = {
            "YYYY": r"(?P<year>\d{4})",
            "MM": r"(?P<month>\d{2})",
            "DD": r"(?P<day>\d{2})",
            "HH": r"(?P<hour>\d{2})",
            "mm": r"(?P<minute>\d{2})",
            "SS": r"(?P<second>\d{2})",
            "nnn": r"(?P<seq>\d+)"
        }
        for t, r in tokens.items():
            fmt = fmt.replace(t, r)
        return re.compile(fmt)
    except re.error as e:
        raise RuntimeError(f"Invalid datetime format regex: {e}")


def parse_file(path, regex, config):
    try:
        m = regex.search(path.name)
        if not m:
            raise ValueError("pattern not matched")

        d = m.groupdict()
        ts = datetime(
            int(d['year']), int(d['month']), int(d['day']),
            int(d['hour']), int(d['minute']), int(d['second'])
        )
        seq = int(d.get("seq", 0))
        return ts, seq

    except Exception as e:
        mode = config.get("on_parse_failure", "warn")

        if "skip" in mode:
            log("WARN", f"Skipping file due to parse failure: {path}")
            return None
        elif "warn" in mode:
            log("WARN", f"Parse issue: {path} ({e})")
            return None
        elif "error" in mode:
            raise RuntimeError(f"Parse failure: {path} ({e})")

        return None

def duration(file):
    try:
        r = subprocess.run(
            ["ffprobe", "-v", "error",
             "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1",
             file],
            capture_output=True, text=True
        )
        if r.returncode != 0:
            raise RuntimeError(r.stderr)

        return float(r.stdout.strip())

    except Exception as e:
        log("ERROR", f"Failed to get duration for {file}: {e}")
        return 0.0

def apply_sync(name, ts, config):
    try:
        sync = config.get("sync", {})
        if sync.get("mode") != "sync_points":
            return ts

        for sp in sync.get("sync_points", []):
            if sp["target_camera"] == name:
                ref = datetime.fromisoformat(sp["reference_time"])
                tgt = datetime.fromisoformat(sp["target_time"])

                if ts >= tgt:
                    return ts + (ref - tgt)

        return ts

    except Exception as e:
        log("ERROR", f"Sync application failed: {e}")
        return ts


def apply_drift(ts, base, drift):
    try:
        rate = drift / 3600.0
        elapsed = (ts - base).total_seconds()
        return ts + timedelta(seconds=elapsed * rate)
    except Exception as e:
        log("ERROR", f"Drift failed: {e}")
        return ts

def build_timeline(files, src, config):
    timeline = []

    try:
        offset = src.get("offset_seconds", 0)
        drift = src.get("drift_seconds_per_hour", 0)

        for f in files:
            ts = f["ts"]

            ts += timedelta(seconds=offset)
            ts = apply_sync(src["name"], ts, config)
            ts = apply_drift(ts, ts, drift)

            dur = f["duration"]

            timeline.append({
                "start": ts,
                "end": ts + timedelta(seconds=dur),
                "file": f["file"]
            })

    except Exception as e:
        raise RuntimeError(f"Timeline build failed: {e}")

    return timeline

def compute_session(timelines):
    try:
        start = min(seg["start"] for t in timelines for seg in t)
        end   = max(seg["end"]   for t in timelines for seg in t)
        return start, end
    except ValueError:
        raise RuntimeError("No valid timeline data found")


def align_timeline(timeline, start, end):
    try:
        segments = []
        current = start

        for seg in sorted(timeline, key=lambda x: x["start"]):

            if seg["start"] > current:
                segments.append({
                    "type": "black",
                    "duration": (seg["start"] - current).total_seconds()
                })

            segments.append({
                "type": "video",
                "duration": (seg["end"] - seg["start"]).total_seconds(),
                "file": seg["file"]
            })

            current = seg["end"]

        if current < end:
            segments.append({
                "type": "black",
                "duration": (end - current).total_seconds()
            })

        return segments

    except Exception as e:
        raise RuntimeError(f"Alignment failed: {e}")

def run_ffmpeg(cmd, dry):
    log("INFO", "FFMPEG command:")
    print(" ".join(cmd))

    if dry:
        return

    try:
        r = subprocess.run(cmd)
        if r.returncode != 0:
            raise RuntimeError("ffmpeg failed")

    except Exception as e:
        log("ERROR", f"FFmpeg execution failed: {e}")

def main():
    try:
        parser = argparse.ArgumentParser()
        parser.add_argument("--config", required=True)
        parser.add_argument("--dry-run", action="store_true")
        args = parser.parse_args()

        config = load_config(args.config)

        dry = args.dry_run or config.get("dry_run", False)

        timelines = []

        for src in config["sources"]:
            try:
                regex = build_regex(src["datetime_format"])
                path = Path(src["path"])

                if not path.exists():
                    raise RuntimeError(f"Source path does not exist: {path}")

                files = []

                for f in path.glob("*"):
                    parsed = parse_file(f, regex, config)
                    if not parsed:
                        continue

                    ts, seq = parsed

                    files.append({
                        "file": str(f),
                        "ts": ts,
                        "seq": seq,
                        "duration": duration(str(f))
                    })

                if not files:
                    log("WARN", f"No valid files found in source {src['name']}")
                    continue

                timeline = build_timeline(files, src, config)
                timelines.append(timeline)

            except Exception as e:
                log("ERROR", f"Source processing failed ({src['name']}): {e}")

        if not timelines:
            raise RuntimeError("No valid timelines produced")

        session_start, session_end = compute_session(timelines)

        aligned = []
        for t in timelines:
            aligned.append(align_timeline(t, session_start, session_end))

        inputs = []
        filters = []

        idx = 0
        concat_tags = []

        for i, segs in enumerate(aligned):
            parts = []
            for seg in segs:
                try:
                    if seg["type"] == "video":
                        inputs += ["-i", seg["file"]]
                    else:
                        inputs += ["-f", "lavfi", "-t", str(seg["duration"]),
                                   "-i", "color=c=black:s=1280x720"]

                    parts.append(f"[{idx}:v]")
                    idx += 1

                except Exception as e:
                    log("ERROR", f"Segment build failed: {e}")

            concat = "".join(parts) + f"concat=n={len(parts)}:v=1:a=0[out{i}]"
            filters.append(concat)
            concat_tags.append(f"[out{i}]")

        layout = config["output_mode"]["stack"]["layout"]

        stack = f"xstack=inputs={len(concat_tags)}"
        filters.append("".join(concat_tags) + stack + "[v]")

        output = os.path.join(config["output_dir"], "session.mp4")

        cmd = ["ffmpeg", "-y"] + inputs + [
            "-filter_complex", ";".join(filters),
            "-map", "[v]",
            "-c:v", "libx264",
            output
        ]

        run_ffmpeg(cmd, dry)

        log("INFO", "Processing complete")

    except Exception as e:
        log("FATAL", str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()