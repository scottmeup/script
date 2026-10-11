#!/usr/bin/env python3
"""
Inputs:
- CHROME_CDP_HOST: string from .env; loopback host used by load_config and main.
- CHROME_CDP_PORT: integer from .env, 1-65535; used by load_config and main.
- CHROME_CDP_TIMEOUT_SECONDS: positive number from .env; used for HTTP and WebSocket operations.
- CHROME_CDP_ENV_FILE: optional path environment variable; selects the .env file, defaulting to ./.env.
- Chrome /json/list response: JSON list of target objects. Page targets require type and webSocketDebuggerUrl strings.
Outputs:
- Console summary and per-target errors, produced by main.
- CDP Page.stopLoading requests, sent by stop_target to every page target.
Functions:
- load_env_file reads simple KEY=VALUE entries without overriding exported environment variables.
- load_config validates and returns host, port, and timeout.
- fetch_targets reads and validates the CDP target list.
- stop_target connects to one target and confirms the matching CDP response.
- main stops loading on every page target and returns nonzero if discovery or any target fails.
Top-level variables:
- None; configuration is loaded only when main runs.
"""
import json
import os
import sys
import urllib.request
from pathlib import Path

import websocket


def load_env_file(path):
    env_path = Path(path)
    if not env_path.is_file():
        raise ValueError(f"Environment file not found: {env_path}")
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"Malformed .env entry: {raw_line}")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if not key:
            raise ValueError("Empty .env key")
        os.environ.setdefault(key, value)


def load_config():
    load_env_file(os.environ.get("CHROME_CDP_ENV_FILE", ".env"))
    host = os.environ.get("CHROME_CDP_HOST", "").strip()
    if host not in {"127.0.0.1", "localhost", "::1"}:
        raise ValueError("CHROME_CDP_HOST must be a loopback host")
    try:
        port = int(os.environ.get("CHROME_CDP_PORT", ""))
        timeout = float(os.environ.get("CHROME_CDP_TIMEOUT_SECONDS", ""))
    except ValueError as exc:
        raise ValueError("Port must be an integer and timeout must be numeric") from exc
    if not 1 <= port <= 65535:
        raise ValueError("CHROME_CDP_PORT must be between 1 and 65535")
    if timeout <= 0:
        raise ValueError("CHROME_CDP_TIMEOUT_SECONDS must be positive")
    return host, port, timeout


def fetch_targets(host, port, timeout):
    url = f"http://{host}:{port}/json/list"
    with urllib.request.urlopen(url, timeout=timeout) as response:
        targets = json.load(response)
    if not isinstance(targets, list):
        raise ValueError("CDP /json/list did not return a list")
    return targets


def stop_target(target, timeout, request_id):
    if not isinstance(target, dict):
        raise ValueError("Target entry is not an object")
    ws_url = target.get("webSocketDebuggerUrl")
    if not isinstance(ws_url, str) or not ws_url.startswith(("ws://", "wss://")):
        raise ValueError("Page target has no valid webSocketDebuggerUrl")
    connection = websocket.create_connection(ws_url, timeout=timeout, suppress_origin=True)
    try:
        connection.send(json.dumps({"id": request_id, "method": "Page.stopLoading"}))
        while True:
            message = json.loads(connection.recv())
            if isinstance(message, dict) and message.get("id") == request_id:
                if "error" in message:
                    raise RuntimeError(f"CDP error: {message['error']}")
                return
    finally:
        connection.close()


def main():
    try:
        host, port, timeout = load_config()
        targets = fetch_targets(host, port, timeout)
    except Exception as exc:
        print(f"Discovery failed: {exc}", file=sys.stderr)
        return 1
    page_targets = [target for target in targets if isinstance(target, dict) and target.get("type") == "page"]
    failures = 0
    for index, target in enumerate(page_targets, start=1):
        try:
            stop_target(target, timeout, index)
        except Exception as exc:
            failures += 1
            title = target.get("title") or target.get("url") or target.get("id") or "unknown target"
            print(f"Failed: {title}: {exc}", file=sys.stderr)
    stopped = len(page_targets) - failures
    print(f"Stopped loading on {stopped} of {len(page_targets)} page targets.")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
