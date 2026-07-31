#!/usr/bin/env bash
# jellyfin-library-pruner.sh
# Project-level summary:
# - Cleans Jellyfin movie/show library folders when trickplay images and sidecars are stored beside media files.
# - Reads a dotenv-style config file, scans configured movie and show roots, prints dry-run actions by default, and performs deletion only when DELETE_MODE=true.
# - Movie roots contain one movie folder per direct child. Show roots contain one show folder per direct child. Show folders contain season folders matching SEASON_DIR_GLOB.
# Inputs:
# - ENV_FILE: optional path to the dotenv config file. Defaults to ./.env. Used by main.
# - MOVIE_PATHS: colon-separated movie library roots. Each direct child is one movie folder. Used by process_movie_root.
# - SHOW_PATHS: colon-separated show library roots. Each direct child is one show folder. Used by process_show_root.
# - TV_PATHS: backward-compatible alias for SHOW_PATHS if SHOW_PATHS is empty. Used by main.
# - VIDEO_EXTENSIONS: space-separated playable media extensions without leading dots. Used by has_recursive_video, is_video_file, and matching_episode_video_exists.
# - EPISODE_SIDECAREXTENSIONS: space-separated file extensions treated as episode sidecars. Used by is_episode_sidecar_file.
# - TRICKPLAY_SUFFIX: suffix for Jellyfin trickplay directories. Default is .trickplay. Used by is_episode_sidecar_dir and sidecar_candidate_bases.
# - THUMB_SUFFIX: suffix used for episode thumbnail files before the extension. Default is -thumb. Used by sidecar_candidate_bases.
# - SEASON_DIR_GLOB: find -name pattern for season directories under a show folder. Default is Season *.
# - DELETE_MODE: boolean string true or false. false prints intended actions. true performs filesystem deletion.
# - CREATE_FORCE_RESCAN: boolean string true or false. true creates FORCE_RESCAN_FILENAME markers in configured library roots and preserved folders.
# - FORCE_RESCAN_FILENAME: marker filename. Default is .forcerescan.
# Outputs:
# - Console output: timestamped logs and dry-run/delete actions.
# - Filesystem side effects only when DELETE_MODE=true: movie folders without videos are deleted, orphan episode sidecars are deleted, empty/no-video season folders are deleted, show folders with no remaining videos are deleted, and optional .forcerescan files are created.
# Functions:
# - log: writes timestamped status messages.
# - fail: writes an error and exits non-zero.
# - load_env: reads and exports key=value config entries.
# - split_paths: converts colon-separated roots into newline-separated paths.
# - is_video_file: returns success if a file has a configured video extension.
# - has_recursive_video: returns success if a directory tree contains at least one configured video file.
# - remove_path: prints or performs file/directory deletion.
# - touch_force_rescan: prints or creates a rescan marker.
# - is_episode_sidecar_dir: returns success for episode-associated trickplay directories.
# - is_episode_sidecar_file: returns success for episode-associated sidecar files.
# - sidecar_candidate_bases: prints possible media basenames for a sidecar, including language subtitle handling.
# - matching_episode_video_exists: returns success if any sidecar candidate basename has a matching video file in the season directory.
# - clean_movie_folder: implements movie rules i and ii.
# - clean_episode_sidecars: implements episode rule iii inside seasons that still have at least one video.
# - clean_season_folder: implements season rules iv and v.
# - clean_show_folder: implements show root rules vi and vii after season cleanup.
# - process_movie_root: scans one movie library root.
# - process_show_root: scans one show library root.
# - main: validates config and runs the cleanup flow.

set -euo pipefail
IFS=$' \t\n'

ENV_FILE="${ENV_FILE:-./.env}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

load_env() {
  local file="$1"
  [ -f "$file" ] || fail "Config file not found: $file"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    if ! printf '%s' "$line" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*='; then
      fail "Invalid .env line: $line"
    fi
    local key="${line%%=*}"
    local value="${line#*=}"
    value="${value%$'\r'}"
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
      \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    export "$key=$value"
  done < "$file"
}

split_paths() {
  printf '%s\n' "$1" | tr ':' '\n' | sed '/^$/d'
}

is_video_file() {
  local path="$1"
  local name="${path##*/}"
  local ext
  for ext in ${VIDEO_EXTENSIONS}; do
    if [[ "$name" == *."$ext" ]]; then
      return 0
    fi
  done
  return 1
}

has_recursive_video() {
  local dir="$1"
  local ext
  for ext in ${VIDEO_EXTENSIONS}; do
    if find "$dir" -type f -iname "*.${ext}" -print -quit | grep -q .; then
      return 0
    fi
  done
  return 1
}

remove_path() {
  local target="$1"
  local reason="$2"
  if [ "${DELETE_MODE}" = "true" ]; then
    if [ -d "$target" ]; then
      rm -rf -- "$target"
      log "Deleted directory: $target -- $reason"
    elif [ -f "$target" ]; then
      rm -f -- "$target"
      log "Deleted file: $target -- $reason"
    fi
  else
    printf 'DRY-RUN delete: %s -- %s\n' "$target" "$reason"
  fi
}

touch_force_rescan() {
  local dir="$1"
  [ "${CREATE_FORCE_RESCAN}" = "true" ] || return 0
  [ -d "$dir" ] || return 0
  local marker="$dir/${FORCE_RESCAN_FILENAME}"
  if [ "${DELETE_MODE}" = "true" ]; then
    : > "$marker"
    log "Created marker: $marker"
  else
    printf 'DRY-RUN create marker: %s\n' "$marker"
  fi
}

is_episode_sidecar_dir() {
  local path="$1"
  local name="${path##*/}"
  local suffix="${TRICKPLAY_SUFFIX:-.trickplay}"
  [ -d "$path" ] && [[ "$name" == *"$suffix" ]]
}

is_episode_sidecar_file() {
  local path="$1"
  [ -f "$path" ] || return 1
  local name="${path##*/}"
  local thumb_suffix="${THUMB_SUFFIX:--thumb}"
  if [[ "$name" == *"$thumb_suffix".jpg || "$name" == *"$thumb_suffix".jpeg || "$name" == *"$thumb_suffix".png || "$name" == *"$thumb_suffix".webp ]]; then
    return 0
  fi
  local ext
  for ext in ${EPISODE_SIDECAREXTENSIONS}; do
    if [[ "$name" == *."$ext" ]]; then
      return 0
    fi
  done
  return 1
}

sidecar_candidate_bases() {
  local path="$1"
  local name="${path##*/}"
  local suffix="${TRICKPLAY_SUFFIX:-.trickplay}"
  local thumb_suffix="${THUMB_SUFFIX:--thumb}"
  if [ -d "$path" ] && [[ "$name" == *"$suffix" ]]; then
    printf '%s\n' "${name%$suffix}"
    return 0
  fi
  case "$name" in
    *"$thumb_suffix".jpg) printf '%s\n' "${name%$thumb_suffix.jpg}"; return 0 ;;
    *"$thumb_suffix".jpeg) printf '%s\n' "${name%$thumb_suffix.jpeg}"; return 0 ;;
    *"$thumb_suffix".png) printf '%s\n' "${name%$thumb_suffix.png}"; return 0 ;;
    *"$thumb_suffix".webp) printf '%s\n' "${name%$thumb_suffix.webp}"; return 0 ;;
  esac
  local ext
  for ext in ${EPISODE_SIDECAREXTENSIONS}; do
    if [[ "$name" == *."$ext" ]]; then
      local without_ext="${name%.${ext}}"
      printf '%s\n' "$without_ext"
      if [[ "$without_ext" == *.* ]]; then
        printf '%s\n' "${without_ext%.*}"
      fi
      return 0
    fi
  done
  return 1
}

matching_episode_video_exists() {
  local season_dir="$1"
  local sidecar="$2"
  local candidate
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    local ext
    for ext in ${VIDEO_EXTENSIONS}; do
      if [ -f "$season_dir/$candidate.$ext" ]; then
        return 0
      fi
    done
  done < <(sidecar_candidate_bases "$sidecar")
  return 1
}

clean_movie_folder() {
  local movie_dir="$1"
  if has_recursive_video "$movie_dir"; then
    log "Movie has at least one video, preserving movie folder and all contents: $movie_dir"
    touch_force_rescan "$movie_dir"
  else
    remove_path "$movie_dir" "movie folder contains no video files"
  fi
}

clean_episode_sidecars() {
  local season_dir="$1"
  find "$season_dir" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -print | sort | while IFS= read -r item; do
    if is_video_file "$item"; then
      continue
    fi
    if is_episode_sidecar_dir "$item" || is_episode_sidecar_file "$item"; then
      if ! matching_episode_video_exists "$season_dir" "$item"; then
        remove_path "$item" "episode-associated sidecar has no matching video file"
      fi
    fi
  done
}

clean_season_folder() {
  local season_dir="$1"
  if has_recursive_video "$season_dir"; then
    log "Season has at least one video, preserving season folder: $season_dir"
    clean_episode_sidecars "$season_dir"
    touch_force_rescan "$season_dir"
  else
    remove_path "$season_dir" "season folder contains no video files"
  fi
}

clean_show_folder() {
  local show_dir="$1"
  find "$show_dir" -mindepth 1 -maxdepth 1 -type d -name "${SEASON_DIR_GLOB}" -print | sort | while IFS= read -r season_dir; do
    clean_season_folder "$season_dir"
  done
  if has_recursive_video "$show_dir"; then
    log "Show root has at least one video after cleanup, preserving show folder: $show_dir"
    touch_force_rescan "$show_dir"
  else
    remove_path "$show_dir" "show root contains no video files after season cleanup"
  fi
}

process_movie_root() {
  local root="$1"
  [ -d "$root" ] || fail "Movie root does not exist or is not a directory: $root"
  log "Processing movie root: $root"
  find "$root" -mindepth 1 -maxdepth 1 -type d -print | sort | while IFS= read -r movie_dir; do
    clean_movie_folder "$movie_dir"
  done
  touch_force_rescan "$root"
}

process_show_root() {
  local root="$1"
  [ -d "$root" ] || fail "Show root does not exist or is not a directory: $root"
  log "Processing show root: $root"
  find "$root" -mindepth 1 -maxdepth 1 -type d -print | sort | while IFS= read -r show_dir; do
    clean_show_folder "$show_dir"
  done
  touch_force_rescan "$root"
}

main() {
  load_env "$ENV_FILE"
  : "${MOVIE_PATHS:=}"
  : "${SHOW_PATHS:=${TV_PATHS:-}}"
  : "${VIDEO_EXTENSIONS:=mkv mp4 avi mov m4v ts m2ts webm mpg mpeg wmv iso}"
  : "${EPISODE_SIDECAREXTENSIONS:=srt ass sub idx vtt nfo jpg jpeg png webp}"
  : "${TRICKPLAY_SUFFIX:=.trickplay}"
  : "${THUMB_SUFFIX:=-thumb}"
  : "${SEASON_DIR_GLOB:=Season *}"
  : "${DELETE_MODE:=false}"
  : "${CREATE_FORCE_RESCAN:=false}"
  : "${FORCE_RESCAN_FILENAME:=.forcerescan}"
  case "$DELETE_MODE" in true|false) ;; *) fail "DELETE_MODE must be true or false" ;; esac
  case "$CREATE_FORCE_RESCAN" in true|false) ;; *) fail "CREATE_FORCE_RESCAN must be true or false" ;; esac
  [ -n "$MOVIE_PATHS$SHOW_PATHS" ] || fail "Set MOVIE_PATHS and/or SHOW_PATHS in $ENV_FILE"
  log "DELETE_MODE=$DELETE_MODE"
  log "CREATE_FORCE_RESCAN=$CREATE_FORCE_RESCAN"
  if [ -n "$MOVIE_PATHS" ]; then
    split_paths "$MOVIE_PATHS" | while IFS= read -r root; do process_movie_root "$root"; done
  fi
  if [ -n "$SHOW_PATHS" ]; then
    split_paths "$SHOW_PATHS" | while IFS= read -r root; do process_show_root "$root"; done
  fi
  log "Finished"
}

main "$@"
