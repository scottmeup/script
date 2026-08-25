# Build and deploy Cronos Dropbear with Termux SFTP

## 1. Build on the build machine

Install `bash`, `git`, `curl` or `wget`, `unzip`, `coreutils`, `file`, and `binutils`. Copy `dropbear-cronos-bootstrap.env.example` to `dropbear-cronos-bootstrap.env`, then run:

```bash
chmod 755 build-dropbear-cronos-bootstrap.sh
./build-dropbear-cronos-bootstrap.sh
```

Confirm `output/build-manifest.txt` identifies an ELF32 ARM binary and contains the required PATH plus `/data/local/bin/dropbear-sftp-server`.

## 2. Transfer to the separate ADB host

Transfer these files from the build machine to the ADB host using the available trusted method:

```text
output/dropbear
prepare-dropbear-sftp-candidate-local.sh
validate-dropbear-sftp-candidate-windows.cmd
promote-dropbear-sftp-port22-local.sh
rollback-dropbear-sftp-port22-local.sh
```

The build machine is not assumed to have ADB access.

## 3. Stage and start the isolated candidate from the ADB host

```bash
adb shell mkdir -p /sdcard/dropbear-candidate
adb push dropbear /sdcard/dropbear-candidate/dropbear
adb push prepare-dropbear-sftp-candidate-local.sh /sdcard/dropbear-candidate/prepare-dropbear-sftp-candidate-local.sh
adb shell su -c '/system/bin/sh /sdcard/dropbear-candidate/prepare-dropbear-sftp-candidate-local.sh'
```

The script creates persistent candidate files under `/data/ssh-candidate`, recreates `/dev/dropbear-candidate/authorized_keys` with strict ownership and permissions, and starts port 2222 with `-D /dev/dropbear-candidate`. Port 22 remains unchanged.

## 4. Validate from Windows

```cmd
validate-dropbear-sftp-candidate-windows.cmd
```

The required result is:

```text
PASS: candidate SSH and SFTP validation completed.
```

## 5. Validate WinSCP on port 2222

Use SFTP, host `192.168.1.117`, port `2222`, username `root`, and the existing private key. Test listing, upload, rename, download, content comparison, and deletion. Do not promote if any test fails.

## 6. Promote after all candidate tests pass

From the ADB host:

```bash
adb push promote-dropbear-sftp-port22-local.sh /sdcard/dropbear-candidate/promote-dropbear-sftp-port22-local.sh
adb push rollback-dropbear-sftp-port22-local.sh /sdcard/dropbear-candidate/rollback-dropbear-sftp-port22-local.sh
adb shell su -c 'PROMOTE=YES /system/bin/sh /sdcard/dropbear-candidate/promote-dropbear-sftp-port22-local.sh'
```

Record the printed `/data/ssh-backup-before-sftp-YYYYMMDD-HHMMSS` path.

## 7. Validate port 22 and reboot persistence

Run the Windows validator with `CRONOS_PORT=22`, repeat the WinSCP test on port 22, reboot the Echo, and repeat SSH and SFTP validation after reboot. Keep ADB available until all checks pass.

## 8. Cleanup after successful reboot validation

Cleanup removes candidate-only runtime and staging state. It does not remove the promotion backup:

```bash
adb shell su -c 'if [ -f /data/ssh-candidate/dropbear.pid ]; then pid=$(cat /data/ssh-candidate/dropbear.pid 2>/dev/null); [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; fi; rm -rf /data/ssh-candidate /dev/dropbear-candidate /sdcard/dropbear-candidate'
```

Keep the timestamped promotion backup until the final installation has remained stable for an appropriate period.

## 9. Rollback

From the ADB host, substitute the exact recorded backup path:

```bash
adb shell su -c 'BACKUP_DIR=/data/ssh-backup-before-sftp-YYYYMMDD-HHMMSS /system/bin/sh /sdcard/dropbear-candidate/rollback-dropbear-sftp-port22-local.sh'
```

Rollback restores the original Dropbear binary and boot service. Added SFTP files remain inert under the restored service.

## Validated deployment result

The completed deployment passed root SSH, the full compiled PATH, `/dev/script`, `/dev/user-script`, `termux-shell`, command-line SFTP, WinSCP SFTP, port 22 promotion, and post-reboot validation.
