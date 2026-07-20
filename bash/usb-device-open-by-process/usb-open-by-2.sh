#!/usr/bin/env bash
set -u -o pipefail

section() {
    printf '\n%s\n' "================================================================================"
    printf '%s\n' "$1"
    printf '%s\n' "================================================================================"
}

subsection() {
    printf '\n%s\n' "--------------------------------------------------------------------------------"
    printf '%s\n' "$1"
    printf '%s\n' "--------------------------------------------------------------------------------"
}

indent() {
    sed 's/^/  /'
}

run_and_show() {
    local title="$1"
    shift

    subsection "$title"

    local output
    output="$("$@" 2>&1)"
    local rc=$?

    if [[ -z "$output" ]]; then
        echo "  No output"
    else
        printf '%s\n' "$output" | indent
    fi

    if [[ "$rc" -ne 0 ]]; then
        echo "  Exit code: $rc"
    fi
}

run_lsof_path() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        echo "  Path does not exist: $path"
        return
    fi

    local output
    output="$(sudo lsof "$path" 2>&1)"
    local rc=$?

    if [[ -z "$output" ]]; then
        echo "  No lsof output; no user-space process appears to have this path open"
    else
        printf '%s\n' "$output" | indent
    fi

    if [[ "$rc" -ne 0 && "$rc" -ne 1 ]]; then
        echo "  lsof exit code: $rc"
    fi
}

run_fuser_path() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        echo "  Path does not exist: $path"
        return
    fi

    local output
    output="$(sudo fuser -v "$path" 2>&1)"
    local rc=$?

    if [[ -z "$output" ]]; then
        echo "  No fuser output; no user-space process appears to have this path open"
    else
        printf '%s\n' "$output" | indent
    fi

    if [[ "$rc" -ne 0 && "$rc" -ne 1 ]]; then
        echo "  fuser exit code: $rc"
    fi
}

run_lsof_mount() {
    local mountpoint="$1"

    if [[ ! -d "$mountpoint" ]]; then
        echo "  Mountpoint does not exist or is not a directory: $mountpoint"
        return
    fi

    local output
    output="$(sudo lsof +f -- "$mountpoint" 2>&1)"
    local rc=$?

    if [[ -z "$output" ]]; then
        echo "  No lsof output for mounted filesystem"
    else
        printf '%s\n' "$output" | indent
    fi

    if [[ "$rc" -ne 0 && "$rc" -ne 1 ]]; then
        echo "  lsof exit code: $rc"
    fi
}

run_fuser_mount() {
    local mountpoint="$1"

    if [[ ! -d "$mountpoint" ]]; then
        echo "  Mountpoint does not exist or is not a directory: $mountpoint"
        return
    fi

    local output
    output="$(sudo fuser -vm "$mountpoint" 2>&1)"
    local rc=$?

    if [[ -z "$output" ]]; then
        echo "  No fuser output for mounted filesystem"
    else
        printf '%s\n' "$output" | indent
    fi

    if [[ "$rc" -ne 0 && "$rc" -ne 1 ]]; then
        echo "  fuser exit code: $rc"
    fi
}

udev_properties_for_sys_path() {
    local sys_path="$1"

    if [[ ! -e "$sys_path" ]]; then
        return
    fi

    local rel="${sys_path#/sys}"
    udevadm info -q property -p "$rel" 2>/dev/null || true
}

udev_all_for_node() {
    local node="$1"

    if [[ ! -e "$node" ]]; then
        echo "  Path does not exist: $node"
        return
    fi

    local output
    output="$(udevadm info -q all -n "$node" 2>&1)"
    local rc=$?

    if [[ -z "$output" ]]; then
        echo "  No udevadm output"
    else
        printf '%s\n' "$output" | indent
    fi

    if [[ "$rc" -ne 0 ]]; then
        echo "  udevadm exit code: $rc"
    fi
}

unique_lines() {
    awk 'NF && !seen[$0]++'
}

get_related_nodes_for_sysfs() {
    local sysfs_root="$1"

    if [[ ! -d "$sysfs_root" ]]; then
        return
    fi

    find "$sysfs_root" -name dev -type f 2>/dev/null | while IFS= read -r dev_file; do
        local node_sys
        node_sys="$(dirname "$dev_file")"

        udev_properties_for_sys_path "$node_sys" | awk -F= '
            $1 == "DEVNAME" { print $2 }
            $1 == "DEVLINKS" {
                for (i = 2; i <= NF; i++) {
                    split($i, links, " ")
                    for (j in links) print links[j]
                }
            }
        '
    done | unique_lines
}

get_mountpoints_for_node() {
    local node="$1"

    if [[ ! -e "$node" ]]; then
        return
    fi

    lsblk -nrpo MOUNTPOINT "$node" 2>/dev/null | awk 'NF' | unique_lines
}

get_external_mountpoints() {
    lsblk -nrpo NAME,TRAN,RM,TYPE,MOUNTPOINT 2>/dev/null | awk '
        {
            name=$1
            tran=$2
            rm=$3
            type=$4
            $1=$2=$3=$4=""
            sub(/^[[:space:]]+/, "", $0)
            mountpoint=$0
            if (mountpoint != "" && (tran == "usb" || rm == "1")) {
                print mountpoint
            }
        }
    ' | unique_lines
}

glob_existing() {
    local p
    for p in "$@"; do
        [[ -e "$p" ]] && printf '%s\n' "$p"
    done
}

common_device_nodes() {
    shopt -s nullglob
    glob_existing \
        /dev/ttyUSB* \
        /dev/ttyACM* \
        /dev/hidraw* \
        /dev/input/event* \
        /dev/video* \
        /dev/media* \
        /dev/snd/*
    shopt -u nullglob
}

process_usb_device() {
    local line="$1"
    local bus="$2"
    local device="$3"
    local usb_id="$4"
    local devbus="/dev/bus/usb/$bus/$device"

    section "USB device $usb_id on bus $bus device $device"

    subsection "lsusb entry"
    echo "  $line"

    subsection "Raw USB device node"
    echo "  $devbus"

    subsection "sudo lsof on raw USB node"
    run_lsof_path "$devbus"

    subsection "sudo fuser on raw USB node"
    run_fuser_path "$devbus"

    local sys_rel=""
    local sys_abs=""

    if [[ -e "$devbus" ]]; then
        sys_rel="$(udevadm info -q path -n "$devbus" 2>/dev/null || true)"
        if [[ -n "$sys_rel" ]]; then
            sys_abs="/sys$sys_rel"
        fi
    fi

    subsection "Kernel/sysfs path"
    if [[ -n "$sys_abs" && -e "$sys_abs" ]]; then
        echo "  $sys_abs"
    else
        echo "  No sysfs path found via udevadm for $devbus"
    fi

    subsection "udevadm info for raw USB node"
    if [[ -e "$devbus" ]]; then
        udev_all_for_node "$devbus"
    else
        echo "  Raw USB node does not exist"
    fi

    subsection "USB hierarchy from lsusb -t"
    local tree
    tree="$(lsusb -t 2>&1)"
    if [[ -z "$tree" ]]; then
        echo "  No output"
    else
        printf '%s\n' "$tree" | indent
    fi

    local related_nodes=""
    if [[ -n "$sys_abs" && -d "$sys_abs" ]]; then
        related_nodes="$(get_related_nodes_for_sysfs "$sys_abs")"
    fi

    subsection "Related /dev nodes discovered from sysfs subtree"
    if [[ -z "$related_nodes" ]]; then
        echo "  No related /dev nodes discovered"
    else
        printf '%s\n' "$related_nodes" | indent
    fi

    if [[ -n "$related_nodes" ]]; then
        while IFS= read -r node; do
            [[ -z "$node" ]] && continue

            subsection "udevadm info -q all -n $node"
            udev_all_for_node "$node"

            subsection "sudo lsof $node"
            run_lsof_path "$node"

            subsection "sudo fuser -v $node"
            run_fuser_path "$node"

            local mountpoints
            mountpoints="$(get_mountpoints_for_node "$node")"

            if [[ -n "$mountpoints" ]]; then
                while IFS= read -r mountpoint; do
                    [[ -z "$mountpoint" ]] && continue

                    subsection "Mounted filesystem related to $node: $mountpoint"

                    subsection "sudo lsof +f -- $mountpoint"
                    run_lsof_mount "$mountpoint"

                    subsection "sudo fuser -vm $mountpoint"
                    run_fuser_mount "$mountpoint"
                done <<< "$mountpoints"
            fi
        done <<< "$related_nodes"
    fi
}

process_all_usb_devices() {
    local lsusb_output
    lsusb_output="$(lsusb 2>&1)"
    local rc=$?

    if [[ "$rc" -ne 0 ]]; then
        echo "lsusb failed:"
        printf '%s\n' "$lsusb_output" | indent
        exit "$rc"
    fi

    if [[ -z "$lsusb_output" ]]; then
        echo "No USB devices reported by lsusb"
        exit 0
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local bus
        local device
        local usb_id

        bus="$(awk '{print $2}' <<< "$line")"
        device="$(awk '{gsub(":", "", $4); print $4}' <<< "$line")"
        usb_id="$(awk '{print $6}' <<< "$line")"

        if [[ -z "$bus" || -z "$device" || -z "$usb_id" ]]; then
            section "Unparseable lsusb entry"
            echo "  $line"
            continue
        fi

        process_usb_device "$line" "$bus" "$device" "$usb_id"
    done <<< "$lsusb_output"
}

run_global_common_device_scan() {
    section "Global scan of common device nodes"

    local nodes
    nodes="$(common_device_nodes)"

    subsection "Common device nodes found"
    if [[ -z "$nodes" ]]; then
        echo "  No matching common device nodes found"
        return
    fi

    printf '%s\n' "$nodes" | indent

    subsection "sudo lsof on common device nodes"
    local output
    output="$(sudo lsof $nodes 2>/dev/null)"
    local rc=$?

    if [[ -z "$output" ]]; then
        echo "  No lsof output for common device nodes"
    else
        printf '%s\n' "$output" | indent
    fi

    if [[ "$rc" -ne 0 && "$rc" -ne 1 ]]; then
        echo "  lsof exit code: $rc"
    fi

    subsection "sudo fuser -v on common device nodes"
    output="$(sudo fuser -v $nodes 2>/dev/null)"
    rc=$?

    if [[ -z "$output" ]]; then
        echo "  No fuser output for common device nodes"
    else
        printf '%s\n' "$output" | indent
    fi

    if [[ "$rc" -ne 0 && "$rc" -ne 1 ]]; then
        echo "  fuser exit code: $rc"
    fi
}

run_external_mount_scan() {
    section "Global scan of mounted external devices"

    local mountpoints
    mountpoints="$(get_external_mountpoints)"

    subsection "Mounted external filesystems detected by lsblk"
    if [[ -z "$mountpoints" ]]; then
        echo "  No mounted external filesystems detected"
        return
    fi

    printf '%s\n' "$mountpoints" | indent

    while IFS= read -r mountpoint; do
        [[ -z "$mountpoint" ]] && continue

        subsection "sudo lsof +f -- $mountpoint"
        run_lsof_mount "$mountpoint"

        subsection "sudo fuser -vm $mountpoint"
        run_fuser_mount "$mountpoint"
    done <<< "$mountpoints"
}

main() {
    section "USB device usage report"
    echo "  Host: $(hostname 2>/dev/null || echo unknown)"
    echo "  Time: $(date -Is 2>/dev/null || date)"
    echo "  User: $(id -un 2>/dev/null || echo unknown)"

    process_all_usb_devices
    run_global_common_device_scan
    run_external_mount_scan
}

main "$@"