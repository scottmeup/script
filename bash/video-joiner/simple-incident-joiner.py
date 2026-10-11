#!/usr/bin/env python3
# FILE: simple-incident-joiner.py
# PURPOSE: Groups chronologically adjacent compatible video clips into recording incidents and joins every multi-clip incident by FFmpeg stream copy. Optionally writes rotation display metadata without re-encoding.
# INPUTS: simple-incident-joiner.env beside this script unless --config overrides it. SOURCE_DIR and OUTPUT_DIR are paths. INCIDENT_GAP_SECONDS is a nonnegative integer. ROTATION is 0, 90, 180, or 270. OUTPUT_PREFIX is a filename-safe prefix. EXTENSIONS is a comma-separated extension list. CLI options override matching configuration entries.
# OUTPUTS: One MP4 for each compatible incident containing at least two clips, named OUTPUT_PREFIX-YYYY-MM-DD-HH-MM-SS.mp4; simple-incident-joiner.trace containing untouched native Python trace output; standard-error status lines. Source files are only read and are never deleted or modified.
# FUNCTIONS: parse_env loads strict configuration. probe obtains timing and stream compatibility data with ffprobe. group_incidents groups by clip timing and exact stream signature. concat_list_line escapes paths for FFmpeg's concat demuxer. join_incident joins with -c copy and optionally writes rotation metadata. application coordinates discovery, grouping, collision checks, joining, and duration validation. traced_child re-executes under Python's standard trace module without trace post-processing.
# GLOBALS: TRACE_ENV prevents trace recursion. VIDEO_FIELDS and AUDIO_FIELDS define the compatibility signature. ISO_FORMATS define supported creation_time representations.
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

TRACE_ENV = "SIMPLE_INCIDENT_JOINER_TRACED"
VIDEO_FIELDS = ("codec_name", "profile", "width", "height", "pix_fmt", "r_frame_rate", "time_base")
AUDIO_FIELDS = ("codec_name", "profile", "sample_rate", "channels", "channel_layout", "time_base")
ISO_FORMATS = ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d %H:%M:%S")


def parse_env(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise ValueError(f"Configuration file is missing: {path}")
    values = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        if "=" not in raw:
            raise ValueError(f"Malformed configuration line {number}")
        key, value = raw.split("=", 1)
        if key in values:
            raise ValueError(f"Duplicate configuration key: {key}")
        values[key] = value
    required = {"SOURCE_DIR", "OUTPUT_DIR", "INCIDENT_GAP_SECONDS", "ROTATION", "OUTPUT_PREFIX", "EXTENSIONS"}
    if set(values) != required:
        raise ValueError(f"Configuration keys invalid; missing={sorted(required-values.keys())} unknown={sorted(values.keys()-required)}")
    return values


def executable(name: str) -> str:
    value = shutil.which(name)
    if not value:
        raise ValueError(f"Required executable is unavailable through PATH: {name}")
    return value


def creation_timestamp(metadata: dict, path: Path) -> float:
    value = metadata.get("format", {}).get("tags", {}).get("creation_time")
    if not value:
        for stream in metadata.get("streams", []):
            value = stream.get("tags", {}).get("creation_time")
            if value:
                break
    if value:
        for pattern in ISO_FORMATS:
            try:
                parsed = dt.datetime.strptime(value, pattern).replace(tzinfo=dt.timezone.utc)
                return parsed.timestamp()
            except ValueError:
                pass
    return path.stat().st_mtime


def stream_signature(metadata: dict) -> tuple:
    streams = metadata.get("streams", [])
    video = next((stream for stream in streams if stream.get("codec_type") == "video"), None)
    audio = next((stream for stream in streams if stream.get("codec_type") == "audio"), None)
    if video is None:
        raise ValueError("No video stream")
    return (
        tuple(video.get(field) for field in VIDEO_FIELDS),
        tuple(audio.get(field) for field in AUDIO_FIELDS) if audio else None,
        tuple(stream.get("codec_type") for stream in streams),
    )


def probe(ffprobe: str, path: Path) -> dict:
    command = [ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)]
    result = subprocess.run(command, check=True, capture_output=True, text=True, shell=False)
    metadata = json.loads(result.stdout)
    duration = float(metadata.get("format", {}).get("duration") or 0)
    if duration <= 0:
        raise ValueError("Duration is missing or nonpositive")
    start = creation_timestamp(metadata, path)
    return {"path": path, "start": start, "duration": duration, "end": start + duration, "signature": stream_signature(metadata)}


def group_incidents(clips: list[dict], gap: int) -> list[list[dict]]:
    groups = []
    for clip in sorted(clips, key=lambda item: (item["start"], item["path"].name.casefold())):
        if not groups:
            groups.append([clip])
            continue
        previous = groups[-1][-1]
        if clip["signature"] == previous["signature"] and clip["start"] <= previous["end"] + gap:
            groups[-1].append(clip)
        else:
            groups.append([clip])
    return groups


def concat_list_line(path: Path) -> str:
    escaped = str(path.resolve()).replace("'", "'\\''")
    return f"file '{escaped}'\n"


def output_name(prefix: str, start: float) -> str:
    stamp = dt.datetime.fromtimestamp(start, dt.timezone.utc).strftime("%Y-%m-%d-%H-%M-%S")
    return f"{prefix}-{stamp}.mp4"


def join_incident(ffmpeg: str, ffprobe: str, clips: list[dict], output: Path, rotation: int) -> None:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".txt", dir=output.parent) as stream:
        list_path = Path(stream.name)
        for clip in clips:
            stream.write(concat_list_line(clip["path"]))
    temporary = output.with_name(f".{output.stem}.partial{output.suffix}")
    try:
        command = [ffmpeg, "-v", "error", "-f", "concat", "-safe", "0", "-i", str(list_path), "-map", "0", "-c", "copy"]
        if rotation:
            command += ["-metadata:s:v:0", f"rotate={rotation}"]
        command += ["-movflags", "+faststart", "-y", str(temporary)]
        subprocess.run(command, check=True, shell=False)
        expected = sum(clip["duration"] for clip in clips)
        actual_data = json.loads(subprocess.run([ffprobe, "-v", "error", "-show_entries", "format=duration", "-of", "json", str(temporary)], check=True, capture_output=True, text=True, shell=False).stdout)
        actual = float(actual_data["format"]["duration"])
        tolerance = max(1.0, expected * 0.02)
        if abs(actual - expected) > tolerance:
            raise ValueError(f"Output duration {actual:.3f}s differs from expected {expected:.3f}s")
        os.replace(temporary, output)
    finally:
        list_path.unlink(missing_ok=True)
        temporary.unlink(missing_ok=True)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser()
    value.add_argument("--config")
    value.add_argument("--source-dir")
    value.add_argument("--output-dir")
    value.add_argument("--gap-seconds", type=int)
    value.add_argument("--rotation", type=int)
    value.add_argument("--prefix")
    return value


def application(args) -> int:
    script = Path(__file__).resolve()
    config_path = Path(args.config).expanduser().resolve() if args.config else script.with_name("simple-incident-joiner.env")
    config = parse_env(config_path)
    source = Path(args.source_dir or config["SOURCE_DIR"]).expanduser().resolve()
    output = Path(args.output_dir or config["OUTPUT_DIR"]).expanduser().resolve()
    gap = args.gap_seconds if args.gap_seconds is not None else int(config["INCIDENT_GAP_SECONDS"])
    rotation = args.rotation if args.rotation is not None else int(config["ROTATION"])
    prefix = args.prefix or config["OUTPUT_PREFIX"]
    if not source.is_dir():
        raise ValueError(f"SOURCE_DIR is unavailable: {source}")
    if gap < 0 or rotation not in {0, 90, 180, 270}:
        raise ValueError("Gap must be nonnegative and rotation must be 0, 90, 180, or 270")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", prefix):
        raise ValueError("OUTPUT_PREFIX may contain only letters, digits, dot, underscore, and hyphen")
    extensions = {item.strip().casefold() for item in config["EXTENSIONS"].split(",") if item.strip()}
    output.mkdir(parents=True, exist_ok=True)
    ffmpeg = executable("ffmpeg")
    ffprobe = executable("ffprobe")
    candidates = [path for path in source.iterdir() if path.is_file() and path.suffix.casefold() in extensions and path.parent != output]
    if not candidates:
        raise ValueError("No supported source videos found")
    clips = []
    for path in candidates:
        try:
            clips.append(probe(ffprobe, path))
        except Exception as exc:
            print(f"SKIP={path} REASON={exc}", file=sys.stderr)
    groups = [group for group in group_incidents(clips, gap) if len(group) >= 2]
    if not groups:
        raise ValueError("No compatible multi-clip recording incidents found")
    for group in groups:
        target = output / output_name(prefix, group[0]["start"])
        if target.exists():
            raise ValueError(f"Output already exists: {target}")
        join_incident(ffmpeg, ffprobe, group, target, rotation)
        print(f"OUTPUT={target}", file=sys.stderr)
        for clip in group:
            print(f"INPUT={clip['path']}", file=sys.stderr)
    return 0


def traced_child(arguments: list[str], trace_path: Path) -> int:
    environment = os.environ.copy()
    environment[TRACE_ENV] = "1"
    command = [sys.executable, "-m", "trace", "--trace", str(Path(__file__).resolve()), *arguments]
    with trace_path.open("a", encoding="utf-8") as stream:
        return subprocess.run(command, stdout=stream, stderr=None, env=environment, shell=False).returncode


def main() -> int:
    arguments = sys.argv[1:]
    trace_path = Path(__file__).resolve().with_name("simple-incident-joiner.trace")
    if os.environ.get(TRACE_ENV) != "1":
        return traced_child(arguments, trace_path)
    try:
        return application(parser().parse_args(arguments))
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
