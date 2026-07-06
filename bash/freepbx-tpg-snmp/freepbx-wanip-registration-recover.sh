#!/usr/bin/env bash
# install this file to /usr/local/sbin/freepbx-wanip-registration-recover
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/freepbx-wanip-hosts/freepbx-wanip-hosts.env}"

if [ ! -r "$ENV_FILE" ]; then
  logger -t freepbx-wanip-recovery "environment file not readable: $ENV_FILE"
  exit 10
fi

. "$ENV_FILE"

TRUNK_NAME="${TRUNK_NAME:?TRUNK_NAME is required}"
REGISTER_STATUS_CHECK_INTERVAL_SECONDS="${REGISTER_STATUS_CHECK_INTERVAL_SECONDS:-1}"
REGISTER_COMMAND_INTERVAL_SECONDS="${REGISTER_COMMAND_INTERVAL_SECONDS:-10}"
REGISTER_FAILURE_TIMEOUT_SECONDS="${REGISTER_FAILURE_TIMEOUT_SECONDS:-180}"
REGISTER_STABLE_CHECKS="${REGISTER_STABLE_CHECKS:-5}"
ASTERISK_RESTART_ON_REGISTRATION_FAILURE="${ASTERISK_RESTART_ON_REGISTRATION_FAILURE:-yes}"
ASTERISK_RESTART_CALL_CHECK_INTERVAL_SECONDS="${ASTERISK_RESTART_CALL_CHECK_INTERVAL_SECONDS:-5}"
ASTERISK_RESTART_WAIT_TIMEOUT_SECONDS="${ASTERISK_RESTART_WAIT_TIMEOUT_SECONDS:-0}"
ASTERISK_RESTART_REGISTRATION_TIMEOUT_SECONDS="${ASTERISK_RESTART_REGISTRATION_TIMEOUT_SECONDS:-180}"

exec 8>/run/freepbx-wanip-registration-recover.lock
flock -n 8 || exit 0

log_msg() {
  logger -t freepbx-wanip-recovery "$1"
}

is_registered() {
  asterisk -rx "pjsip show registrations" 2>/dev/null |
    awk -v trunk="$TRUNK_NAME" '
      index($0, trunk "/") > 0 && index($0, "Registered") > 0 {
        found = 1
      }
      END {
        exit found ? 0 : 1
      }
    '
}

send_register() {
  asterisk -rx "pjsip send register $TRUNK_NAME" >/dev/null 2>&1 || true
}

trunk_call_active() {
  asterisk -rx "core show channels concise" 2>/dev/null |
    grep -F "PJSIP/${TRUNK_NAME}-" >/dev/null
}

wait_for_no_trunk_calls() {
  start_epoch="$(date +%s)"

  while trunk_call_active; do
    if [ "$ASTERISK_RESTART_WAIT_TIMEOUT_SECONDS" -gt 0 ]; then
      now_epoch="$(date +%s)"
      elapsed="$((now_epoch - start_epoch))"

      if [ "$elapsed" -ge "$ASTERISK_RESTART_WAIT_TIMEOUT_SECONDS" ]; then
        log_msg "restart deferred timeout reached while $TRUNK_NAME trunk calls are still active"
        return 1
      fi
    fi

    log_msg "$TRUNK_NAME trunk call active; delaying Asterisk restart"
    sleep "$ASTERISK_RESTART_CALL_CHECK_INTERVAL_SECONDS"
  done

  return 0
}

registration_retry_loop() {
  timeout_seconds="$1"
  start_epoch="$(date +%s)"
  last_register_epoch=0
  stable_checks=0

  while true; do
    now_epoch="$(date +%s)"
    elapsed="$((now_epoch - start_epoch))"

    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      if [ "$stable_checks" -ge "$REGISTER_STABLE_CHECKS" ]; then
        log_msg "$TRUNK_NAME is Registered and stable"
        return 0
      fi

      log_msg "$TRUNK_NAME did not become Registered and stable within ${timeout_seconds}s"
      return 1
    fi

    since_last_register="$((now_epoch - last_register_epoch))"

    if [ "$last_register_epoch" -eq 0 ] || [ "$since_last_register" -ge "$REGISTER_COMMAND_INTERVAL_SECONDS" ]; then
      log_msg "sending explicit register for $TRUNK_NAME"
      send_register
      last_register_epoch="$(date +%s)"
      stable_checks=0
    fi

    sleep "$REGISTER_STATUS_CHECK_INTERVAL_SECONDS"

    if is_registered; then
      stable_checks="$((stable_checks + 1))"

      if [ "$stable_checks" -ge "$REGISTER_STABLE_CHECKS" ]; then
        log_msg "$TRUNK_NAME is Registered and stable"
        return 0
      fi

      log_msg "$TRUNK_NAME is Registered; stable check ${stable_checks}/${REGISTER_STABLE_CHECKS}"
    else
      stable_checks=0
      log_msg "$TRUNK_NAME is not Registered; checking again in ${REGISTER_STATUS_CHECK_INTERVAL_SECONDS}s"
    fi
  done
}

log_msg "starting WAN IP registration recovery for $TRUNK_NAME"

if registration_retry_loop "$REGISTER_FAILURE_TIMEOUT_SECONDS"; then
  exit 0
fi

if [ "$ASTERISK_RESTART_ON_REGISTRATION_FAILURE" != "yes" ]; then
  log_msg "Asterisk restart disabled after registration failure"
  exit 1
fi

if ! wait_for_no_trunk_calls; then
  exit 2
fi

log_msg "restarting Asterisk after extended registration failure"

systemctl restart asterisk

sleep 5

if registration_retry_loop "$ASTERISK_RESTART_REGISTRATION_TIMEOUT_SECONDS"; then
  log_msg "registration recovered after Asterisk restart"
  exit 0
fi

log_msg "registration did not recover after Asterisk restart"
exit 3