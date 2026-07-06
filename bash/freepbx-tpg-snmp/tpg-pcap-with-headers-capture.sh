timeout 40 tcpdump -ni any -s0 -A \
'udp port 5060 and (host 172.26.0.33 or host 172.26.0.34 or host 172.26.0.81 or host 172.26.0.82)' \
| tee /root/tpg-one-failed-outbound-full.txt