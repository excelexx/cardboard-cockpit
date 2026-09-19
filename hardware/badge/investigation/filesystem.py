#!/usr/bin/env python3
"""Inspect the recovered LittleFS volume offline, without formatting or writing it.

Default output contains counts/geometry only. Paths or contents are exported
only with explicit options; put those outputs under an ignored .private/.
"""
import argparse
import collections
import hashlib
import json
import os
from pathlib import Path, PurePosixPath

from littlefs import LittleFS
from littlefs.context import UserContext


class ReadOnlyContext(UserContext):
    def prog(self, *args):
        return -5

    def erase(self, *args):
        return -5


def inspect_volume(image, block_size=4096, extract_to=None):
    if block_size < 512 or block_size % 128 or len(image) % block_size:
        raise ValueError("Expected a complete volume with compatible block size")
    context = ReadOnlyContext(len(image))
    context.buffer = bytearray(image)
    fs = LittleFS(
        context=context,
        block_size=block_size,
        block_count=len(image) // block_size,
        read_size=128,
        prog_size=128,
        cache_size=512,
        lookahead_size=128,
        mount=False,
    )
    fs.mount()  # No auto-format fallback.
    inventory = []
    extensions = collections.Counter()
    try:
        stat = fs.fs_stat()
        if extract_to:
            extract_to = Path(extract_to).resolve()
            if extract_to.exists() and any(extract_to.iterdir()):
                raise ValueError("Extraction destination must be empty")
            extract_to.mkdir(parents=True, exist_ok=True)
        for directory, _, files in fs.walk("/"):
            for name in files:
                source = directory.rstrip("/") + "/" + name
                info = fs.stat(source)
                extensions[Path(name).suffix or "(none)"] += 1
                inventory.append({"path": source, "bytes": info.size})
                if extract_to:
                    relative = PurePosixPath(source.lstrip("/"))
                    if ".." in relative.parts or "\\" in source or "\x00" in source:
                        raise ValueError("Unsafe filesystem path")
                    destination = (extract_to / str(relative)).resolve()
                    if extract_to not in destination.parents:
                        raise ValueError("Path escaped extraction directory")
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    with fs.open(source, "rb") as source_file:
                        data = source_file.read()
                    fd = os.open(
                        destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600
                    )
                    with os.fdopen(fd, "wb") as output:
                        output.write(data)
        summary = {
            "disk_version": f"{stat.disk_version>>16}.{stat.disk_version&65535}",
            "block_size": stat.block_size,
            "block_count": stat.block_count,
            "volume_bytes": len(image),
            "volume_sha256": hashlib.sha256(image).hexdigest(),
            "file_count": len(inventory),
            "total_file_bytes": sum(item["bytes"] for item in inventory),
            "extensions": dict(extensions),
            "installed_app_lua_sources": sum(
                item["path"].startswith("/apps/") and item["path"].endswith(".lua")
                for item in inventory
            ),
        }
    finally:
        fs.unmount()
    if bytes(context.buffer) != image:
        raise RuntimeError("Read-only image unexpectedly changed")
    summary["source_buffer_unchanged"] = True
    return summary, inventory


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("flash", type=Path)
    p.add_argument("--offset", type=lambda s: int(s, 0), default=0x2B0000)
    p.add_argument("--size", type=lambda s: int(s, 0), default=0x140000)
    p.add_argument("--block-size", type=int, default=4096)
    p.add_argument("--summary", type=Path)
    p.add_argument("--private-inventory", type=Path)
    p.add_argument("--extract-to", type=Path)
    args = p.parse_args()
    flash = args.flash.read_bytes()
    if args.offset < 0 or args.size <= 0 or args.offset + args.size > len(flash):
        p.error("Volume is outside the input image")
    summary, inventory = inspect_volume(
        flash[args.offset : args.offset + args.size], args.block_size, args.extract_to
    )
    summary["flash_offset"] = hex(args.offset)
    encoded = json.dumps(summary, indent=2) + "\n"
    if args.summary:
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        args.summary.write_text(encoded)
    if args.private_inventory:
        args.private_inventory.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(
            args.private_inventory, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600
        )
        with os.fdopen(fd, "w") as output:
            json.dump(inventory, output, indent=2)
    print(encoded, end="")


if __name__ == "__main__":
    main()
