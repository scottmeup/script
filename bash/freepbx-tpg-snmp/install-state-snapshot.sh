cat > /root/tpg-state-snapshot.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== time ==="
date -Is

echo
echo "=== /etc/hosts public.ip.address ==="
grep -n "public.ip.address" /etc/hosts || true
getent hosts public.ip.address || true

echo
echo "=== FreePBX/Asterisk registration ==="
asterisk -rx "pjsip show registrations"
echo
asterisk -rx "pjsip show registration TPG-VoIP"

echo
echo "=== Asterisk transport external address ==="
asterisk -rx "pjsip show transport 0.0.0.0-udp" | grep -E "external_media_address|external_signaling_address|local_net" || true

echo
echo "=== Router SNMP WAN view ==="
. /etc/freepbx-wanip-hosts/freepbx-wanip-hosts.env

echo "ROUTER_IP=$ROUTER_IP"
echo "WAN_IFNAME=$WAN_IFNAME"

echo
echo "--- SNMP interfaces ---"
MIBS= snmpwalk -On -v2c -t 2 -r 1 -c "$SNMP_COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.2.2.1.2

echo
echo "--- SNMP IP table ---"
MIBS= snmpwalk -On -v2c -t 2 -r 1 -c "$SNMP_COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.4.20.1

echo
echo "=== updater timer state ==="
systemctl list-timers --all | grep freepbx-wanip || true
systemctl status freepbx-wanip-hosts-update.timer -l --no-pager || true
systemctl status freepbx-wanip-hosts-update.service -l --no-pager || true

echo
echo "=== recent updater logs ==="
journalctl -u freepbx-wanip-hosts-update.service -n 40 --no-pager || true
journalctl -t freepbx-wanip-hosts -n 40 --no-pager || true

echo
echo "=== updater status file ==="
cat /var/lib/freepbx-wanip-hosts/last-status 2>/dev/null || echo "No last-status file"
EOF

chmod 700 /root/tpg-state-snapshot.sh