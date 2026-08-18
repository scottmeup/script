#!/usr/bin/env bash
# install script to /var/lib/vz/snippets/
# install env file to /etc/
# then run qm set <VMID> --hookscript local:snippets/antplus-reset.sh

set -euo pipefail

VMID="${1:-}"
PHASE="${2:-}"

ENV_FILE="/etc/antplus-reset.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

ANT_USB_VENDOR="${ANT_USB_VENDOR:-0fcf}"
ANT_USB_PRODUCT="${ANT_USB_PRODUCT:-1009}"
ANT_RESET_SETTLE_SECONDS="${ANT_RESET_SETTLE_SECONDS:-3}"
BLUETOOTH_USB_VENDOR="${ANT_USB_VENDOR:-0fcf}"
BLUETOOTH_USB_PRODUCT="${ANT_USB_PRODUCT:-1009}"
BLUETOOTH_RESET_SETTLE_SECONDS="${ANT_RESET_SETTLE_SECONDS:-3}"
ANT_FINISHED=0
BLUETOOTH_FINISHED=0
LOOP_FINISHED=0
EXIT_CODE=0

case "$PHASE" in
  pre-start|post-stop)
    ;;
  *)
    exit 0
    ;;
esac


reset_device(){
  local DEVICE="$1"
  local SETTLE_SECONDS="$2"
  if [ -w "$DEVICE/authorized" ]; then
    echo 0 > "$DEVICE/authorized"
    sleep "$SETTLE_SECONDS"
    echo 1 > "$DEVICE/authorized"
    sleep "$SETTLE_SECONDS"
    break
  fi

  DEVICENAME="$(basename "$DEVICE")"
  if [ -e "/sys/bus/usb/drivers/usb/unbind" ] && [ -e "/sys/bus/usb/drivers/usb/bind" ]; then
    echo -n "$DEVICENAME" > /sys/bus/usb/drivers/usb/unbind || true
    sleep "$SETTLE_SECONDS"
    echo -n "$DEVICENAME" > /sys/bus/usb/drivers/usb/bind || true
    sleep "$SETTLE_SECONDS"
    break
  fi

  echo "No usable reset method found for $d"
  break
}


while [ "$LOOP_FINISHED" -eq 0 ]; do
  for d in /sys/bus/usb/devices/*; do
    [ -f "$d/idVendor" ] || continue
    [ -f "$d/idProduct" ] || continue

    vendor="$(cat "$d/idVendor" | tr 'A-F' 'a-f')"
    product="$(cat "$d/idProduct" | tr 'A-F' 'a-f')"

    if [ "$vendor" = "$ANT_USB_VENDOR" ] && [ "$product" = "$ANT_USB_PRODUCT" ] && [ "$ANT_FINISHED" -eq 0 ]; then
      echo "Resetting ANT+ USB device $d for VM $VMID phase $PHASE"
      ANT_FINISHED=1
    fi

    if [ "$vendor" = "$BLUETOOTH_USB_VENDOR" ] && [ "$product" = "$BLUETOOTH_USB_PRODUCT" ] && [ "$BLUETOOTH_FINISHED" -eq 0 ]; then
      echo "Resetting Bluetooth USB device $d for VM $VMID phase $PHASE"
      BLUETOOTH_FINISHED=1
    fi

    if [ "$ANT_FINISHED" -eq 1 ] && [ "$BLUETOOTH_FINISHED" -eq 1 ]; then
      LOOP_FINISHED=1
      break
    fi
  done

done

if [ "$ANT_FINISHED" -eq 0 ]; then 
  echo "ANT+ USB device ${ANT_USB_VENDOR}:${ANT_USB_PRODUCT} not found"
  EXIT_CODE = 1
fi
if [ "$BLUETOOTH_FINISHED" -eq 0 ]; then 
  echo "Bluetooth USB device ${BLUETOOTH_USB_VENDOR}:${BLUETOOTH_USB_PRODUCT} not found"
  EXIT_CODE = 1
fi
exit "$EXIT_CODE"