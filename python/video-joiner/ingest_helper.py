#!/usr/bin/env python3

import yaml
import os
import sys
from pathlib import Path
import stat

def log(level, msg):
    print(f"[{level}] {msg}")

def load_config(path):
    with open(path) as f:
        return yaml.safe_load(f)

def ensure_dirs(config):
    dirs = []

    for src in config.get("sources", []):
        dirs.append(src["path"])

    for w in config.get("watcher", {}).get("watch_dirs", []):
        dirs.append(w)

    for v in config.get("ingest", {}).get("volumes", []):
        dirs.append(v["dest_path"])

    for d in set(dirs):
        p = Path(d)
        if not p.exists():
            p.mkdir(parents=True, exist_ok=True)

def create_udev(config):
    volumes = config.get("ingest", {}).get("volumes", [])
    rules = []

    for v in volumes:
        label = v["label"]
        rules.append(
            f'ACTION=="add", SUBSYSTEM=="block", ENV{{ID_FS_LABEL}}=="{label}", RUN+="/usr/local/bin/run_ingest.sh"'
        )

    rules_path = "/etc/udev/rules.d/99-video-ingest.rules"

    with open(rules_path, "w") as f:
        f.write("\n".join(rules))

    script_path = "/usr/local/bin/run_ingest.sh"

    script = f"""#!/bin/bash
sleep 2
/usr/bin/python3 {config['paths']['ingest_script']} {config['paths']['config']}
"""

    with open(script_path, "w") as f:
        f.write(script)

    os.chmod(script_path, stat.S_IRWXU | stat.S_IRGRP | stat.S_IROTH)

def create_systemd(config):
    service_path = "/etc/systemd/system/video-ingest.service"

    content = f"""
[Unit]
Description=Run video ingest

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 {config['paths']['ingest_script']} {config['paths']['config']}
"""

    with open(service_path, "w") as f:
        f.write(content)

def main():
    try:
        if len(sys.argv) < 2:
            raise RuntimeError("Usage: ingest_helper.py <config.yaml>")

        config = load_config(sys.argv[1])

        ensure_dirs(config)

        mode = config.get("setup", {}).get("mode", "none")

        if mode == "udev":
            create_udev(config)
        elif mode == "systemd":
            create_systemd(config)

    except Exception as e:
        log("FATAL", str(e))
        sys.exit(1)

if __name__ == "__main__":
    main()