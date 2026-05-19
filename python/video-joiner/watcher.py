#!/usr/bin/env python3

import os
import time
import subprocess
import sys
from pathlib import Path

try:
    from inotify_simple import INotify, flags
except ImportError:
    print("ERROR: inotify_simple is not installed. Install with:")
    print("pip install inotify-simple")
    sys.exit(1)

WATCH_DIR = "/mnt/sdc1/temp/video-joiner-test"
DELAY = 30
PROCESSOR = "./processor.py"
CONFIG = "config.yaml"


def validate_watch_dir(path: str):
    p = Path(path)

    if p.exists():
        if not p.is_dir():
            raise RuntimeError(f"WATCH_DIR exists but is NOT a directory: {path}")
    else:
        print(f"INFO: WATCH_DIR does not exist, creating: {path}")
        try:
            p.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            raise RuntimeError(f"Failed to create WATCH_DIR: {e}")

    if not os.access(path, os.R_OK | os.W_OK | os.X_OK):
        raise RuntimeError(f"WATCH_DIR is not accessible (rwx required): {path}")


def validate_delay(delay):
    if not isinstance(delay, (int, float)):
        raise RuntimeError("DELAY must be a number")
    if delay < 0:
        raise RuntimeError("DELAY must be non-negative")
    return delay


def validate_processor(path):
    p = Path(path)

    if not p.exists():
        raise RuntimeError(f"PROCESSOR does not exist: {path}")

    if not p.is_file():
        raise RuntimeError(f"PROCESSOR is not a file: {path}")

    if not os.access(path, os.X_OK):
        raise RuntimeError(f"PROCESSOR is not executable: {path}")


def validate_config(path):
    p = Path(path)

    if not p.exists():
        raise RuntimeError(f"CONFIG does not exist: {path}")

    if not p.is_file():
        raise RuntimeError(f"CONFIG is not a file: {path}")

    if not os.access(path, os.R_OK):
        raise RuntimeError(f"CONFIG is not readable: {path}")

def main():
    try:
        validate_watch_dir(WATCH_DIR)
        delay = validate_delay(DELAY)
        validate_processor(PROCESSOR)
        validate_config(CONFIG)

        print("INFO: Initialization checks passed.")

        inotify = INotify()

        # Watch for create + modify events
        wd = inotify.add_watch(
            WATCH_DIR,
            flags.CREATE | flags.MODIFY | flags.CLOSE_WRITE | flags.MOVED_TO
        )

        last_event_time = time.time()

        print(f"INFO: Watching directory: {WATCH_DIR}")
        print(f"INFO: Delay: {delay}s")

        while True:
            try:
                events = inotify.read(timeout=1000)

                if events:
                    last_event_time = time.time()
                    # Optional: debug
                    # print(f"DEBUG: event detected ({len(events)} events)")

                # debounce logic
                idle_time = time.time() - last_event_time

                if idle_time >= delay:
                    print("INFO: Directory stable, executing processor")

                    try:
                        result = subprocess.run(
                            ["python3", PROCESSOR, "--config", CONFIG],
                            capture_output=True,
                            text=True
                        )

                        print("INFO: Processor stdout:\n", result.stdout)

                        if result.returncode != 0:
                            print("ERROR: Processor failed")
                            print(result.stderr)

                    except Exception as e:
                        print(f"ERROR: Failed to execute processor: {e}")

                    # Reset timer after run
                    last_event_time = time.time()

            except Exception as e:
                print(f"ERROR: Watch loop error: {e}")
                time.sleep(2)  # prevent tight failure loop

    except Exception as e:
        print(f"FATAL ERROR: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
