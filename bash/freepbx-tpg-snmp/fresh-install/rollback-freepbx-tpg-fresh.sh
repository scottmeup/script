#!/usr/bin/env bash
# Inputs: optional BACKUP_DIR selecting an exact fresh-install backup; otherwise newest backup is used. Outputs: disables bundle units, removes bundle-installed target files, restores every pre-existing file and unit state captured by the installer, and reports the backup used. Functions: top-level validates the backup and performs exact restoration. Persistent data created by the bundle is retained unless it replaced a captured file.
set -euo pipefail
ROOT=/etc/freepbx-wanip-hosts/tpg-fresh-install-backups
[ "$(id -u)" -eq 0 ] || { echo 'ERROR: run as root' >&2; exit 1; }
backup="${BACKUP_DIR:-$(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f %p\n' 2>/dev/null | sort -r | head -n1 | cut -d' ' -f2-)}"; [ -r "$backup/unit-enabled.txt" ] || { echo 'ERROR: complete backup not found' >&2; exit 20; }
units=(freepbx-tpg-node-state.timer freepbx-tpg-node-policy.timer freepbx-tpg-node-event-watch.service freepbx-tpg-outbound-failure-recover.timer freepbx-tpg-router-reboot-recover.timer freepbx-wanip-hosts-update.timer freepbx-wanip-registration-watchdog.timer tpg-sip-error-monitor.service tpg-sip-pcap.service freepbx-tpg-update-verify.timer)
for u in "${units[@]}"; do systemctl disable --now "$u" >/dev/null 2>&1 || true; done
while IFS= read -r p; do rm -f "$p"; done < <(find "$backup/files" -type f -printf '/%P\n')
while IFS= read -r p; do rm -f "$p"; done < "$backup/absent.txt" 2>/dev/null || true
while IFS= read -r src; do p="/${src#${backup}/files/}"; mkdir -p "$(dirname "$p")"; cp -a "$src" "$p"; done < <(find "$backup/files" -type f)
systemctl daemon-reload
while IFS='|' read -r u s; do [ "$s" = enabled ] && systemctl enable "$u" >/dev/null 2>&1 || true; done < "$backup/unit-enabled.txt"
while IFS='|' read -r u s; do [ "$s" = active ] && systemctl start "$u" >/dev/null 2>&1 || true; done < "$backup/unit-active.txt"
printf 'Fresh install rolled back from %s\n' "$backup"
