#!/system/bin/sh
# Inputs: environment variables exported by 80-cronos-integration.sh; source trees under /sdcard/script and /sdcard/user-script.
# Outputs: mirrored executable trees under /dev/script and /dev/user-script; /data/local/tmp/cronos-script-mirror.log.
# Functions: signature computes a recursive change signature; mirror_tree atomically rebuilds only the changed destination; transform_file removes .sh suffixes and sets modes.
# Globals: ROOT_SOURCE, USER_SOURCE, ROOT_RUNTIME, USER_RUNTIME, TERMUX_UID, TERMUX_GID, TERMUX_SECONTEXT, POLL_SECONDS, LOG_FILE.
set -u
BB=/data/adb/magisk/busybox
LOG_FILE=/data/local/tmp/cronos-script-mirror.log
signature() {
    src=$1
    if [ ! -d "$src" ]; then
        printf 'missing'
        return
    fi
    "$BB" find "$src" -mindepth 1 -print0 2>/dev/null | "$BB" sort -z | while IFS= read -r -d '' p; do
        if [ -f "$p" ]; then "$BB" md5sum "$p" 2>/dev/null; else "$BB" stat -c '%n|%F|%Y' "$p" 2>/dev/null; fi
    done | "$BB" md5sum | "$BB" awk '{print $1}'
}
transform_file() {
    src=$1
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
    "$BB" mkdir -p "${out%/*}"
    "$BB" cp "$src" "$out"
    "$BB" chown "$owner:$group" "$out"
    "$BB" chmod "$mode" "$out"
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
    "$BB" mkdir -p "$tmp"
    if [ -d "$src" ]; then
        "$BB" find "$src" -mindepth 1 -print0 | while IFS= read -r -d '' p; do
            rel=${p#"$src"/}
            if [ -d "$p" ]; then
                "$BB" mkdir -p "$tmp/$rel"
            elif [ -f "$p" ]; then
                transform_file "$p" "$rel" "$tmp" "$owner" "$group" "$context"
            fi
        done
    fi
    "$BB" chown -R "$owner:$group" "$tmp"
    "$BB" find "$tmp" -type d -exec chmod 755 {} \;
    chcon -R "$context" "$tmp" 2>/dev/null || true
    [ -e "$dst" ] && "$BB" mv "$dst" "$old"
    "$BB" mv "$tmp" "$dst"
    "$BB" rm -rf "$old"
    printf '%s mirrored %s to %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$src" "$dst" >> "$LOG_FILE"
}
root_sig=
user_sig=
while :; do
    next_root=$(signature "$ROOT_SOURCE")
    next_user=$(signature "$USER_SOURCE")
    if [ "$next_root" != "$root_sig" ]; then
        mirror_tree "$ROOT_SOURCE" "$ROOT_RUNTIME" 0 0 u:object_r:device:s0
        root_sig=$next_root
    fi
    if [ "$next_user" != "$user_sig" ]; then
        mirror_tree "$USER_SOURCE" "$USER_RUNTIME" "$TERMUX_UID" "$TERMUX_GID" "$TERMUX_SECONTEXT"
        user_sig=$next_user
    fi
    "$BB" sleep "$POLL_SECONDS"
done
