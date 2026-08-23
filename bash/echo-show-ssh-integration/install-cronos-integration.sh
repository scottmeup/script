#!/usr/bin/env bash
# Inputs: cronos-integration.env beside this installer; five payload scripts; rooted ADB-connected cronos.
# Outputs: timestamped backups, /data/adb/cronos-integration files, additive 80-cronos-integration.sh boot service, updated session-wrapper.sh, and installed control commands.
# Functions: fail stops on invalid evidence; push_install backs up and installs one payload; verify checks exact modes, syntax, boot service, mirrors, PATH, and Termux shell identity.
# Processing: validates the proven device/Termux baseline, preserves every changed current file, installs additive integration, manually starts it, and runs validation without rebooting.
set -euo pipefail
ADB=${ADB:-adb}
DIR=$(cd "$(dirname "$0")" && pwd)
fail(){ echo "ERROR: $1" >&2; exit 1; }
for f in cronos-integration.env 80-cronos-integration.sh script-mirror-daemon.sh termux-shell.sh disable-echo-ui-cronos.sh enable-echo-ui-cronos.sh termux-user-path.sh; do [ -f "$DIR/$f" ] || fail "missing $DIR/$f"; done
[ "$("$ADB" shell getprop ro.product.device | tr -d '\r')" = cronos ] || fail 'not cronos'
[ "$("$ADB" shell stat -c %u /data/data/com.termux | tr -d '\r')" = 10036 ] || fail 'Termux UID differs from collected baseline; rerun diagnostics'
stamp=$(date +%Y%m%d-%H%M%S)
backup(){ "$ADB" shell "if [ -e '$1' ]; then cp -p '$1' '$1.before-$stamp'; fi"; }
push_install(){ src=$1; dst=$2; mode=$3; backup "$dst"; "$ADB" push "$DIR/$src" /data/local/tmp/"$src" >/dev/null; "$ADB" shell "cp '/data/local/tmp/$src' '$dst'; chown 0:0 '$dst'; chmod '$mode' '$dst'"; }
"$ADB" shell 'mkdir -p /data/adb/cronos-integration /data/local/bin /data/adb/service.d'
push_install cronos-integration.env /data/adb/cronos-integration/cronos-integration.env 600
push_install script-mirror-daemon.sh /data/adb/cronos-integration/script-mirror-daemon.sh 700
push_install 80-cronos-integration.sh /data/adb/service.d/80-cronos-integration.sh 755
push_install termux-shell.sh /data/local/bin/termux-shell 755
push_install disable-echo-ui-cronos.sh /data/local/bin/disable-echo-ui 755
push_install enable-echo-ui-cronos.sh /data/local/bin/enable-echo-ui 755
termux_uid=$("$ADB" shell stat -c %u /data/data/com.termux | tr -d "\r")
termux_gid=$("$ADB" shell stat -c %g /data/data/com.termux | tr -d "\r")
backup /data/data/com.termux/files/usr/etc/profile.d/cronos-user-script.sh
"$ADB" push "$DIR/termux-user-path.sh" /data/local/tmp/termux-user-path.sh >/dev/null
"$ADB" shell "cp /data/local/tmp/termux-user-path.sh /data/data/com.termux/files/usr/etc/profile.d/cronos-user-script.sh; chown $termux_uid:$termux_gid /data/data/com.termux/files/usr/etc/profile.d/cronos-user-script.sh; chmod 600 /data/data/com.termux/files/usr/etc/profile.d/cronos-user-script.sh"
backup /data/ssh/session-wrapper.sh
"$ADB" shell "cp -p /data/ssh/session-wrapper.sh /data/ssh/session-wrapper.sh.working-$stamp"
"$ADB" shell "sed -e 's|^export PATH=.*|export PATH=/sbin:/system/sbin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin:/data/adb/magisk:/data/local/bin:/dev/script:/dev/user-script:/data/data/com.termux/files/usr/bin|' /data/ssh/session-wrapper.sh > /data/local/tmp/session-wrapper.sh.new && cp /data/local/tmp/session-wrapper.sh.new /data/ssh/session-wrapper.sh && chown 0:0 /data/ssh/session-wrapper.sh && chmod 700 /data/ssh/session-wrapper.sh"
"$ADB" shell '/data/adb/magisk/busybox sh -n /data/adb/service.d/80-cronos-integration.sh; /system/bin/sh -n /data/adb/cronos-integration/script-mirror-daemon.sh; /system/bin/sh -n /data/local/bin/termux-shell; /system/bin/sh -n /data/local/bin/disable-echo-ui; /system/bin/sh -n /data/local/bin/enable-echo-ui; /system/bin/sh -n /data/data/com.termux/files/usr/etc/profile.d/cronos-user-script.sh; /system/bin/sh -n /data/ssh/session-wrapper.sh'
"$ADB" shell 'ASH_STANDALONE=1 /data/adb/magisk/busybox sh /data/adb/service.d/80-cronos-integration.sh'
sleep 4
"$ADB" shell 'ls -ldnZ /dev/script /dev/user-script; cat /data/local/tmp/cronos-integration-boot.log; cat /data/local/tmp/cronos-script-mirror.log; grep "^export PATH=" /data/ssh/session-wrapper.sh; /data/local/bin/termux-shell -c id 2>/dev/null || true'
echo "Installed with backups suffixed .before-$stamp and session-wrapper.sh.working-$stamp. Reboot not performed."
