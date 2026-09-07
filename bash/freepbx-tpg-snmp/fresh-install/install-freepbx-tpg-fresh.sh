#!/usr/bin/env bash
# Inputs: all bundle files and freepbx-tpg-fresh-install.env in SOURCE_DIR, default current directory. The target is a configured FreePBX 17/Debian host with registration TPG-VoIP. Outputs: exact pre-install backup, installed final node-state/policy/event/recovery stack, generated site-specific env files, enabled final units, disabled superseded units, dynamic accepted checksums, and PASS verification. Functions: need validates bundle files; render_env copies a template then replaces documented site values; restore reinstates every overwritten file and captured unit state if installation fails.
set -euo pipefail
SOURCE_DIR="${SOURCE_DIR:-$(pwd -P)}"; SITE_ENV="$SOURCE_DIR/freepbx-tpg-fresh-install.env"; ROOT=/etc/freepbx-wanip-hosts; BACKUPS=$ROOT/tpg-fresh-install-backups
[ "$(id -u)" -eq 0 ] || { echo 'ERROR: run as root' >&2; exit 1; }
[ -r "$SITE_ENV" ] || { echo "ERROR: missing $SITE_ENV" >&2; exit 20; }
set -a; . "$SITE_ENV"; set +a
for key in TPG_HOST TRUNK_NAME ROUTER_IP WAN_IFNAME HOST_ALIAS SNMP_COMMUNITY TASMOTA_POWER_OFF_URL PCAP_DIR STATE_ROOT; do [ -n "${!key:-}" ] || { echo "ERROR: $key must be set in $SITE_ENV" >&2; exit 21; }; done
scripts=(freepbx-tpg-node-state freepbx-tpg-node-policy freepbx-tpg-node-event-watch freepbx-tpg-outbound-failure-recover freepbx-wanip-registration-recover freepbx-tpg-router-reboot-recover freepbx-wanip-hosts-update freepbx-wanip-registration-watchdog tpg-sip-error-monitor freepbx-tpg-update-verify)
envs=(freepbx-tpg-node-state.env freepbx-tpg-node-policy.env freepbx-tpg-node-event-watch.env freepbx-tpg-outbound-failure-recover.env freepbx-wanip-hosts.env)
units=(freepbx-tpg-node-state.service freepbx-tpg-node-state.timer freepbx-tpg-node-policy.service freepbx-tpg-node-policy.timer freepbx-tpg-node-event-watch.service freepbx-tpg-outbound-failure-recover.service freepbx-tpg-outbound-failure-recover.timer freepbx-tpg-router-reboot-recover.service freepbx-tpg-router-reboot-recover.timer freepbx-wanip-hosts-update.service freepbx-wanip-hosts-update.timer freepbx-wanip-registration-watchdog.service freepbx-wanip-registration-watchdog.timer tpg-sip-error-monitor.service tpg-sip-pcap.service freepbx-tpg-update-verify.service freepbx-tpg-update-verify.timer)
for f in "${scripts[@]}" "${units[@]}" freepbx-tpg-update-verify.env; do [ -f "$SOURCE_DIR/$f" ] || { echo "ERROR: missing $SOURCE_DIR/$f" >&2; exit 22; }; done
for f in "${envs[@]}"; do [ -f "$SOURCE_DIR/$f.template" ] || { echo "ERROR: missing $SOURCE_DIR/$f.template" >&2; exit 22; }; done
for cmd in python3 systemctl tcpdump inotifywait asterisk getent sha256sum; do command -v "$cmd" >/dev/null || { echo "ERROR: prerequisite command missing: $cmd" >&2; exit 23; }; done
asterisk -rx "pjsip show registration $TRUNK_NAME" | grep -q "$TRUNK_NAME" || { echo "ERROR: PJSIP registration $TRUNK_NAME is not configured" >&2; exit 24; }
for f in freepbx-tpg-node-state freepbx-tpg-node-policy freepbx-tpg-node-event-watch freepbx-tpg-outbound-failure-recover freepbx-tpg-update-verify; do python3 -m py_compile "$SOURCE_DIR/$f"; done
for f in freepbx-tpg-node-state freepbx-tpg-node-policy freepbx-tpg-node-event-watch freepbx-tpg-update-verify; do "$SOURCE_DIR/$f" --self-test; done
stamp="$(date +%Y%m%d-%H%M%S)"; backup="$BACKUPS/$stamp"; install -d -o root -g root -m 750 "$backup/files"
paths=(); for f in "${scripts[@]}"; do paths+=("/usr/local/sbin/$f"); done; for f in "${envs[@]}"; do paths+=("$ROOT/$f"); done; paths+=("$ROOT/freepbx-tpg-update-verify.env" "$ROOT/freepbx-tpg-update-accepted.sha256"); for f in "${units[@]}"; do paths+=("/etc/systemd/system/$f"); done
for p in "${paths[@]}"; do if [ -e "$p" ]; then mkdir -p "$backup/files/$(dirname "${p#/}")"; cp -a "$p" "$backup/files/${p#/}"; else printf '%s\n' "$p" >> "$backup/absent.txt"; fi; done
systemctl list-unit-files --no-legend | awk '{print $1"|"$2}' | grep -E '^(freepbx-tpg|freepbx-wanip|tpg-sip)' > "$backup/unit-enabled.txt" || true
systemctl list-units --all --no-legend | awk '{print $1"|"$3}' | grep -E '^(freepbx-tpg|freepbx-wanip|tpg-sip)' > "$backup/unit-active.txt" || true
restore(){ rc=$?; if [ "$rc" -ne 0 ]; then for u in "${units[@]}"; do systemctl disable --now "$u" >/dev/null 2>&1 || true; done; for p in "${paths[@]}"; do rm -f "$p"; [ -e "$backup/files/${p#/}" ] && { mkdir -p "$(dirname "$p")"; cp -a "$backup/files/${p#/}" "$p"; }; done; systemctl daemon-reload; while IFS='|' read -r u s; do [ "$s" = enabled ] && systemctl enable "$u" >/dev/null 2>&1 || true; done < "$backup/unit-enabled.txt"; while IFS='|' read -r u s; do [ "$s" = active ] && systemctl start "$u" >/dev/null 2>&1 || true; done < "$backup/unit-active.txt"; echo "ERROR: fresh install failed; restored $backup" >&2; fi; exit "$rc"; }; trap restore EXIT
install -d -o root -g root -m 750 "$ROOT" "$ROOT/tpg-node-state" "$ROOT/tpg-node-policy" "$ROOT/tpg-node-event-watch" "$ROOT/tpg-update-verification" "$PCAP_DIR"
for f in "${scripts[@]}"; do install -o root -g root -m 750 "$SOURCE_DIR/$f" "/usr/local/sbin/$f"; done
python3 - "$SOURCE_DIR" "$ROOT" <<'PY'
import os,sys
from pathlib import Path
src=Path(sys.argv[1]); root=Path(sys.argv[2])
values={k:os.environ[k] for k in ('TPG_HOST','TRUNK_NAME','ROUTER_IP','WAN_IFNAME','HOST_ALIAS','SNMP_COMMUNITY','TASMOTA_POWER_OFF_URL','PCAP_DIR')}
for name in ('freepbx-tpg-node-state.env','freepbx-tpg-node-policy.env','freepbx-tpg-node-event-watch.env','freepbx-tpg-outbound-failure-recover.env','freepbx-wanip-hosts.env'):
 lines=[]
 for raw in (src/(name+'.template')).read_text().splitlines():
  if '=' in raw and not raw.lstrip().startswith('#'):
   k=raw.split('=',1)[0]
   if k in values: raw=k+'='+values[k]
   if k=='ROUTER_POWER_CYCLE_ENABLED': raw=k+'='+os.environ.get('ENABLE_ROUTER_POWER_CYCLE','yes')
  lines.append(raw)
 (root/name).write_text('\n'.join(lines)+'\n')
PY
for f in "${envs[@]}"; do chown root:root "$ROOT/$f"; chmod 640 "$ROOT/$f"; done
install -o root -g root -m 640 "$SOURCE_DIR/freepbx-tpg-update-verify.env" "$ROOT/freepbx-tpg-update-verify.env"
for f in "${units[@]}"; do install -o root -g root -m 644 "$SOURCE_DIR/$f" "/etc/systemd/system/$f"; done
systemctl disable --now freepbx-tpg-sip-health-policy.timer freepbx-tpg-sip-health-policy-watch.service freepbx-tpg-sip-health-check.timer freepbx-tpg-node-health-update.timer >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable --now tpg-sip-pcap.service tpg-sip-error-monitor.service freepbx-tpg-node-event-watch.service freepbx-tpg-node-state.timer freepbx-tpg-node-policy.timer freepbx-tpg-outbound-failure-recover.timer freepbx-tpg-router-reboot-recover.timer freepbx-wanip-hosts-update.timer freepbx-wanip-registration-watchdog.timer
systemctl start freepbx-wanip-hosts-update.service freepbx-tpg-node-state.service freepbx-tpg-node-policy.service
accepted="$ROOT/freepbx-tpg-update-accepted.sha256"; : > "$accepted"
for f in freepbx-tpg-node-state freepbx-tpg-node-policy freepbx-tpg-node-event-watch freepbx-tpg-outbound-failure-recover; do sha256sum "/usr/local/sbin/$f" >> "$accepted"; done
for f in freepbx-tpg-node-state.env freepbx-tpg-node-policy.env freepbx-tpg-node-event-watch.env freepbx-tpg-outbound-failure-recover.env; do sha256sum "$ROOT/$f" >> "$accepted"; done
for f in freepbx-tpg-node-state.service freepbx-tpg-node-state.timer freepbx-tpg-node-policy.service freepbx-tpg-node-policy.timer freepbx-tpg-node-event-watch.service freepbx-tpg-outbound-failure-recover.service freepbx-tpg-outbound-failure-recover.timer; do sha256sum "/etc/systemd/system/$f" >> "$accepted"; done
chmod 640 "$accepted"; chown root:root "$accepted"
systemctl enable --now freepbx-tpg-update-verify.timer
systemctl start freepbx-tpg-update-verify.service
grep -qx 'status=PASS' "$ROOT/tpg-update-verification/latest.txt"
trap - EXIT
cat "$ROOT/tpg-update-verification/latest.txt"
printf 'Fresh install complete. Rollback backup: %s\n' "$backup"
