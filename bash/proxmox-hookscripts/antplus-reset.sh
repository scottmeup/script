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

case "$PHASE" in
  pre-start|post-stop)
    ;;
  *)
    exit 0
    ;;
esac

for d in /sys/bus/usb/devices/*; do
  [ -f "$d/idVendor" ] || continue
  [ -f "$d/idProduct" ] || continue

  vendor="$(cat "$d/idVendor" | tr 'A-F' 'a-f')"
  product="$(cat "$d/idProduct" | tr 'A-F' 'a-f')"

  if [ "$vendor" = "$ANT_USB_VENDOR" ] && [ "$product" = "$ANT_USB_PRODUCT" ]; then
    echo "Resetting ANT+ USB device $d for VM $VMID phase $PHASE"

    if [ -w "$d/authorized" ]; then
      echo 0 > "$d/authorized"
      sleep "$ANT_RESET_SETTLE_SECONDS"
      echo 1 > "$d/authorized"
      sleep "$ANT_RESET_SETTLE_SECONDS"
      exit 0
    fi

    devname="$(basename "$d")"
    if [ -e "/sys/bus/usb/drivers/usb/unbind" ] && [ -e "/sys/bus/usb/drivers/usb/bind" ]; then
      echo -n "$devname" > /sys/bus/usb/drivers/usb/unbind || true
      sleep "$ANT_RESET_SETTLE_SECONDS"
      echo -n "$devname" > /sys/bus/usb/drivers/usb/bind || true
      sleep "$ANT_RESET_SETTLE_SECONDS"
      exit 0
    fi

    echo "No usable reset method found for $d"
    exit 0
  fi
done

echo "ANT+ USB device ${ANT_USB_VENDOR}:${ANT_USB_PRODUCT} not found"
exit 0