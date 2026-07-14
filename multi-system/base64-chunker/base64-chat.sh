#!/usr/bin/env bash
# File role: Bash entrypoint that reads .env automatically and packages one input file as chat-sized Base64 text.
# Inputs: .env beside this script. INPUT_FILE is a file path; OUTPUT_DIR is a directory path; MAX_CHARS is a positive integer; marker templates support {filename}, {part}, and {total}.
# Processing: load_env parses configuration without executing it; render substitutes placeholders; part_overhead, capacity, and fits_total determine the minimum feasible part count; the top-level flow encodes, frames, checks, and writes output.
# Outputs: <filename>.b64 or sortable <filename>.<sequence>.b64 files, plus a console summary. Existing outputs are not overwritten.
# Functions: trim removes surrounding whitespace; load_env parses required entries; render substitutes placeholders; char_count counts characters; write_text writes a new file; part_overhead calculates framing size; capacity calculates payload room; fits_total tests a candidate part count.
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
env_file="$script_dir/.env"
trim() { local v=$1; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }
load_env() {
  local file=$1 line key value
  [[ -f "$file" ]] || { printf 'Configuration file not found: %s\n' "$file" >&2; exit 2; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}; [[ -z "$(trim "$line")" || "$(trim "$line")" == \#* ]] && continue
    [[ "$line" == *=* ]] || { printf 'Invalid configuration line: %s\n' "$line" >&2; exit 2; }
    key=$(trim "${line%%=*}"); value=${line#*=}
    case "$key" in INPUT_FILE|OUTPUT_DIR|MAX_CHARS|SINGLE_BEGIN|SINGLE_END|MULTI_INTRO|PART_BEGIN|PART_END|FINAL_SIGNAL) printf -v "$key" '%s' "$value" ;; *) printf 'Unsupported configuration key: %s\n' "$key" >&2; exit 2 ;; esac
  done < "$file"
}
render() { local s=$1; s=${s//\{filename\}/$filename}; s=${s//\{part\}/$2}; s=${s//\{total\}/$3}; printf '%s' "$s"; }
char_count() { printf '%s' "$1" | wc -m | tr -d ' '; }
write_text() { [[ ! -e "$1" ]] || { printf 'Refusing to overwrite existing output: %s\n' "$1" >&2; exit 5; }; printf '%s' "$2" > "$1"; }
part_overhead() { local part=$1 total=$2 first=$3 last=$4 text=""; [[ "$first" == 1 ]] && text+="$(render "$MULTI_INTRO" "$part" "$total")"$'\n'; text+="$(render "$PART_BEGIN" "$part" "$total")"$'\n\n'"$(render "$PART_END" "$part" "$total")"; [[ "$last" == 1 ]] && text+=$'\n'"$(render "$FINAL_SIGNAL" "$part" "$total")"; char_count "$text"; }
capacity() { local n; n=$(part_overhead "$1" "$2" "$3" "$4"); (( MAX_CHARS > n )) && printf '%d' "$((MAX_CHARS-n))" || printf '0'; }
fits_total() { local total=$1 sum=0 i cap; for ((i=1; i<=total; i++)); do cap=$(capacity "$i" "$total" "$((i==1))" "$((i==total))"); (( cap > 0 )) || return 1; sum=$((sum+cap)); done; (( sum >= payload_len )); }

INPUT_FILE="" OUTPUT_DIR="" MAX_CHARS="" SINGLE_BEGIN="" SINGLE_END="" MULTI_INTRO="" PART_BEGIN="" PART_END="" FINAL_SIGNAL=""
load_env "$env_file"
for key in INPUT_FILE OUTPUT_DIR MAX_CHARS SINGLE_BEGIN SINGLE_END MULTI_INTRO PART_BEGIN PART_END FINAL_SIGNAL; do [[ -n "${!key}" ]] || { printf 'Missing or empty configuration key: %s\n' "$key" >&2; exit 2; }; done
[[ "$MAX_CHARS" =~ ^[1-9][0-9]*$ ]] || { echo 'MAX_CHARS must be a positive integer' >&2; exit 2; }
[[ "$INPUT_FILE" = /* ]] && input=$INPUT_FILE || input="$script_dir/$INPUT_FILE"
[[ "$OUTPUT_DIR" = /* ]] && output_dir=$OUTPUT_DIR || output_dir="$script_dir/$OUTPUT_DIR"
[[ -f "$input" ]] || { printf 'Input file not found: %s\n' "$input" >&2; exit 2; }
mkdir -p "$output_dir"; filename=$(basename "$input")
payload=$(base64 -w 0 -- "$input" 2>/dev/null || base64 -- "$input" | tr -d '\r\n'); payload_len=$(char_count "$payload")
single="$(render "$SINGLE_BEGIN" 1 1)"$'\n'"$payload"$'\n'"$(render "$SINGLE_END" 1 1)"; single_len=$(char_count "$single")
if (( single_len <= MAX_CHARS )); then output="$output_dir/$filename.b64"; write_text "$output" "$single"; printf 'Mode: single\nPayload characters: %d\nOutput characters including markers: %d\nLimit: %d\nFile: %s\n' "$payload_len" "$single_len" "$MAX_CHARS" "$output"; exit 0; fi
total=2; while ! fits_total "$total"; do total=$((total+1)); (( total <= 1000000 )) || { echo 'Unable to determine a practical part count' >&2; exit 3; }; done
width=${#total}; offset=0
for ((part=1; part<=total; part++)); do first=$((part==1)); last=$((part==total)); cap=$(capacity "$part" "$total" "$first" "$last"); remaining=$((payload_len-offset)); take=$((remaining<cap ? remaining : cap)); chunk=${payload:offset:take}; offset=$((offset+take)); text=""; (( first )) && text+="$(render "$MULTI_INTRO" "$part" "$total")"$'\n'; text+="$(render "$PART_BEGIN" "$part" "$total")"$'\n'"$chunk"$'\n'"$(render "$PART_END" "$part" "$total")"; (( last )) && text+=$'\n'"$(render "$FINAL_SIGNAL" "$part" "$total")"; printf -v seq "%0${width}d" "$part"; output="$output_dir/$filename.$seq.b64"; write_text "$output" "$text"; count=$(char_count "$text"); (( count <= MAX_CHARS )) || { printf 'Internal size error in %s\n' "$output" >&2; exit 4; }; printf 'Part %d/%d: %d characters: %s\n' "$part" "$total" "$count" "$output"; done
(( offset == payload_len )) || { echo 'Internal payload accounting error' >&2; exit 4; }; printf 'Mode: multipart\nPayload characters: %d\nParts: %d\nLimit per part: %d\n' "$payload_len" "$total" "$MAX_CHARS"
