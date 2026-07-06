# Only run while trunk is healthy: outgoing calls can be made
timeout 25 tcpdump -ni any -s0 -A \
'udp port 5060 and (host 172.26.0.33 or host 172.26.0.34 or host 172.26.0.81 or host 172.26.0.82)' &
TCPDUMP_PID=$!

sleep 1
asterisk -rx "pjsip send register TPG-VoIP"

sleep 10
kill "$TCPDUMP_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true

asterisk -rx "pjsip show registrations"
