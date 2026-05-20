#!/usr/bin/env python3

import os
import sys
import yaml
import shutil
import subprocess
from pathlib import Path

def log(level, msg):
    print(f"[{level}] {msg}")

def run(cmd):
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return result.returncode == 0
    except:
        return False

def check_bin(name):
    return shutil.which(name) is not None

def load_config(path):
    p = Path(path)
    if not p.exists():
        raise RuntimeError(f"Config missing: {path}")
    if not os.access(path, os.R_OK):
        raise RuntimeError(f"Config not readable: {path}")
    with open(path) as f:
        return yaml.safe_load(f)

def ensure_dirs(config):
    dirs = []

    for src in config.get("sources", []):
        dirs.append(src["path"])

    for entry in config.get("watcher", {}).get("watch_dirs", []):
        dirs.append(entry["path"])

    for v in config.get("ingest", {}).get("volumes", []):
        dirs.append(v["dest_path"])

    for d in set(dirs):
        try:
            p = Path(d)
            if not p.exists():
                p.mkdir(parents=True, exist_ok=True)
                log("INFO", f"Created {d}")
            if not os.access(d, os.R_OK | os.W_OK | os.X_OK):
                log("ERROR", f"Permission issue: {d}")
        except Exception as e:
            log("ERROR", f"Dir setup failed {d}: {e}")

def check_dependencies():
    missing = []

    for bin_name in ["ffmpeg", "ffprobe", "python3"]:
        if not check_bin(bin_name):
            missing.append(bin_name)

    try:
        import yaml
    except:
        missing.append("pyyaml")

    try:
        import inotify_simple
    except:
        missing.append("inotify-simple")

    if missing:
        log("ERROR", f"Missing dependencies: {missing}")
        return False

    return True

def validate_paths(config):
    paths = config.get("paths", {})

    for key in ["processor", "ingest_script"]:
        p = paths.get(key)
        if p:
            if not Path(p).exists():
                raise RuntimeError(f"Missing path: {p}")

def create_udev(config):
    try:
        rules = []

        for v in config.get("ingest", {}).get("volumes", []):
            label = v["label"]
            rules.append(
                f'ACTION=="add", SUBSYSTEM=="block", ENV{{ID_FS_LABEL}}=="{label}", RUN+="/usr/local/bin/run_ingest.sh"'
            )

        with open("/etc/udev/rules.d/99-video-ingest.rules", "w") as f:
            f.write("\n".join(rules))

        script = f"""#!/bin/bash
sleep 2
/usr/bin/python3 {config['paths']['ingest_script']} {config['paths']['config']}
"""

        with open("/usr/local/bin/run_ingest.sh", "w") as f:
            f.write(script)

        os.chmod("/usr/local/bin/run_ingest.sh", 0o755)

    except Exception as e:
        log("ERROR", f"udev setup failed: {e}")

def create_systemd(config):
    try:
        service = f"""
[Unit]
Description=Video Ingest

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 {config['paths']['ingest_script']} {config['paths']['config']}
"""
        with open("/etc/systemd/system/video-ingest.service", "w") as f:
            f.write(service)
    except Exception as e:
        log("ERROR", f"systemd setup failed: {e}")

def main():
    try:
        if len(sys.argv) < 2:
            raise RuntimeError("Usage: setup.py <config.yaml>")

        config = load_config(sys.argv[1])

        if not check_dependencies():
            sys.exit(1)

        validate_paths(config)
        ensure_dirs(config)

        mode = config.get("setup", {}).get("mode", "none")

        if mode == "udev":
            create_udev(config)
        elif mode == "systemd":
            create_systemd(config)

        log("INFO", "Setup complete")

    except Exception as e:
        log("FATAL", str(e))
        sys.exit(1)

if __name__ == "__main__":
    main()