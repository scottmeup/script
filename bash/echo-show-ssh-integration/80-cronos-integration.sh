#!/system/bin/sh
# Inputs: /data/adb/cronos-integration/cronos-integration.env and script-mirror-daemon.sh; installed com.termux package.
# Outputs: source directories, runtime mirrors, background mirror daemon, and boot log.
# Processing: dynamically derives the Termux UID/GID and SELinux category context, creates sources, exports daemon configuration, and starts one daemon instance.
set -u
BASE=/data/adb/cronos-integration
ENV_FILE=$BASE/cronos-integration.env
DAEMON=$BASE/script-mirror-daemon.sh
LOG=/data/local/tmp/cronos-integration-boot.log
[ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE" >> "$LOG"; exit 1; }
. "$ENV_FILE"
TERMUX_UID=$(stat -c %u /data/data/com.termux 2>/dev/null)
TERMUX_GID=$(stat -c %g /data/data/com.termux 2>/dev/null)
TERMUX_SECONTEXT=$(ls -Zd /data/data/com.termux 2>/dev/null | grep -o 'u:object_r:[^ ]*' | head -n 1)
[ -n "$TERMUX_UID" ] && [ -n "$TERMUX_GID" ] && [ -n "$TERMUX_SECONTEXT" ] || { echo 'Termux identity resolution failed' >> "$LOG"; exit 1; }
mkdir -p "$ROOT_SOURCE" "$USER_SOURCE"
if [ -f /data/local/tmp/cronos-script-mirror.pid ]; then
    pid=$(cat /data/local/tmp/cronos-script-mirror.pid 2>/dev/null)
    if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] && tr '\000' ' ' < "/proc/$pid/cmdline" | grep -q "$DAEMON"; then
        exit 0
    fi
fi
export ROOT_SOURCE USER_SOURCE ROOT_RUNTIME USER_RUNTIME POLL_SECONDS TERMUX_UID TERMUX_GID TERMUX_SECONTEXT
"$DAEMON" >> /data/local/tmp/cronos-script-mirror-daemon.log 2>&1 &
echo $! > /data/local/tmp/cronos-script-mirror.pid
echo "started pid=$! uid=$TERMUX_UID context=$TERMUX_SECONTEXT" >> "$LOG"
