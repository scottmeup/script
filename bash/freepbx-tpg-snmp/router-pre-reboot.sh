logger -t tpg-ip-test "START router reboot/IP-change test $(date -Is)"
/root/tpg-state-snapshot.sh | tee /root/tpg-state-before-router-reboot.txt