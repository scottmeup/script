mkdir -p /etc/freepbx-wanip-hosts /usr/local/sbin

cat > /etc/freepbx-wanip-hosts/freepbx-wanip-hosts.env <<'EOF'
ROUTER_IP=192.168.1.1
SNMP_COMMUNITY=REPLACE_WITH_YOUR_SNMP_COMMUNITY
WAN_IFNAME=ppp3
HOST_ALIAS=public.ip.address
TRUNK_NAME=TPG-VoIP
FORCE_REGISTER=yes
EOF

chmod 600 /etc/freepbx-wanip-hosts/freepbx-wanip-hosts.env

cat > /usr/local/sbin/freepbx-wanip-hosts-update <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

. /etc/freepbx-wanip-hosts/freepbx-wanip-hosts.env

exec 9>/run/freepbx-wanip-hosts-update.lock
flock -n 9 || exit 0

wan_ifindex="$(
  MIBS= snmpwalk -On -v2c -c "$SNMP_COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.2.2.1.2 |
  awk -v name="$WAN_IFNAME" '$0 ~ " = STRING: \"" name "\"$" { n=$1; sub(/^.*\./, "", n); print n; exit }'
)"

if [ -z "$wan_ifindex" ]; then
  logger -t freepbx-wanip-hosts "could not find SNMP interface index for $WAN_IFNAME"
  exit 1
fi

wan_ip="$(
  MIBS= snmpwalk -On -v2c -c "$SNMP_COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.4.20.1.2 |
  awk -v idx="$wan_ifindex" '$NF == idx { n=$1; sub(/^\.?1\.3\.6\.1\.2\.1\.4\.20\.1\.2\./, "", n); print n; exit }'
)"

if ! printf '%s\n' "$wan_ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
  logger -t freepbx-wanip-hosts "invalid WAN IP from SNMP: $wan_ip"
  exit 2
fi

case "$wan_ip" in
  0.*|10.*|127.*|169.254.*|192.168.*|172.16.*|172.17.*|172.18.*|172.19.*|172.20.*|172.21.*|172.22.*|172.23.*|172.24.*|172.25.*|172.26.*|172.27.*|172.28.*|172.29.*|172.30.*|172.31.*)
    logger -t freepbx-wanip-hosts "refusing private/non-public WAN IP: $wan_ip"
    exit 3
    ;;
esac

current_ip="$(
  awk -v host="$HOST_ALIAS" '
    {
      for (i = 2; i <= NF; i++) {
        if ($i == host) {
          print $1
        }
      }
    }
  ' /etc/hosts | tail -n 1
)"

if [ "$current_ip" = "$wan_ip" ]; then
  exit 0
fi

tmpfile="$(mktemp)"

matches="$(
  awk -v host="$HOST_ALIAS" '
    /^[[:space:]]*#/ { next }
    {
      for (i = 2; i <= NF; i++) {
        if ($i == host) {
          count++
        }
      }
    }
    END { print count + 0 }
  ' /etc/hosts
)"

if [ "$matches" -eq 0 ]; then
  logger -t freepbx-wanip-hosts "no active /etc/hosts entry found for $HOST_ALIAS; refusing to add one automatically"
  exit 4
fi

if [ "$matches" -gt 1 ]; then
  logger -t freepbx-wanip-hosts "multiple active /etc/hosts entries found for $HOST_ALIAS; refusing to choose one"
  exit 5
fi

current_ip="$(
  awk -v host="$HOST_ALIAS" '
    /^[[:space:]]*#/ { next }
    {
      for (i = 2; i <= NF; i++) {
        if ($i == host) {
          print $1
          exit
        }
      }
    }
  ' /etc/hosts
)"

if [ "$current_ip" = "$wan_ip" ]; then
  exit 0
fi

cp -a /etc/hosts /etc/hosts.freepbx-wanip.bak

tmpfile="$(mktemp)"

awk -v host="$HOST_ALIAS" -v ip="$wan_ip" '
  /^[[:space:]]*#/ {
    print
    next
  }
  {
    found = 0
    for (i = 2; i <= NF; i++) {
      if ($i == host) {
        found = 1
      }
    }
    if (found) {
      $1 = ip
    }
    print
  }
' /etc/hosts > "$tmpfile"

cat "$tmpfile" > /etc/hosts
rm -f "$tmpfile"

logger -t freepbx-wanip-hosts "updated $HOST_ALIAS from '$current_ip' to '$wan_ip' in /etc/hosts"

if [ "${FORCE_REGISTER:-yes}" = "yes" ]; then
  asterisk -rx "pjsip send register $TRUNK_NAME" >/dev/null 2>&1 || true
fi
EOF

chmod 700 /usr/local/sbin/freepbx-wanip-hosts-update

cat > /etc/systemd/system/freepbx-wanip-hosts-update.service <<'EOF'
[Unit]
Description=Update /etc/hosts public IP alias for FreePBX SIP NAT

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/freepbx-wanip-hosts-update
EOF

cat > /etc/systemd/system/freepbx-wanip-hosts-update.timer <<'EOF'
[Unit]
Description=Run FreePBX public IP hosts updater every 30 seconds

[Timer]
OnBootSec=20
OnUnitActiveSec=30
AccuracySec=5
Unit=freepbx-wanip-hosts-update.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now freepbx-wanip-hosts-update.timer

/usr/local/sbin/freepbx-wanip-hosts-update

grep -n "public.ip.address" /etc/hosts
getent hosts public.ip.address
asterisk -rx "pjsip show transport 0.0.0.0-udp" | grep -E "external_media_address|external_signaling_address"
systemctl status freepbx-wanip-hosts-update.timer --no-pager