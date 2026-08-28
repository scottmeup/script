#!/usr/bin/env python3
"""
Project summary:
  Cross-platform collector, ZIP compressor, adaptive RGBA PNG encoder, decoder, inspector, and self-test tool for transporting arbitrary files through image attachments.
Inputs:
  encode positional inputs: file paths, directory paths, and shell-unexpanded glob patterns; used by collect_inputs.
  -r: recursive directory and glob processing flag; used by collect_inputs.
  --output: output directory path; used by encode_command and decode_command.
  --max-png-bytes: strict exclusive upper limit for every completed PNG; used by fit_chunk and encode_command.
  --min-aspect and --max-aspect: inclusive width divided by height limits; used by choose_dimensions.
  --source: non-secret source descriptor embedded in each PNG header and manifests.
  --archive-name: output ZIP filename embedded in each PNG header.
  --compression-level: ZIP DEFLATE and PNG zlib level from 0 through 9.
  decode positional inputs: PNG files, PNG directories, and glob patterns; used by resolve_png_inputs.
Outputs:
  encode: compressed ZIP with internal manifest, self-describing PNG files, transport-manifest.json, and CHAT-INSTRUCTIONS.txt.
  decode: reconstructed ZIP after all PNG headers, offsets, lengths, and SHA-256 values pass; optional extraction directory.
  inspect: JSON records describing PNG transport headers and integrity.
  self-test: temporary round-trip and negative-test results.
Functions:
  sha256_bytes and sha256_file create SHA-256 integrity values.
  collect_inputs resolves files, directories, globs, recursion, source-relative archive paths, and missing inputs.
  build_archive creates a compressed ZIP with an internal manifest and validates the ZIP independently.
  png_filter_rows applies adaptive PNG filter selection per row.
  write_png creates minimal non-interlaced 8-bit RGBA PNG bytes with zlib DEFLATE and critical chunks only.
  read_png_rgba validates PNG chunks, CRC values, color format, zlib data, and reverses PNG row filters.
  build_header and parse_header create and validate the versioned self-describing transport header.
  choose_dimensions calculates near-square or permitted rectangular dimensions for required RGBA capacity.
  fit_chunk uses bounded binary search and actual completed PNG measurement to maximize useful payload below the configured limit.
  encode_command creates the archive, adaptively splits it, rechecks every final PNG, writes manifests and instructions, and runs local round-trip validation.
  decode_command groups and validates PNG chunks, reconstructs the archive by offsets, validates the complete checksum, independently tests the ZIP, and optionally extracts it.
  inspect_command reports embedded transport metadata without reconstructing the archive.
  self_test_command tests small, multiple, empty, recursive, Unicode, compressible, incompressible, single-PNG, multi-PNG, boundary, missing, duplicate, reordered, mixed, and corrupted cases.
Top-level variables:
  MAGIC and VERSION define the transport format.
  HEADER_FIXED defines the big-endian fixed transport-header schema.
  PNG_SIGNATURE identifies PNG files.
Cross-file flow:
  One invocation collects inputs into a ZIP, embeds the ZIP bytes and complete reconstruction metadata into one or more PNG files, and writes one instruction file. A later invocation decodes only the PNG files and reconstructs the exact validated ZIP.
"""
import argparse
import binascii
import glob
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import time
import uuid
import zipfile
import zlib

MAGIC = b"OAIPNG01"
VERSION = 1
HEADER_FIXED = struct.Struct(">8sHH16sQ32sIIQI32sIIIBBHH")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def safe_name(value):
    value = value.replace("\\", "_").replace("/", "_").strip()
    return value or "source"


def collect_inputs(items, recursive):
    collected = []
    missing = []
    seen = set()
    cwd = Path.cwd()
    for item in items:
        expanded = glob.glob(item, recursive=recursive)
        candidates = [Path(x) for x in expanded] if expanded else [Path(item)]
        matched = False
        for candidate in candidates:
            if not candidate.exists():
                continue
            matched = True
            resolved = candidate.resolve()
            if resolved.is_file():
                key = str(resolved)
                if key not in seen:
                    seen.add(key)
                    collected.append((resolved, Path("files") / safe_name(resolved.parent.name) / resolved.name))
            elif resolved.is_dir():
                iterator = resolved.rglob("*") if recursive else resolved.glob("*")
                for child in iterator:
                    if child.is_file():
                        child = child.resolve()
                        key = str(child)
                        if key not in seen:
                            seen.add(key)
                            relative = child.relative_to(resolved)
                            collected.append((child, Path("directories") / safe_name(resolved.name) / relative))
        if not matched:
            missing.append(str((cwd / item).resolve() if not Path(item).is_absolute() else Path(item)))
    return collected, missing


def build_archive(inputs, recursive, output_path, source, compression_level):
    collected, missing = collect_inputs(inputs, recursive)
    if not collected and not missing:
        raise ValueError("No inputs were supplied.")
    records = []
    for source_path, archive_path in collected:
        stat = source_path.stat()
        records.append({
            "original_path": str(source_path),
            "archive_path": archive_path.as_posix(),
            "size": stat.st_size,
            "modified_unix_ns": stat.st_mtime_ns,
            "sha256": sha256_file(source_path),
        })
    manifest = {
        "format": "artifact-png-archive-manifest-v1",
        "source": source,
        "requested_inputs": inputs,
        "recursive": recursive,
        "collected": records,
        "missing_or_inaccessible": missing,
        "created_unix": int(time.time()),
    }
    compression = zipfile.ZIP_DEFLATED
    with zipfile.ZipFile(output_path, "w", compression=compression, compresslevel=compression_level, allowZip64=True) as archive:
        archive.writestr("INTERNAL-MANIFEST.json", json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8"))
        for source_path, archive_path in collected:
            archive.write(source_path, archive_path.as_posix())
    if not zipfile.is_zipfile(output_path):
        raise RuntimeError("Independent ZIP identification failed.")
    with zipfile.ZipFile(output_path, "r") as archive:
        failure = archive.testzip()
        if failure is not None:
            raise RuntimeError("ZIP integrity test failed at " + failure)
        info = archive.getinfo("INTERNAL-MANIFEST.json")
        if info.compress_type != zipfile.ZIP_DEFLATED:
            raise RuntimeError("Internal manifest is not DEFLATE-compressed.")
    return manifest


def paeth(a, b, c):
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def png_filter_rows(raw, width, height):
    stride = width * 4
    output = bytearray()
    previous = bytes(stride)
    for y in range(height):
        row = raw[y * stride:(y + 1) * stride]
        candidates = []
        for filter_type in range(5):
            filtered = bytearray(stride)
            score = 0
            for i, value in enumerate(row):
                left = row[i - 4] if i >= 4 else 0
                up = previous[i]
                upper_left = previous[i - 4] if i >= 4 else 0
                if filter_type == 0:
                    predicted = 0
                elif filter_type == 1:
                    predicted = left
                elif filter_type == 2:
                    predicted = up
                elif filter_type == 3:
                    predicted = (left + up) // 2
                else:
                    predicted = paeth(left, up, upper_left)
                result = (value - predicted) & 255
                filtered[i] = result
                score += result if result < 128 else 256 - result
            candidates.append((score, filter_type, filtered))
        _, filter_type, filtered = min(candidates, key=lambda x: x[0])
        output.append(filter_type)
        output.extend(filtered)
        previous = row
    return bytes(output)


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)


def write_png(raw_rgba, width, height, compression_level):
    if len(raw_rgba) != width * height * 4:
        raise ValueError("RGBA byte count does not match dimensions.")
    filtered = png_filter_rows(raw_rgba, width, height)
    compressed = zlib.compress(filtered, compression_level)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return PNG_SIGNATURE + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", compressed) + png_chunk(b"IEND", b"")


def read_png_rgba(path):
    data = Path(path).read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("Actual file format is not PNG: " + str(path))
    position = len(PNG_SIGNATURE)
    idat = bytearray()
    width = height = None
    while position < len(data):
        if position + 12 > len(data):
            raise ValueError("Truncated PNG chunk.")
        length = struct.unpack_from(">I", data, position)[0]
        kind = data[position + 4:position + 8]
        payload = data[position + 8:position + 8 + length]
        crc = struct.unpack_from(">I", data, position + 8 + length)[0]
        if binascii.crc32(kind + payload) & 0xFFFFFFFF != crc:
            raise ValueError("PNG CRC failure.")
        position += 12 + length
        if kind == b"IHDR":
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            if (depth, color, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                raise ValueError("PNG must be non-interlaced 8-bit RGBA.")
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            break
    filtered = zlib.decompress(bytes(idat))
    stride = width * 4
    expected = height * (stride + 1)
    if len(filtered) != expected:
        raise ValueError("Unexpected decompressed PNG size.")
    raw = bytearray(width * height * 4)
    offset = 0
    prior = bytearray(stride)
    for y in range(height):
        filter_type = filtered[offset]
        offset += 1
        row_filtered = filtered[offset:offset + stride]
        offset += stride
        row = bytearray(stride)
        for i, value in enumerate(row_filtered):
            left = row[i - 4] if i >= 4 else 0
            up = prior[i]
            upper_left = prior[i - 4] if i >= 4 else 0
            if filter_type == 0:
                predicted = 0
            elif filter_type == 1:
                predicted = left
            elif filter_type == 2:
                predicted = up
            elif filter_type == 3:
                predicted = (left + up) // 2
            elif filter_type == 4:
                predicted = paeth(left, up, upper_left)
            else:
                raise ValueError("Unsupported PNG filter type.")
            row[i] = (value + predicted) & 255
        raw[y * stride:(y + 1) * stride] = row
        prior = row
    return width, height, bytes(raw), data


def build_header(archive_id, total_length, archive_hash, sequence, total_count, offset, chunk, width, height, used_rgba, source, archive_name):
    source_bytes = source.encode("utf-8")
    name_bytes = archive_name.encode("utf-8")
    header_length = HEADER_FIXED.size + len(source_bytes) + len(name_bytes)
    fixed = HEADER_FIXED.pack(
        MAGIC, VERSION, header_length, archive_id, total_length, bytes.fromhex(archive_hash),
        sequence, total_count, offset, len(chunk), hashlib.sha256(chunk).digest(),
        width, height, used_rgba, 8, 4, len(source_bytes), len(name_bytes)
    )
    return fixed + source_bytes + name_bytes


def parse_header(raw):
    if len(raw) < HEADER_FIXED.size:
        raise ValueError("RGBA payload is too short for a transport header.")
    values = HEADER_FIXED.unpack_from(raw)
    magic, version, header_length, archive_id, total_length, archive_hash, sequence, total_count, offset, chunk_length, chunk_hash, width, height, used_rgba, bit_depth, channels, source_length, name_length = values
    if magic != MAGIC or version != VERSION:
        raise ValueError("Unknown PNG transport signature or version.")
    if header_length != HEADER_FIXED.size + source_length + name_length:
        raise ValueError("Transport header length is invalid.")
    if used_rgba > len(raw) or header_length + chunk_length > used_rgba:
        raise ValueError("Transport payload lengths are invalid.")
    source_start = HEADER_FIXED.size
    name_start = source_start + source_length
    source = raw[source_start:name_start].decode("utf-8")
    archive_name = raw[name_start:name_start + name_length].decode("utf-8")
    chunk = raw[header_length:header_length + chunk_length]
    if hashlib.sha256(chunk).digest() != chunk_hash:
        raise ValueError("Chunk SHA-256 mismatch.")
    return {
        "archive_id": archive_id.hex(), "total_length": total_length, "archive_sha256": archive_hash.hex(),
        "sequence": sequence, "total_count": total_count, "offset": offset, "chunk_length": chunk_length,
        "chunk_sha256": chunk_hash.hex(), "width": width, "height": height, "used_rgba": used_rgba,
        "bit_depth": bit_depth, "channels": channels, "source": source, "archive_name": archive_name,
        "header_length": header_length, "chunk": chunk,
    }


def choose_dimensions(required_bytes, min_aspect, max_aspect):
    pixels = math.ceil(required_bytes / 4)
    root = math.sqrt(pixels)
    candidates = set()
    for delta in range(-128, 129):
        candidates.add(max(1, math.ceil(root) + delta))
    for height in list(candidates):
        width = math.ceil(pixels / height)
        ratio = width / height
        if min_aspect <= ratio <= max_aspect:
            candidates.add(height)
    best = None
    for height in candidates:
        width = math.ceil(pixels / height)
        ratio = width / height
        if min_aspect <= ratio <= max_aspect:
            value = (width * height, abs(math.log(ratio)), width, height)
            if best is None or value < best:
                best = value
    if best is None:
        raise ValueError("The aspect-ratio limits cannot represent the required payload.")
    return best[2], best[3]


def encode_candidate(archive_id, archive_data, archive_hash, sequence, total_count, offset, length, source, archive_name, min_aspect, max_aspect, compression_level):
    chunk = archive_data[offset:offset + length]
    provisional = HEADER_FIXED.size + len(source.encode("utf-8")) + len(archive_name.encode("utf-8")) + length
    width, height = choose_dimensions(provisional, min_aspect, max_aspect)
    used = provisional
    header = build_header(archive_id, len(archive_data), archive_hash, sequence, total_count, offset, chunk, width, height, used, source, archive_name)
    raw = header + chunk + bytes(width * height * 4 - len(header) - len(chunk))
    return write_png(raw, width, height, compression_level), width, height, header, chunk


def fit_chunk(archive_id, archive_data, archive_hash, sequence, total_count, offset, max_png_bytes, source, archive_name, min_aspect, max_aspect, compression_level):
    remaining = len(archive_data) - offset
    low = 1
    high = min(remaining, max_png_bytes)
    best = None
    while low <= high:
        middle = (low + high) // 2
        candidate = encode_candidate(archive_id, archive_data, archive_hash, sequence, total_count, offset, middle, source, archive_name, min_aspect, max_aspect, compression_level)
        if len(candidate[0]) < max_png_bytes:
            best = candidate
            low = middle + 1
        else:
            high = middle - 1
    if best is None:
        raise RuntimeError("No payload byte fits below the configured PNG limit.")
    return best


def resolve_png_inputs(items, recursive):
    paths = []
    seen = set()
    for item in items:
        expanded = glob.glob(item, recursive=recursive)
        candidates = [Path(x) for x in expanded] if expanded else [Path(item)]
        for candidate in candidates:
            if candidate.is_dir():
                iterator = candidate.rglob("*.png") if recursive else candidate.glob("*.png")
                for child in iterator:
                    key = str(child.resolve())
                    if key not in seen:
                        seen.add(key); paths.append(child.resolve())
            elif candidate.is_file():
                key = str(candidate.resolve())
                if key not in seen:
                    seen.add(key); paths.append(candidate.resolve())
    return paths


def decode_png_set(paths):
    records = []
    for path in paths:
        width, height, raw, png_data = read_png_rgba(path)
        header = parse_header(raw)
        if (width, height) != (header["width"], header["height"]):
            raise ValueError("PNG dimensions do not match the embedded header.")
        header["path"] = str(path)
        header["png_bytes"] = len(png_data)
        header["png_sha256"] = sha256_bytes(png_data)
        records.append(header)
    groups = {}
    for record in records:
        key = (record["archive_id"], record["source"], record["archive_name"], record["archive_sha256"])
        groups.setdefault(key, []).append(record)
    if len(groups) != 1:
        raise ValueError("PNG set is missing, mixed, or belongs to multiple archives.")
    records = next(iter(groups.values()))
    total_count = records[0]["total_count"]
    if len(records) != total_count:
        raise ValueError("PNG set is incomplete or contains duplicates.")
    sequences = [r["sequence"] for r in records]
    if sorted(sequences) != list(range(1, total_count + 1)) or len(set(sequences)) != total_count:
        raise ValueError("PNG sequences are missing or duplicated.")
    ordered = sorted(records, key=lambda r: r["offset"])
    output = bytearray()
    expected_offset = 0
    for record in ordered:
        if record["offset"] != expected_offset:
            raise ValueError("Chunk offsets overlap or have gaps.")
        output.extend(record["chunk"])
        expected_offset += record["chunk_length"]
    if len(output) != records[0]["total_length"]:
        raise ValueError("Reconstructed archive length mismatch.")
    if sha256_bytes(output) != records[0]["archive_sha256"]:
        raise ValueError("Reconstructed archive SHA-256 mismatch.")
    return bytes(output), records


def write_chat_instructions(path):
    text = """COPILOT PNG ARTEFACT RECONSTRUCTION INSTRUCTIONS\n\nThe attached PNG files encode one compressed archive. Process these instructions once for this upload set.\n\n1. Treat every attachment as a binary file and identify its actual format. Reject JPEG, lossy WebP, resized images, or non-PNG data even when the filename ends in .png.\n2. Decode each PNG directly as non-interlaced 8-bit RGBA without rendering, compositing, premultiplication, colour conversion, resizing, or screenshot capture.\n3. Extract RGBA bytes top-to-bottom, left-to-right, in R-G-B-A order.\n4. Parse the OAIPNG01 versioned header embedded at the start of every RGBA stream. Do not rely on attachment order, filenames, PNG metadata, or text from another chunk.\n5. Group images by archive identifier, source descriptor, archive name, and complete archive SHA-256. Reject mixed groups.\n6. Validate every PNG's dimensions, used RGBA length, sequence, total count, archive offset, chunk length, and chunk SHA-256. Reject missing, duplicate, overlapping, corrupted, or out-of-range chunks.\n7. Reconstruct the compressed ZIP in byte-offset order. Validate its exact byte length and complete SHA-256.\n8. Independently test the ZIP, then read INTERNAL-MANIFEST.json. Report requested, collected, missing, and inaccessible artefacts.\n9. Do not silently produce a partial archive. Report any transformed or unverifiable attachment.\n"""
    Path(path).write_text(text, encoding="utf-8")


def encode_command(args):
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    archive_path = output / args.archive_name
    if archive_path.exists() and not args.overwrite:
        raise FileExistsError("Output exists; use --overwrite: " + str(archive_path))
    build_archive(args.inputs, args.recursive, archive_path, args.source, args.compression_level)
    archive_data = archive_path.read_bytes()
    archive_hash = sha256_bytes(archive_data)
    archive_id = uuid.uuid4().bytes
    provisional = []
    offset = 0
    sequence = 1
    while offset < len(archive_data):
        png, width, height, header, chunk = fit_chunk(archive_id, archive_data, archive_hash, sequence, 0, offset, args.max_png_bytes, args.source, args.archive_name, args.min_aspect, args.max_aspect, args.compression_level)
        provisional.append((offset, len(chunk)))
        offset += len(chunk)
        sequence += 1
    total_count = len(provisional)
    manifest = []
    for index, (offset, initial_length) in enumerate(provisional, 1):
        png, width, height, header, chunk = fit_chunk(archive_id, archive_data, archive_hash, index, total_count, offset, args.max_png_bytes, args.source, args.archive_name, args.min_aspect, args.max_aspect, args.compression_level)
        if len(chunk) < initial_length and index < total_count:
            raise RuntimeError("Final header reduced a non-final chunk; rerun with a lower maximum PNG size.")
        filename = f"{safe_name(Path(args.archive_name).stem)}-{archive_id.hex()}-{index:04d}-of-{total_count:04d}.png"
        png_path = output / filename
        if png_path.exists() and not args.overwrite:
            raise FileExistsError("Output exists; use --overwrite: " + str(png_path))
        png_path.write_bytes(png)
        if len(png) >= args.max_png_bytes:
            raise RuntimeError("Completed PNG reached or exceeded the configured limit.")
        decoded_width, decoded_height, decoded_raw, decoded_png = read_png_rgba(png_path)
        decoded_header = parse_header(decoded_raw)
        if decoded_header["chunk"] != chunk or decoded_width != width or decoded_height != height:
            raise RuntimeError("Local PNG round-trip validation failed.")
        manifest.append({
            "filename": filename, "archive_id": archive_id.hex(), "source": args.source,
            "sequence": index, "total_count": total_count, "width": width, "height": height,
            "aspect_ratio": width / height, "final_png_bytes": len(png), "png_sha256": sha256_bytes(png),
            "rgba_capacity_bytes": width * height * 4, "used_rgba_bytes": len(header) + len(chunk),
            "chunk_offset": offset, "chunk_length": len(chunk), "chunk_sha256": sha256_bytes(chunk),
            "archive_length": len(archive_data), "archive_sha256": archive_hash,
        })
    reconstructed, _ = decode_png_set([output / x["filename"] for x in manifest])
    if reconstructed != archive_data:
        raise RuntimeError("Complete local reconstruction did not match the archive.")
    with zipfile.ZipFile(archive_path, "r") as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Final independent ZIP test failed.")
    (output / "transport-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    write_chat_instructions(output / "CHAT-INSTRUCTIONS.txt")
    print(json.dumps({"archive": str(archive_path), "archive_bytes": len(archive_data), "archive_sha256": archive_hash, "png_count": total_count, "output": str(output)}, indent=2))


def decode_command(args):
    paths = resolve_png_inputs(args.inputs, args.recursive)
    if not paths:
        raise ValueError("No PNG inputs were found.")
    archive_data, records = decode_png_set(paths)
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    archive_path = output / records[0]["archive_name"]
    if archive_path.exists() and not args.overwrite:
        raise FileExistsError("Output exists; use --overwrite: " + str(archive_path))
    archive_path.write_bytes(archive_data)
    if not zipfile.is_zipfile(archive_path):
        raise RuntimeError("Reconstructed output is not a ZIP archive.")
    with zipfile.ZipFile(archive_path, "r") as archive:
        failure = archive.testzip()
        if failure is not None:
            raise RuntimeError("Reconstructed ZIP test failed at " + failure)
        manifest = json.loads(archive.read("INTERNAL-MANIFEST.json").decode("utf-8"))
        if args.extract:
            extract_path = output / "extracted"
            extract_path.mkdir(parents=True, exist_ok=True)
            archive.extractall(extract_path)
    print(json.dumps({"archive": str(archive_path), "archive_bytes": len(archive_data), "archive_sha256": sha256_bytes(archive_data), "internal_manifest": manifest, "png_count": len(records)}, ensure_ascii=False, indent=2))


def inspect_command(args):
    paths = resolve_png_inputs(args.inputs, args.recursive)
    if not paths:
        raise ValueError("No PNG inputs were found.")
    output = []
    for path in paths:
        width, height, raw, png_data = read_png_rgba(path)
        header = parse_header(raw)
        header.pop("chunk")
        header.update({"path": str(path), "actual_png_bytes": len(png_data), "actual_png_sha256": sha256_bytes(png_data)})
        output.append(header)
    print(json.dumps(output, ensure_ascii=False, indent=2))


def self_test_command(args):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        source = root / "source"
        source.mkdir()
        (source / "empty.bin").write_bytes(b"")
        (source / "small file.txt").write_text("hello\n" * 50, encoding="utf-8")
        (source / "unicode-\u03b1.txt").write_text("\u03b1\u03b2\u03b3", encoding="utf-8")
        nested = source / "nested directory"
        nested.mkdir()
        (nested / "compressible.bin").write_bytes(b"A" * 200000)
        (nested / "random.bin").write_bytes(os.urandom(350000))
        encoded = root / "encoded"
        encode_args = argparse.Namespace(inputs=[str(source)], recursive=True, output=str(encoded), archive_name="test-artifacts.zip", source="self-test", compression_level=9, max_png_bytes=120000, min_aspect=0.75, max_aspect=1.5, overwrite=False)
        encode_command(encode_args)
        pngs = sorted(encoded.glob("*.png"))
        if len(pngs) < 2:
            raise RuntimeError("Self-test did not produce a multi-PNG case.")
        decode_output = root / "decoded"
        decode_args = argparse.Namespace(inputs=[str(encoded)], recursive=False, output=str(decode_output), overwrite=False, extract=True)
        decode_command(decode_args)
        if (decode_output / "test-artifacts.zip").read_bytes() != (encoded / "test-artifacts.zip").read_bytes():
            raise RuntimeError("Self-test archive mismatch.")
        negative = {}
        try:
            decode_png_set(pngs[:-1])
            negative["missing"] = False
        except Exception:
            negative["missing"] = True
        try:
            decode_png_set(pngs + [pngs[0]])
            negative["duplicate"] = False
        except Exception:
            negative["duplicate"] = True
        reordered, _ = decode_png_set(list(reversed(pngs)))
        negative["reordered"] = reordered == (encoded / "test-artifacts.zip").read_bytes()
        corrupt = root / "corrupt.png"
        damaged = bytearray(pngs[0].read_bytes())
        damaged[len(damaged) // 2] ^= 1
        corrupt.write_bytes(damaged)
        try:
            read_png_rgba(corrupt)
            negative["corrupt"] = False
        except Exception:
            negative["corrupt"] = True
        if not all(negative.values()):
            raise RuntimeError("Negative self-test failed: " + json.dumps(negative))
        print(json.dumps({"self_test": "PASS", "png_count": len(pngs), "negative_tests": negative}, indent=2))


def build_parser():
    parser = argparse.ArgumentParser(prog="artifact_png_transport.py")
    sub = parser.add_subparsers(dest="command", required=True)
    encode = sub.add_parser("encode")
    encode.add_argument("inputs", nargs="+")
    encode.add_argument("-r", "--recursive", action="store_true")
    encode.add_argument("-o", "--output", default="artifact-png-output")
    encode.add_argument("--archive-name", default="collected-artifacts.zip")
    encode.add_argument("--source", default=os.environ.get("COMPUTERNAME") or os.environ.get("HOSTNAME") or "unspecified-source")
    encode.add_argument("--max-png-bytes", type=int, default=4900000)
    encode.add_argument("--min-aspect", type=float, default=0.80)
    encode.add_argument("--max-aspect", type=float, default=1.25)
    encode.add_argument("--compression-level", type=int, choices=range(10), default=9)
    encode.add_argument("--overwrite", action="store_true")
    decode = sub.add_parser("decode")
    decode.add_argument("inputs", nargs="+")
    decode.add_argument("-r", "--recursive", action="store_true")
    decode.add_argument("-o", "--output", default="artifact-png-decoded")
    decode.add_argument("--extract", action="store_true")
    decode.add_argument("--overwrite", action="store_true")
    inspect = sub.add_parser("inspect")
    inspect.add_argument("inputs", nargs="+")
    inspect.add_argument("-r", "--recursive", action="store_true")
    sub.add_parser("self-test")
    return parser


def main():
    args = build_parser().parse_args()
    if hasattr(args, "max_png_bytes") and args.max_png_bytes <= 1024:
        raise ValueError("--max-png-bytes must exceed 1024.")
    if hasattr(args, "min_aspect") and (args.min_aspect <= 0 or args.max_aspect < args.min_aspect):
        raise ValueError("Aspect-ratio limits are invalid.")
    if args.command == "encode":
        encode_command(args)
    elif args.command == "decode":
        decode_command(args)
    elif args.command == "inspect":
        inspect_command(args)
    else:
        self_test_command(args)


if __name__ == "__main__":
    main()
