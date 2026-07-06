logger -t tpg-ip-test "END router reboot/IP-change test $(date -Is)"
/root/tpg-state-snapshot.sh | tee /root/tpg-state-after-router-reboot.txt