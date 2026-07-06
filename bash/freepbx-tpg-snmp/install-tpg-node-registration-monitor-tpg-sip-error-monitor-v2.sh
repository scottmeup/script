cat > /usr/local/sbin/tpg-sip-error-monitor <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${LOG_FILE:-/var/log/tpg-sip-node-errors.log}"

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

function record_status(line_text) {
  if (line_text ~ /SIP\/2\.0 [456][0-9][0-9]/) {
    status = line_text
    sub(/^.*SIP\/2\.0/, "SIP/2.0", status)
    sub(/\r.*$/, "", status)
  }
}

function flush() {
  if (node != "" && status != "") {
    code = status
    sub(/^SIP\/2\.0[[:space:]]+/, "", code)
    sub(/[[:space:]].*$/, "", code)

    if (code != "401" && code != "407" && code != "487") {
      ts = strftime("%Y-%m-%dT%H:%M:%S%z")
      line = ts " node=" node " status=\"" status "\" cseq=\"" cseq "\" callid=\"" callid "\""
      print line >> logfile
      fflush(logfile)
      system("logger -t tpg-sip-error-monitor " q line q)
    }
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
  record_status($0)
  next
}

/^[[:space:]]*$/ {
  flush()
  next
}

{
  record_status($0)
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

if [ "${1:-}" = "--parse-only" ]; then
  parse_stream
  exit 0
fi

if [ "${1:-}" = "--self-test" ]; then
  cat <<'TESTDATA' | parse_stream
20:45:08.493906 eth0 In IP 172.26.0.82.5060 > 192.168.1.25.5060: SIP: SIP/2.0 403 Forbidden
E.....SIP/2.0 403 Forbidden
Call-ID: test-call-id-403
CSeq: 20094 INVITE

20:45:19.503494 eth0 In IP 172.26.0.34.5060 > 192.168.1.25.5060: SIP: SIP/2.0 407 Proxy Authentication Required
E.....SIP/2.0 407 Proxy Authentication Required
Call-ID: test-call-id-407
CSeq: 3199 INVITE

20:45:45.568391 eth0 In IP 172.26.0.34.5060 > 192.168.1.25.5060: SIP: SIP/2.0 603 Decline
E.....SIP/2.0 603 Decline
Call-ID: test-call-id-603
CSeq: 3200 INVITE
TESTDATA
  exit 0
fi

FILTER='udp port 5060 and (src host 172.26.0.33 or src host 172.26.0.34 or src host 172.26.0.81 or src host 172.26.0.82)'

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
