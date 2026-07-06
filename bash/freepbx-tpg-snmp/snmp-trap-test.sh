mkdir -p /etc/freepbx-wanip-traps
cat > /etc/freepbx-wanip-traps/freepbx-wanip-traps.env <<'EOF'
SNMP_COMMUNITY=REPLACE_WITH_YOUR_SNMP_COMMUNITY
TRAP_LOG_FILE=/var/log/freepbx-wanip-traps/tplink-snmptraps.log
TRAP_LOG_MAX_BYTES=1048576
RUN_HOSTS_UPDATER_ON_TRAP=no
HOSTS_UPDATER=/usr/local/sbin/freepbx-wanip-hosts-update
EOF

chmod 600 /etc/freepbx-wanip-traps/freepbx-wanip-traps.env


cat > /usr/local/sbin/freepbx-wanip-snmptrap-log <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

exec 9>/run/freepbx-wanip-snmptrap-log.lock
flock 9

ENV_FILE=/etc/freepbx-wanip-traps/freepbx-wanip-traps.env

if [ -r "$ENV_FILE" ]; then
  . "$ENV_FILE"
fi

TRAP_LOG_FILE="${TRAP_LOG_FILE:-/var/log/freepbx-wanip-traps/tplink-snmptraps.log}"
TRAP_LOG_MAX_BYTES="${TRAP_LOG_MAX_BYTES:-1048576}"
RUN_HOSTS_UPDATER_ON_TRAP="${RUN_HOSTS_UPDATER_ON_TRAP:-no}"
HOSTS_UPDATER="${HOSTS_UPDATER:-/usr/local/sbin/freepbx-wanip-hosts-update}"

tmp="$(mktemp)"
cat > "$tmp"

logdir="$(dirname "$TRAP_LOG_FILE")"
mkdir -p "$logdir"

if [ -f "$TRAP_LOG_FILE" ]; then
  size="$(stat -c '%s' "$TRAP_LOG_FILE" 2>/dev/null || echo 0)"
  if [ "$size" -gt "$TRAP_LOG_MAX_BYTES" ]; then
    mv -f "$TRAP_LOG_FILE" "$TRAP_LOG_FILE.1"
  fi
fi

{
  echo "===== SNMP TRAP $(date -Is) ====="
  echo "handler_user=$(id -un)"
  echo "handler_uid=$(id -u)"
  echo "args=$*"
  echo "--- payload ---"
  cat "$tmp"
  echo
} >> "$TRAP_LOG_FILE"

logger -t freepbx-wanip-trap "SNMP trap logged to $TRAP_LOG_FILE"

if [ "$RUN_HOSTS_UPDATER_ON_TRAP" = "yes" ] && [ -x "$HOSTS_UPDATER" ]; then
  "$HOSTS_UPDATER" || logger -t freepbx-wanip-trap "hosts updater failed after SNMP trap"
fi

rm -f "$tmp"
EOF

chmod 700 /usr/local/sbin/freepbx-wanip-snmptrap-log

SNMPD_USER="$(getent passwd Debian-snmp >/dev/null && echo Debian-snmp || echo root)"

mkdir -p /var/log/freepbx-wanip-traps
touch /var/log/freepbx-wanip-traps/tplink-snmptraps.log

chown -R "$SNMPD_USER":adm /var/log/freepbx-wanip-traps
chmod 750 /var/log/freepbx-wanip-traps
chmod 640 /var/log/freepbx-wanip-traps/tplink-snmptraps.log

CONF=/etc/snmp/snmptrapd.conf
ENV_FILE=/etc/freepbx-wanip-traps/freepbx-wanip-traps.env

. "$ENV_FILE"

case "$SNMP_COMMUNITY" in
  ""|REPLACE_WITH_YOUR_SNMP_COMMUNITY)
    echo "Set SNMP_COMMUNITY in $ENV_FILE first"
    exit 1
    ;;
esac

cp -a "$CONF" "$CONF.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

tmp="$(mktemp)"

if [ -f "$CONF" ]; then
  awk '
    /# BEGIN FREEPBX-WANIP-TRAP-LOGGER/ { skip=1; next }
    /# END FREEPBX-WANIP-TRAP-LOGGER/ { skip=0; next }
    skip != 1 { print }
  ' "$CONF" > "$tmp"
else
  : > "$tmp"
fi

cat >> "$tmp" <<EOF

# BEGIN FREEPBX-WANIP-TRAP-LOGGER
disableAuthorization no
authCommunity log,execute,net $SNMP_COMMUNITY
traphandle default /usr/local/sbin/freepbx-wanip-snmptrap-log
# END FREEPBX-WANIP-TRAP-LOGGER
EOF

install -o root -g root -m 644 "$tmp" "$CONF"
rm -f "$tmp"


chown root:Debian-snmp /usr/local/sbin/freepbx-wanip-snmptrap-log
chmod 750 /usr/local/sbin/freepbx-wanip-snmptrap-log

chown root:Debian-snmp /etc/freepbx-wanip-traps/freepbx-wanip-traps.env
chmod 640 /etc/freepbx-wanip-traps/freepbx-wanip-traps.env

chmod 750 /etc/freepbx-wanip-traps


systemctl stop snmptrapd.service snmptrapd.socket 2>/dev/null || true
systemctl daemon-reload
systemctl enable --now snmptrapd.socket
systemctl restart snmptrapd.socket

ss -lunp | grep ':162'

. /etc/freepbx-wanip-traps/freepbx-wanip-traps.env

snmptrap -v2c -c "$SNMP_COMMUNITY" 127.0.0.1 '' 1.3.6.1.6.3.1.1.5.1

sleep 2

tail -n 50 /var/log/freepbx-wanip-traps/tplink-snmptraps.log

# run this in another terminal at the same time as tcpdump while restarting the snmp device
# tail -f /var/log/freepbx-wanip-traps/tplink-snmptraps.log

tcpdump -ni any udp port 162