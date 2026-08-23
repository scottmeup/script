# Transition from session wrapper to rebuilt Dropbear

## Required build settings

Compile Dropbear with `DEFAULT_ROOT_PATH` containing the existing Android paths plus `/data/local/bin`, `/dev/script`, `/dev/user-script`, and the Termux bin directory. Configure its external SFTP subsystem path to the final installed `sftp-server` path.

## File changes

1. Replace the current `90-dropbear-sshd.sh` with `90-dropbear-sshd-rebuilt.sh` only after the candidate passes SSH and SFTP on port 2222.
2. Remove `-c /data/ssh/session-wrapper.sh` from Dropbear startup.
3. Add `-e` and export Android, Termux, library, and PATH variables in the boot service.
4. Use `install-cronos-integration-rebuilt-dropbear.sh` for future integration installs. It does not modify `session-wrapper.sh`.
5. Keep `80-cronos-integration.sh`, `script-mirror-daemon.sh`, `termux-shell`, the Termux profile fragment, and UI controls unchanged.
6. Preserve `session-wrapper.sh` during the transition. It becomes unused, but should not be removed until the rebuilt daemon passes reboot, SSH, remote-command, SCP, SFTP, and forwarding tests.

## Promotion

Place the tested candidate at `/data/ssh/dropbear-rebuilt-candidate`, then run `migrate-to-rebuilt-dropbear.sh` from the ADB host. It backs up the current binary and service and does not reboot.

## Validation

Test ordinary SSH, `ssh host command`, `scp`, `sftp`, local forwarding, PATH, Android variables, `termux-shell`, `/dev/script`, and `/dev/user-script`. Then power-cycle and repeat before removing any obsolete wrapper.

## Rollback

Use the migration timestamp with `rollback-rebuilt-dropbear.sh`:

```sh
REBUILD_SUFFIX=YYYYMMDD-HHMMSS ./rollback-rebuilt-dropbear.sh
```
