echo "=== time ==="
date -Is

echo
echo "=== snmptrapd status ==="
systemctl status snmptrapd.service snmptrapd.socket -l --no-pager

echo
echo "=== UDP 162 listener ==="
ss -lunp | grep ':162' || true

echo
echo "=== trap config mode ==="
sed -n '1,120p' /etc/freepbx-wanip-traps/freepbx-wanip-traps.env | sed -E 's/(COMMUNITY|PASSWORD|SECRET|TOKEN|KEY)=.*/\1=REDACTED/I'

echo
echo "=== snmptrapd config relevant lines ==="
awk '
  index($0, "FREEPBX-WANIP") > 0 { print NR ":" $0; next }
  index($0, "traphandle") > 0 { print NR ":" $0; next }
  index($0, "authCommunity") > 0 { print NR ":authCommunity REDACTED"; next }
' /etc/snmp/snmptrapd.conf

echo
echo "=== recent trap handler journal ==="
journalctl -t freepbx-wanip-trap -n 50 --no-pager

echo
echo "=== trap log directory ==="
ls -lah /var/log/freepbx-wanip-traps/

echo
echo "=== trap log tail ==="
tail -n 120 /var/log/freepbx-wanip-traps/tplink-snmptraps.log