# Cronos SSH, Termux, script mirroring, and UI controls

## Changes

The installer adds a new Magisk service, installs commands under `/data/local/bin`, adds a Termux profile fragment for `/dev/user-script`, and modifies `/data/ssh/session-wrapper.sh` only by replacing its PATH line. It backs up every replaced file. It does not modify `90-dropbear-sshd.sh`.

The derived runtime directories are true mirrors. When a source entry is removed, the corresponding runtime entry is removed on the next rebuild. Runtime `.sh` filenames lose the suffix and become executable. Source files remain unchanged.

## Install

Copy `cronos-integration.env.example` to `cronos-integration.env`, review it, and keep all payload files beside the installer. Then run from a Bash-capable ADB host:

```sh
chmod 755 install-cronos-integration.sh uninstall-cronos-integration.sh
./install-cronos-integration.sh
```

## Validate before reboot

From SSH:

```sh
which termux-shell
echo "$PATH"
termux-shell
```

Inside the Termux shell:

```sh
id
echo "$PREFIX"
echo "$PATH"
pkg update
```

Package installation should be performed inside the normal Termux app or through `termux-shell`, which runs under the Termux UID. Do not run `pkg` directly as root.

Create test sources:

```sh
mkdir -p /sdcard/script /sdcard/user-script
printf '#!/system/bin/sh\necho root-script-ok\n' > /sdcard/script/root-test.sh
printf '#!/data/data/com.termux/files/usr/bin/sh\necho user-script-ok\n' > /sdcard/user-script/user-test.sh
sleep 4
/dev/script/root-test
termux-shell -c /dev/user-script/user-test
```

UI controls from SSH or ADB root:

```sh
disable-echo-ui
enable-echo-ui
```

## Reboot validation

After all manual tests pass, reboot and verify `/dev/script`, `/dev/user-script`, `termux-shell`, UI controls, and SSH PATH before changing any other components.

## Rollback

Use the timestamp printed by the installer:

```sh
BACKUP_SUFFIX=YYYYMMDD-HHMMSS ./uninstall-cronos-integration.sh
```
