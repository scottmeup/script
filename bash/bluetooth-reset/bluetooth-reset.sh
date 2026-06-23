#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  source "${SCRIPT_DIR}/.env"
  set +a
fi

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

SERVICE_NAME="${SERVICE_NAME:-gymnasticon}"
EXTRA_STOP_SERVICES="${EXTRA_STOP_SERVICES:-}"
HCI_PREFERRED="${HCI_PREFERRED:-hci0}"
VENDOR_ID="${VENDOR_ID:-}"
PRODUCT_ID="${PRODUCT_ID:-}"
WAIT_SECS="${WAIT_SECS:-12}"
VALIDATE_SECS="${VALIDATE_SECS:-12}"

stop_service_if_exists() {
  local s="$1"
  if systemctl list-unit-files --type=service --no-pager | awk '{print $1}' | grep -qx "${s}.service"; then
    ${SUDO} systemctl stop "${s}.service" || true
    ${SUDO} systemctl kill "${s}.service" || true
    for _ in {1..50}; do
      ${SUDO} systemctl is-active --quiet "${s}.service" || break
      sleep 0.1
    done
  fi
}

start_service_if_exists() {
  local s="$1"
  if systemctl list-unit-files --type=service --no-pager | awk '{print $1}' | grep -qx "${s}.service"; then
    ${SUDO} systemctl start "${s}.service" || true
  fi
}

ensure_usb_modeswitch() {
  if ! dpkg -s usb-modeswitch >/dev/null 2>&1; then
    ${SUDO} apt-get update
    ${SUDO} apt-get install -y usb-modeswitch
  fi
}

sysfs_vidpid_for_hci() {
  local hci="$1"
  local devpath="/sys/class/bluetooth/${hci}/device"
  [[ -e "$devpath" ]] || return 1
  local p
  p="$(readlink -f "$devpath")"
  while [[ "$p" != "/" ]]; do
    if [[ -f "${p}/idVendor" && -f "${p}/idProduct" ]]; then
      local vid pid
      vid="$(tr -d '[:space:]' < "${p}/idVendor")"
      pid="$(tr -d '[:space:]' < "${p}/idProduct")"
      [[ -n "$vid" && -n "$pid" ]] || return 1
      printf "%s %s\n" "$vid" "$pid"
      return 0
    fi
    p="$(dirname "$p")"
  done
  return 1
}

detect_vidpid() {
  if [[ -n "$VENDOR_ID" && -n "$PRODUCT_ID" ]]; then
    printf "%s %s\n" "$VENDOR_ID" "$PRODUCT_ID"
    return 0
  fi

  if [[ -d /sys/class/bluetooth ]]; then
    if [[ -e "/sys/class/bluetooth/${HCI_PREFERRED}" ]]; then
      if sysfs_vidpid_for_hci "${HCI_PREFERRED}" >/tmp/.bt_vidpid 2>/dev/null; then
        cat /tmp/.bt_vidpid
        rm -f /tmp/.bt_vidpid
        return 0
      fi
    fi

    for d in /sys/class/bluetooth/hci*; do
      [[ -e "$d" ]] || continue
      local hci
      hci="$(basename "$d")"
      if sysfs_vidpid_for_hci "$hci" >/tmp/.bt_vidpid 2>/dev/null; then
        cat /tmp/.bt_vidpid
        rm -f /tmp/.bt_vidpid
        return 0
      fi
    done
  fi

  local line
  line="$(lsusb | grep -i bluetooth | grep -viE 'ID 1d6b:' | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    line="$(lsusb | grep -viE 'ID 1d6b:' | head -n 1 || true)"
  fi
  [[ -n "$line" ]] || return 1
  local id
  id="$(awk '{print $6}' <<<"$line")"
  [[ "$id" == *:* ]] || return 1
  printf "%s %s\n" "${id%:*}" "${id#*:}"
}

bring_back_as_hci0() {
  ${SUDO} rfkill unblock bluetooth || true

  ${SUDO} systemctl stop bluetooth.service || true
  ${SUDO} pkill -x bluetoothd || true

  ${SUDO} modprobe -r btusb >/dev/null 2>&1 || true
  ${SUDO} modprobe btusb

  ${SUDO} systemctl start bluetooth.service || true

  local deadline=$(( $(date +%s) + WAIT_SECS ))
  while [[ $(date +%s) -lt $deadline ]]; do
    [[ -e /sys/class/bluetooth/hci0 ]] && break
    sleep 0.2
  done

  if [[ ! -e /sys/class/bluetooth/hci0 ]]; then
    ${SUDO} systemctl stop bluetooth.service || true
    ${SUDO} pkill -x bluetoothd || true
    ${SUDO} modprobe -r btusb >/dev/null 2>&1 || true
    ${SUDO} modprobe btusb
    ${SUDO} systemctl start bluetooth.service || true
    sleep 1
  fi

  if [[ -e /sys/class/bluetooth/hci0 ]]; then
    ${SUDO} hciconfig hci0 up || true
    ${SUDO} btmgmt --index 0 power on >/dev/null 2>&1 || true
    ${SUDO} btmgmt --index 0 connectable on >/dev/null 2>&1 || true
  else
    for d in /sys/class/bluetooth/hci*; do
      [[ -e "$d" ]] || continue
      local hci
      hci="$(basename "$d")"
      ${SUDO} hciconfig "$hci" up || true
    done
  fi
}

validate_bt_ready_for_gymnasticon() {
  local deadline=$(( $(date +%s) + VALIDATE_SECS ))
  while [[ $(date +%s) -lt $deadline ]]; do
    if [[ -e /sys/class/bluetooth/hci0 ]]; then
      local hcistate
      hcistate="$(${SUDO} hciconfig hci0 2>/dev/null | tr '\n' ' ' || true)"
      if grep -q "UP RUNNING" <<<"$hcistate"; then
        if ${SUDO} systemctl is-active --quiet bluetooth.service; then
          local cur
          cur="$(${SUDO} btmgmt --index 0 info 2>/dev/null | awk -F': ' '/current settings:/{print $2}' || true)"
          if [[ -n "$cur" ]] && grep -qw "powered" <<<"$cur" && grep -qw "le" <<<"$cur" && grep -qw "connectable" <<<"$cur"; then
            return 0
          fi
        fi
      fi
    fi

    ${SUDO} rfkill unblock bluetooth || true
    ${SUDO} systemctl start bluetooth.service || true
    [[ -e /sys/class/bluetooth/hci0 ]] && ${SUDO} hciconfig hci0 up || true
    ${SUDO} btmgmt --index 0 power on >/dev/null 2>&1 || true
    ${SUDO} btmgmt --index 0 connectable on >/dev/null 2>&1 || true

    sleep 0.5
  done

  echo "ERROR: Validation failed. Expected:"
  echo "  - hci0 exists"
  echo "  - hciconfig hci0 shows UP RUNNING"
  echo "  - bluetooth.service active"
  echo "  - btmgmt current settings include: powered le connectable"
  echo
  echo "Diagnostics:"
  ${SUDO} hciconfig -a || true
  ${SUDO} btmgmt info || true
  ${SUDO} systemctl status bluetooth --no-pager -l || true
  return 1
}

main() {
  stop_service_if_exists "$SERVICE_NAME"
  if [[ -n "$EXTRA_STOP_SERVICES" ]]; then
    for s in $EXTRA_STOP_SERVICES; do
      stop_service_if_exists "$s"
    done
  fi

  ${SUDO} systemctl stop bluetooth.service || true
  ${SUDO} pkill -x bluetoothd || true

  ensure_usb_modeswitch

  local vid pid
  read -r vid pid < <(detect_vidpid)
  [[ -n "$vid" && -n "$pid" ]] || { echo "ERROR: could not detect Bluetooth VID/PID"; exit 1; }

  ${SUDO} usb_modeswitch -v "$vid" -p "$pid" --reset-usb
  sleep 2

  bring_back_as_hci0

  local ok=0
  if ! validate_bt_ready_for_gymnasticon; then
    ok=2
  fi

  if [[ -n "$EXTRA_STOP_SERVICES" ]]; then
    for s in $EXTRA_STOP_SERVICES; do
      start_service_if_exists "$s"
    done
  fi
  start_service_if_exists "$SERVICE_NAME"

  exit "$ok"
}

main "$@"