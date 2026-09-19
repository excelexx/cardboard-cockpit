#!/usr/bin/env python3
"""Compile optional bridge firmware; NEVER uploads or erases a device.

PlatformIO 6.12.0 selects Intel GCC on Apple Silicon. Replace only this
workspace's compiler with Espressif's matching native ARM64 release, verified
against the SHA-256 in ESP-IDF v4.4.7 tools/tools.json.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent
ARM_URL = "https://github.com/espressif/crosstool-NG/releases/download/esp-2021r2-patch5/riscv32-esp-elf-gcc8_4_0-esp-2021r2-patch5-macos-arm64.tar.gz"
ARM_SHA = "6e03f2ab1f145be13f8890c6de77b53f52c7bffe3d9d5824549db20298f5ba91"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-dir", type=Path, default=ROOT / ".tools/platformio")
    args = parser.parse_args()
    env = dict(os.environ, PLATFORMIO_CORE_DIR=str(args.core_dir.resolve()))
    pio = [sys.executable, "-m", "platformio"]
    subprocess.run(
        pio + ["pkg", "install", "-d", str(ROOT / "firmware")], env=env, check=True
    )
    if platform.system() == "Darwin" and platform.machine().lower() == "arm64":
        target = args.core_dir / "packages/toolchain-riscv32-esp"
        marker = target / ".native-arm64-installed"
        if not marker.exists():
            downloads = ROOT / ".tools/downloads"
            downloads.mkdir(parents=True, exist_ok=True)
            archive = downloads / "riscv32-macos-arm64.tar.gz"
            if not archive.exists():
                urllib.request.urlretrieve(ARM_URL, archive)
            if hashlib.sha256(archive.read_bytes()).hexdigest() != ARM_SHA:
                raise RuntimeError("Native GCC archive hash mismatch")
            extract = downloads / "native-gcc"
            extract.mkdir(exist_ok=True)
            with tarfile.open(archive) as package:
                for member in package.getmembers():
                    resolved = (extract / member.name).resolve()
                    if (
                        resolved != extract.resolve()
                        and extract.resolve() not in resolved.parents
                    ):
                        raise RuntimeError("Unsafe toolchain archive path")
                    if member.issym() or member.islnk():
                        linked = (
                            (resolved.parent / member.linkname).resolve()
                            if member.issym()
                            else (extract / member.linkname).resolve()
                        )
                        if extract.resolve() not in linked.parents:
                            raise RuntimeError("Unsafe toolchain archive link")
                package.extractall(extract)
            shutil.copytree(extract / "riscv32-esp-elf", target, dirs_exist_ok=True)
            marker.write_text(json.dumps({"url": ARM_URL, "sha256": ARM_SHA}) + "\n")
    subprocess.run(pio + ["run", "-d", str(ROOT / "firmware")], env=env, check=True)


if __name__ == "__main__":
    main()
