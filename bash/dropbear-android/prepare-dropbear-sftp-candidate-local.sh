#!/system/bin/sh
# Inputs: /sdcard/dropbear-candidate/dropbear built by the bootstrap project; existing Termux sftp-server and libandroid-support.so; current host key and authorized_keys.
# Outputs: /data/ssh-candidate with Dropbear, SFTP wrapper, SFTP binary, support library, runtime authorized_keys, PID, and log files.
# Functions: fail exits safely; stop_candidate stops only port 2222 candidate state; verify_file checks required inputs.
# Processing: installs an isolated candidate, preserves port 22, starts port 2222 without a forced command, and verifies that its process remains running.
set -eu
CANDIDATE=/data/ssh-candidate
STAGING=/sdcard/dropbear-candidate
TERMUX=/data/data/com.termux/files/usr
PORT=2222
fail(){ echo "ERROR: $*" >&2; exit 1; }
verify_file(){ [ -f "$1" ] || fail "missing $1"; }
stop_candidate(){
    if [ -f "$CANDIDATE/dropbear.pid" ]; then
        pid=$(cat "$CANDIDATE/dropbear.pid" 2>/dev/null || true)
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
        rm -f "$CANDIDATE/dropbear.pid"
    fi
}
verify_file "$STAGING/dropbear"
verify_file "$TERMUX/libexec/sftp-server"
verify_file "$TERMUX/lib/libandroid-support.so"
verify_file /data/ssh/dropbear_host_ed25519
verify_file /data/ssh/authorized_keys
[ ! -e /data/local/bin/dropbear-sftp-server ] || fail "refusing to overwrite existing /data/local/bin/dropbear-sftp-server"
stop_candidate
rm -rf "$CANDIDATE.new"
mkdir -p "$CANDIDATE.new/libexec" "$CANDIDATE.new/lib" "$CANDIDATE.new/auth"
cp "$STAGING/dropbear" "$CANDIDATE.new/dropbear"
cp "$TERMUX/libexec/sftp-server" "$CANDIDATE.new/libexec/sftp-server"
cp "$TERMUX/lib/libandroid-support.so" "$CANDIDATE.new/lib/libandroid-support.so"
cp /data/ssh/dropbear_host_ed25519 "$CANDIDATE.new/dropbear_host_ed25519"
cp /data/ssh/authorized_keys "$CANDIDATE.new/auth/authorized_keys"
cat > "$CANDIDATE.new/libexec/sftp-server-wrapper" <<'WRAPPER'
#!/system/bin/sh
# Inputs: SSH subsystem stdin/stdout and files in /data/ssh-candidate/libexec and /data/ssh-candidate/lib.
# Outputs: OpenSSH SFTP protocol over the inherited SSH channel.
# Processing: supplies Android and relocated-library environment values, then replaces itself with the Termux SFTP server.
export ANDROID_ROOT=/system
export ANDROID_DATA=/data
export EXTERNAL_STORAGE=/sdcard
export TMPDIR=/data/local/tmp
export LD_LIBRARY_PATH=/data/ssh-candidate/lib
exec /data/ssh-candidate/libexec/sftp-server
WRAPPER
chown -R 0:0 "$CANDIDATE.new"
chmod 755 "$CANDIDATE.new" "$CANDIDATE.new/dropbear" "$CANDIDATE.new/libexec" "$CANDIDATE.new/libexec/sftp-server" "$CANDIDATE.new/libexec/sftp-server-wrapper" "$CANDIDATE.new/lib" "$CANDIDATE.new/lib/libandroid-support.so"
chmod 700 "$CANDIDATE.new/auth"
chmod 600 "$CANDIDATE.new/auth/authorized_keys" "$CANDIDATE.new/dropbear_host_ed25519"
cat > /data/local/bin/dropbear-sftp-server <<'STABLE_WRAPPER'
#!/system/bin/sh
# Inputs: SSH subsystem channel and isolated candidate SFTP files.
# Outputs: SFTP protocol on the inherited channel.
# Processing: dispatches the compiled Dropbear subsystem path to the candidate wrapper.
exec /data/ssh-candidate/libexec/sftp-server-wrapper
STABLE_WRAPPER
chown 0:0 /data/local/bin/dropbear-sftp-server
chmod 755 /data/local/bin/dropbear-sftp-server
rm -rf "$CANDIDATE"
mv "$CANDIDATE.new" "$CANDIDATE"
"$CANDIDATE/dropbear" -E -p "$PORT" -P "$CANDIDATE/dropbear.pid" -r "$CANDIDATE/dropbear_host_ed25519" -D "$CANDIDATE/auth" >> "$CANDIDATE/dropbear.log" 2>&1
sleep 2
pid=$(cat "$CANDIDATE/dropbear.pid" 2>/dev/null || true)
[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || fail "candidate did not remain running"
echo "PASS: candidate listening process started on port $PORT with pid $pid"
