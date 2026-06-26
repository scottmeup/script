#!/usr/bin/env bash
set -euo pipefail

#troubleshooting section
systemctl stop gymnasticon || true
pkill -f '/opt/gymnasticon|node' || true
systemctl stop bluetooth || true
pkill -x bluetoothd || true
rfkill unblock bluetooth || true
modprobe -r btusb btintel btbcm btrtl || true
modprobe btusb
sleep 2
hciconfig hci0 up
systemctl start bluetooth
sleep 1
btmgmt --index 0 power on
btmgmt --index 0 connectable on
btmgmt --index 0 le on
btmgmt --index 0 name gymnasticon-test
btmgmt --index 0 advertising on

#verify status
hciconfig -a
btmgmt info
hcitool dev

#OPTIONAL - bring up advertising
btmgmt --index 0 name gymnasticon-test
btmgmt --index 0 advertising on




ENV_FILE="${ENV_FILE:-/opt/gymnasticon-bt.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

SERVICE_NAME="${SERVICE_NAME:-gymnasticon}"
TARGET_HCI_NAME="${TARGET_HCI_NAME:-hci0}"
TARGET_VENDOR_ID="${TARGET_VENDOR_ID:-${VENDOR_ID:-8087}}"
TARGET_PRODUCT_ID="${TARGET_PRODUCT_ID:-${PRODUCT_ID:-0aaa}}"
TARGET_USB_PATH="${TARGET_USB_PATH:-}"
TARGET_BDADDR="${TARGET_BDADDR:-}"
FIRMWARE_FILE="${FIRMWARE_FILE:-/lib/firmware/intel/ibt-17-16-1.sfi}"
APT_SOURCE_FILE="${APT_SOURCE_FILE:-/etc/apt/sources.list.d/gymnasticon-bt-firmware.list}"
EXTRA_KILL_PATTERNS="${EXTRA_KILL_PATTERNS:-}"
RECYCLE_ATTEMPTS="${RECYCLE_ATTEMPTS:-4}"
TARGET_WAIT_SECS="${TARGET_WAIT_SECS:-20}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root"
    exit 1
  fi
}

read_codename() {
  . /etc/os-release
  printf '%s\n' "${VERSION_CODENAME:-}"
}

have_source_line() {
  local line="$1"
  grep -RqsFx -- "$line" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null
}

ensure_buster_sources_if_needed() {
  local codename
  codename="$(read_codename)"
  if [[ "$codename" != "buster" ]]; then
    return 0
  fi

  local line1="deb http://archive.debian.org/debian buster main contrib non-free"
  local line2="deb http://archive.debian.org/debian-security buster/updates main contrib non-free"

  if have_source_line "$line1" && have_source_line "$line2"; then
    return 0
  fi

  install -d -m 0755 /etc/apt/sources.list.d
  printf '%s\n%s\n' "$line1" "$line2" > "$APT_SOURCE_FILE"
}

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

pkg_candidate_available() {
  local pkg="$1"
  local candidate
  candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/{print $2; exit}')"
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

ensure_packages() {
  local need_update=0

  if ! pkg_candidate_available firmware-iwlwifi; then
    ensure_buster_sources_if_needed
    need_update=1
  fi

  if ! pkg_installed usb-modeswitch || ! pkg_installed firmware-iwlwifi; then
    need_update=1
  fi

  if [[ "$need_update" -eq 1 ]]; then
    apt-get -o Acquire::Check-Valid-Until=false update
    apt-get install -y usb-modeswitch firmware-iwlwifi
  fi
}

stop_service_hard() {
  local svc="$1"
  systemctl stop "${svc}.service" >/dev/null 2>&1 || true
  systemctl kill "${svc}.service" >/dev/null 2>&1 || true
  for _ in {1..30}; do
    systemctl is-active --quiet "${svc}.service" || return 0
    sleep 0.2
  done
  return 0
}

kill_competitor_processes() {
  pkill -x bluetoothd >/dev/null 2>&1 || true
  for name in bluetoothctl btmon hcitool gatttool; do
    pkill -x "$name" >/dev/null 2>&1 || true
  done
  if [[ -n "$EXTRA_KILL_PATTERNS" ]]; then
    for pattern in $EXTRA_KILL_PATTERNS; do
      pkill -f "$pattern" >/dev/null 2>&1 || true
    done
  fi
}

bring_all_hci_down() {
  for d in /sys/class/bluetooth/hci*; do
    [[ -e "$d" ]] || continue
    hciconfig "$(basename "$d")" down >/dev/null 2>&1 || true
  done
}

quiesce_bluetooth_stack() {
  stop_service_hard "$SERVICE_NAME"
  stop_service_hard bluetooth
  kill_competitor_processes
  rfkill unblock bluetooth >/dev/null 2>&1 || true
  bring_all_hci_down
}

find_usb_parent_for_hci() {
  local hci="$1"
  local p
  p="$(readlink -f "/sys/class/bluetooth/${hci}/device" 2>/dev/null || true)"
  [[ -n "$p" ]] || return 1
  while [[ "$p" != "/" ]]; do
    if [[ -f "$p/idVendor" && -f "$p/idProduct" ]]; then
      printf '%s\n' "$p"
      return 0
    fi
    p="$(dirname "$p")"
  done
  return 1
}

usb_path_from_parent() {
  local parent="$1"
  basename "$parent"
}

bdaddr_for_hci() {
  hciconfig "$1" 2>/dev/null | awk -F'BD Address: ' '/BD Address:/{print $2}' | awk '{print $1}' || true
}

hci_matches_target() {
  local hci="$1"
  local parent vid pid upath bdaddr

  parent="$(find_usb_parent_for_hci "$hci" 2>/dev/null || true)"
  [[ -n "$parent" ]] || return 1

  vid="$(tr -d '[:space:]' < "${parent}/idVendor" 2>/dev/null || true)"
  pid="$(tr -d '[:space:]' < "${parent}/idProduct" 2>/dev/null || true)"
  [[ "$vid" == "$TARGET_VENDOR_ID" && "$pid" == "$TARGET_PRODUCT_ID" ]] || return 1

  if [[ -n "$TARGET_USB_PATH" ]]; then
    upath="$(usb_path_from_parent "$parent")"
    [[ "$upath" == "$TARGET_USB_PATH" ]] || return 1
  fi

  if [[ -n "$TARGET_BDADDR" ]]; then
    bdaddr="$(bdaddr_for_hci "$hci")"
    [[ "${bdaddr^^}" == "${TARGET_BDADDR^^}" ]] || return 1
  fi

  return 0
}

find_target_hci() {
  for d in /sys/class/bluetooth/hci*; do
    [[ -e "$d" ]] || continue
    local hci
    hci="$(basename "$d")"
    if hci_matches_target "$hci"; then
      printf '%s\n' "$hci"
      return 0
    fi
  done
  return 1
}

count_hci_devices() {
  local n=0
  for d in /sys/class/bluetooth/hci*; do
    [[ -e "$d" ]] || continue
    n=$((n + 1))
  done
  printf '%s\n' "$n"
}

detect_vid_pid_fallback() {
  if [[ -n "$TARGET_VENDOR_ID" && -n "$TARGET_PRODUCT_ID" ]]; then
    printf '%s %s\n' "$TARGET_VENDOR_ID" "$TARGET_PRODUCT_ID"
    return 0
  fi

  local line id
  line="$(lsusb | awk 'tolower($0) ~ /bluetooth/ && $0 !~ /1d6b:/ {print; exit}')"
  [[ -n "$line" ]] || return 1
  id="$(awk '{print $6}' <<<"$line")"
  [[ "$id" == *:* ]] || return 1
  printf '%s %s\n' "${id%:*}" "${id#*:}"
}

wait_for_target_hci() {
  local deadline=$((SECONDS + TARGET_WAIT_SECS))
  while (( SECONDS < deadline )); do
    local hci
    hci="$(find_target_hci 2>/dev/null || true)"
    if [[ -n "$hci" ]]; then
      printf '%s\n' "$hci"
      return 0
    fi
    sleep 0.2
  done
  return 1
}

reload_bt_stack() {
  rfkill unblock bluetooth >/dev/null 2>&1 || true
  modprobe -r btusb btintel btbcm btrtl >/dev/null 2>&1 || true
  modprobe btusb
}

reset_usb_device() {
  local vid="$1"
  local pid="$2"
  usb_modeswitch -v "$vid" -p "$pid" --reset-usb >/dev/null 2>&1 || true
  sleep 2
}

force_target_to_hci0() {
  local attempt=1
  local current=""

  current="$(find_target_hci 2>/dev/null || true)"
  if [[ "$current" == "$TARGET_HCI_NAME" ]]; then
    printf '%s\n' "$current"
    return 0
  fi

  while (( attempt <= RECYCLE_ATTEMPTS )); do
    quiesce_bluetooth_stack
    reload_bt_stack

    current="$(wait_for_target_hci 2>/dev/null || true)"
    if [[ "$current" == "$TARGET_HCI_NAME" ]]; then
      printf '%s\n' "$current"
      return 0
    fi

    attempt=$((attempt + 1))
    sleep 1
  done

  current="$(find_target_hci 2>/dev/null || true)"
  if [[ -n "$current" ]]; then
    echo "Target adapter is present as ${current}, not ${TARGET_HCI_NAME}" >&2
    echo "Detected HCI count: $(count_hci_devices)" >&2
    echo "If another controller is occupying ${TARGET_HCI_NAME}, it cannot be safely renumbered in-place." >&2
  else
    echo "Target adapter did not reappear after recycling btusb" >&2
  fi

  return 1
}

prepare_target_hci() {
  local hci="$1"

  hciconfig "$hci" up
  btmgmt --index 0 power on
  btmgmt --index 0 connectable on
  btmgmt --index 0 le on
}

validate_target_on_hci0() {
  local target_hci
  target_hci="$(find_target_hci 2>/dev/null || true)"
  [[ "$target_hci" == "$TARGET_HCI_NAME" ]] || return 1

  local hcistate
  hcistate="$(hciconfig "$TARGET_HCI_NAME" 2>/dev/null | tr '\n' ' ' || true)"
  grep -q "UP RUNNING" <<<"$hcistate" || return 1

  local cur
  cur="$(btmgmt --index 0 info 2>/dev/null | awk -F': ' '/current settings:/{print $2}' || true)"
  grep -qw "powered" <<<"$cur" || return 1
  grep -qw "connectable" <<<"$cur" || return 1
  grep -qw "le" <<<"$cur" || return 1

  return 0
}

main() {
  require_root
  ensure_packages

  if [[ ! -f "$FIRMWARE_FILE" ]]; then
    echo "Missing firmware file: $FIRMWARE_FILE"
    exit 1
  fi

  quiesce_bluetooth_stack

  local vid pid
  read -r vid pid < <(detect_vid_pid_fallback)

  reset_usb_device "$vid" "$pid"

  local target_hci
  target_hci="$(force_target_to_hci0)"
  prepare_target_hci "$target_hci"

  if ! validate_target_on_hci0; then
    echo "Bluetooth adapter validation failed"
    hciconfig -a || true
    btmgmt info || true
    exit 1
  fi

  stop_service_hard bluetooth
  kill_competitor_processes
}

main "$@"