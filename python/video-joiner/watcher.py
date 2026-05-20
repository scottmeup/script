#!/usr/bin/env python3

import os
import time
import subprocess
import sys
from pathlib import Path
import yaml
import shutil

from inotify_simple import INotify, flags


def log(level, msg):
    print(f"[{level}] {msg}")


def load_config(path):
    if not Path(path).exists():
        raise RuntimeError(f"Config file does not exist: {path}")
    if not os.access(path, os.R_OK):
        raise RuntimeError(f"Config file is not readable: {path}")
    with open(path) as f:
        return yaml.safe_load(f)


def validate_watch_dirs(paths):
    for path in paths:
        p = Path(path)
        if p.exists():
            if not p.is_dir():
                raise RuntimeError(f"Watch path exists but is not a directory: {path}")
        else:
            try:
                p.mkdir(parents=True, exist_ok=True)
                log("INFO", f"Created watch directory: {path}")
            except Exception as e:
                raise RuntimeError(f"Failed to create watch directory {path}: {e}")

        if not os.access(path, os.R_OK | os.W_OK | os.X_OK):
            raise RuntimeError(f"Watch directory lacks required permissions (rwx): {path}")


def validate_delay(value):
    if not isinstance(value, (int, float)):
        raise RuntimeError("delay_seconds must be numeric")
    if value < 0:
        raise RuntimeError("delay_seconds must be non-negative")


def validate_file(path, require_exec=False):
    p = Path(path)
    if not p.exists():
        raise RuntimeError(f"Missing file: {path}")
    if not p.is_file():
        raise RuntimeError(f"Not a file: {path}")
    if not os.access(path, os.R_OK):
        raise RuntimeError(f"File not readable: {path}")
    if require_exec and not os.access(path, os.X_OK):
        raise RuntimeError(f"File not executable: {path}")


def move_files(src, dest):
    try:
        src_p = Path(src)
        dest_p = Path(dest)

        if not src_p.exists():
            log("ERROR", f"Move source does not exist: {src}")
            return

        dest_p.mkdir(parents=True, exist_ok=True)

        for f in src_p.glob("*"):
            if f.is_file():
                try:
                    target = dest_p / f.name
                    shutil.move(str(f), str(target))
                    log("INFO", f"Moved {f} → {target}")
                except Exception as e:
                    log("ERROR", f"Failed moving {f}: {e}")

    except Exception as e:
        log("ERROR", f"move_files failure: {e}")


def run_subprocess(cmd):
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        log("INFO", result.stdout)

        if result.returncode != 0:
            log("ERROR", f"Command failed: {' '.join(cmd)}")
            log("ERROR", result.stderr)

    except Exception as e:
        log("ERROR", f"Subprocess execution failed: {e}")


def watch(config):
    watcher_cfg = config.get("watcher", {})
    paths_cfg = config.get("paths", {})

    watch_dirs = watcher_cfg.get("watch_dirs", [])
    delay = watcher_cfg.get("delay_seconds", 30)
    run_ingest = watcher_cfg.get("run_ingest_before_processing", False)
    move_cfg = watcher_cfg.get("move", {})

    processor = paths_cfg.get("processor")
    ingest = paths_cfg.get("ingest_script")
    cfg_path = paths_cfg.get("config")

    if not watch_dirs:
        raise RuntimeError("No watch directories configured")

    validate_watch_dirs(watch_dirs)
    validate_delay(delay)

    validate_file(processor)
    validate_file(cfg_path)

    if run_ingest:
        validate_file(ingest)

    inotify = INotify()
    wd_map = {}

    for d in watch_dirs:
        try:
            wd = inotify.add_watch(
                d,
                flags.CREATE | flags.MODIFY | flags.CLOSE_WRITE | flags.MOVED_TO
            )
            wd_map[wd] = d
            log("INFO", f"Watching: {d}")
        except Exception as e:
            raise RuntimeError(f"Failed to watch directory {d}: {e}")

    last_event_time = time.time()

    while True:
        try:
            events = inotify.read(timeout=1000)

            if events:
                last_event_time = time.time()

            idle_time = time.time() - last_event_time

            if idle_time >= delay:
                log("INFO", "Stable state detected")

                if move_cfg.get("enabled"):
                    dest = move_cfg.get("dest")
                    if not dest:
                        log("ERROR", "Move enabled but no destination configured")
                    else:
                        for d in watch_dirs:
                            move_files(d, dest)

                if run_ingest:
                    run_subprocess(["python3", ingest, cfg_path])

                run_subprocess(["python3", processor, "--config", cfg_path])

                last_event_time = time.time()

        except Exception as e:
            log("ERROR", f"Watch loop error: {e}")
            time.sleep(2)


def main():
    try:
        if len(sys.argv) < 2:
            raise RuntimeError("Usage: watcher.py <config.yaml>")

        config_path = sys.argv[1]
        config = load_config(config_path)
        watch(config)

    except Exception as e:
        log("FATAL", str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()