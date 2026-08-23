#!/system/bin/sh
# Inputs: installed com.termux private prefix and dynamically resolved UID/GID.
# Output: interactive Termux Bash session under the Termux UID while retaining the Magisk SELinux domain.
# Processing: constructs the complete Termux environment and uses MagiskSU with required Android supplementary groups.
PREFIX=/data/data/com.termux/files/usr
HOME=/data/data/com.termux/files/home
UID_VALUE=$(stat -c %u /data/data/com.termux) || exit 1
GID_VALUE=$(stat -c %g /data/data/com.termux) || exit 1
export PREFIX HOME TMPDIR="$PREFIX/tmp" LANG=C.UTF-8
export PATH="$PREFIX/bin:/dev/user-script:/system/bin:/system/xbin"
export LD_LIBRARY_PATH="$PREFIX/lib"
export LD_PRELOAD="$PREFIX/lib/libtermux-exec-ld-preload.so"
export ANDROID_ROOT=/system ANDROID_DATA=/data EXTERNAL_STORAGE=/sdcard
if [ "$#" -gt 0 ]; then
    quoted=
    for arg in "$@"; do quoted="$quoted '$(printf %s "$arg" | sed "s/'/'\\''/g")'"; done
    exec su -g "$GID_VALUE" -G 3003 -G 9997 -G "$((UID_VALUE + 40000))" -s "$PREFIX/bin/bash" "$UID_VALUE" -c "cd '$HOME'; exec bash -lc $quoted"
fi
exec su -g "$GID_VALUE" -G 3003 -G 9997 -G "$((UID_VALUE + 40000))" -s "$PREFIX/bin/bash" "$UID_VALUE" -c "cd '$HOME'; exec bash -l"
