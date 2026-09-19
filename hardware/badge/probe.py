#!/usr/bin/env python3
"""Enumerate serial descriptors. Does not open, reset, or write to a device."""
import json
from serial.tools.list_ports import comports

print(
    json.dumps(
        [
            {
                "port": p.device,
                "vid": f"{p.vid:04x}" if p.vid is not None else None,
                "pid": f"{p.pid:04x}" if p.pid is not None else None,
                "serial": p.serial_number,
                "product": p.product,
                "manufacturer": p.manufacturer,
            }
            for p in comports()
        ],
        indent=2,
    )
)
