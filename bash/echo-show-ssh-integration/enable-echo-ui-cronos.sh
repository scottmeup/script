#!/system/bin/sh
# Inputs: saved /data/local/tmp/cronos-ui-state.env or configured HOME/IME fallbacks.
# Outputs: enabled/default IME and launched HOME activity.
# Processing: restores the recorded IME selection, starts its package, and launches the recorded HOME component.
set -eu
STATE=/data/local/tmp/cronos-ui-state.env
CONFIG=/data/adb/cronos-integration/cronos-integration.env
[ -f "$CONFIG" ] && . "$CONFIG"
[ -f "$STATE" ] && . "$STATE"
HOME_COMPONENT=${HOME_COMPONENT:-${LAUNCHER_PACKAGE:-com.amazon.paladin}/.app.MMLauncherActivity}
IME_COMPONENT=${IME_COMPONENT:-com.amazon.bluestone.keyboard/.DictationIME}
IME_PACKAGE=${IME_COMPONENT%%/*}
pm enable "$IME_PACKAGE" >/dev/null 2>&1 || true
ime enable "$IME_COMPONENT" >/dev/null 2>&1 || true
ime set "$IME_COMPONENT"
monkey -p "$IME_PACKAGE" 1 >/dev/null 2>&1 || true
am start -n "$HOME_COMPONENT"
echo "restored $HOME_COMPONENT and $IME_COMPONENT"
