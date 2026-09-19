#!/usr/bin/env python3
"""Analyze a supplied 4MB backup; exports no provisioning data or raw strings.

Image extraction is opt-in. Use an ignored .private/ output directory.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct


def analyze(data):
    if len(data) != 4 * 1024 * 1024:
        raise ValueError("Expected a complete 4MB ESP32-C3 flash image")
    partitions = []
    for offset in range(0x8000, 0x9000, 32):
        entry = data[offset : offset + 32]
        if entry[:2] != b"\xaa\x50":
            break
        _, typ, sub, start, size, label, flags = struct.unpack("<HBBII16sI", entry)
        if start + size > len(data):
            raise ValueError("Partition extends past flash")
        partitions.append(
            {
                "type": typ,
                "subtype": sub,
                "offset": start,
                "size": size,
                "label": label.rstrip(b"\0").decode("ascii", errors="replace"),
                "flags": flags,
            }
        )
    retained = []
    for offset, address, length in [
        (0x150018, 0x42000020, 0x12C700),
        (0x27DABC, 0x40380000, 0x19BAC),
    ]:
        actual = struct.unpack_from("<II", data, offset)
        retained.append(
            {
                "header_offset": hex(offset),
                "load_address": hex(address),
                "length": hex(length),
                "header_matches_investigated_snapshot": actual == (address, length),
            }
        )
    digest = hashlib.sha256(data).hexdigest()
    known = digest == "40c7491de4f3dbb34f7befce59eaca4db914848c5968c8395b486f83fb21c103"
    return {
        "bytes": len(data),
        "sha256": digest,
        "matches_investigated_snapshot": known,
        "current_partition_table": partitions,
        "retained_segment_candidates": retained,
        "factory_firmware_complete": False if known else None,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("flash", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--extract-images", action="store_true")
    args = parser.parse_args()
    data = args.flash.read_bytes()
    result = analyze(data)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "manifest.json").write_text(json.dumps(result, indent=2) + "\n")
    if args.extract_images:
        for part in result["current_partition_table"]:
            if part["type"] != 0:
                continue
            label = re.sub(r"[^a-zA-Z0-9_-]", "_", part["label"]) or "unnamed"
            start, size = part["offset"], part["size"]
            (args.output / f"app-{label}-{start:06x}.bin").write_bytes(
                data[start : start + size]
            )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
