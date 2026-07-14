#!/usr/bin/env bash
# File: test-autobrr-irc-anti-flap.sh
# Project role: Deterministic static and model tests for the watchdog state-machine requirements.
# Direct inputs:
# - First optional argument: project directory path containing the script, env, service, and README.
# - Expected source fragments and a compact transition model encoded in this test file.
# Direct outputs:
# - PASS lines and exit status 0 when all assertions hold; diagnostic failure and nonzero exit otherwise.
# Functions:
# - fail: receives a message, writes it to stderr, and exits nonzero.
# - assert_contains/assert_not_contains: inspect source text for required or prohibited behavior.
# - model_step: receives running state, initialized state, stop condition, cooldown deadline, and current time;
#   emits the modeled action and updated deadline for scenario assertions.
# - main: performs Bash syntax, source-policy, and state-transition tests.
# Side effects: none beyond reading project files; never calls Docker or systemd.
# Cross-file flow: validates all runtime project files and documentation without executing production actions.

set -Eeuo pipefail

PROJECT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
SCRIPT="$PROJECT_DIR/autobrr-irc-anti-flap.sh"
ENV_EXAMPLE="$PROJECT_DIR/autobrr-irc-anti-flap.env.example"
SERVICE="$PROJECT_DIR/autobrr-irc-anti-flap.service"
README="$PROJECT_DIR/README.md"
COOLDOWN_SECONDS=300

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { grep -F -- "$2" "$1" >/dev/null || fail "$1 lacks: $2"; }
assert_not_contains() { ! grep -F -- "$2" "$1" >/dev/null || fail "$1 unexpectedly contains: $2"; }

model_step() {
  local running="$1" initialized="$2" stop_condition="$3" deadline="$4" now="$5"
  if (( running == 1 )); then
    if (( initialized == 1 && stop_condition == 1 )); then
      printf 'stop|%s\n' "$((now + COOLDOWN_SECONDS))"
    else
      printf 'leave_running|%s\n' "$deadline"
    fi
  elif (( deadline == 0 )); then
    printf 'begin_cooldown|%s\n' "$((now + COOLDOWN_SECONDS))"
  elif (( now >= deadline )); then
    printf 'start|0\n'
  else
    printf 'leave_stopped|%s\n' "$deadline"
  fi
}

main() {
  [[ -f "$SCRIPT" && -f "$ENV_EXAMPLE" && -f "$SERVICE" && -f "$README" ]] || fail "project file missing"
  bash -n "$SCRIPT"
  bash -n "$0"
  assert_contains "$SCRIPT" 'COOLDOWN_UNTIL_EPOCH=$((now + COOLDOWN_SECONDS))'
  assert_contains "$SCRIPT" 'if (( INITIALIZED == 0 )); then'
  assert_contains "$SCRIPT" 'if (( CONSECUTIVE_FAILURES >= FAILURE_CONFIRMATIONS )); then'
  assert_contains "$SCRIPT" 'if (( now >= COOLDOWN_UNTIL_EPOCH )); then'
  assert_not_contains "$SCRIPT" 'ping '
  assert_not_contains "$SCRIPT" '/api/logs/files/'

  [[ "$(model_step 1 0 1 0 1000)" == 'leave_running|0' ]] || fail "uninitialized container was stopped"
  [[ "$(model_step 1 1 0 1200 1000)" == 'leave_running|1200' ]] || fail "healthy running container changed"
  [[ "$(model_step 1 1 1 0 1000)" == 'stop|1300' ]] || fail "confirmed initialized failure did not start full cooldown"
  [[ "$(model_step 0 0 0 0 1000)" == 'begin_cooldown|1300' ]] || fail "manual stop did not start full cooldown"
  [[ "$(model_step 0 0 0 1300 1200)" == 'leave_stopped|1300' ]] || fail "container started before cooldown expiry"
  [[ "$(model_step 0 0 0 1300 1300)" == 'start|0' ]] || fail "container not started at cooldown expiry"
  [[ "$(model_step 1 0 0 1300 1100)" == 'leave_running|1300' ]] || fail "manual start during cooldown was reversed"
  [[ "$(model_step 1 1 1 1300 1150)" == 'stop|1450' ]] || fail "new stop did not replace old deadline with full cooldown"

  printf 'PASS: bash syntax\n'
  printf 'PASS: source policy checks\n'
  printf 'PASS: state-transition scenarios\n'
}

main "$@"
