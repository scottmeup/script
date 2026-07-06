printf '%s\n' 'f /var/log/asterisk/restapps.log 0640 asterisk asterisk -' > /etc/tmpfiles.d/freepbx-restapps-log.conf

systemd-tmpfiles --create /etc/tmpfiles.d/freepbx-restapps-log.conf

fail2ban-server -t

systemctl restart fail2ban

sleep 3

systemctl status fail2ban -l --no-pager