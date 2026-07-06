logger -t tpg-registration-test "START systemctl restart asterisk $(date -Is)"

systemctl restart asterisk

sleep 25

logger -t tpg-registration-test "END systemctl restart asterisk $(date -Is)"

echo "=== registration after systemctl restart asterisk ==="
asterisk -rx "pjsip show registrations"
asterisk -rx "pjsip show registration TPG-VoIP"