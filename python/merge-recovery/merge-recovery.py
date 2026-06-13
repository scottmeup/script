from pathlib import Path
import hashlib
import json
import os
import shutil


def load_env(path):
    values = {}
    env_path = Path(path)
    if not env_path.exists():
        raise SystemExit(f"Missing env file: {env_path}")
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def sha256_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def list_files(root):
    root = Path(root)
    result = {}
    for path in sorted(root.rglob("*")):
        if path.is_file():
            rel = str(path.relative_to(root)).replace("\\", "/")
            result[rel] = {
                "size": path.stat().st_size,
                "sha256": sha256_file(path)
            }
    return result


def copy_file(src_root, dst_root, rel):
    src = Path(src_root) / rel
    dst = Path(dst_root) / rel
    if not src.exists():
        raise SystemExit(f"Overlay file missing: {rel}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def union_env_file(base_path, overlay_path, output_path):
    lines = []
    seen = set()
    for path in [base_path, overlay_path]:
        if not Path(path).exists():
            continue
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if not stripped:
                if lines and lines[-1] != "":
                    lines.append("")
                continue
            if stripped.startswith("#"):
                if stripped not in seen:
                    lines.append(line)
                    seen.add(stripped)
                continue
            key = stripped.split("=", 1)[0] if "=" in stripped else stripped
            if key not in seen:
                lines.append(line)
                seen.add(key)
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    Path(output_path).write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def extract_service_block(compose_text, service_name):
    lines = compose_text.splitlines()
    marker = f"  {service_name}:"
    start = None
    for index, line in enumerate(lines):
        if line == marker:
            start = index
            break
    if start is None:
        return None
    end = len(lines)
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if line.startswith("  ") and not line.startswith("    ") and line.endswith(":"):
            end = index
            break
        if line.startswith("volumes:") or line.startswith("networks:"):
            end = index
            break
    return "\n".join(lines[start:end]).rstrip()


def ensure_env_file_entry(compose_text, service_name, entry):
    lines = compose_text.splitlines()
    marker = f"  {service_name}:"
    start = None
    for index, line in enumerate(lines):
        if line == marker:
            start = index
            break
    if start is None:
        return compose_text
    end = len(lines)
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if line.startswith("  ") and not line.startswith("    ") and line.endswith(":"):
            end = index
            break
        if line.startswith("volumes:") or line.startswith("networks:"):
            end = index
            break
    block = lines[start:end]
    if any(entry in line for line in block):
        return compose_text
    env_index = None
    for index, line in enumerate(block):
        if line.strip() == "env_file:":
            env_index = index
            break
    if env_index is None:
        insert_at = None
        for index, line in enumerate(block):
            if line.strip().startswith("build:"):
                insert_at = index + 2
                break
        if insert_at is None:
            insert_at = 1
        block[insert_at:insert_at] = ["    env_file:", f"      - {entry}"]
    else:
        insert_at = env_index + 1
        while insert_at < len(block) and block[insert_at].strip().startswith("- "):
            insert_at += 1
        block.insert(insert_at, f"      - {entry}")
    return "\n".join(lines[:start] + block + lines[end:]) + "\n"


def merge_compose(base_path, overlay_path, output_path):
    base = Path(base_path).read_text(encoding="utf-8")
    overlay = Path(overlay_path).read_text(encoding="utf-8") if Path(overlay_path).exists() else ""
    merged = base
    merged = ensure_env_file_entry(merged, "org-core", "./env-templates/providers.env")
    merged = ensure_env_file_entry(merged, "eink-client", "./env-templates/providers.env")
    for service in ["home-assistant", "node-red"]:
        if f"  {service}:" not in merged:
            block = extract_service_block(overlay, service)
            if block:
                marker = "\nvolumes:\n"
                if marker in merged:
                    merged = merged.replace(marker, "\n" + block + "\n" + marker, 1)
                else:
                    merged = merged.rstrip() + "\n\n" + block + "\n"
    Path(output_path).write_text(merged.rstrip() + "\n", encoding="utf-8")


def merge_package_json(base_path, output_path, version):
    data = json.loads(Path(base_path).read_text(encoding="utf-8"))
    if version:
        data["version"] = version
    Path(output_path).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def merge_audit_undo_migration(base_path, output_path):
    text = Path(base_path).read_text(encoding="utf-8")
    old = "create table if not exists undo_entries (id uuid primary key default gen_random_uuid(), audit_event_id uuid references audit_events(id), created_at timestamptz not null default now());"
    new = "create table if not exists undo_entries (id uuid primary key default gen_random_uuid(), audit_event_id uuid references audit_events(id), status text not null default 'pending', applied_at timestamptz null, created_at timestamptz not null default now());"
    if old in text:
        text = text.replace(old, new)
    elif "status text not null default 'pending'" not in text:
        text = text.rstrip() + "\nalter table undo_entries add column if not exists status text not null default 'pending';\nalter table undo_entries add column if not exists applied_at timestamptz null;\n"
    Path(output_path).write_text(text.rstrip() + "\n", encoding="utf-8")


def apply_known_corrections(output_root):
    replacements = {
        "services/org-core/src/db/repositories/entities/service-connections.js": [
            ("input.enabled ?? False", "input.enabled ?? false"),
            ("import { getPool } from '../client.js';", "import { getPool } from '../../client.js';")
        ],
        "services/org-core/src/db/repositories/entities/calendar-events.js": [
            ("import { getPool } from '../client.js';", "import { getPool } from '../../client.js';"),
            ("import { serializeMetadataBlock } from '../../metadata/parser.js';", "import { serializeMetadataBlock } from '../../../metadata/parser.js';")
        ],
        "services/org-core/src/db/repositories/entities/tasks.js": [
            ("import { getPool } from '../client.js';", "import { getPool } from '../../client.js';"),
            ("import { serializeMetadataBlock } from '../../metadata/parser.js';", "import { serializeMetadataBlock } from '../../../metadata/parser.js';")
        ],
        "services/org-core/src/db/repositories/entities/recurrence-rules.js": [
            ("import { getPool } from '../client.js';", "import { getPool } from '../../client.js';")
        ],
        "services/org-core/src/db/repositories/entities/reminder-rules.js": [
            ("import { getPool } from '../client.js';", "import { getPool } from '../../client.js';")
        ],
        "services/org-core/src/db/repositories/entities/reports.js": [
            ("import { getPool } from '../client.js';", "import { getPool } from '../../client.js';")
        ],
        "services/org-core/src/db/repositories/entities/shopping-items.js": [
            ("import { getPool } from '../client.js';", "import { getPool } from '../../client.js';")
        ]
    }
    changed = []
    for rel, pairs in replacements.items():
        path = Path(output_root) / rel
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        original = text
        for old, new in pairs:
            text = text.replace(old, new)
        if text != original:
            path.write_text(text, encoding="utf-8")
            changed.append(rel)
    return changed


def write_report(report_dir, data):
    report_dir = Path(report_dir)
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "merge-report.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
    lines = []
    lines.append(f"baseline: {data['baseline_dir']}")
    lines.append(f"overlay: {data['overlay_dir']}")
    lines.append(f"output: {data['output_dir']}")
    lines.append(f"baseline_file_count: {data['baseline_file_count']}")
    lines.append(f"output_file_count: {data['output_file_count']}")
    lines.append(f"missing_baseline_file_count: {len(data['missing_baseline_files'])}")
    lines.append(f"added_file_count: {len(data['added_files'])}")
    lines.append(f"changed_file_count: {len(data['changed_files'])}")
    lines.append("")
    lines.append("added_from_overlay:")
    lines.extend(f"  {item}" for item in data["added_from_overlay"])
    lines.append("")
    lines.append("replaced_from_overlay:")
    lines.extend(f"  {item}" for item in data["replaced_from_overlay"])
    lines.append("")
    lines.append("manual_merged:")
    lines.extend(f"  {item}" for item in data["manual_merged"])
    lines.append("")
    lines.append("known_corrections:")
    lines.extend(f"  {item}" for item in data["known_corrections"])
    lines.append("")
    lines.append("missing_baseline_files:")
    lines.extend(f"  {item}" for item in data["missing_baseline_files"])
    (report_dir / "merge-summary.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    env = load_env(os.environ.get("MERGE_ENV", ".env.merge-recovery"))
    baseline_dir = Path(env["BASELINE_DIR"])
    overlay_dir = Path(env["OVERLAY_DIR"])
    output_dir = Path(env["OUTPUT_DIR"])
    policy = read_json(env["POLICY_FILE"])
    report_dir = Path(env.get("REPORT_DIR", "merge-recovery-report"))
    overwrite = env.get("MERGE_OVERWRITE_OUTPUT", "false").lower() == "true"
    recovered_version = env.get("RECOVERED_PACKAGE_VERSION", "")

    if not baseline_dir.exists():
        raise SystemExit(f"Baseline dir missing: {baseline_dir}")
    if not overlay_dir.exists():
        raise SystemExit(f"Overlay dir missing: {overlay_dir}")
    if output_dir.exists():
        if not overwrite:
            raise SystemExit(f"Output dir exists and MERGE_OVERWRITE_OUTPUT is false: {output_dir}")
        shutil.rmtree(output_dir)

    shutil.copytree(baseline_dir, output_dir)

    added = []
    replaced = []
    manual = []

    for rel in policy.get("add_from_overlay", []):
        dst = output_dir / rel
        if dst.exists():
            raise SystemExit(f"Additive overlay target already exists: {rel}")
        copy_file(overlay_dir, output_dir, rel)
        added.append(rel)

    for rel in policy.get("replace_from_overlay", []):
        if not (output_dir / rel).exists():
            raise SystemExit(f"Replacement target missing from baseline: {rel}")
        copy_file(overlay_dir, output_dir, rel)
        replaced.append(rel)

    union_env_file(baseline_dir / ".env.example", overlay_dir / ".env.example", output_dir / ".env.example")
    manual.append(".env.example")

    merge_compose(baseline_dir / "docker-compose.yml", overlay_dir / "docker-compose.yml", output_dir / "docker-compose.yml")
    manual.append("docker-compose.yml")

    union_env_file(baseline_dir / "services/org-core/.env.example", overlay_dir / "services/org-core/.env.example", output_dir / "services/org-core/.env.example")
    manual.append("services/org-core/.env.example")

    merge_package_json(baseline_dir / "services/org-core/package.json", output_dir / "services/org-core/package.json", recovered_version)
    manual.append("services/org-core/package.json")

    merge_audit_undo_migration(baseline_dir / "services/org-core/migrations/005_audit_undo.sql", output_dir / "services/org-core/migrations/005_audit_undo.sql")
    manual.append("services/org-core/migrations/005_audit_undo.sql")

    known_corrections = apply_known_corrections(output_dir)

    baseline_manifest = list_files(baseline_dir)
    output_manifest = list_files(output_dir)

    missing = sorted(set(baseline_manifest) - set(output_manifest))
    added_files = sorted(set(output_manifest) - set(baseline_manifest))
    changed_files = sorted(
        rel for rel in set(baseline_manifest).intersection(output_manifest)
        if baseline_manifest[rel]["sha256"] != output_manifest[rel]["sha256"]
    )

    report = {
        "baseline_dir": str(baseline_dir),
        "overlay_dir": str(overlay_dir),
        "output_dir": str(output_dir),
        "policy_file": env["POLICY_FILE"],
        "baseline_file_count": len(baseline_manifest),
        "output_file_count": len(output_manifest),
        "missing_baseline_files": missing,
        "added_files": added_files,
        "changed_files": changed_files,
        "added_from_overlay": added,
        "replaced_from_overlay": replaced,
        "manual_merged": manual,
        "known_corrections": known_corrections,
        "kept_baseline": policy.get("keep_baseline", [])
    }

    write_report(report_dir, report)

    if missing:
        raise SystemExit(f"Merge failed: missing baseline files: {len(missing)}")

    print(f"wrote recovered baseline: {output_dir}")
    print(f"wrote report: {report_dir / 'merge-summary.txt'}")


if __name__ == "__main__":
    main()