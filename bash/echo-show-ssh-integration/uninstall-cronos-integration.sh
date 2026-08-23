#!/usr/bin/env bash
# Inputs: rooted ADB-connected cronos and the exact backup suffix printed by the installer as BACKUP_SUFFIX.
# Outputs: stops the mirror daemon and restores the backed-up session wrapper; preserves installed files by renaming them with a disabled suffix.
# Processing: validates the backup, stops only the recorded daemon, restores baseline, and disables additive boot integration without deleting evidence.
set -euo pipefail
ADB=${ADB:-adb}
: "${BACKUP_SUFFIX:?Set BACKUP_SUFFIX to the installer timestamp, for example 20260823-153000}"
backup=/data/ssh/session-wrapper.sh.before-$BACKUP_SUFFIX
"$ADB" shell "test -f '$backup'" || { echo "missing $backup" >&2; exit 1; }
"$ADB" shell 'pid=$(cat /data/local/tmp/cronos-script-mirror.pid 2>/dev/null); if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi'
"$ADB" shell "cp -p '$backup' /data/ssh/session-wrapper.sh; mv /data/adb/service.d/80-cronos-integration.sh /data/adb/service.d/80-cronos-integration.sh.disabled-$BACKUP_SUFFIX; chmod 644 /data/adb/service.d/80-cronos-integration.sh.disabled-$BACKUP_SUFFIX; rm -rf /dev/user-script; echo rollback-complete"
