ls -l \
  /data/ssh/dropbear \
  /data/ssh/dropbear_host_ed25519 \
  /data/ssh/authorized_keys \
  /data/ssh/session-wrapper.sh \
  /data/adb/service.d/90-dropbear-sshd.sh

chown root:root \
  /data/ssh/dropbear \
  /data/ssh/dropbear_host_ed25519 \
  /data/ssh/authorized_keys \
  /data/ssh/session-wrapper.sh \
  /data/adb/service.d/90-dropbear-sshd.sh

chmod 755 /data/ssh/dropbear
chmod 600 /data/ssh/dropbear_host_ed25519
chmod 600 /data/ssh/authorized_keys
chmod 700 /data/ssh/session-wrapper.sh
chmod 755 /data/adb/service.d/90-dropbear-sshd.sh