#!/usr/bin/env python3

import os
import sys
import time
import yaml
import shutil
import argparse
import subprocess
from pathlib import Path
from inotify_simple import INotify, flags

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

def validate_delay(value):
    if not isinstance(value, (int, float)):
        raise RuntimeError("delay_seconds must be numeric")
    if value < 0:
        raise RuntimeError("delay_seconds must be non-negative")

def ensure_watch_dir(path, require_exists):
    p = Path(path)
    if p.exists():
        if not p.is_dir():
            raise RuntimeError(f"Watch path exists but is not a directory: {path}")
    else:
        if require_exists:
            p.mkdir(parents=True, exist_ok=True)
        else:
            return False
    if not os.access(str(p), os.R_OK | os.X_OK):
        raise RuntimeError(f"Watch directory not accessible (rx required): {path}")
    return True

def validate_file(path):
    p = Path(path)
    if not p.exists():
        raise RuntimeError(f"Missing file: {path}")
    if not p.is_file():
        raise RuntimeError(f"Not a file: {path}")
    if not os.access(str(p), os.R_OK):
        raise RuntimeError(f"File not readable: {path}")

def move_files(src, dest):
    src_p = Path(src)
    dest_p = Path(dest)
    dest_p.mkdir(parents=True, exist_ok=True)
    for f in src_p.glob("*"):
        if f.is_file():
            shutil.move(str(f), str(dest_p / f.name))

def run_cmd(cmd):
    try:
        subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except Exception as e:
        log("ERROR", str(e))

def build_runtime_from_config(cfg, config_path):
    watcher_cfg = cfg.get("watcher", {})
    paths_cfg = cfg.get("paths", {})

    watch_entries = watcher_cfg.get("watch_dirs", [])
    delay = watcher_cfg.get("delay_seconds", 30)
    run_ingest = watcher_cfg.get("run_ingest_before_processing", False)
    move_cfg = watcher_cfg.get("move", {})

    processor = paths_cfg.get("processor")
    ingest = paths_cfg.get("ingest_script")

    if not watch_entries:
        raise RuntimeError("No watcher.watch_dirs configured")

    if not processor:
        raise RuntimeError("paths.processor missing in config.yaml")

    validate_delay(delay)
    validate_file(processor)
    if run_ingest:
        if not ingest:
            raise RuntimeError("paths.ingest_script missing but run_ingest_before_processing is true")
        validate_file(ingest)

    return {
        "config_path": config_path,
        "processor": processor,
        "ingest": ingest,
        "run_ingest": bool(run_ingest),
        "delay": delay,
        "move_enabled": bool(move_cfg.get("enabled", False)),
        "move_dest": move_cfg.get("dest"),
        "watch_entries": watch_entries
    }

def build_runtime_from_cli(args):
    if not args.watch_dir:
        raise RuntimeError("CLI-only mode requires at least one --watch-dir")

    validate_delay(args.delay_seconds)

    if not args.processor:
        raise RuntimeError("CLI-only mode requires --processor")
    validate_file(args.processor)

    if args.run_ingest_before_processing:
        if not args.ingest_script:
            raise RuntimeError("CLI-only mode requires --ingest-script when --run-ingest-before-processing is set")
        validate_file(args.ingest_script)

    watch_entries = [{"path": d, "require_exists": True} for d in args.watch_dir]

    return {
        "config_path": None,
        "processor": args.processor,
        "ingest": args.ingest_script,
        "run_ingest": bool(args.run_ingest_before_processing),
        "delay": args.delay_seconds,
        "move_enabled": bool(args.move_enabled),
        "move_dest": args.move_dest,
        "watch_entries": watch_entries
    }

def watch(runtime):
    inotify = INotify()
    active = {}

    for entry in runtime["watch_entries"]:
        try:
            ok = ensure_watch_dir(entry["path"], bool(entry.get("require_exists", True)))
            if not ok:
                log("INFO", f"Watch dir not present (allowed): {entry['path']}")
                continue
            wd = inotify.add_watch(
                entry["path"],
                flags.CREATE | flags.MODIFY | flags.CLOSE_WRITE | flags.MOVED_TO
            )
            active[wd] = entry["path"]
            log("INFO", f"Watching: {entry['path']}")
        except Exception as e:
            log("ERROR", str(e))

    last_event_time = time.time()

    while True:
        try:
            events = inotify.read(timeout=1000)
            if events:
                last_event_time = time.time()

            idle_time = time.time() - last_event_time

            if idle_time >= runtime["delay"]:
                log("INFO", "Stable state detected")

                if runtime["move_enabled"]:
                    if not runtime["move_dest"]:
                        log("ERROR", "Move enabled but no destination configured")
                    else:
                        for entry in runtime["watch_entries"]:
                            try:
                                if Path(entry["path"]).exists():
                                    move_files(entry["path"], runtime["move_dest"])
                            except Exception as e:
                                log("ERROR", str(e))

                if runtime["run_ingest"]:
                    if runtime["config_path"]:
                        run_cmd(["python3", runtime["ingest"], runtime["config_path"]])
                    else:
                        log("ERROR", "run_ingest requested but no config path available in CLI-only watcher mode")

                if runtime["config_path"]:
                    run_cmd(["python3", runtime["processor"], "--config", runtime["config_path"]])
                else:
                    run_cmd(["python3", runtime["processor"]])

                last_event_time = time.time()

        except Exception as e:
            log("ERROR", str(e))
            time.sleep(2)

def parse_args():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--config", default=None)
    ap.add_argument("--watch-dir", action="append", default=[])
    ap.add_argument("--delay-seconds", type=float, default=30.0)
    ap.add_argument("--processor", default=None)
    ap.add_argument("--ingest-script", default=None)
    ap.add_argument("--run-ingest-before-processing", action="store_true")
    ap.add_argument("--move-enabled", action="store_true")
    ap.add_argument("--move-dest", default=None)
    return ap.parse_args()

def main():
    try:
        if len(sys.argv) == 1:
            default_cfg = resolve_default_config_path()
            if not default_cfg:
                raise RuntimeError("No arguments provided and config.yaml not found next to watcher.py")
            cfg = load_config(str(default_cfg))
            runtime = build_runtime_from_config(cfg, str(default_cfg))
            watch(runtime)
            return

        args = parse_args()

        if args.config:
            cfg = load_config(args.config)
            runtime = build_runtime_from_config(cfg, args.config)
            watch(runtime)
            return

        runtime = build_runtime_from_cli(args)
        watch(runtime)

    except Exception as e:
        log("FATAL", str(e))
        sys.exit(1)

if __name__ == "__main__":
    main()