# Cronos Dropbear plus Termux SFTP bootstrap project

## Project tree

```text
dropbear-cronos-bootstrap.env.example
build-dropbear-cronos-bootstrap.sh
prepare-dropbear-sftp-candidate-local.sh
validate-dropbear-sftp-candidate-windows.cmd
promote-dropbear-sftp-port22-local.sh
rollback-dropbear-sftp-port22-local.sh
PROJECT-DOCUMENTATION.md
RUN-DROPBEAR-SFTP-BOOTSTRAP.md
```

## Project-wide flow

The build-host script downloads and verifies a project-local Android NDK, clones the pinned Android Dropbear build adapter, applies the Cronos PATH and SFTP compile-time settings, builds an ARMv7 server, and validates its embedded values. The candidate script relocates the Termux SFTP server and its non-system library, recreates `/dev/dropbear-candidate` for public-key authentication, starts Dropbear on port 2222, and leaves port 22 untouched. The Windows validator exercises SSH, PATH, and SFTP. Promotion backs up each replaced functional file and changes port 22 only after explicit opt-in. Rollback restores the captured binary and service.

## Runtime authentication design

The persistent public key remains at `/data/ssh/authorized_keys`. Candidate startup copies it to `/dev/dropbear-candidate/authorized_keys`, sets the directory to `root:root` mode `700`, sets the key to `root:root` mode `600`, and starts Dropbear with `-D /dev/dropbear-candidate`. This mirrors the proven working final layout at `/dev/dropbear`. The `/dev` candidate directory is volatile and is recreated whenever the candidate preparation script runs.

## File roles

### dropbear-cronos-bootstrap.env.example

Provides build locations, pinned source and toolchain identifiers, target API and ABI, Echo address, ports, key path, compiled PATH, and the stable SFTP wrapper path.

### build-dropbear-cronos-bootstrap.sh

Creates the ARMv7 `dropbear` binary and build manifest. It verifies architecture, compiled PATH, and `/data/local/bin/dropbear-sftp-server`.

### prepare-dropbear-sftp-candidate-local.sh

Runs as root on the Echo. It consumes the staged binary, persistent key material, and installed Termux SFTP files. It creates `/data/ssh-candidate`, recreates `/dev/dropbear-candidate`, and starts only port 2222.

### validate-dropbear-sftp-candidate-windows.cmd

Validates root SSH, the compiled PATH, `/dev/script`, `/dev/user-script`, `termux-shell`, SFTP upload, rename, download, deletion, and byte equality.

### promote-dropbear-sftp-port22-local.sh

Backs up the current server, installs the validated candidate and SFTP files, uses `/dev/dropbear` for runtime authentication, starts port 22, and restores the previous binary and service if startup fails.

### rollback-dropbear-sftp-port22-local.sh

Restores the captured binary and boot service from the selected promotion backup and verifies startup.

### RUN-DROPBEAR-SFTP-BOOTSTRAP.md

Contains the ordered build, transfer between the separate build and ADB hosts, candidate test, WinSCP test, promotion, reboot verification, cleanup, and rollback procedure.

## Proven result

The rebuilt Dropbear 2026.94 ARMv7/API 24 binary passed root public-key SSH, the complete compiled PATH, `/dev/script`, `/dev/user-script`, Termux command resolution, command-line SFTP, WinSCP SFTP, port 22 promotion, and post-reboot validation on the Cronos Echo.
