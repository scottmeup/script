#!/usr/bin/env python3

import os
import sys
import yaml
import shutil
import argparse
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
        raise RuntimeError(f"Config missing: {path}")
    if not os.access(str(p), os.R_OK):
        raise RuntimeError(f"Config not readable: {path}")
    with open(p) as f:
        return yaml.safe_load(f)

def check_bin(name):
    return shutil.which(name) is not None

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
        raise RuntimeError(f"Missing dependencies: {missing}")

def ensure_dirs(config):
    dirs = set()
    for src in config.get("sources", []):
        if "path" in src:
            dirs.add(src["path"])
    for entry in config.get("watcher", {}).get("watch_dirs", []):
        if "path" in entry:
            dirs.add(entry["path"])
    for v in config.get("ingest", {}).get("volumes", []):
        if "dest_path" in v:
            dirs.add(v["dest_path"])
    out = config.get("output_dir")
    if out:
        dirs.add(out)
    for d in dirs:
        p = Path(d)
        if not p.exists():
            p.mkdir(parents=True, exist_ok=True)

def validate_paths(config):
    paths = config.get("paths", {})
    for key in ["processor", "ingest_script"]:
        p = paths.get(key)
        if p and not Path(p).exists():
            raise RuntimeError(f"Missing path: {p}")

def parse_args():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--config", default=None)
    return ap.parse_args()

def main():
    try:
        if len(sys.argv) == 1:
            default_cfg = resolve_default_config_path()
            if not default_cfg:
                raise RuntimeError("No arguments provided and config.yaml not found next to setup.py")
            cfg_path = str(default_cfg)
        else:
            args = parse_args()
            if not args.config:
                raise RuntimeError("setup.py requires --config when any arguments are provided")
            cfg_path = args.config

        config = load_config(cfg_path)
        check_dependencies()
        validate_paths(config)
        ensure_dirs(config)
        log("INFO", "Setup complete")

    except Exception as e:
        log("FATAL", str(e))
        sys.exit(1)

if __name__ == "__main__":
    main()
