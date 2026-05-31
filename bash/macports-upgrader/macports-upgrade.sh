#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"

if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

PORT_BIN="${PORT_BIN:-/opt/local/bin/port}"
SUDO_BIN="${SUDO_BIN:-/usr/bin/sudo}"
SUDO_KEEPALIVE_INTERVAL="${SUDO_KEEPALIVE_INTERVAL:-60}"
SLEEP_BETWEEN_PASSES="${SLEEP_BETWEEN_PASSES:-0}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-0}"
MODE="${MODE:-random}"

failed_ports=""
attempted_count=0
successful_count=0
last_attempted_port=""
prev_ports=()

cleanup() {
  if [ "${SUDO_KEEPALIVE_PID:-}" != "" ]; then
    kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

if [ ! -x "$PORT_BIN" ]; then
  echo "Error: port binary not found or not executable: $PORT_BIN" >&2
  exit 1
fi

if [ ! -x "$SUDO_BIN" ]; then
  echo "Error: sudo binary not found or not executable: $SUDO_BIN" >&2
  exit 1
fi

case "$MODE" in
  random|sequential)
    ;;
  *)
    echo "Error: MODE must be 'random' or 'sequential'" >&2
    exit 1
    ;;
esac

"$SUDO_BIN" -v || exit 1

(
  while true; do
    "$SUDO_BIN" -n true >/dev/null 2>&1 || exit
    sleep "$SUDO_KEEPALIVE_INTERVAL"
  done
) &
SUDO_KEEPALIVE_PID=$!

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

is_failed_port() {
  case ",$failed_ports," in
    *,"$1",*) return 0 ;;
    *) return 1 ;;
  esac
}

append_failed_port() {
  if [ "$failed_ports" = "" ]; then
    failed_ports="$1"
  else
    failed_ports="$failed_ports,$1"
  fi
}

array_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

get_outdated_ports() {
  "$PORT_BIN" outdated 2>/dev/null | awk '
    /^The following installed ports are outdated:/ { capture=1; next }
    capture && NF > 0 {
      if (!seen[$1]++) {
        print $1
      }
    }
  '
}

load_current_ports() {
  current_ports=()
  while IFS= read -r port_name; do
    [ -z "$port_name" ] && continue
    current_ports[${#current_ports[@]}]="$port_name"
  done < <(get_outdated_ports)
}

select_random_port() {
  selectable_ports=()
  local port_name
  for port_name in "${current_ports[@]}"; do
    if [ "$CONTINUE_ON_ERROR" = "1" ] && is_failed_port "$port_name"; then
      continue
    fi
    selectable_ports[${#selectable_ports[@]}]="$port_name"
  done

  if [ "${#selectable_ports[@]}" -eq 0 ]; then
    return 1
  fi

  selected_index=$((RANDOM % ${#selectable_ports[@]}))
  selected_port="${selectable_ports[$selected_index]}"
  return 0
}

select_sequential_port() {
  local i
  local found_index
  found_index=-1

  if [ "${#current_ports[@]}" -eq 0 ]; then
    return 1
  fi

  if [ "$last_attempted_port" = "" ] || [ "${#prev_ports[@]}" -eq 0 ]; then
    selected_port="${current_ports[0]}"
    return 0
  fi

  for ((i=0; i<${#prev_ports[@]}; i++)); do
    if [ "${prev_ports[$i]}" = "$last_attempted_port" ]; then
      found_index=$i
      break
    fi
  done

  if [ "$found_index" -ge 0 ]; then
    for ((i=found_index+1; i<${#prev_ports[@]}; i++)); do
      if array_contains "${prev_ports[$i]}" "${current_ports[@]}"; then
        selected_port="${prev_ports[$i]}"
        return 0
      fi
    done

    for ((i=0; i<=found_index; i++)); do
      if array_contains "${prev_ports[$i]}" "${current_ports[@]}"; then
        selected_port="${prev_ports[$i]}"
        return 0
      fi
    done
  fi

  selected_port="${current_ports[0]}"
  return 0
}

while true; do
  load_current_ports

  if [ "${#current_ports[@]}" -eq 0 ]; then
    echo "[$(timestamp)] No more outdated ports remain."
    echo "[$(timestamp)] Final summary | Attempted: $attempted_count | Successful: $successful_count"
    exit 0
  fi

  if [ "$MODE" = "random" ]; then
    if ! select_random_port; then
      echo "[$(timestamp)] No selectable outdated ports remain."
      echo "[$(timestamp)] Final summary | Attempted: $attempted_count | Successful: $successful_count | Failed and skipped: $failed_ports" >&2
      exit 1
    fi
  else
    if ! select_sequential_port; then
      echo "[$(timestamp)] No selectable outdated ports remain."
      echo "[$(timestamp)] Final summary | Attempted: $attempted_count | Successful: $successful_count" >&2
      exit 1
    fi
  fi

  next_attempt_number=$((attempted_count + 1))

  echo "[$(timestamp)] Attempt #$next_attempt_number | Attempted: $attempted_count | Successful: $successful_count | Current package: $selected_port"
  echo "[$(timestamp)] Running: $SUDO_BIN $PORT_BIN -N upgrade $selected_port"

  prev_ports=("${current_ports[@]}")
  last_attempted_port="$selected_port"

  if "$SUDO_BIN" "$PORT_BIN" -N upgrade "$selected_port"; then
    attempted_count=$((attempted_count + 1))
    successful_count=$((successful_count + 1))
    echo "[$(timestamp)] Upgrade succeeded: $selected_port"
    echo "[$(timestamp)] Summary | Attempted: $attempted_count | Successful: $successful_count"
  else
    attempted_count=$((attempted_count + 1))
    echo "[$(timestamp)] Upgrade failed: $selected_port" >&2
    echo "[$(timestamp)] Summary | Attempted: $attempted_count | Successful: $successful_count" >&2

    if [ "$CONTINUE_ON_ERROR" = "1" ]; then
      if [ "$MODE" = "random" ]; then
        append_failed_port "$selected_port"
        echo "[$(timestamp)] Continuing in random mode. Failed ports skipped for the remainder of this run: $failed_ports" >&2
      else
        echo "[$(timestamp)] Continuing in sequential mode." >&2
      fi
    else
      exit 1
    fi
  fi

  if [ "$SLEEP_BETWEEN_PASSES" -gt 0 ] 2>/dev/null; then
    sleep "$SLEEP_BETWEEN_PASSES"
  fi
done