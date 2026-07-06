echo "=== time ==="
date -Is

echo
echo "=== hosts ==="
grep -n "public.ip.address" /etc/hosts
getent hosts public.ip.address

echo
echo "=== router SNMP WAN ==="
. /etc/freepbx-wanip-hosts/freepbx-wanip-hosts.env
MIBS= snmpwalk -On -v2c -t 2 -r 1 -c "$SNMP_COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.2.2.1.2
echo
MIBS= snmpwalk -On -v2c -t 2 -r 1 -c "$SNMP_COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.4.20.1

echo
echo "=== registration ==="
asterisk -rx "pjsip show registrations"
asterisk -rx "pjsip show registration TPG-VoIP"

echo
echo "=== transport ==="
asterisk -rx "pjsip show transport 0.0.0.0-udp" | grep -E "external_media_address|external_signaling_address|local_net"

echo
echo "=== monitors ==="
systemctl status tpg-sip-pcap.service -l --no-pager
systemctl status tpg-sip-error-monitor.service -l --no-pager