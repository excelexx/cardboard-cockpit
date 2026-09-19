#!/usr/bin/env python3
"""Reproduce instruction listings from the exact investigated flash snapshot.

Does not open a device. Function names/types are not restored automatically.
"""
import argparse
import hashlib
from pathlib import Path
from capstone import Cs, CS_ARCH_RISCV, CS_MODE_RISCV32, CS_MODE_RISCVC

KNOWN_SHA = "40c7491de4f3dbb34f7befce59eaca4db914848c5968c8395b486f83fb21c103"


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("flash", type=Path)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    data = args.flash.read_bytes()
    if hashlib.sha256(data).hexdigest() != KNOWN_SHA:
        p.error(
            "Snapshot differs; identify its image/segment layout before disassembling it"
        )
    args.output.mkdir(parents=True, exist_ok=True)
    decoder = Cs(CS_ARCH_RISCV, CS_MODE_RISCV32 | CS_MODE_RISCVC)
    decoder.skipdata = True
    segments = [
        ("installed-app-irom", 0x30020, 0x59494, 0x42000020),
        ("retained-stock-irom", 0x150020, 0x27C720, 0x42000020),
        ("retained-stock-iram", 0x27DAC4, 0x297670, 0x40380000),
    ]
    for name, start, end, address in segments:
        with (args.output / f"{name}.asm").open("w") as output:
            for ins in decoder.disasm(data[start:end], address):
                output.write(f"{ins.address:08x}: {ins.mnemonic:12} {ins.op_str}\n")
        print(name, hex(start), hex(end), hex(address))


if __name__ == "__main__":
    main()
