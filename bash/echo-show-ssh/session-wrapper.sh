#!/system/bin/sh

# Save to /data/ssh/session-wrapper.sh
# in terminal run:
# chown root:root /data/ssh/session-wrapper.sh
# chmod 700 /data/ssh/session-wrapper.sh

export PATH=/sbin:/system/sbin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin:/data/adb/magisk
export HOME=/
export SHELL=/system/bin/sh
export USER=root
export LOGNAME=root
export ANDROID_ROOT=/system
export ANDROID_DATA=/data
export EXTERNAL_STORAGE=/sdcard
export TMPDIR=/data/local/tmp

if [ -n "$SSH_ORIGINAL_COMMAND" ]; then
    exec /system/bin/sh -c "$SSH_ORIGINAL_COMMAND"
fi

exec /system/bin/sh -i