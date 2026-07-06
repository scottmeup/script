ROUTER_IP="192.168.1.1"
COMMUNITY="REPLACE_WITH_YOUR_SNMP_COMMUNITY"

apt update
apt install -y snmp snmptrapd

echo "=== SNMP basic system test ==="
snmpget -v2c -c "$COMMUNITY" "$ROUTER_IP" \
  1.3.6.1.2.1.1.1.0 \
  1.3.6.1.2.1.1.3.0 \
  1.3.6.1.2.1.1.5.0

echo
echo "=== Interface names/descriptions ==="
snmpwalk -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.2.2.1.2
snmpwalk -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.31.1.1.1.1
snmpwalk -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.31.1.1.1.18

echo
echo "=== Interface operational status ==="
snmpwalk -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.2.2.1.8

echo
echo "=== IPv4 address table, legacy MIB ==="
snmpwalk -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.4.20.1

echo
echo "=== IPv4/IPv6 address table, newer MIB if supported ==="
snmpwalk -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.4.34.1

echo
echo "=== Route table, if exposed ==="
snmpwalk -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.4.21.1

echo
echo "=== Current known public IP from outside, for comparison ==="
curl -fsS https://www.cloudflare.com/cdn-cgi/trace | awk -F= '/^ip=/{print $2}'

echo
echo "=== Starting temporary SNMP trap listener for 180 seconds ==="
echo "While this is running, go to the router and save/apply SNMP settings, or reboot the router if safe."
cat > /tmp/snmptrapd-test.conf <<EOF
authCommunity log,execute,net $COMMUNITY
disableAuthorization no
EOF
timeout 180 snmptrapd -f -Lo -n -C -c /tmp/snmptrapd-test.conf
rm -f /tmp/snmptrapd-test.conf