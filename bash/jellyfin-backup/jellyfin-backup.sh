#!/usr/bin/env bash
# Outputs:
# - Backup archive: .tar.gz file in BACKUP_OUTPUT_DIR containing selected Jellyfin configuration and database files under a jellyfin/ root.
# Variables:
# - ENV_FILE: optional environment variable or first CLI argument; path to a .env file containing backup settings. If omitted, the script reads ./jellyfin-backup.env.
# - SCRIPT_DIR: directory containing this script, used to locate the default .env file.
# - ENV_PATH: selected .env path from ENV_FILE, first CLI argument, or ./backup_jellyfin.env.
# - MANIFEST_FILE: temporary file containing relative paths selected for backup.
# - STAGING_DIR: temporary directory used to assemble the archive.
# - ARCHIVE_PATH: final compressed archive path.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATH="/opt/script/jellyfin-backup.env"
MANIFEST_FILE="$(mktemp)"
STAGING_DIR=''
ARCHIVE_PATH=''

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

load_env() {
  #local env_path="$1"
  local env_path="$ENV_PATH"
  [[ -f "$env_path" ]] || fail "Env file not found: $env_path"
  set -a
  # shellcheck disable=SC1090
  source "$env_path"
  set +a
}

bool_is_true() {
  local value="${1:-0}"
  case "${value,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

is_excluded_path() {
  local rel="$1"
  case "/$rel" in
    */metadata/*|*/metadata|*/cache/*|*/cache|*/logs/*|*/logs|*/log/*|*/log|*/transcodes/*|*/transcodes|*/transcode/*|*/transcode|*/temp/*|*/temp|*/tmp/*|*/tmp|*/trickplay/*|*/trickplay|*/chapter-images/*|*/chapter-images|*/previews/*|*/previews|*/imagesbyname/*|*/imagesbyname)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

add_file_if_allowed() {
  local absolute="$1"
  local rel
  [[ -f "$absolute" ]] || return 0
  rel="${absolute#"$JELLYFIN_CONFIG_DIR"/}"
  [[ "$rel" != "$absolute" ]] || return 0
  if is_excluded_path "$rel"; then
    info "Skipping excluded path: $rel"
    return 0
  fi
  printf '%s\n' "$rel" >> "$MANIFEST_FILE"
}

discover_files() {
  : > "$MANIFEST_FILE"

  find "$JELLYFIN_CONFIG_DIR" -maxdepth 1 -type f \( \
    -name '*.xml' -o -name '*.json' -o -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db-wal' -o -name '*.db-shm' -o -name '*.sqlite-wal' -o -name '*.sqlite-shm' \
  \) -print0 | while IFS= read -r -d '' file; do
    add_file_if_allowed "$file"
  done

  for dir in config root default; do
    if [[ -d "$JELLYFIN_CONFIG_DIR/$dir" ]]; then
      find "$JELLYFIN_CONFIG_DIR/$dir" -type f \( \
        -name '*.xml' -o -name '*.json' -o -name '*.conf' -o -name '*.config' -o -name '*.ini' -o -name '*.yaml' -o -name '*.yml' \
      \) -print0 | while IFS= read -r -d '' file; do
        add_file_if_allowed "$file"
      done
    fi
  done

  if [[ -d "$JELLYFIN_CONFIG_DIR/data" ]]; then
    find "$JELLYFIN_CONFIG_DIR/data" -type f \( \
      -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db-wal' -o -name '*.db-shm' -o -name '*.sqlite-wal' -o -name '*.sqlite-shm' -o -name '*.xml' -o -name '*.json' \
    \) -print0 | while IFS= read -r -d '' file; do
      add_file_if_allowed "$file"
    done
  fi

  if bool_is_true "${INCLUDE_PLUGIN_CONFIGS:-1}" && [[ -d "$JELLYFIN_CONFIG_DIR/plugins/configurations" ]]; then
    find "$JELLYFIN_CONFIG_DIR/plugins/configurations" -type f \( \
      -name '*.xml' -o -name '*.json' -o -name '*.conf' -o -name '*.config' -o -name '*.ini' -o -name '*.yaml' -o -name '*.yml' \
    \) -print0 | while IFS= read -r -d '' file; do
      add_file_if_allowed "$file"
    done
  fi

  if [[ -n "${EXTRA_INCLUDE_PATHS:-}" ]]; then
    local old_ifs="$IFS"
    IFS=':'
    read -r -a extra_paths <<< "$EXTRA_INCLUDE_PATHS"
    IFS="$old_ifs"
    for rel in "${extra_paths[@]}"; do
      [[ -n "$rel" ]] || continue
      rel="${rel#/}"
      if is_excluded_path "$rel"; then
        info "Skipping excluded extra include path: $rel"
        continue
      fi
      if [[ -f "$JELLYFIN_CONFIG_DIR/$rel" ]]; then
        add_file_if_allowed "$JELLYFIN_CONFIG_DIR/$rel"
      elif [[ -d "$JELLYFIN_CONFIG_DIR/$rel" ]]; then
        find "$JELLYFIN_CONFIG_DIR/$rel" -type f -print0 | while IFS= read -r -d '' file; do
          add_file_if_allowed "$file"
        done
      else
        info "Extra include path not found, skipping: $rel"
      fi
    done
  fi

  sort -u "$MANIFEST_FILE" -o "$MANIFEST_FILE"
}

run_optional_stop() {
  if [[ -n "${STOP_JELLYFIN_COMMAND:-}" ]]; then
    info "Running stop command: $STOP_JELLYFIN_COMMAND"
    bash -c "$STOP_JELLYFIN_COMMAND"
  elif bool_is_true "${REQUIRE_STOP:-0}"; then
    fail "REQUIRE_STOP=1 but STOP_JELLYFIN_COMMAND is empty"
  else
    info "No stop command configured. For best database consistency, run backups while Jellyfin is stopped."
  fi
}

run_optional_start() {
  if [[ -n "${START_JELLYFIN_COMMAND:-}" ]]; then
    info "Running start command: $START_JELLYFIN_COMMAND"
    bash -c "$START_JELLYFIN_COMMAND"
  fi
}

create_archive() {
  local backup_name_prefix="${BACKUP_NAME_PREFIX:-jellyfin-important-backup}"
  local timestamp
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  ARCHIVE_PATH="$BACKUP_OUTPUT_DIR/${backup_name_prefix}-${timestamp}.tar.gz"
  STAGING_DIR="$(mktemp -d)"
  mkdir -p "$STAGING_DIR/jellyfin-important"

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    mkdir -p "$STAGING_DIR/jellyfin-important/$(dirname "$rel")"
    cp -a "$JELLYFIN_CONFIG_DIR/$rel" "$STAGING_DIR/jellyfin-important/$rel"
  done < "$MANIFEST_FILE"

  tar -C "$STAGING_DIR" -czf "$ARCHIVE_PATH" jellyfin-important
  rm -rf "$STAGING_DIR"
}

write_checksum() {
  sha256sum "$ARCHIVE_PATH" > "$ARCHIVE_PATH.sha256"
}

trap '[[ -n "${STAGING_DIR:-}" && -d "$STAGING_DIR" ]] && rm -rf "$STAGING_DIR"; [[ -n "${MANIFEST_FILE:-}" && -f "$MANIFEST_FILE" ]] && rm -f "$MANIFEST_FILE"' EXIT

load_env "$ENV_PATH"

[[ -n "${JELLYFIN_CONFIG_DIR:-}" ]] || fail "JELLYFIN_CONFIG_DIR is required in $ENV_PATH"
[[ -n "${BACKUP_OUTPUT_DIR:-}" ]] || fail "BACKUP_OUTPUT_DIR is required in $ENV_PATH"
[[ -d "$JELLYFIN_CONFIG_DIR" ]] || fail "JELLYFIN_CONFIG_DIR does not exist or is not a directory: $JELLYFIN_CONFIG_DIR"
mkdir -p "$BACKUP_OUTPUT_DIR"
[[ -d "$BACKUP_OUTPUT_DIR" ]] || fail "BACKUP_OUTPUT_DIR could not be created: $BACKUP_OUTPUT_DIR"

JELLYFIN_CONFIG_DIR="$(cd "$JELLYFIN_CONFIG_DIR" && pwd)"
BACKUP_OUTPUT_DIR="$(cd "$BACKUP_OUTPUT_DIR" && pwd)"

run_optional_stop

discover_files

if [[ ! -s "$MANIFEST_FILE" ]]; then
  run_optional_start
  fail "No important Jellyfin config/database files were found to back up under $JELLYFIN_CONFIG_DIR"
fi

info "Selected files for backup:"
sed 's/^/  /' "$MANIFEST_FILE"

if bool_is_true "${DRY_RUN:-0}"; then
  info "DRY_RUN=1, no archive created."
  run_optional_start
  exit 0
fi

create_archive
write_checksum
run_optional_start

info "Backup archive: $ARCHIVE_PATH"
info "Checksum file: $ARCHIVE_PATH.sha256"
info "Archive size bytes: $(wc -c < "$ARCHIVE_PATH")"
info "SHA-256: $(cut -d ' ' -f 1 "$ARCHIVE_PATH.sha256")"
