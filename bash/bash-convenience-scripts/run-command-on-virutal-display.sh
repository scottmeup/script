#!/usr/bin/env bash

set -e
debug=0

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

log_files=(
    /tmp/fluxbox.log
    /tmp/xvfb.log
    /tmp/x11vnc.log
)

for pkg in "${required_packages[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        missing_packages+=("$pkg")
    fi
done

if [ "${#missing_packages[@]}" -gt 0 ]; then
    echo "Missing packages detected:"
    printf '  %s\n' "${missing_packages[@]}"

    export DEBIAN_FRONTEND=noninteractive

    sudo apt-get update
    sudo apt-get install -y "${missing_packages[@]}"
fi

clear_log_files(){
    for file in "$log_files"; do
        if [ -f "$file" ]; then
            rm "$file"
        fi
    done
}

clear_log_files

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

clear_log_files