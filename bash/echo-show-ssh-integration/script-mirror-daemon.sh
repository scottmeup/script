#!/system/bin/sh
# Inputs: environment variables exported by 80-cronos-integration.sh; source trees under /sdcard/script and /sdcard/user-script.
# Outputs: one-way transformed mirrors under /dev/script and /dev/user-script; operation and error logs under /data/local/tmp.
# Functions: signature hashes source paths and contents; relative_path derives a checked source-relative path; transform_file copies one entry and removes a final .sh suffix; mirror_tree atomically replaces one changed destination.
# Globals: ROOT_SOURCE, USER_SOURCE, ROOT_RUNTIME, USER_RUNTIME, TERMUX_UID, TERMUX_GID, TERMUX_SECONTEXT, POLL_SECONDS, BB, LOG_FILE, ERROR_LOG.
set -u
BB=/data/adb/magisk/busybox
LOG_FILE=/data/local/tmp/cronos-script-mirror.log
ERROR_LOG=/data/local/tmp/cronos-script-mirror-errors.log
signature() {
    src=$1
    if [ ! -d "$src" ]; then
        printf 'missing'
        return
    fi
    "$BB" find "$src" -mindepth 1 -print0 2>/dev/null | "$BB" sort -z | while IFS= read -r -d '' p; do
        if [ -f "$p" ]; then
            "$BB" md5sum "$p" 2>/dev/null
        else
            "$BB" stat -c '%n|%F|%Y' "$p" 2>/dev/null
        fi
    done | "$BB" md5sum | "$BB" awk '{print $1}'
}
relative_path() {
    src=$1
    item=$2
    case "$item" in
        "$src"/*) "$BB" printf '%s\n' "$item" | "$BB" sed "s#^$src/##" ;;
        *) return 1 ;;
    esac
}
transform_file() {
    src_file=$1
    rel=$2
    dst_root=$3
    owner=$4
    group=$5
    context=$6
    case "$rel" in
        *.sh) out_rel=${rel%.sh}; mode=755 ;;
        *) out_rel=$rel; mode=644 ;;
    esac
    out="$dst_root/$out_rel"
    "$BB" mkdir -p "${out%/*}" || return 1
    "$BB" cp "$src_file" "$out" || return 1
    "$BB" chown "$owner:$group" "$out" || return 1
    "$BB" chmod "$mode" "$out" || return 1
    chcon "$context" "$out" 2>/dev/null || true
}
mirror_tree() {
    src=$1
    dst=$2
    owner=$3
    group=$4
    context=$5
    tmp="${dst}.new.$$"
    old="${dst}.old.$$"
    "$BB" rm -rf "$tmp" "$old"
    "$BB" mkdir -p "$tmp" || return 1
    if [ -d "$src" ]; then
        "$BB" find "$src" -mindepth 1 -print0 | while IFS= read -r -d '' p; do
            rel=$(relative_path "$src" "$p") || {
                printf '%s invalid source path: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$p" >> "$ERROR_LOG"
                continue
            }
            if [ -d "$p" ]; then
                "$BB" mkdir -p "$tmp/$rel" || exit 1
            elif [ -f "$p" ]; then
                transform_file "$p" "$rel" "$tmp" "$owner" "$group" "$context" || exit 1
            fi
        done || return 1
    fi
    "$BB" chown -R "$owner:$group" "$tmp" || return 1
    "$BB" find "$tmp" -type d -exec chmod 755 {} \; || return 1
    chcon -R "$context" "$tmp" 2>/dev/null || true
    [ -e "$dst" ] && "$BB" mv "$dst" "$old"
    "$BB" mv "$tmp" "$dst" || return 1
    "$BB" rm -rf "$old"
    printf '%s mirrored %s to %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$src" "$dst" >> "$LOG_FILE"
}
root_sig=
user_sig=
while :; do
    next_root=$(signature "$ROOT_SOURCE")
    next_user=$(signature "$USER_SOURCE")
    if [ "$next_root" != "$root_sig" ]; then
        if mirror_tree "$ROOT_SOURCE" "$ROOT_RUNTIME" 0 0 u:object_r:device:s0; then
            root_sig=$next_root
        else
            printf '%s root mirror failed\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$ERROR_LOG"
        fi
    fi
    if [ "$next_user" != "$user_sig" ]; then
        if mirror_tree "$USER_SOURCE" "$USER_RUNTIME" "$TERMUX_UID" "$TERMUX_GID" "$TERMUX_SECONTEXT"; then
            user_sig=$next_user
        else
            printf '%s user mirror failed\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$ERROR_LOG"
        fi
    fi
    "$BB" sleep "$POLL_SECONDS"
done
