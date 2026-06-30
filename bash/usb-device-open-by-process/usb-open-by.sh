#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage:"
    echo "  $0"
    echo "  $0 <vendor:product> [vendor:product ...]"
    echo
    echo "Examples:"
    echo "  $0"
    echo "  $0 0fcf:1009"
    echo "  $0 0fcf:1009 046d:c52b"
}

validate_usb_id() {
    local usb_id="$1"

    if [[ ! "$usb_id" =~ ^[[:xdigit:]]{4}:[[:xdigit:]]{4}$ ]]; then
        echo "Error: invalid USB ID: $usb_id" >&2
        echo "USB IDs must be in the form vendor:product, for example 0fcf:1009" >&2
        exit 1
    fi
}

run_lsof_for_lsusb_line() {
    local line="$1"
    local bus
    local device
    local dev_path
    local lsof_output

    bus="$(awk '{print $2}' <<< "$line")"
    device="$(awk '{gsub(":", "", $4); print $4}' <<< "$line")"

    dev_path="/dev/bus/usb/$bus/$device"

    echo "Matched USB device:"
    echo "  $line"
    echo "Linux device node:"
    echo "  $dev_path"

    if [[ ! -e "$dev_path" ]]; then
        echo "Status:"
        echo "  Device node does not exist"
        echo
        return
    fi

    lsof_output="$(sudo lsof "$dev_path" 2>&1 || true)"

    echo "lsof result:"

    if [[ -z "$lsof_output" ]]; then
        echo "  Device does not appear to be in use"
    else
        sed 's/^/  /' <<< "$lsof_output"
    fi

    echo
}

process_usb_id() {
    local usb_id="$1"
    local usb_id_lower
    local matches

    validate_usb_id "$usb_id"

    usb_id_lower="$(tr '[:upper:]' '[:lower:]' <<< "$usb_id")"

    matches="$(
        lsusb | awk -v id="$usb_id_lower" '
            {
                line = tolower($0)
                if (line ~ "id " id) {
                    print $0
                }
            }
        '
    )"

    if [[ -z "$matches" ]]; then
        echo "No USB device found matching ID $usb_id"
        echo
        return
    fi

    while IFS= read -r line; do
        run_lsof_for_lsusb_line "$line"
    done <<< "$matches"
}

process_all_devices() {
    local devices

    devices="$(lsusb)"

    if [[ -z "$devices" ]]; then
        echo "No USB devices found by lsusb"
        exit 1
    fi

    while IFS= read -r line; do
        run_lsof_for_lsusb_line "$line"
    done <<< "$devices"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -eq 0 ]]; then
    process_all_devices
else
    for usb_id in "$@"; do
        process_usb_id "$usb_id"
    done
fi