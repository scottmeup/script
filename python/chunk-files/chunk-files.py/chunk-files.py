from pathlib import Path
import hashlib
import os


def load_env(path):
    values = {}
    env_path = Path(path)
    if not env_path.exists():
        return values
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def split_csv(value):
    return [item.strip() for item in value.split(",") if item.strip()]


def has_allowed_extension(path, allowed):
    name = path.name
    suffix = path.suffix
    if name in allowed:
        return True
    if suffix in allowed:
        return True
    if any(name.endswith(item) for item in allowed):
        return True
    return False


def is_under_only_paths(rel_path, only_paths):
    if not only_paths:
        return True
    rel = str(rel_path).replace("\\", "/")
    return any(rel == item or rel.startswith(item.rstrip("/") + "/") for item in only_paths)


def is_text(data):
    try:
        data.decode("utf-8")
        return True
    except UnicodeDecodeError:
        return False


def file_block(root_name, root, path):
    data = path.read_bytes()
    text = data.decode("utf-8")
    rel = path.relative_to(root)
    rel_text = str(rel).replace("\\", "/")
    sha = hashlib.sha256(data).hexdigest()
    return (
        f"----- BEGIN FILE -----\n"
        f"artifact: {root_name}\n"
        f"path: {rel_text}\n"
        f"size: {len(data)}\n"
        f"sha256: {sha}\n"
        f"----- CONTENT START -----\n"
        f"{text}\n"
        f"----- CONTENT END -----\n"
        f"----- END FILE -----\n\n"
    )


def write_chunk(output_dir, index, content):
    path = output_dir / f"chunk-{index:04d}.txt"
    path.write_text(content, encoding="utf-8")
    return path


def main():
    env = load_env(os.environ.get("CHUNK_ENV", ".env"))

    source_roots = split_csv(env.get("CHUNK_SOURCE_ROOTS", ""))
    if not source_roots:
        raise SystemExit("CHUNK_SOURCE_ROOTS is required")

    output_dir = Path(env.get("CHUNK_OUTPUT_DIR", "chunks"))
    output_dir.mkdir(parents=True, exist_ok=True)

    char_limit = int(env.get("CHUNK_CHAR_LIMIT", "12000"))
    allowed_extensions = set(split_csv(env.get("CHUNK_INCLUDE_EXTENSIONS", "")))
    exclude_dir_names = set(split_csv(env.get("CHUNK_EXCLUDE_DIR_NAMES", "")))
    max_file_bytes = int(env.get("CHUNK_MAX_FILE_BYTES", "200000"))
    only_paths = split_csv(env.get("CHUNK_ONLY_PATHS", ""))

    for old in output_dir.glob("chunk-*.txt"):
        old.unlink()
    for old in output_dir.glob("chunks-index.txt"):
        old.unlink()
    for old in output_dir.glob("chunks-done.txt"):
        old.unlink()

    chunk_index = 1
    current = ""
    written = []
    skipped = []

    for root_name in source_roots:
        root = Path(root_name)
        if not root.exists():
            skipped.append(f"{root_name}: root missing")
            continue

        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue

            rel = path.relative_to(root)
            if any(part in exclude_dir_names for part in rel.parts):
                continue

            if not is_under_only_paths(rel, only_paths):
                continue

            if allowed_extensions and not has_allowed_extension(path, allowed_extensions):
                skipped.append(f"{root_name}/{str(rel).replace('\\', '/')}: extension skipped")
                continue

            size = path.stat().st_size
            if size > max_file_bytes:
                skipped.append(f"{root_name}/{str(rel).replace('\\', '/')}: too large")
                continue

            data = path.read_bytes()
            if not is_text(data):
                skipped.append(f"{root_name}/{str(rel).replace('\\', '/')}: binary skipped")
                continue

            block = file_block(root_name, root, path)

            if len(block) > char_limit:
                if current:
                    written.append(write_chunk(output_dir, chunk_index, current))
                    chunk_index += 1
                    current = ""
                lines = block.splitlines(keepends=True)
                part = ""
                part_number = 1
                header = (
                    f"----- BEGIN SPLIT FILE PART -----\n"
                    f"artifact: {root_name}\n"
                    f"path: {str(rel).replace('\\', '/')}\n"
                )
                for line in lines:
                    next_part = part + line
                    if len(header) + len(next_part) + 80 > char_limit:
                        content = header + f"part: {part_number}\n----- PART CONTENT START -----\n" + part + "----- PART CONTENT END -----\n"
                        written.append(write_chunk(output_dir, chunk_index, content))
                        chunk_index += 1
                        part_number += 1
                        part = line
                    else:
                        part = next_part
                if part:
                    content = header + f"part: {part_number}\n----- PART CONTENT START -----\n" + part + "----- PART CONTENT END -----\n"
                    written.append(write_chunk(output_dir, chunk_index, content))
                    chunk_index += 1
                continue

            if len(current) + len(block) > char_limit:
                written.append(write_chunk(output_dir, chunk_index, current))
                chunk_index += 1
                current = ""

            current += block

    if current:
        written.append(write_chunk(output_dir, chunk_index, current))

    index_lines = []
    index_lines.append("Paste each chunk file in numeric order.")
    index_lines.append("After the final chunk, paste the contents of chunks-done.txt.")
    index_lines.append("")
    index_lines.append("Chunks:")
    for path in written:
        index_lines.append(path.name)
    index_lines.append("")
    index_lines.append("Skipped:")
    index_lines.extend(skipped)

    (output_dir / "chunks-index.txt").write_text("\n".join(index_lines) + "\n", encoding="utf-8")
    (output_dir / "chunks-done.txt").write_text("done\n", encoding="utf-8")

    print(f"wrote {len(written)} chunks to {output_dir}")
    print(f"index: {output_dir / 'chunks-index.txt'}")
    print(f"done marker: {output_dir / 'chunks-done.txt'}")


if __name__ == "__main__":
    main()
