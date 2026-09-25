#!/usr/bin/env python3

import argparse
import json
import math
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

import yaml


def log(level, message):
    print(f"[{level}] {message}")


def resolve_default_config_path():
    candidate = Path(__file__).resolve().parent / "config.yaml"
    return candidate if candidate.is_file() else None


def load_config(path):
    p = Path(path)
    if not p.is_file():
        raise RuntimeError(f"Config file does not exist: {p}")
    if not os.access(p, os.R_OK):
        raise RuntimeError(f"Config file is not readable: {p}")
    with p.open("r", encoding="utf-8") as handle:
        loaded = yaml.safe_load(handle)
    if not isinstance(loaded, dict):
        raise RuntimeError("Configuration root must be a YAML mapping")
    return loaded


def find_executable(name):
    path = shutil.which(name)
    if not path:
        raise RuntimeError(f"Required executable not found in PATH: {name}")
    if not os.access(path, os.X_OK):
        raise RuntimeError(f"Executable is not usable: {path}")
    return path


def build_regex(fmt):
    fixed = {
        "YYYY": r"(?P<year>\d{4})",
        "DD": r"(?P<day>\d{2})",
        "HH": r"(?P<hour>\d{2})",
        "mm": r"(?P<minute>\d{2})",
        "SS": r"(?P<second>\d{2})",
        "nnn": r"(?P<seq>\d+)"
    }
    ordered = ["YYYY", "nnn", "MM", "DD", "HH", "mm", "SS"]
    parts = []
    index = 0
    uppercase_mm_count = 0
    while index < len(fmt):
        token = next((value for value in ordered if fmt.startswith(value, index)), None)
        if token == "MM":
            uppercase_mm_count += 1
            if uppercase_mm_count == 1:
                parts.append(r"(?P<month>\d{2})")
            else:
                parts.append(r"(?P<minute>\d{2})")
            index += 2
        elif token:
            parts.append(fixed[token])
            index += len(token)
        else:
            parts.append(re.escape(fmt[index]))
            index += 1
    return re.compile("".join(parts))


def parse_filename(path, regex):
    match = regex.search(path.stem)
    if not match:
        return None
    values = match.groupdict()
    timestamp = datetime(
        int(values["year"]),
        int(values["month"]),
        int(values["day"]),
        int(values["hour"]),
        int(values["minute"]),
        int(values["second"])
    )
    sequence = int(values["seq"]) if values.get("seq") is not None else None
    return timestamp, sequence


def run_capture(command):
    return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def probe_media(ffprobe_path, file_path):
    result = run_capture([
        ffprobe_path,
        "-v", "error",
        "-show_streams",
        "-show_format",
        "-of", "json",
        str(file_path)
    ])
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed for {file_path}: {result.stderr.strip()}")
    try:
        metadata = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid ffprobe JSON for {file_path}: {exc}") from exc
    video = next((s for s in metadata.get("streams", []) if s.get("codec_type") == "video"), None)
    audio = next((s for s in metadata.get("streams", []) if s.get("codec_type") == "audio"), None)
    if not video:
        raise RuntimeError(f"No video stream found: {file_path}")
    duration_value = metadata.get("format", {}).get("duration")
    if duration_value is None:
        duration_value = video.get("duration")
    if duration_value is None:
        raise RuntimeError(f"No usable duration found: {file_path}")
    duration = float(duration_value)
    if not math.isfinite(duration) or duration <= 0:
        raise RuntimeError(f"Invalid duration for {file_path}: {duration}")
    return {
        "duration": duration,
        "video": video,
        "audio": audio,
        "format_name": metadata.get("format", {}).get("format_name"),
        "container_suffix": Path(file_path).suffix.lower().lstrip(".")
    }


def rational_to_float(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value)
    if "/" in text:
        numerator, denominator = text.split("/", 1)
        denominator_value = float(denominator)
        return float(numerator) / denominator_value if denominator_value else None
    return float(text)


def stream_signature(probe):
    video = probe["video"]
    audio = probe["audio"]
    return {
        "video_codec": video.get("codec_name"),
        "width": video.get("width"),
        "height": video.get("height"),
        "pixel_format": video.get("pix_fmt"),
        "fps": rational_to_float(video.get("avg_frame_rate")) or rational_to_float(video.get("r_frame_rate")),
        "audio_codec": audio.get("codec_name") if audio else None,
        "sample_rate": int(audio["sample_rate"]) if audio and audio.get("sample_rate") else None,
        "channels": audio.get("channels") if audio else None,
        "container": probe.get("container_suffix")
    }


def get_filesystem_time(path, field):
    stat = path.stat()
    if field == "mtime":
        return datetime.fromtimestamp(stat.st_mtime)
    return datetime.fromtimestamp(stat.st_ctime)


def group_adjacency(items, maximum_seconds, key):
    if not items:
        return []
    ordered = sorted(items, key=key)
    groups = [[ordered[0]]]
    for item in ordered[1:]:
        difference = (key(item) - key(groups[-1][-1])).total_seconds()
        if difference <= maximum_seconds:
            groups[-1].append(item)
        else:
            groups.append([item])
    return groups


def order_import_event(files):
    filesystem_order = sorted(files, key=lambda item: (item["filesystem_time"], item["path"].name))
    sequences = [item["sequence"] for item in filesystem_order]
    sequence_usable = all(value is not None for value in sequences)
    sequence_usable = sequence_usable and len(sequences) == len(set(sequences))
    if sequence_usable:
        return sorted(files, key=lambda item: (item["sequence"], item["filesystem_time"], item["path"].name)), "sequence"
    return sorted(files, key=lambda item: (item["filename_time"], item["path"].name)), "timestamp"


def create_sequence_epochs(import_events, minimum_value):
    epochs = []
    current = []
    previous_sequence = None
    for event in import_events:
        ordered, method = order_import_event(event)
        for item in ordered:
            sequence = item["sequence"]
            reset = previous_sequence is not None and sequence is not None and sequence <= minimum_value and sequence <= previous_sequence
            if reset and current:
                epochs.append(current)
                current = []
            item["ordering_method"] = method
            current.append(item)
            if sequence is not None:
                previous_sequence = sequence
    if current:
        epochs.append(current)
    return epochs


def split_sessions_by_filename_time(ordered_files, maximum_seconds):
    if not ordered_files:
        return []
    sessions = [[ordered_files[0]]]
    for item in ordered_files[1:]:
        previous = sessions[-1][-1]
        difference = abs((item["filename_time"] - previous["filename_time"]).total_seconds())
        item["adjacent_filename_difference_seconds"] = difference
        if difference <= maximum_seconds:
            sessions[-1].append(item)
        else:
            sessions.append([item])
    return sessions


def applicable_sync_offset(source_name, raw_time, config):
    sync = config.get("sync", {})
    if sync.get("mode") != "sync_points":
        return 0.0, None
    applicable = []
    for point in sync.get("sync_points", []):
        if point.get("target_camera") != source_name:
            continue
        target_time = datetime.fromisoformat(point["target_time"])
        if raw_time >= target_time:
            reference_time = datetime.fromisoformat(point["reference_time"])
            applicable.append((target_time, (reference_time - target_time).total_seconds()))
    if not applicable:
        return 0.0, None
    target_time, offset = max(applicable, key=lambda pair: pair[0])
    return offset, target_time


def correct_time(source_name, raw_time, source_config, config, drift_epoch):
    manual_offset = float(source_config.get("offset_seconds", 0.0))
    sync_offset, sync_epoch = applicable_sync_offset(source_name, raw_time, config)
    base = raw_time + timedelta(seconds=manual_offset + sync_offset)
    epoch = sync_epoch + timedelta(seconds=manual_offset + sync_offset) if sync_epoch else drift_epoch
    drift = float(source_config.get("drift_seconds_per_hour", 0.0))
    elapsed = (base - epoch).total_seconds() if epoch else 0.0
    return base + timedelta(seconds=elapsed * drift / 3600.0)


def validate_continuity(session, grouping_config, warnings):
    continuity = grouping_config.get("continuity_check", {})
    if not continuity.get("enabled", True):
        return
    tolerance = float(continuity.get("tolerance_seconds", 3.0))
    overlap_config = grouping_config.get("same_source_overlap", {})
    overlap_tolerance = float(overlap_config.get("tolerance_seconds", tolerance))
    overlap_action = overlap_config.get("action", "warn")
    for current, following in zip(session, session[1:]):
        expected = current["filename_time"] + timedelta(seconds=current["probe"]["duration"])
        error = (following["filename_time"] - expected).total_seconds()
        following["expected_start"] = expected
        following["continuity_error_seconds"] = error
        following["continuity_classification"] = "continuous" if abs(error) <= tolerance else "same_session_gap"
        if error < -overlap_tolerance:
            message = f"Same-source overlap detected: {current['path'].name} -> {following['path'].name}, {error:.3f}s"
            if overlap_action.endswith("error") or overlap_action == "error":
                raise RuntimeError(message)
            warnings.append(message)


def build_source_runtime(source_config, config, ffprobe_path):
    name = source_config.get("name")
    source_path = Path(source_config.get("path", ""))
    if not name or not source_path:
        raise RuntimeError("Every source requires name and path")
    if not source_path.is_dir():
        raise RuntimeError(f"Source directory does not exist: {source_path}")
    if not os.access(source_path, os.R_OK | os.X_OK):
        raise RuntimeError(f"Source directory is not readable: {source_path}")
    filename_format = source_config.get("datetime_format")
    if not filename_format:
        raise RuntimeError(f"datetime_format missing for source {name}")
    regex = build_regex(filename_format)
    extensions = {str(value).lower().lstrip(".") for value in source_config.get("extensions", [])}
    fs_field = config.get("filesystem_time", {}).get("field", "ctime")
    files = []
    warnings = []
    for path in sorted(source_path.iterdir()):
        if not path.is_file():
            continue
        if extensions and path.suffix.lower().lstrip(".") not in extensions:
            continue
        try:
            parsed = parse_filename(path, regex)
        except Exception as exc:
            warnings.append(f"Filename parse error for {path.name}: {exc}")
            continue
        if not parsed:
            continue
        filename_time, sequence = parsed
        files.append({
            "path": path,
            "filename_time": filename_time,
            "sequence": sequence,
            "filesystem_time": get_filesystem_time(path, fs_field)
        })
    import_gap = float(config.get("import_event", {}).get("max_gap_seconds", 30))
    import_events = group_adjacency(files, import_gap, key=lambda item: item["filesystem_time"])
    sequence_config = config.get("sequence", {})
    epochs = create_sequence_epochs(import_events, int(sequence_config.get("minimum_value", 1)))
    max_timestamp_difference = float(config.get("grouping", {}).get("max_adjacent_timestamp_difference_seconds", config.get("grouping", {}).get("max_gap_seconds", 600)))
    preliminary_sessions = []
    for epoch in epochs:
        preliminary_sessions.extend(split_sessions_by_filename_time(epoch, max_timestamp_difference))
    for session in preliminary_sessions:
        for item in session:
            item["probe"] = probe_media(ffprobe_path, item["path"])
            item["signature"] = stream_signature(item["probe"])
        validate_continuity(session, config.get("grouping", {}), warnings)
    corrected_sessions = []
    for session in preliminary_sessions:
        first = session[0]
        sync_offset, _ = applicable_sync_offset(name, first["filename_time"], config)
        drift_epoch = first["filename_time"] + timedelta(seconds=float(source_config.get("offset_seconds", 0.0)) + sync_offset)
        timeline = []
        for item in session:
            start = correct_time(name, item["filename_time"], source_config, config, drift_epoch)
            end = start + timedelta(seconds=item["probe"]["duration"])
            item["corrected_start"] = start
            item["corrected_end"] = end
            timeline.append(item)
        corrected_sessions.append({
            "source": name,
            "files": session,
            "start": min(item["corrected_start"] for item in timeline),
            "end": max(item["corrected_end"] for item in timeline)
        })
    return {
        "name": name,
        "key": re.sub(r"[^A-Za-z0-9_]", "_", name),
        "config": source_config,
        "path": source_path,
        "files": files,
        "import_events": import_events,
        "sequence_epochs": epochs,
        "recording_groups": corrected_sessions,
        "warnings": warnings,
        "signature": stream_signature(preliminary_sessions[0][0]["probe"]) if preliminary_sessions else None
    }


def merge_cross_source_sessions(source_runtimes):
    groups = []
    for runtime in source_runtimes:
        groups.extend(runtime["recording_groups"])
    groups.sort(key=lambda group: group["start"])
    sessions = []
    for group in groups:
        if not sessions or group["start"] > sessions[-1]["end"]:
            sessions.append({"start": group["start"], "end": group["end"], "groups": [group]})
        else:
            sessions[-1]["groups"].append(group)
            if group["end"] > sessions[-1]["end"]:
                sessions[-1]["end"] = group["end"]
    return sessions


def build_rotate_filter(degrees):
    value = int(degrees) % 360
    if value == 0:
        return None
    if value == 90:
        return "transpose=1"
    if value == 180:
        return "hflip,vflip"
    if value == 270:
        return "transpose=2"
    raise RuntimeError("Rotation must be 0, 90, 180, or 270 degrees")


def source_filter_chain(source_runtime, stack_mode, target_width, target_height, target_fps):
    filters = []
    source_config = source_runtime["config"]
    filters_config = source_config.get("filters", {})
    rotate = filters_config.get("rotate", {})
    rotate_mode = rotate.get("mode", "none") if isinstance(rotate, dict) else "none"
    rotate_degrees = int(rotate.get("degrees", 0)) if isinstance(rotate, dict) else int(rotate or 0)
    if rotate_mode == "physical":
        rotation = build_rotate_filter(rotate_degrees)
        if rotation:
            filters.extend(rotation.split(","))
    elif rotate_mode == "metadata" and stack_mode and rotate_degrees:
        fallback = rotate.get("fallback", "physical")
        if fallback == "physical":
            filters.extend(build_rotate_filter(rotate_degrees).split(","))
        else:
            raise RuntimeError(f"Source {source_runtime['name']} requires metadata rotation that cannot be retained independently in a stack")
    scale = filters_config.get("scale", {})
    if isinstance(scale, dict) and scale.get("mode") == "explicit":
        filters.append(f"scale={int(scale['width'])}:{int(scale['height'])}")
    fps = filters_config.get("fps", {})
    if isinstance(fps, dict) and fps.get("mode") == "explicit":
        filters.append(f"fps={float(fps['value'])}")
    if stack_mode and target_width and target_height:
        filters.append(f"scale={target_width}:{target_height}")
    if stack_mode and target_fps:
        filters.append(f"fps={target_fps}")
    filters.append("setsar=1")
    return filters


def available_ffmpeg_encoders(ffmpeg_path):
    result = run_capture([ffmpeg_path, "-hide_banner", "-encoders"])
    if result.returncode != 0:
        raise RuntimeError(f"Unable to query FFmpeg encoders: {result.stderr.strip()}")
    available = set()
    for line in result.stdout.splitlines():
        match = re.match(r"^\s*[VAS\.]{6}\s+(\S+)", line)
        if match:
            available.add(match.group(1))
    return available


def resolve_source_encoder(config, source_runtimes, ffmpeg_path):
    encoding = config.get("encoding", {})
    source_encoding = encoding.get("source", {})
    source_name = source_encoding.get("source_name")
    runtime = next((item for item in source_runtimes if item["name"] == source_name), None)
    if not runtime or not runtime.get("signature"):
        raise RuntimeError(f"Source-derived encoding source is unavailable: {source_name}")
    family = runtime["signature"].get("video_codec")
    mapping = source_encoding.get("encoder_map", {})
    candidates = mapping.get(family, [])
    if isinstance(candidates, str):
        candidates = [candidates]
    available = available_ffmpeg_encoders(ffmpeg_path)
    encoder = next((candidate for candidate in candidates if candidate in available), None)
    if not encoder:
        raise RuntimeError(f"No configured available encoder for source codec family {family}")
    return encoder, runtime


def explicit_encode_args(config):
    settings = config.get("encoding", {}).get("explicit", {})
    args = ["-c:v", str(settings.get("video_codec", "libx264"))]
    if settings.get("crf") is not None:
        args += ["-crf", str(settings["crf"])]
    if settings.get("preset"):
        args += ["-preset", str(settings["preset"])]
    if settings.get("pix_fmt"):
        args += ["-pix_fmt", str(settings["pix_fmt"])]
    if settings.get("audio_codec"):
        args += ["-c:a", str(settings["audio_codec"])]
    if settings.get("audio_bitrate"):
        args += ["-b:a", str(settings["audio_bitrate"])]
    return args


def final_encode_args(config, source_runtimes, ffmpeg_path):
    encoding = config.get("encoding", {})
    mode = encoding.get("mode", "explicit")
    if mode == "copy_if_possible":
        mode = encoding.get("fallback", "explicit")
    if mode == "source":
        try:
            encoder, runtime = resolve_source_encoder(config, source_runtimes, ffmpeg_path)
            args = ["-c:v", encoder]
            explicit = encoding.get("explicit", {})
            if explicit.get("pix_fmt"):
                args += ["-pix_fmt", str(explicit["pix_fmt"])]
            if explicit.get("audio_codec"):
                args += ["-c:a", str(explicit["audio_codec"])]
            if explicit.get("audio_bitrate"):
                args += ["-b:a", str(explicit["audio_bitrate"])]
            return args, f"source:{runtime['name']}:{encoder}"
        except RuntimeError as exc:
            log("WARN", f"Source-derived encoding unavailable, using explicit fallback: {exc}")
            return explicit_encode_args(config), "explicit_fallback"
    return explicit_encode_args(config), "explicit"


def target_video_properties(source_runtimes, config):
    signatures = [runtime["signature"] for runtime in source_runtimes if runtime.get("signature")]
    if not signatures:
        return 1280, 720, 30.0
    normalize = config.get("normalize_inputs", {})
    resolution_mode = normalize.get("resolution", "match_first")
    fps_mode = normalize.get("fps", "match_first")
    if resolution_mode == "scale_max":
        selected = max(signatures, key=lambda value: int(value.get("width") or 0) * int(value.get("height") or 0))
    elif resolution_mode == "scale_min":
        selected = min(signatures, key=lambda value: int(value.get("width") or 0) * int(value.get("height") or 0))
    else:
        selected = signatures[0]
    fps_values = [value.get("fps") for value in signatures if value.get("fps")]
    fps = fps_values[0] if fps_values else 30.0
    if fps_mode == "explicit":
        fps = float(normalize["fps_value"])
    return int(selected.get("width") or 1280), int(selected.get("height") or 720), float(fps)


def add_input(command, input_path):
    index = sum(1 for value in command if value == "-i")
    command += ["-i", str(input_path)]
    return index


def add_lavfi_input(command, expression, duration):
    index = sum(1 for value in command if value == "-i")
    command += ["-f", "lavfi", "-t", f"{duration:.6f}", "-i", expression]
    return index


def build_source_streams(command, filter_parts, runtime, group, session_start, session_end, video_filters, width, height, fps, build_audio):
    files = sorted(group["files"], key=lambda item: item["corrected_start"])
    video_labels = []
    audio_labels = []
    current = session_start
    segment_number = 0
    sample_rate = int(runtime.get("signature", {}).get("sample_rate") or 48000)
    channel_layout = "stereo"
    for item in files:
        if item["corrected_start"] > current:
            duration = (item["corrected_start"] - current).total_seconds()
            video_input = add_lavfi_input(command, f"color=c=black:s={width}x{height}:r={fps}", duration)
            video_label = f"[v{runtime['key']}_{segment_number}]"
            filter_parts.append(f"[{video_input}:v]setsar=1{video_label}")
            video_labels.append(video_label)
            if build_audio:
                audio_input = add_lavfi_input(command, f"anullsrc=r={sample_rate}:cl={channel_layout}", duration)
                audio_label = f"[a{runtime['key']}_{segment_number}]"
                filter_parts.append(f"[{audio_input}:a]atrim=duration={duration:.6f},asetpts=PTS-STARTPTS{audio_label}")
                audio_labels.append(audio_label)
            segment_number += 1
        input_index = add_input(command, item["path"])
        video_label = f"[v{runtime['key']}_{segment_number}]"
        chain = ["setpts=PTS-STARTPTS"] + video_filters
        filter_parts.append(f"[{input_index}:v]{','.join(chain)}{video_label}")
        video_labels.append(video_label)
        if build_audio:
            audio_label = f"[a{runtime['key']}_{segment_number}]"
            if item["probe"]["audio"]:
                filter_parts.append(f"[{input_index}:a]aresample={sample_rate},asetpts=PTS-STARTPTS{audio_label}")
            else:
                duration = item["probe"]["duration"]
                audio_input = add_lavfi_input(command, f"anullsrc=r={sample_rate}:cl={channel_layout}", duration)
                filter_parts.append(f"[{audio_input}:a]atrim=duration={duration:.6f},asetpts=PTS-STARTPTS{audio_label}")
            audio_labels.append(audio_label)
        current = max(current, item["corrected_end"])
        segment_number += 1
    if current < session_end:
        duration = (session_end - current).total_seconds()
        video_input = add_lavfi_input(command, f"color=c=black:s={width}x{height}:r={fps}", duration)
        video_label = f"[v{runtime['key']}_{segment_number}]"
        filter_parts.append(f"[{video_input}:v]setsar=1{video_label}")
        video_labels.append(video_label)
        if build_audio:
            audio_input = add_lavfi_input(command, f"anullsrc=r={sample_rate}:cl={channel_layout}", duration)
            audio_label = f"[a{runtime['key']}_{segment_number}]"
            filter_parts.append(f"[{audio_input}:a]atrim=duration={duration:.6f},asetpts=PTS-STARTPTS{audio_label}")
            audio_labels.append(audio_label)
    video_output = f"[video_{runtime['key']}]"
    filter_parts.append(f"{''.join(video_labels)}concat=n={len(video_labels)}:v=1:a=0{video_output}")
    audio_output = None
    if build_audio:
        audio_output = f"[audio_{runtime['key']}]"
        filter_parts.append(f"{''.join(audio_labels)}concat=n={len(audio_labels)}:v=0:a=1{audio_output}")
    return video_output, audio_output


def audio_filter(audio_outputs, audio_config, session_duration, filter_parts):
    mode = audio_config.get("mode", "none")
    if mode == "none":
        return None
    if mode == "mix":
        labels = []
        for index, item in enumerate(audio_config.get("sources", [])):
            source = item.get("source")
            if source not in audio_outputs:
                if audio_config.get("on_missing_audio", "silence") == "error":
                    raise RuntimeError(f"Audio source unavailable: {source}")
                continue
            level = float(item.get("level_db", 0.0))
            label = f"[mix_audio_{index}]"
            filter_parts.append(f"{audio_outputs[source]}volume={level}dB{label}")
            labels.append(label)
        if not labels:
            return None
        output = "[audio_out]"
        normalize = 1 if audio_config.get("normalize", False) else 0
        filter_parts.append(f"{''.join(labels)}amix=inputs={len(labels)}:duration=longest:normalize={normalize}{output}")
        return output
    if mode == "select":
        labels = []
        selections = sorted(audio_config.get("selections", []), key=lambda value: float(value.get("start_seconds", 0.0)))
        previous_end = 0.0
        for index, selection in enumerate(selections):
            source = selection.get("source")
            start = float(selection.get("start_seconds", 0.0))
            end_value = selection.get("end_seconds")
            end = session_duration if end_value is None else float(end_value)
            if start < previous_end or end <= start or start < 0 or end > session_duration + 0.001:
                raise RuntimeError("Invalid or overlapping audio selection interval")
            previous_end = end
            if source not in audio_outputs:
                if audio_config.get("on_missing_audio", "silence") == "error":
                    raise RuntimeError(f"Audio source unavailable: {source}")
                continue
            level = float(selection.get("level_db", 0.0))
            delay = int(round(start * 1000.0))
            label = f"[selected_audio_{index}]"
            filter_parts.append(f"{audio_outputs[source]}atrim=start={start:.6f}:end={end:.6f},asetpts=PTS-STARTPTS,volume={level}dB,adelay={delay}|{delay}{label}")
            labels.append(label)
        if not labels:
            return None
        output = "[audio_out]"
        filter_parts.append(f"{''.join(labels)}amix=inputs={len(labels)}:duration=longest:normalize=0{output}")
        return output
    raise RuntimeError("audio.mode must be none, select, or mix")


def build_stack_command(session, source_runtimes, config, ffmpeg_path, output_path):
    width, height, fps = target_video_properties(source_runtimes, config)
    layout = config.get("output_mode", {}).get("stack", {}).get("layout", "horizontal")
    if layout not in ("horizontal", "vertical"):
        raise RuntimeError("Initial stack implementation supports only horizontal or vertical layout")
    audio_config = config.get("audio", {"mode": "none"})
    build_audio = audio_config.get("mode", "none") != "none"
    groups_by_source = {group["source"]: group for group in session["groups"]}
    command = [ffmpeg_path, "-y", "-hide_banner"]
    filter_parts = []
    video_outputs = []
    audio_outputs = {}
    for runtime in source_runtimes:
        group = groups_by_source.get(runtime["name"])
        if not group:
            group = {"source": runtime["name"], "files": []}
        filters = source_filter_chain(runtime, True, width, height, fps)
        video_output, audio_output = build_source_streams(
            command,
            filter_parts,
            runtime,
            group,
            session["start"],
            session["end"],
            filters,
            width,
            height,
            fps,
            build_audio
        )
        video_outputs.append(video_output)
        if audio_output:
            audio_outputs[runtime["name"]] = audio_output
    video_final = "[video_out]"
    if layout == "horizontal":
        xstack_layout = "|".join("0_0" if index == 0 else f"w0*{index}_0" for index in range(len(video_outputs)))
    else:
        xstack_layout = "|".join("0_0" if index == 0 else f"0_h0*{index}" for index in range(len(video_outputs)))
    filter_parts.append(f"{''.join(video_outputs)}xstack=inputs={len(video_outputs)}:layout={xstack_layout}{video_final}")
    session_duration = (session["end"] - session["start"]).total_seconds()
    audio_final = audio_filter(audio_outputs, audio_config, session_duration, filter_parts)
    command += ["-filter_complex", ";".join(filter_parts), "-map", video_final]
    if audio_final:
        command += ["-map", audio_final]
    encode_args, encode_plan = final_encode_args(config, source_runtimes, ffmpeg_path)
    command += encode_args
    if not audio_final:
        command += ["-an"]
    command += [str(output_path)]
    return command, encode_plan



def build_concat_list(paths, list_path):
    with Path(list_path).open("w", encoding="utf-8") as handle:
        for path in paths:
            value = str(Path(path).resolve()).replace("'", r"'\''")
            handle.write(f"file '{value}'\n")


def per_source_metadata_rotation(runtime):
    rotate = runtime["config"].get("filters", {}).get("rotate", {})
    if not isinstance(rotate, dict):
        return None
    if rotate.get("mode", "none") != "metadata":
        return None
    degrees = int(rotate.get("degrees", 0)) % 360
    return degrees if degrees else None


def physical_filters_for_concatenate(runtime):
    filters = []
    config = runtime["config"].get("filters", {})
    rotate = config.get("rotate", {})
    if isinstance(rotate, dict) and rotate.get("mode") == "physical":
        value = build_rotate_filter(int(rotate.get("degrees", 0)))
        if value:
            filters.extend(value.split(","))
    scale = config.get("scale", {})
    if isinstance(scale, dict) and scale.get("mode") == "explicit":
        filters.append(f"scale={int(scale['width'])}:{int(scale['height'])}")
    fps = config.get("fps", {})
    if isinstance(fps, dict) and fps.get("mode") == "explicit":
        filters.append(f"fps={float(fps['value'])}")
    return filters


def signatures_compatible(files):
    signatures = [item["signature"] for item in files]
    if not signatures:
        return False
    keys = ("video_codec", "width", "height", "pixel_format", "fps", "audio_codec", "sample_rate", "channels", "container")
    first = signatures[0]
    for signature in signatures[1:]:
        for key in keys:
            a = first.get(key)
            b = signature.get(key)
            if key == "fps" and a is not None and b is not None:
                if abs(float(a) - float(b)) > 0.01:
                    return False
            elif a != b:
                return False
    return True


def execute_or_report(command, dry_run, output_path, ffprobe_path):
    if dry_run:
        return
    result = subprocess.run(command)
    if result.returncode != 0:
        raise RuntimeError(f"FFmpeg failed with exit code {result.returncode}: {output_path}")
    if not output_path.is_file() or output_path.stat().st_size == 0:
        raise RuntimeError(f"Output validation failed: {output_path}")
    probe_media(ffprobe_path, output_path)


def build_concat_command(files, runtime, config, ffmpeg_path, output_path, list_path, copy_requested):
    build_concat_list([item["path"] for item in files], list_path)
    physical_filters = physical_filters_for_concatenate(runtime)
    metadata_rotation = per_source_metadata_rotation(runtime)
    copy_eligible = copy_requested and not physical_filters and signatures_compatible(files)
    command = [ffmpeg_path, "-y", "-hide_banner", "-f", "concat", "-safe", "0", "-i", str(list_path)]
    if copy_eligible:
        command += ["-c", "copy"]
        if metadata_rotation is not None and config.get("encoding", {}).get("copy_if_possible", {}).get("allow_metadata_rotation", True):
            command += ["-metadata:s:v", f"rotate={metadata_rotation}"]
        plan = "copy"
    else:
        if physical_filters:
            command += ["-vf", ",".join(physical_filters)]
        encode_args, plan = final_encode_args(config, [runtime], ffmpeg_path)
        command += encode_args
        if metadata_rotation is not None:
            command += ["-metadata:s:v", f"rotate={metadata_rotation}"]
    command += [str(output_path)]
    return command, plan, copy_eligible


def process_concatenate_sessions(sessions, source_runtimes, config, ffmpeg_path, ffprobe_path, output_directory, container, dry_run, report):
    concatenate = config.get("output_mode", {}).get("concatenate", {})
    ordering = concatenate.get("ordering", "chronological")
    configured_order = concatenate.get("camera_order", [])
    copy_requested = config.get("encoding", {}).get("mode") == "copy_if_possible"
    runtime_by_name = {runtime["name"]: runtime for runtime in source_runtimes}
    for session_index, session in enumerate(sessions, start=1):
        groups = list(session["groups"])
        if ordering == "camera_order":
            rank = {name: index for index, name in enumerate(configured_order)}
            groups.sort(key=lambda group: (rank.get(group["source"], len(rank)), group["start"]))
        else:
            groups.sort(key=lambda group: group["start"])
        intermediate_paths = []
        intermediate_reports = []
        with tempfile.TemporaryDirectory(prefix="video_joiner_", dir=output_directory) as temporary:
            temporary_path = Path(temporary)
            final_copy_possible = True
            for group_index, group in enumerate(groups, start=1):
                runtime = runtime_by_name[group["source"]]
                intermediate = temporary_path / f"{group_index:03d}_{runtime['key']}.{container}"
                list_path = temporary_path / f"{group_index:03d}_{runtime['key']}.txt"
                command, plan, copied = build_concat_command(group["files"], runtime, config, ffmpeg_path, intermediate, list_path, copy_requested)
                intermediate_reports.append({"source": runtime["name"], "encoding_plan": plan, "ffmpeg_command": shlex.join(command)})
                execute_or_report(command, dry_run, intermediate, ffprobe_path)
                if dry_run:
                    intermediate_paths.extend(str(item["path"]) for item in group["files"])
                else:
                    intermediate_paths.append(str(intermediate))
                final_copy_possible = final_copy_possible and copied
            final_output = output_directory / f"session_{session['start'].strftime('%Y%m%d_%H%M%S')}_{session_index:03d}.{container}"
            final_list = temporary_path / "final.txt"
            build_concat_list(intermediate_paths, final_list)
            final_command = [ffmpeg_path, "-y", "-hide_banner", "-f", "concat", "-safe", "0", "-i", str(final_list)]
            if copy_requested and final_copy_possible:
                final_command += ["-c", "copy"]
                final_plan = "copy"
            else:
                args, final_plan = final_encode_args(config, source_runtimes, ffmpeg_path)
                final_command += args
            final_command += [str(final_output)]
            session_report = {
                "index": session_index,
                "start": session["start"],
                "end": session["end"],
                "duration_seconds": (session["end"] - session["start"]).total_seconds(),
                "sources": [group["source"] for group in groups],
                "output": str(final_output),
                "encoding_plan": final_plan,
                "intermediate_commands": intermediate_reports,
                "ffmpeg_command": shlex.join(final_command)
            }
            report["sessions"].append(session_report)
            execute_or_report(final_command, dry_run, final_output, ffprobe_path)

def output_container(config, source_runtimes):
    encoding = config.get("encoding", {})
    mode = encoding.get("mode", "explicit")
    if mode == "source":
        source_name = encoding.get("source", {}).get("source_name")
        runtime = next((item for item in source_runtimes if item["name"] == source_name), None)
        source_policy = encoding.get("source", {}).get("container", "match_source")
        if source_policy == "match_source" and runtime and runtime.get("signature"):
            return runtime["signature"].get("container") or "mp4"
        if source_policy != "match_source":
            return str(source_policy).lstrip(".")
    return str(encoding.get("explicit", {}).get("container", "mp4")).lstrip(".")


def render_report(report, config):
    dry_output = config.get("dry_run_output", {})
    mode = dry_output.get("format", "text")
    text = json.dumps(report, indent=2, default=str)
    if mode in ("text", "text_and_json"):
        print(text)
    if mode in ("json", "text_and_json"):
        file_value = dry_output.get("file")
        if not file_value:
            raise RuntimeError("dry_run_output.file is required for JSON output")
        path = Path(file_value)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main():
    try:
        if len(sys.argv) == 1:
            config_path = resolve_default_config_path()
            if not config_path:
                raise RuntimeError("No arguments supplied and config.yaml was not found beside processor.py")
            arguments = None
        else:
            arguments = parse_args()
            if not arguments.config:
                raise RuntimeError("--config is required when command-line arguments are supplied")
            config_path = Path(arguments.config)
        config = load_config(config_path)
        ffmpeg_path = find_executable("ffmpeg")
        ffprobe_path = find_executable("ffprobe")
        output_directory = Path(config.get("output_dir", ""))
        if not output_directory:
            raise RuntimeError("output_dir is required")
        output_directory.mkdir(parents=True, exist_ok=True)
        if not os.access(output_directory, os.W_OK):
            raise RuntimeError(f"Output directory is not writable: {output_directory}")
        source_runtimes = [build_source_runtime(source, config, ffprobe_path) for source in config.get("sources", [])]
        source_runtimes = [runtime for runtime in source_runtimes if runtime["recording_groups"]]
        if not source_runtimes:
            raise RuntimeError("No matching recordings were found")
        sessions = merge_cross_source_sessions(source_runtimes)
        mode = config.get("output_mode", {}).get("type", "stack")
        if mode not in ("stack", "concatenate", "none"):
            raise RuntimeError("output_mode.type must be stack, concatenate, or none")
        dry_run = bool(config.get("dry_run", False) or (arguments and arguments.dry_run))
        report = {"dry_run": dry_run, "sources": [], "sessions": [], "warnings": []}
        for runtime in source_runtimes:
            report["sources"].append({
                "name": runtime["name"],
                "path": str(runtime["path"]),
                "file_count": len(runtime["files"]),
                "import_event_count": len(runtime["import_events"]),
                "sequence_epoch_count": len(runtime["sequence_epochs"]),
                "recording_group_count": len(runtime["recording_groups"]),
                "warnings": runtime["warnings"]
            })
            report["warnings"].extend(runtime["warnings"])
        container = output_container(config, source_runtimes)
        if mode == "stack":
            for index, session in enumerate(sessions, start=1):
                output_path = output_directory / f"session_{session['start'].strftime('%Y%m%d_%H%M%S')}_{index:03d}.{container}"
                command, encode_plan = build_stack_command(session, source_runtimes, config, ffmpeg_path, output_path)
                session_report = {
                    "index": index,
                    "start": session["start"],
                    "end": session["end"],
                    "duration_seconds": (session["end"] - session["start"]).total_seconds(),
                    "sources": [group["source"] for group in session["groups"]],
                    "output": str(output_path),
                    "encoding_plan": encode_plan,
                    "ffmpeg_command": shlex.join(command)
                }
                report["sessions"].append(session_report)
                execute_or_report(command, dry_run, output_path, ffprobe_path)
        elif mode == "concatenate":
            process_concatenate_sessions(sessions, source_runtimes, config, ffmpeg_path, ffprobe_path, output_directory, container, dry_run, report)
        else:
            report["warnings"].append("output_mode.type is none; no media output was generated")
        render_report(report, config)
    except KeyboardInterrupt:
        log("FATAL", "Interrupted")
        raise SystemExit(130)
    except Exception as exc:
        log("FATAL", str(exc))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
