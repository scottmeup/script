#!/usr/bin/env python3
"""
File role: Python entrypoint that reads .env automatically and packages one file as chat-sized Base64 text.
Inputs: .env beside this script. INPUT_FILE is a source-file path; OUTPUT_DIR is a directory path; MAX_CHARS is a positive integer; SINGLE_BEGIN, SINGLE_END, MULTI_INTRO, PART_BEGIN, PART_END, and FINAL_SIGNAL are single-line templates supporting {filename}, {part}, and {total}.
Processing: load_env parses configuration without executing it; render substitutes placeholders; framing creates complete blocks; capacities and choose_part_count select the minimum feasible part count; main encodes bytes, chooses single or multipart output, and checks every character ceiling.
Outputs: <filename>.b64 or sortable <filename>.<sequence>.b64 files encoded as UTF-8 without a trailing newline; a console summary. Existing outputs are not overwritten.
Top-level variables: SCRIPT_DIR locates .env and resolves relative configured paths; REQUIRED_KEYS defines the accepted configuration schema.
"""
from __future__ import annotations

import base64
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REQUIRED_KEYS = {
    "INPUT_FILE", "OUTPUT_DIR", "MAX_CHARS", "SINGLE_BEGIN", "SINGLE_END",
    "MULTI_INTRO", "PART_BEGIN", "PART_END", "FINAL_SIGNAL",
}


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        raise SystemExit(f"Configuration file not found: {path}")
    for number, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "=" not in raw:
            raise SystemExit(f"Invalid configuration line {number}: {raw}")
        key, value = raw.split("=", 1)
        key = key.strip()
        if key not in REQUIRED_KEYS:
            raise SystemExit(f"Unsupported configuration key: {key}")
        values[key] = value
    missing = sorted(REQUIRED_KEYS - values.keys())
    if missing:
        raise SystemExit(f"Missing configuration keys: {', '.join(missing)}")
    return values


def render(template: str, filename: str, part: int, total: int) -> str:
    return template.replace("{filename}", filename).replace("{part}", str(part)).replace("{total}", str(total))


def framing(cfg: dict[str, str], filename: str, payload: str, part: int, total: int, first: bool, last: bool) -> str:
    lines: list[str] = []
    if first:
        lines.append(render(cfg["MULTI_INTRO"], filename, part, total))
    lines.extend((render(cfg["PART_BEGIN"], filename, part, total), payload, render(cfg["PART_END"], filename, part, total)))
    if last:
        lines.append(render(cfg["FINAL_SIGNAL"], filename, part, total))
    return "\n".join(lines)


def capacities(cfg: dict[str, str], filename: str, max_chars: int, total: int) -> list[int]:
    result = []
    for part in range(1, total + 1):
        overhead = len(framing(cfg, filename, "", part, total, part == 1, part == total))
        result.append(max_chars - overhead)
    return result


def choose_part_count(cfg: dict[str, str], filename: str, max_chars: int, payload_length: int) -> tuple[int, list[int]]:
    for total in range(2, 1_000_001):
        caps = capacities(cfg, filename, max_chars, total)
        if min(caps) > 0 and sum(caps) >= payload_length:
            return total, caps
    raise SystemExit("Unable to determine a practical part count")


def write_new(path: Path, text: str) -> None:
    if path.exists():
        raise SystemExit(f"Refusing to overwrite existing output: {path}")
    path.write_text(text, encoding="utf-8", newline="")


def main() -> None:
    cfg = load_env(SCRIPT_DIR / ".env")
    try:
        max_chars = int(cfg["MAX_CHARS"])
    except ValueError as exc:
        raise SystemExit("MAX_CHARS must be a positive integer") from exc
    if max_chars <= 0:
        raise SystemExit("MAX_CHARS must be a positive integer")
    input_path = Path(cfg["INPUT_FILE"])
    output_dir = Path(cfg["OUTPUT_DIR"])
    if not input_path.is_absolute():
        input_path = SCRIPT_DIR / input_path
    if not output_dir.is_absolute():
        output_dir = SCRIPT_DIR / output_dir
    if not input_path.is_file():
        raise SystemExit(f"Input file not found: {input_path}")
    output_dir.mkdir(parents=True, exist_ok=True)
    filename = input_path.name
    payload = base64.b64encode(input_path.read_bytes()).decode("ascii")
    single = "\n".join((render(cfg["SINGLE_BEGIN"], filename, 1, 1), payload, render(cfg["SINGLE_END"], filename, 1, 1)))
    if len(single) <= max_chars:
        path = output_dir / f"{filename}.b64"
        write_new(path, single)
        print(f"Mode: single\nPayload characters: {len(payload)}\nOutput characters including markers: {len(single)}\nLimit: {max_chars}\nFile: {path}")
        return
    total, caps = choose_part_count(cfg, filename, max_chars, len(payload))
    width = len(str(total))
    offset = 0
    for part, cap in enumerate(caps, 1):
        chunk = payload[offset:offset + cap]
        offset += len(chunk)
        text = framing(cfg, filename, chunk, part, total, part == 1, part == total)
        if len(text) > max_chars:
            raise SystemExit(f"Internal size error in part {part}")
        path = output_dir / f"{filename}.{part:0{width}d}.b64"
        write_new(path, text)
        print(f"Part {part}/{total}: {len(text)} characters: {path}")
    if offset != len(payload):
        raise SystemExit("Internal payload accounting error")
    print(f"Mode: multipart\nPayload characters: {len(payload)}\nParts: {total}\nLimit per part: {max_chars}")


if __name__ == "__main__":
    main()
