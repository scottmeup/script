ROUTER_IP="192.168.1.1"
COMMUNITY="FigureStencil3Parka"

DEV_IP="$(ip -4 route get "$ROUTER_IP" | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')"
echo "This machine IP is: $DEV_IP"
echo "Set the router Trap Manager IP to: $DEV_IP if testing traps from this machine."

sudo systemctl stop snmptrapd.service snmptrapd.socket 2>/dev/null || true
sudo systemctl stop snmpd.service 2>/dev/null || true

echo "Ports currently using UDP 161/162:"
sudo ss -lunp | egrep ':161|:162' || true

echo
echo "Testing SNMP v2c basic sysDescr:"
MIBS= snmpget -On -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.1.1.0

echo
echo "Testing SNMP v1 basic sysDescr:"
MIBS= snmpget -On -v1 -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.1.1.0

echo
echo "Testing packet-level SNMP request/reply visibility:"
sudo timeout 8 tcpdump -ni any "host $ROUTER_IP and udp port 161" &
TCPDUMP_PID=$!
sleep 1
MIBS= snmpget -On -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.1.1.0 || true
sleep 2
wait "$TCPDUMP_PID" || true

echo
echo "If SNMP replies work, walk interface names:"
MIBS= snmpwalk -On -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.2.2.1.2

echo
echo "If SNMP replies work, walk IP address table:"
MIBS= snmpwalk -On -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.4.20.1

echo
echo "Starting trap listener for 180 seconds."
echo "While this runs, save/apply SNMP settings on the router, or reboot router if acceptable."
cat > /tmp/snmptrapd-test.conf <<EOF
authCommunity log,execute,net $COMMUNITY
disableAuthorization no
EOF

sudo timeout 180 env MIBS= snmptrapd -f -Lo -n -C -c /tmp/snmptrapd-test.conf

rm -f /tmp/snmptrapd-test.conf