ROUTER_IP="192.168.1.1"
COMMUNITY="YOUR_COMMUNITY_HERE"

WAN_IFINDEX="$(MIBS= snmpwalk -On -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.2.2.1.2 | awk -F'[.= ]+' '/STRING: "ppp3"/ {print $12}')"

WAN_IP="$(MIBS= snmpwalk -On -v2c -c "$COMMUNITY" "$ROUTER_IP" 1.3.6.1.2.1.4.20.1.2 | awk -v idx="$WAN_IFINDEX" '$NF == idx { sub(/^.*1\.3\.6\.1\.2\.1\.4\.20\.1\.2\./, "", $1); print $1 }')"

echo "WAN_IFINDEX=$WAN_IFINDEX"
echo "WAN_IP=$WAN_IP"

mysql -u root asterisk -e "SELECT * FROM kvstore_Sipsettings WHERE \`key\`='externip';"

asterisk -rx "pjsip show transport 0.0.0.0-udp" | grep -E "external_media_address|external_signaling_address"