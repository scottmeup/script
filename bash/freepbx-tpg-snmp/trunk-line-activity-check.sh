if asterisk -rx "core show channels concise" | grep -F "PJSIP/TPG-VoIP-" >/dev/null; then
  echo "TPG trunk call active"
else
  echo "No TPG trunk call active"
fi