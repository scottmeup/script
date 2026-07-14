# Base64 Chat Packaging Scripts

## Project files

- `base64-chat.sh` — Bash implementation.
- `base64-chat.py` — Python 3 implementation.
- `base64-chat.ps1` — PowerShell implementation.
- `base64-chat.env.example` — shared configuration template.

## Project-wide input, processing, and output flow

Copy `base64-chat.env.example` to `.env` in the same directory as the scripts. Set `INPUT_FILE`, `OUTPUT_DIR`, `MAX_CHARS`, and marker templates. Run any script without arguments. It resolves relative configured paths from its own directory, reads the source bytes, creates unwrapped RFC 4648 Base64, measures the complete framed output, and writes either one output or the minimum feasible number of maximum-sized blocks. Existing outputs are not overwritten.

## Configuration input structure

`.env` is UTF-8 text containing one `KEY=VALUE` entry per line. Blank lines and lines whose first non-whitespace character is `#` are ignored. Values are not shell-executed and must remain on one line.

- `INPUT_FILE`: existing file path processed by the top-level flow.
- `OUTPUT_DIR`: existing or creatable directory path receiving outputs.
- `MAX_CHARS`: positive integer inclusive ceiling for each complete output block.
- `SINGLE_BEGIN`, `SINGLE_END`: templates framing a single-block payload.
- `MULTI_INTRO`: first-block instructions telling Copilot to retain parts and wait for `FINAL_SIGNAL`.
- `PART_BEGIN`, `PART_END`: templates framing each multipart payload.
- `FINAL_SIGNAL`: completion template appended only to the last part.
- `{filename}`, `{part}`, `{total}`: literal placeholders replaced by each script.

Use ASCII marker text for identical cross-platform character counting. Newline separators are LF and are included in all size calculations.

## Running without arguments

Linux Bash:

```bash
cp base64-chat.env.example .env
chmod +x base64-chat.sh
./base64-chat.sh
```

Python 3:

```bash
cp base64-chat.env.example .env
chmod +x base64-chat.py
./base64-chat.py
```

PowerShell:

```powershell
Copy-Item base64-chat.env.example .env
./base64-chat.ps1
```

## Output naming

A single output is `<filename>.b64`. Multipart output uses the digit width of the final total: 1–9 parts use `.1.b64`; 10–99 use `.01.b64`; 100–999 use `.001.b64`; the pattern extends automatically.

## File documentation

### `base64-chat.sh`

Consumes `.env` and source bytes. Its parser, renderer, character counter, capacity functions, and top-level flow create new `.b64` files and console status. It depends on Bash, `base64`, `wc`, `tr`, `basename`, and `mkdir`. It creates `OUTPUT_DIR` when needed.

### `base64-chat.py`

Consumes `.env` and source bytes. `load_env`, `render`, `framing`, `capacities`, `choose_part_count`, `write_new`, and `main` perform parsing, substitution, sizing, selection, guarded output, and orchestration. It uses only the Python standard library and creates `OUTPUT_DIR` when needed.

### `base64-chat.ps1`

Consumes `.env` and source bytes. `Read-Env`, `Render`, `Get-PartText`, `Get-PartOverhead`, `Get-Capacity`, `Test-Total`, and `Write-Utf8NoBom` perform parsing, substitution, sizing, selection, and guarded UTF-8 output. The top-level flow orchestrates encoding and creates `OUTPUT_DIR` when needed.

### `base64-chat.env.example`

Declarative template consumed by all three scripts. It has no functions, generated outputs, or side effects.

### `BASE64_CHAT_PROJECT.md`

Documents the recursive project tree, configuration schema, cross-file data flow, usage, outputs, functions, side effects, and dependencies. It has no runtime side effects.
