#!/usr/bin/env python3
"""Install the pinned Espressif OpenOCD release into this package's .tools/.

Downloads only the platform's official vendor archive and verifies its pinned
SHA-256 before extraction. Python dependencies are installed separately.
"""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent


def asset_name(system=None, machine=None):
    system = system or platform.system()
    machine = (machine or platform.machine()).lower()
    if system == "Darwin":
        target = "macos-arm64" if machine in ("arm64", "aarch64") else "macos"
    elif system == "Linux":
        target = {
            "x86_64": "linux-amd64",
            "amd64": "linux-amd64",
            "aarch64": "linux-arm64",
            "arm64": "linux-arm64",
            "armv7l": "linux-armhf",
            "armv6l": "linux-armel",
        }.get(machine)
        if not target:
            raise RuntimeError(f"Unsupported Linux architecture {machine}")
    elif system == "Windows":
        target = "win-arm64" if machine in ("arm64", "aarch64") else "win64"
    else:
        raise RuntimeError(f"Unsupported platform {system}/{machine}")
    extension = "zip" if system == "Windows" else "tar.gz"
    return f"openocd-esp32-{target}-0.12.0-esp32-20260831.{extension}"


def install():
    lock = json.loads((ROOT / "toolchain-lock.json").read_text())
    name = asset_name()
    record = lock["assets"][name]
    destination = ROOT / ".tools"
    destination.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination) as temporary:
        temp = Path(temporary)
        archive = temp / name
        print("Downloading", record["url"], flush=True)
        urllib.request.urlretrieve(record["url"], archive)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != record["sha256"]:
            raise RuntimeError("OpenOCD archive hash mismatch")
        unpack = temp / "unpacked"
        unpack.mkdir()
        if name.endswith(".zip"):
            with zipfile.ZipFile(archive) as package:
                for member in package.infolist():
                    resolved = (unpack / member.filename).resolve()
                    if unpack.resolve() not in resolved.parents:
                        raise RuntimeError("Unsafe archive path")
                package.extractall(unpack)
        else:
            with tarfile.open(archive) as package:
                for member in package.getmembers():
                    resolved = (unpack / member.name).resolve()
                    if (
                        resolved != unpack.resolve()
                        and unpack.resolve() not in resolved.parents
                    ):
                        raise RuntimeError("Unsafe archive path")
                    if member.issym() or member.islnk():
                        target = (
                            (resolved.parent / member.linkname).resolve()
                            if member.issym()
                            else (unpack / member.linkname).resolve()
                        )
                        if unpack.resolve() not in target.parents:
                            raise RuntimeError("Unsafe archive link")
                package.extractall(unpack)
        source = unpack / "openocd-esp32"
        if not source.is_dir():
            raise RuntimeError("Archive layout changed")
        shutil.copytree(source, destination / "openocd-esp32", dirs_exist_ok=True)
    (destination / "openocd-version.json").write_text(
        json.dumps({"asset": name, **record}, indent=2) + "\n"
    )
    print("Installed verified OpenOCD into", destination / "openocd-esp32")


if __name__ == "__main__":
    install()
