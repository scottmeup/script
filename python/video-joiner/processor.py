#!/usr/bin/env python3

import os
import re
import sys
import yaml
import math
import json
import argparse
import subprocess
import statistics
from datetime import datetime, timedelta
from pathlib import Path

def log(level, msg):
    print(f"[{level}] {msg}")

def resolve_default_config_path():
    script_dir = Path(__file__).resolve().parent
    candidate = script_dir / "config.yaml"
    return candidate if candidate.exists() else None

def load_config(path):
    p = Path(path)
    if not p.exists():
        raise RuntimeError(f"Config file does not exist: {path}")
    if not p.is_file():
        raise RuntimeError(f"Config path is not a file: {path}")
    if not os.access(str(p), os.R_OK):
        raise RuntimeError(f"Config file not readable: {path}")
    with open(p, "r") as f:
        return yaml.safe_load(f)

def build_regex(fmt):
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

def parse_file(path, regex):
    m = regex.search(path.name)
    if not m:
        return None
    d = m.groupdict()
    ts = datetime(
        int(d["year"]), int(d["month"]), int(d["day"]),
        int(d["hour"]), int(d["minute"]), int(d["second"])
    )
    seq = int(d.get("seq", 0))
    return ts, seq

def ffprobe_duration(file):
    try:
        r = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", file],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        if r.returncode != 0:
            return None
        s = (r.stdout or "").strip()
        return float(s) if s else None
    except:
        return None

def apply_sync(src_name, ts, config):
    sync = config.get("sync", {})
    if sync.get("mode") != "sync_points":
        return ts
    offset = 0.0
    for sp in sync.get("sync_points", []):
        if sp.get("target_camera") == src_name:
            ref = datetime.fromisoformat(sp["reference_time"])
            tgt = datetime.fromisoformat(sp["target_time"])
            if ts >= tgt:
                offset = (ref - tgt).total_seconds()
    return ts + timedelta(seconds=offset)

def apply_drift(ts, segment_start, drift_seconds_per_hour):
    rate = float(drift_seconds_per_hour) / 3600.0
    elapsed = (ts - segment_start).total_seconds()
    return ts + timedelta(seconds=elapsed * rate)

def group_by_adjacency(files, max_gap_seconds):
    if not files:
        return []
    files.sort(key=lambda x: x["ts"])
    groups = []
    cur = [files[0]]
    for prev, nxt in zip(files, files[1:]):
        if (nxt["ts"] - prev["ts"]).total_seconds() <= max_gap_seconds:
            cur.append(nxt)
        else:
            groups.append(cur)
            cur = [nxt]
    groups.append(cur)
    return groups

def align_timeline(timeline, start, end):
    segments = []
    current = start
    for seg in sorted(timeline, key=lambda x: x["start"]):
        if seg["start"] > current:
            segments.append({"type": "black", "duration": (seg["start"] - current).total_seconds()})
        segments.append({"type": "video", "duration": (seg["end"] - seg["start"]).total_seconds(), "file": seg["file"]})
        current = seg["end"]
    if current < end:
        segments.append({"type": "black", "duration": (end - current).total_seconds()})
    return segments

def build_stack_ffmpeg(segments_per_cam, output_path, layout, resolution):
    inputs = []
    filters = []
    idx = 0
    outs = []

    for cam_i, segs in enumerate(segments_per_cam):
        parts = []
        for seg in segs:
            if seg["type"] == "video":
                inputs += ["-i", seg["file"]]
            else:
                inputs += ["-f", "lavfi", "-t", str(seg["duration"]), "-i", f"color=c=black:s={resolution}"]
            parts.append(f"[{idx}:v]")
            idx += 1
        filters.append("".join(parts) + f"concat=n={len(parts)}:v=1:a=0[out{cam_i}]")
        outs.append(f"[out{cam_i}]")

    if layout == "horizontal":
        stack = "xstack=layout=0_0|w0_0"
    elif layout == "vertical":
        stack = "xstack=layout=0_0|0_h0"
    else:
        stack = f"xstack=inputs={len(outs)}"

    filters.append("".join(outs) + stack + "[v]")

    cmd = ["ffmpeg", "-y"] + inputs + [
        "-filter_complex", ";".join(filters),
        "-map", "[v]",
        "-c:v", "libx264",
        str(output_path)
    ]
    return cmd

def run_ffmpeg(cmd, dry_run):
    print(" ".join(cmd))
    if dry_run:
        return 0
    r = subprocess.run(cmd)
    return r.returncode

def parse_args():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--config", default=None)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--source", action="append", default=[])
    ap.add_argument("--output-dir", default=None)
    ap.add_argument("--rotate", type=int, default=None)
    ap.add_argument("--max-gap-seconds", type=int, default=None)
    return ap.parse_args()

def main():
    try:
        if len(sys.argv) == 1:
            default_cfg = resolve_default_config_path()
            if not default_cfg:
                raise RuntimeError("No arguments provided and config.yaml not found next to processor.py")
            cfg = load_config(str(default_cfg))
            config_path = str(default_cfg)
            args = None
        else:
            args = parse_args()
            if args.config:
                cfg = load_config(args.config)
                config_path = args.config
            else:
                cfg = {"sources": []}
                config_path = None

        dry_run = False
        if args and args.dry_run:
            dry_run = True
        elif cfg.get("dry_run", False):
            dry_run = True

        if args and args.output_dir:
            cfg["output_dir"] = args.output_dir

        if "output_dir" not in cfg or not cfg["output_dir"]:
            raise RuntimeError("output_dir must be set via config or CLI")

        Path(cfg["output_dir"]).mkdir(parents=True, exist_ok=True)

        sources = []
        if cfg.get("sources"):
            sources = cfg["sources"]

        if args and args.source:
            sources = [{"name": f"src{i+1}", "path": p, "datetime_format": "YYYY_MMDD_HHMMSS_nnn", "offset_seconds": 0.0, "drift_seconds_per_hour": 0.0} for i, p in enumerate(args.source)]

        if not sources:
            raise RuntimeError("No sources configured (config sources[] or CLI --source)")

        grouping_cfg = cfg.get("grouping", {})
        max_gap = grouping_cfg.get("max_gap_seconds", 600)
        if args and args.max_gap_seconds is not None:
            max_gap = args.max_gap_seconds

        output_mode = cfg.get("output_mode", {"type": "none"})
        mode_type = output_mode.get("type", "none")

        normalize = cfg.get("normalize_inputs", {})
        resolution = normalize.get("resolution_value", "1280x720")

        all_timelines = []

        for src in sources:
            name = src.get("name", "source")
            base = Path(src["path"])
            fmt = src.get("datetime_format")
            if not fmt:
                raise RuntimeError(f"datetime_format missing for source {name}")
            rx = build_regex(fmt)

            files = []
            for f in base.glob("*"):
                if not f.is_file():
                    continue
                parsed = parse_file(f, rx)
                if not parsed:
                    continue
                ts, seq = parsed
                dur = ffprobe_duration(str(f))
                if dur is None:
                    dur = 0.0
                files.append({
                    "file": str(f),
                    "ts_raw": ts,
                    "seq": seq,
                    "dur": float(dur)
                })

            if not files:
                continue

            offset_seconds = float(src.get("offset_seconds", 0.0))
            drift_sph = float(src.get("drift_seconds_per_hour", 0.0))

            timeline = []
            for item in files:
                ts = item["ts_raw"] + timedelta(seconds=offset_seconds)
                ts = apply_sync(name, ts, cfg)
                ts = apply_drift(ts, ts, drift_sph)
                timeline.append({
                    "start": ts,
                    "end": ts + timedelta(seconds=item["dur"]),
                    "file": item["file"],
                    "seq": item["seq"]
                })

            all_timelines.append(timeline)

        if not all_timelines:
            raise RuntimeError("No timelines produced from sources")

        session_start = min(seg["start"] for t in all_timelines for seg in t)
        session_end = max(seg["end"] for t in all_timelines for seg in t)

        if mode_type == "stack":
            stack_cfg = output_mode.get("stack", {})
            layout = stack_cfg.get("layout", "horizontal")
            aligned = [align_timeline(t, session_start, session_end) for t in all_timelines]
            output_path = Path(cfg["output_dir"]) / "session_stacked.mp4"
            cmd = build_stack_ffmpeg(aligned, output_path, layout, resolution)
            rc = run_ffmpeg(cmd, dry_run)
            if rc != 0:
                raise RuntimeError(f"ffmpeg failed with code {rc}")
        else:
            raise RuntimeError("Only output_mode.type=stack is implemented in this processor variant")

        log("INFO", "Done")

    except Exception as e:
        log("FATAL", str(e))
        sys.exit(1)

if __name__ == "__main__":
    main()