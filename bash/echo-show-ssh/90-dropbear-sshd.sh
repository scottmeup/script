#!/system/bin/sh
#
# Install this file to /data/adb/service.d/90-dropbear-sshd.sh
#
# File role:
# - Starts the existing Dropbear SSH daemon during Magisk late_start boot processing.
#
# Inputs:
# - /data/ssh/dropbear: executable 32-bit ARM Android Dropbear server binary.
# - /data/ssh/dropbear_host_ed25519: persistent Ed25519 host private key.
# - /data/ssh/authorized_keys: persistent OpenSSH authorized-keys file, one public key per line.
# - /dev: writable boot-time tmpfs whose root-owned parent path passes Dropbear permission checks.
# - TCP port 22: listening port; it must not already be occupied by another service.
#
# Processing:
# - Waits up to 60 seconds for the persistent Dropbear files under /data/ssh.
# - Recreates /dev/dropbear after every boot because /dev is temporary.
# - Copies authorized_keys to /dev/dropbear and applies strict root ownership and permissions.
# - Removes a stale PID file only when it does not identify a running process.
# - Starts Dropbear in background mode without a forced-command wrapper.
#
# Outputs and side effects:
# - /dev/dropbear/authorized_keys: runtime key file used for authentication.
# - /data/ssh/dropbear.pid: PID file created by Dropbear.
# - /data/ssh/dropbear.log: appended startup and daemon diagnostics.
# - TCP port 22: accepts public-key SSH connections on available interfaces.
#
# Top-level variables:
# - DROPBEAR_DIR: persistent configuration directory.
# - DROPBEAR_BIN: existing Dropbear server executable.
# - HOST_KEY: persistent SSH host private key.
# - AUTH_SOURCE: persistent authorized-keys source file.
# - AUTH_RUNTIME_DIR: runtime directory whose parent chain passes Dropbear checks.
# - PID_FILE: daemon process ID file.
# - LOG_FILE: persistent diagnostics file.
# - SESSION_WRAPPER_FILE: sets path correctly for ssh clients

DROPBEAR_DIR=/data/
DROPBEAR_BIN=/data/ssh/dropbear
HOST_KEY=/data/ssh/dropbear_host_ed25519
AUTH_SOURCE=/data/ssh/authorized_keys
AUTH_RUNTIME_DIR=/dev/dropbear
PID_FILE=/data/ssh/dropbear.pid
LOG_FILE=/data/ssh/dropbear.log
SESSION_WRAPPER_FILE=/data/ssh/session-wrapper.sh

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
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        exit 0
    fi
    rm -f "$PID_FILE"
fi

"$DROPBEAR_BIN" \
    -E \
    -p 22 \
    -P "$PID_FILE" \
    -r "$HOST_KEY" \
    -D "$AUTH_RUNTIME_DIR" \
    -c "$SESSION_WRAPPER_FILE" \
    >> "$LOG_FILE" 2>&1
