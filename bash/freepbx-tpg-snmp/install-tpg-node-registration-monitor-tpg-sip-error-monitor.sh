cat > /usr/local/sbin/tpg-sip-error-monitor <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/tpg-sip-node-errors.log"

touch "$LOG_FILE"
chown root:adm "$LOG_FILE"
chmod 640 "$LOG_FILE"

parse_stream() {
awk -v logfile="$LOG_FILE" '
function reset_state() {
  node = ""
  status = ""
  cseq = ""
  callid = ""
}

function flush() {
  if (node != "" && status != "") {
    code = status
    sub(/^SIP\/2\.0[[:space:]]+/, "", code)
    sub(/[[:space:]].*$/, "", code)

    if (code == "401" || code == "407" || code == "487") {
      reset_state()
      return
    }

    ts = strftime("%Y-%m-%dT%H:%M:%S%z")
    line = ts " node=" node " status=\"" status "\" cseq=\"" cseq "\" callid=\"" callid "\""
    print line >> logfile
    fflush(logfile)
    system("logger -t tpg-sip-error-monitor " q line q)
  }

  reset_state()
}

BEGIN {
  q = sprintf("%c", 39)
}

/^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ {
  flush()
  node = $0
  sub(/^.* IP /, "", node)
  sub(/\.5060 >.*$/, "", node)
  next
}

/^SIP\/2\.0 [456][0-9][0-9]/ {
  status = $0
  sub(/^.*SIP\/2\.0/, "SIP/2.0", status)
  next
}

/^CSeq:/ {
  cseq = $0
  sub(/^CSeq:[[:space:]]*/, "", cseq)
  next
}

/^Call-ID:/ {
  callid = $0
  sub(/^Call-ID:[[:space:]]*/, "", callid)
  next
}

END {
  flush()
}
'
}

if [ "${1:-}" = "--self-test" ]; then
  cat <<'TESTDATA' | parse_stream
03:25:23.218346 eth0 In IP 172.26.0.82.5060 > 192.168.1.25.5060: SIP: SIP/2.0 403 Forbidden
SIP/2.0 403 Forbidden
Call-ID: test-call-id-403
CSeq: 15926 INVITE

03:25:40.292720 eth0 In IP 172.26.0.34.5060 > 192.168.1.25.5060: SIP: SIP/2.0 407 Proxy Authentication Required
SIP/2.0 407 Proxy Authentication Required
Call-ID: test-call-id-407
CSeq: 23324 INVITE
TESTDATA
  exit 0
fi

FILTER='udp port 5060 and (src host 172.26.0.33 or src host 172.26.0.34 or src host 172.26.0.81 or src host 172.26.0.82) and udp[8:4] = 0x5349502f and (udp[16] = 0x34 or udp[16] = 0x35 or udp[16] = 0x36)'

stdbuf -oL tcpdump -l -nn -s0 -A "$FILTER" 2>/dev/null | parse_stream
EOF

chown root:root /usr/local/sbin/tpg-sip-error-monitor
chmod 750 /usr/local/sbin/tpg-sip-error-monitor

cat > /etc/systemd/system/tpg-sip-error-monitor.service <<'EOF'
[Unit]
Description=Low-noise monitor for TPG SIP node error responses
After=network-online.target asterisk.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/tpg-sip-error-monitor
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now tpg-sip-error-monitor.service


systemctl status tpg-sip-error-monitor.service -l --no-pager
# tail -f /var/log/tpg-sip-node-errors.log #run this to check the logs
