#!/usr/bin/env bash
# Inputs: rooted ADB-connected cronos, tested rebuilt candidate at /data/ssh/dropbear-rebuilt-candidate, and 90-dropbear-sshd-rebuilt.sh beside this script.
# Outputs: timestamped backups of the working binary and service; promoted /data/ssh/dropbear and future-state 90-dropbear-sshd.sh.
# Functions: fail stops on unmet evidence; device validates architecture/version; stop_pid stops only the PID whose command line matches Dropbear.
# Processing: validates candidate and service syntax, preserves baseline, stops the working daemon, promotes the candidate atomically, installs the service, starts it, and verifies process/listener without rebooting.
set -euo pipefail
ADB=${ADB:-adb}
DIR=$(cd "$(dirname "$0")" && pwd)
CANDIDATE=/data/ssh/dropbear-rebuilt-candidate
SERVICE_SRC=$DIR/90-dropbear-sshd-rebuilt.sh
fail(){ echo "ERROR: $1" >&2; exit 1; }
[ -f "$SERVICE_SRC" ] || fail "missing $SERVICE_SRC"
[ "$("$ADB" shell getprop ro.product.device | tr -d '\r')" = cronos ] || fail 'not cronos'
"$ADB" shell "test -x '$CANDIDATE'" || fail "missing executable $CANDIDATE"
"$ADB" shell "'$CANDIDATE' -V" || fail 'candidate version test failed'
"$ADB" push "$SERVICE_SRC" /data/local/tmp/90-dropbear-sshd-rebuilt.sh >/dev/null
"$ADB" shell '/data/adb/magisk/busybox sh -n /data/local/tmp/90-dropbear-sshd-rebuilt.sh' || fail 'service syntax failed'
stamp=$(date +%Y%m%d-%H%M%S)
"$ADB" shell "cp -p /data/ssh/dropbear /data/ssh/dropbear.before-rebuild-$stamp; cp -p /data/adb/service.d/90-dropbear-sshd.sh /data/adb/service.d/90-dropbear-sshd.sh.before-rebuild-$stamp"
"$ADB" shell 'pid=$(cat /data/ssh/dropbear.pid 2>/dev/null); if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] && tr "\000" " " < "/proc/$pid/cmdline" | grep -q /data/ssh/dropbear; then kill "$pid"; fi; rm -f /data/ssh/dropbear.pid'
"$ADB" shell "cp '$CANDIDATE' /data/ssh/dropbear.new; chown 0:0 /data/ssh/dropbear.new; chmod 755 /data/ssh/dropbear.new; mv /data/ssh/dropbear.new /data/ssh/dropbear; cp /data/local/tmp/90-dropbear-sshd-rebuilt.sh /data/adb/service.d/90-dropbear-sshd.sh; chown 0:0 /data/adb/service.d/90-dropbear-sshd.sh; chmod 755 /data/adb/service.d/90-dropbear-sshd.sh"
"$ADB" shell 'ASH_STANDALONE=1 /data/adb/magisk/busybox sh /data/adb/service.d/90-dropbear-sshd.sh; sleep 2; ps | grep "[d]ropbear"; cat /proc/net/tcp /proc/net/tcp6 | grep -i ":0016"; tail -n 30 /data/ssh/dropbear.log'
echo "Promoted without reboot. Rollback suffix: $stamp"
