mkdir -p /var/log/tpg-sip-pcap

# systemd unit for monitoring
cat > /etc/systemd/system/tpg-sip-pcap.service <<'EOF'
[Unit]
Description=Rotating packet capture for TPG SIP signalling
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/tcpdump -ni any -s0 -G 300 -W 24 -w /var/log/tpg-sip-pcap/tpg-sip-%%Y%%m%%d-%%H%%M%%S.pcap udp port 5060 and \(host 172.26.0.33 or host 172.26.0.34 or host 172.26.0.81 or host 172.26.0.82\)
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# decoder script
cat > /root/decode-tpg-sip-pcap-logs.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mapfile -t files < <(find /var/log/tpg-sip-pcap -maxdepth 1 -type f | grep -E '\.pcap$' | sort || true)

if [ "${#files[@]}" -eq 0 ]; then
  echo "No pcap files found in /var/log/tpg-sip-pcap/"
  exit 0
fi

for f in "${files[@]}"; do
  echo "===== $f ====="
  tcpdump -nn -r "$f" -A 2>/dev/null | \
    grep -aE 'REGISTER|INVITE|CANCEL|ACK|BYE|SIP/2.0|Contact:|Via:|Expires:|CSeq:|Call-ID:|WWW-Authenticate|Authorization|Proxy-Authenticate|Proxy-Authorization' || true
done
EOF

chmod 750 /root/decode-tpg-sip-pcap-logs.sh

systemctl daemon-reload
systemctl enable --now tpg-sip-pcap.service
systemctl status tpg-sip-pcap.service -l --no-pager




