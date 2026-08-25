#!/system/bin/sh
# Inputs: BACKUP_DIR naming a promotion backup containing dropbear and 90-dropbear-sshd.sh; current port 22 PID file.
# Outputs: restored original Dropbear binary and boot service, restarted port 22 process, and rollback result.
# Processing: validates the requested backup, stops the current port 22 process, restores only files captured by promotion, and runs the restored service.
set -eu
[ -n "${BACKUP_DIR:-}" ] || { echo 'ERROR: set BACKUP_DIR=/data/ssh-backup-before-sftp-YYYYMMDD-HHMMSS' >&2; exit 1; }
[ -f "$BACKUP_DIR/dropbear" ] || { echo 'ERROR: backup dropbear missing' >&2; exit 1; }
[ -f "$BACKUP_DIR/90-dropbear-sshd.sh" ] || { echo 'ERROR: backup service missing' >&2; exit 1; }
if [ -f /data/ssh/dropbear.pid ]; then pid=$(cat /data/ssh/dropbear.pid 2>/dev/null || true); [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; rm -f /data/ssh/dropbear.pid; fi
cp "$BACKUP_DIR/dropbear" /data/ssh/dropbear
cp "$BACKUP_DIR/90-dropbear-sshd.sh" /data/adb/service.d/90-dropbear-sshd.sh
chown 0:0 /data/ssh/dropbear /data/adb/service.d/90-dropbear-sshd.sh
chmod 755 /data/ssh/dropbear /data/adb/service.d/90-dropbear-sshd.sh
/system/bin/sh /data/adb/service.d/90-dropbear-sshd.sh
sleep 2
pid=$(cat /data/ssh/dropbear.pid 2>/dev/null || true)
[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || { echo 'ERROR: restored server did not start' >&2; exit 1; }
echo "PASS: restored original Dropbear from $BACKUP_DIR with pid $pid"
