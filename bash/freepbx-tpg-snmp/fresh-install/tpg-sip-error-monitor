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
  pos = index(line_text, "SIP/2.0 ")
  if (pos > 0) {
    code = substr(line_text, pos + 8, 3)
    if (code ~ /^[456]/) {
      status = substr(line_text, pos)
      sub(/\r$/, "", status)
    }
  }
}

function record_cseq(line_text) {
  pos = index(line_text, "CSeq:")
  if (pos > 0) {
    cseq = substr(line_text, pos + 6)
    sub(/^[ \t]+/, "", cseq)
    sub(/\r$/, "", cseq)
  }
}

function record_callid(line_text) {
  pos = index(line_text, "Call-ID:")
  if (pos > 0) {
    callid = substr(line_text, pos + 8)
    sub(/^[ \t]+/, "", callid)
    sub(/\r$/, "", callid)
  }
}

function flush() {
  if (node != "" && status != "") {
    code = substr(status, 9, 3)

    if (code != "401" && code != "407" && code != "487") {
      ts = strftime("%Y-%m-%dT%H:%M:%S%z")
      line = ts " node=" node " status=\"" status "\" cseq=\"" cseq "\" callid=\"" callid "\""
      print line >> logfile
      fflush(logfile)
      cmd = "logger -t tpg-sip-error-monitor '\''" line "'\''"
      system(cmd)
    }
  }

  reset_state()
}

function record_packet_header(line_text) {
  node = line_text
  ip_pos = index(node, " IP ")
  if (ip_pos > 0) {
    node = substr(node, ip_pos + 4)
  }

  end_pos = index(node, ".5060 >")
  if (end_pos > 0) {
    node = substr(node, 1, end_pos - 1)
  }
}

BEGIN {
  reset_state()
}

{
  is_header = 0

  if (length($0) >= 8) {
    if (substr($0, 3, 1) == ":" && substr($0, 6, 1) == ":") {
      is_header = 1
    }
  }

  if (is_header == 1) {
    flush()
    record_packet_header($0)
    record_status($0)
    record_cseq($0)
    record_callid($0)
    next
  }

  if (length($0) == 0) {
    flush()
    next
  }

  record_status($0)
  record_cseq($0)
  record_callid($0)
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
