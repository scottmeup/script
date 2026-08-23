#!/system/bin/sh
# Inputs: active HOME activity and default IME, with configured fallbacks from cronos-integration.env.
# Outputs: /data/local/tmp/cronos-ui-state.env; temporarily force-stopped launcher and IME.
# Processing: records current components, dismisses the keyboard, and force-stops both packages without disabling or uninstalling them.
set -eu
STATE=/data/local/tmp/cronos-ui-state.env
CONFIG=/data/adb/cronos-integration/cronos-integration.env
[ -f "$CONFIG" ] && . "$CONFIG"
HOME_COMPONENT=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1)
case "$HOME_COMPONENT" in */*) ;; *) HOME_COMPONENT=${LAUNCHER_PACKAGE:-com.amazon.paladin}/.app.MMLauncherActivity ;; esac
IME=$(settings get secure default_input_method 2>/dev/null)
case "$IME" in */*) ;; *) IME=${IME_COMPONENT:-com.amazon.bluestone.keyboard/.DictationIME} ;; esac
printf "HOME_COMPONENT='%s'\nIME_COMPONENT='%s'\n" "$HOME_COMPONENT" "$IME" > "$STATE"
chmod 600 "$STATE"
input keyevent 111 2>/dev/null || true
input keyevent 4 2>/dev/null || true
am force-stop "${IME%%/*}"
am force-stop "${HOME_COMPONENT%%/*}"
echo "force-stopped ${HOME_COMPONENT%%/*} and ${IME%%/*}"
