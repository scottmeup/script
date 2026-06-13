from pathlib import Path
import hashlib
import json
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


def text_stats(data):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return {"binary": True}
    return {
        "line_count": len(text.splitlines()),
        "nonempty_line_count": sum(1 for line in text.splitlines() if line.strip())
    }


def build_manifest(root_names):
    output = {}
    for root_name in root_names:
        root = Path(root_name)
        files = []
        if not root.exists():
            output[root_name] = {
                "exists": False,
                "file_count": 0,
                "files": []
            }
            continue

        for p in sorted(root.rglob("*")):
            if not p.is_file():
                continue

            data = p.read_bytes()
            item = {
                "path": str(p.relative_to(root)).replace("\\", "/"),
                "size": len(data),
                "sha256": hashlib.sha256(data).hexdigest()
            }
            item.update(text_stats(data))
            files.append(item)

        output[root_name] = {
            "exists": True,
            "file_count": len(files),
            "files": files
        }

    return output


def main():
    env = load_env(os.environ.get("MANIFEST_ENV", ".env"))
    roots = [
        part.strip()
        for part in env.get("MANIFEST_ROOTS", "").split(",")
        if part.strip()
    ]

    if not roots:
        raise SystemExit("MANIFEST_ROOTS is required in .env.manifest")

    output_path = Path(env.get("MANIFEST_OUTPUT", "baseline-candidates-manifest.json"))
    output_path.write_text(
        json.dumps(build_manifest(roots), indent=2),
        encoding="utf-8"
    )

    print(f"wrote {output_path}")


if __name__ == "__main__":
    main()