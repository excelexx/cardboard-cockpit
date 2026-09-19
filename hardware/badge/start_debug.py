#!/usr/bin/env python3
"""Start a localhost-only OpenOCD server, selecting one Espressif USB device."""
import argparse
from pathlib import Path
import platform
import re
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--serial",
        help="USB descriptor serial; required if multiple badges are attached",
    )
    p.add_argument("--port", type=int, default=16666)
    p.add_argument(
        "--gdb-port", type=int, default=0, help="Opt-in GDB port; 0 disables it"
    )
    p.add_argument(
        "--reset",
        action="store_true",
        help="Reset once after attaching; useful when IRAM writes are rejected after a ROM-loader reset",
    )
    args = p.parse_args()
    if not 1 <= args.port <= 65535 or not 0 <= args.gdb_port <= 65535:
        p.error("Invalid TCP port")
    serial = args.serial
    if not serial:
        from serial.tools.list_ports import comports

        ports = [
            item for item in comports() if item.vid == 0x303A and item.pid == 0x1001
        ]
        serials = {item.serial_number for item in ports if item.serial_number}
        if len(serials) != 1:
            p.error(
                "Connect one badge or specify --serial; run probe.py to list devices"
            )
        serial = serials.pop()
    if not re.fullmatch(r"[A-Za-z0-9:._-]{1,128}", serial):
        p.error("Unexpected USB serial format")
    root = Path(__file__).resolve().parent / ".tools/openocd-esp32"
    binary = (
        root / "bin" / ("openocd.exe" if platform.system() == "Windows" else "openocd")
    )
    if not binary.is_file():
        p.error("Run setup_tools.py first")
    command = [
        str(binary),
        "-s",
        str(root / "share/openocd/scripts"),
        "-f",
        "board/esp32c3-builtin.cfg",
        "-c",
        f"adapter serial {serial}",
        "-c",
        "bindto 127.0.0.1",
        "-c",
        f'gdb port {args.gdb_port or "disabled"}',
        "-c",
        "telnet port disabled",
        "-c",
        f"tcl port {args.port}",
    ]
    if args.reset:
        command += ["-c", "init", "-c", "reset run"]
    try:
        raise SystemExit(subprocess.call(command))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
