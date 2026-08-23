#!/system/bin/sh

/data/ssh/dropbearkey -t ed25519 -f /data/ssh/dropbear_host_ed25519
touch /data/ssh/authorized_keys
mkdir -p /dev/dropbear
cp /data/ssh/authorized_keys /dev/dropbear/authorized_keys
chown root:root /dev/dropbear /dev/dropbear/authorized_keys
chmod 700 /dev/dropbear
chmod 600 /dev/dropbear/authorized_keys