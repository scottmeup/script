#!/system/bin/sh
# Inputs: validated /data/ssh-candidate tree; current /data/ssh/dropbear and /data/adb/service.d/90-dropbear-sshd.sh; explicit PROMOTE=YES environment value.
# Outputs: new /data/ssh Dropbear/SFTP files, updated boot service, timestamped backup directory, restarted port 22 server, and promotion result.
# Functions: fail exits; stop_pid stops a PID-file process; rollback restores the timestamped backup and restarts the original service.
# Processing: refuses promotion without explicit opt-in, backs up every replaced file, installs candidate components atomically where possible, removes the forced-command option from the generated service, starts port 22, and automatically rolls back if it fails.
set -eu
[ "${PROMOTE:-}" = YES ] || { echo 'ERROR: run with PROMOTE=YES only after port 2222 tests pass' >&2; exit 1; }
C=/data/ssh-candidate
D=/data/ssh
SERVICE=/data/adb/service.d/90-dropbear-sshd.sh
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=/data/ssh-backup-before-sftp-$STAMP
fail(){ echo "ERROR: $*" >&2; exit 1; }
stop_pid(){ file=$1; [ -f "$file" ] || return 0; pid=$(cat "$file" 2>/dev/null || true); [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; rm -f "$file"; }
[ -x "$C/dropbear" ] || fail 'candidate binary missing'
[ -x "$C/libexec/sftp-server-wrapper" ] || fail 'candidate SFTP wrapper missing'
mkdir -p "$BACKUP"
cp -a "$D/dropbear" "$D/dropbear_host_ed25519" "$D/authorized_keys" "$BACKUP/"
cp -a "$SERVICE" "$BACKUP/90-dropbear-sshd.sh"
[ -f "$D/session-wrapper.sh" ] && cp -a "$D/session-wrapper.sh" "$BACKUP/"
stop_pid "$C/dropbear.pid"
stop_pid "$D/dropbear.pid"
mkdir -p "$D/libexec" "$D/lib"
cp "$C/dropbear" "$D/dropbear.new"
cp "$C/libexec/sftp-server" "$D/libexec/sftp-server"
cp "$C/lib/libandroid-support.so" "$D/lib/libandroid-support.so"
sed 's#/data/ssh-candidate#/data/ssh#g' "$C/libexec/sftp-server-wrapper" > "$D/libexec/sftp-server-wrapper"
chown 0:0 "$D/dropbear.new" "$D/libexec/sftp-server" "$D/libexec/sftp-server-wrapper" "$D/lib/libandroid-support.so"
chmod 755 "$D/dropbear.new" "$D/libexec/sftp-server" "$D/libexec/sftp-server-wrapper" "$D/lib/libandroid-support.so"
mv "$D/dropbear.new" "$D/dropbear"
cat > /data/local/bin/dropbear-sftp-server <<'STABLE_WRAPPER'
#!/system/bin/sh
# Inputs: SSH subsystem channel and promoted SFTP files.
# Outputs: SFTP protocol on the inherited channel.
# Processing: dispatches the compiled Dropbear subsystem path to the promoted wrapper.
exec /data/ssh/libexec/sftp-server-wrapper
STABLE_WRAPPER
chown 0:0 /data/local/bin/dropbear-sftp-server
chmod 755 /data/local/bin/dropbear-sftp-server
cat > "$SERVICE.new" <<'SERVICE_EOF'
#!/system/bin/sh
# Inputs: persistent Dropbear binary, host key, authorized_keys, relocated SFTP files, and writable /dev.
# Outputs: /dev/dropbear/authorized_keys, /data/ssh/dropbear.pid, /data/ssh/dropbear.log, and TCP port 22.
# Processing: recreates strict runtime authentication state and starts rebuilt Dropbear without a forced command because PATH and SFTP are compiled into the binary.
D=/data/ssh
R=/dev/dropbear
count=0
while [ "$count" -lt 60 ]; do [ -x "$D/dropbear" ] && [ -f "$D/dropbear_host_ed25519" ] && [ -f "$D/authorized_keys" ] && break; sleep 1; count=$((count + 1)); done
[ -x "$D/dropbear" ] && [ -f "$D/dropbear_host_ed25519" ] && [ -f "$D/authorized_keys" ] || exit 1
mkdir -p "$R" || exit 1
cp "$D/authorized_keys" "$R/authorized_keys" || exit 1
chown 0:0 "$R" "$R/authorized_keys" || exit 1
chmod 700 "$R" || exit 1
chmod 600 "$R/authorized_keys" || exit 1
if [ -f "$D/dropbear.pid" ]; then pid=$(cat "$D/dropbear.pid" 2>/dev/null); [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && exit 0; rm -f "$D/dropbear.pid"; fi
"$D/dropbear" -E -p 22 -P "$D/dropbear.pid" -r "$D/dropbear_host_ed25519" -D "$R" >> "$D/dropbear.log" 2>&1
SERVICE_EOF
chown 0:0 "$SERVICE.new"
chmod 755 "$SERVICE.new"
mv "$SERVICE.new" "$SERVICE"
/system/bin/sh "$SERVICE"
sleep 2
pid=$(cat "$D/dropbear.pid" 2>/dev/null || true)
if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    cp "$BACKUP/dropbear" "$D/dropbear"
    cp "$BACKUP/90-dropbear-sshd.sh" "$SERVICE"
    /system/bin/sh "$SERVICE"
    fail "promotion failed and original service was restored from $BACKUP"
fi
printf 'PASS: promoted rebuilt Dropbear to port 22\nbackup=%s\npid=%s\n' "$BACKUP" "$pid"
