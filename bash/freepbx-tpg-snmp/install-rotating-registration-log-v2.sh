#!/usr/bin/env bash
set -euo pipefail

mkdir -p /var/log/tpg-sip-pcap
chown root:adm /var/log/tpg-sip-pcap
chmod 750 /var/log/tpg-sip-pcap

# systemd unit for monitoring
cat > /etc/systemd/system/tpg-sip-pcap.service <<'EOF'
[Unit]
Description=Rotating packet capture for TPG SIP signalling
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/sh -c 'exec /usr/bin/tcpdump -ni any -s0 -G 300 -W 24 -w "/var/log/tpg-sip-pcap/tpg-sip-%%Y%%m%%d-%%H%%M%%S.pcap" "udp port 5060 and (host 172.26.0.33 or host 172.26.0.34 or host 172.26.0.81 or host 172.26.0.82)"'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# decoder script
cat > ~/decode-tpg-sip-pcap-logs.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if ! ls /var/log/tpg-sip-pcap/*.pcap >/dev/null 2>&1; then
  echo "No pcap files found in /var/log/tpg-sip-pcap/"
  exit 0
fi

tcpdump -nn -r /var/log/tpg-sip-pcap/*.pcap -A 2>/dev/null | \
grep -aE 'REGISTER|INVITE|CANCEL|ACK|BYE|SIP/2.0|Contact:|Via:|Expires:|CSeq:|Call-ID:|WWW-Authenticate|Authorization|Proxy-Authenticate|Proxy-Authorization' || true
EOF

chmod 750 ~/decode-tpg-sip-pcap-logs.sh

# enable systemd unit
systemctl daemon-reload
systemctl reset-failed tpg-sip-pcap.service >/dev/null 2>&1 || true
systemctl enable tpg-sip-pcap.service >/dev/null
systemctl restart tpg-sip-pcap.service

sleep 2

systemctl status tpg-sip-pcap.service -l --no-pager

echo
echo "=== recent journal ==="
journalctl -u tpg-sip-pcap.service -n 30 --no-pager

echo
echo "=== capture directory ==="
ls -lah /var/log/tpg-sip-pcap/

if systemctl is-active --quiet tpg-sip-pcap.service; then
  echo
  echo "OK: tpg-sip-pcap.service is active"
else
  echo
  echo "ERROR: tpg-sip-pcap.service is not active"
  exit 1
fi