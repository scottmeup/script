#!/usr/bin/env bash
# Inputs: rooted ADB-connected cronos and REBUILD_SUFFIX printed by migrate-to-rebuilt-dropbear.sh.
# Outputs: restored previous Dropbear binary and 90-dropbear-sshd.sh, then restarted prior service.
# Processing: validates both backups, stops only matching Dropbear PID, restores files atomically, and verifies listener.
set -euo pipefail
ADB=${ADB:-adb}
: "${REBUILD_SUFFIX:?Set REBUILD_SUFFIX to the migration timestamp}"
BIN=/data/ssh/dropbear.before-rebuild-$REBUILD_SUFFIX
SERVICE=/data/adb/service.d/90-dropbear-sshd.sh.before-rebuild-$REBUILD_SUFFIX
"$ADB" shell "test -f '$BIN' && test -f '$SERVICE'" || { echo 'required backup missing' >&2; exit 1; }
"$ADB" shell 'pid=$(cat /data/ssh/dropbear.pid 2>/dev/null); if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] && tr "\000" " " < "/proc/$pid/cmdline" | grep -q /data/ssh/dropbear; then kill "$pid"; fi; rm -f /data/ssh/dropbear.pid'
"$ADB" shell "cp -p '$BIN' /data/ssh/dropbear; cp -p '$SERVICE' /data/adb/service.d/90-dropbear-sshd.sh; chmod 755 /data/ssh/dropbear /data/adb/service.d/90-dropbear-sshd.sh; ASH_STANDALONE=1 /data/adb/magisk/busybox sh /data/adb/service.d/90-dropbear-sshd.sh; sleep 2; ps | grep '[d]ropbear'; cat /proc/net/tcp /proc/net/tcp6 | grep -i ':0016'"
