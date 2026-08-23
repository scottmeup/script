#!/system/bin/sh
# Inputs: rebuilt /data/ssh/dropbear with Echo DEFAULT_ROOT_PATH and SFTP subsystem path; persistent host key and authorized_keys; Termux libraries under its prefix.
# Outputs: /dev/dropbear/authorized_keys, /data/ssh/dropbear.pid, /data/ssh/dropbear.log, and root SSH/SFTP service on TCP port 22.
# Processing: waits for required files, recreates secure runtime authentication data, validates stale PID ownership, exports Android/Termux child environment, and starts rebuilt Dropbear with -e and no forced-command wrapper.
# Globals: DROPBEAR_BIN, HOST_KEY, AUTH_SOURCE, AUTH_RUNTIME_DIR, PID_FILE, LOG_FILE, TERMUX_PREFIX.
DROPBEAR_BIN=/data/ssh/dropbear
HOST_KEY=/data/ssh/dropbear_host_ed25519
AUTH_SOURCE=/data/ssh/authorized_keys
AUTH_RUNTIME_DIR=/dev/dropbear
PID_FILE=/data/ssh/dropbear.pid
LOG_FILE=/data/ssh/dropbear.log
TERMUX_PREFIX=/data/data/com.termux/files/usr
count=0
while [ "$count" -lt 60 ]; do
    if [ -x "$DROPBEAR_BIN" ] && [ -f "$HOST_KEY" ] && [ -f "$AUTH_SOURCE" ]; then
        break
    fi
    sleep 1
    count=$((count + 1))
done
if [ ! -x "$DROPBEAR_BIN" ] || [ ! -f "$HOST_KEY" ] || [ ! -f "$AUTH_SOURCE" ]; then
    echo "Dropbear startup failed: required file missing after 60 seconds" >> "$LOG_FILE"
    exit 1
fi
mkdir -p "$AUTH_RUNTIME_DIR" || exit 1
cp "$AUTH_SOURCE" "$AUTH_RUNTIME_DIR/authorized_keys" || exit 1
chown 0:0 "$AUTH_RUNTIME_DIR" "$AUTH_RUNTIME_DIR/authorized_keys" || exit 1
chmod 700 "$AUTH_RUNTIME_DIR" || exit 1
chmod 600 "$AUTH_RUNTIME_DIR/authorized_keys" || exit 1
if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ]; then
        cmdline=$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
        case "$cmdline" in
            *"$DROPBEAR_BIN"*) exit 0 ;;
        esac
    fi
    rm -f "$PID_FILE"
fi
export PATH=/sbin:/system/sbin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin:/data/adb/magisk:/data/local/bin:/dev/script:/dev/user-script:$TERMUX_PREFIX/bin
export HOME=/
export SHELL=/system/bin/sh
export USER=root
export LOGNAME=root
export ANDROID_ROOT=/system
export ANDROID_DATA=/data
export EXTERNAL_STORAGE=/sdcard
export TMPDIR=/data/local/tmp
export PREFIX=$TERMUX_PREFIX
export LD_LIBRARY_PATH=$TERMUX_PREFIX/lib
export LD_PRELOAD=$TERMUX_PREFIX/lib/libtermux-exec-ld-preload.so
"$DROPBEAR_BIN" \
    -e \
    -E \
    -p 22 \
    -P "$PID_FILE" \
    -r "$HOST_KEY" \
    -D "$AUTH_RUNTIME_DIR" \
    >> "$LOG_FILE" 2>&1
