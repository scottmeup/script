echo "=== public IP ==="
curl -s ifconfig.me
echo
grep -n "public.ip.address" /etc/hosts
getent hosts public.ip.address

echo
echo "=== TPG host entries ==="
grep -n "uni-v1.tpg.com.au" /etc/hosts || true
getent hosts uni-v1.tpg.com.au
dig +short uni-v1.tpg.com.au A

echo
echo "=== registration ==="
asterisk -rx "pjsip show registrations"
asterisk -rx "pjsip show registration TPG-VoIP"

echo
echo "=== active channels ==="
asterisk -rx "core show channels concise"