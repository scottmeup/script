#!/usr/bin/env bash

set -e

required_packages=(
    xvfb
    x11vnc
    fluxbox
    dbus-x11
    fonts-liberation
    libnss3
    libatk-bridge2.0-0
    libgtk-3-0
    libxss1
    libasound2
)

missing_packages=()

for pkg in "${required_packages[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        missing_packages+=("$pkg")
    fi
done

if [ "${#missing_packages[@]}" -gt 0 ]; then
    echo "Missing packages detected:"
    printf '  %s\n' "${missing_packages[@]}"

    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get install -y "${missing_packages[@]}"
fi

debug=0

export DISPLAY=:99

Xvfb :99 -screen 0 1366x768x24 >/tmp/xvfb.log 2>&1 &
fluxbox >/tmp/fluxbox.log 2>&1 &
x11vnc -display :99 -forever -shared -rfbport 5900 -nopw >/tmp/x11vnc.log 2>&1 &

Xvfb :99 -screen 0 1366x768x24 >/tmp/xvfb.log 2>&1 &

for i in {1..30}; do
    if xdpyinfo -display :99 >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

if [ "$debug" -eq 1 ]; then
    ps -ef | grep -E 'Xvfb|fluxbox|x11vnc' | grep -v grep
fi

cmd_args=("$@")

if [ "${#cmd_args[@]}" -eq 0 ]; then
    echo "No command specified."
    exit 0
fi

exec "$@"