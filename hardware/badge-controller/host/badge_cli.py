#!/usr/bin/env python3
"""Terminal button tester / BLE diagnostic for the HTN badge.

Prints every step so a failure is visible, then streams button events.

  .venv/bin/python badge_cli.py
"""

import asyncio
import sys
import time

SERVICE_UUID = "5f1d0000-9c2b-4e7a-a3d6-0b8e1c4f2a71"
CHAR_UUID = "5f1d0001-9c2b-4e7a-a3d6-0b8e1c4f2a71"
DEVICE_NAME = "HTN Badge Buttons"

NAMES = {0: "A", 1: "B", 2: "HOME", 3: "DOWN", 4: "LEFT",
         5: "RIGHT", 6: "UP", 8: "START"}


def names_for(mask):
    held = [n for code, n in sorted(NAMES.items()) if mask & (1 << code)]
    return ", ".join(held) if held else "none"


async def main():
    print("1. importing bleak ...", flush=True)
    from bleak import BleakClient, BleakScanner
    print("   ok", flush=True)

    print("2. scanning 12s for the badge ...", flush=True)
    try:
        found = await BleakScanner.discover(timeout=12.0, return_adv=True)
    except Exception as exc:
        print(f"   SCAN FAILED: {type(exc).__name__}: {exc}")
        print("\n   If this says 'Bluetooth device is turned off' while "
              "Bluetooth is on,\n   it is the macOS permission: System Settings > "
              "Privacy & Security >\n   Bluetooth > enable your terminal, then "
              "restart the terminal.")
        return 1

    print(f"   saw {len(found)} BLE device(s)")
    target = None
    for addr, (dev, adv) in found.items():
        name = dev.name or adv.local_name or ""
        uuids = [u.lower() for u in adv.service_uuids]
        if name == DEVICE_NAME or SERVICE_UUID.lower() in uuids:
            target = addr
            print(f"   FOUND badge: {name!r} at {addr} rssi={adv.rssi}")
    if target is None:
        print("   badge NOT found. Nearby names seen:")
        for addr, (dev, adv) in list(found.items())[:15]:
            print(f"     - {dev.name or adv.local_name or '(unnamed)'}  {addr}")
        return 1

    print(f"3. connecting to {target} ...", flush=True)
    async with BleakClient(target) as client:
        print("   connected", flush=True)
        value = await client.read_gatt_char(CHAR_UUID)
        mask = value[0] | (value[1] << 8)
        print(f"   initial read: raw=0x{value[2]:02x} mask=0x{mask:03x} "
              f"held={names_for(mask)}")

        print("\n4. PRESS BUTTONS NOW (Ctrl+C to stop)\n", flush=True)

        def on_notify(_h, data: bytearray):
            if len(data) < 3:
                return
            m = data[0] | (data[1] << 8)
            print(f"  {time.strftime('%H:%M:%S')}  raw=0x{data[2]:02x}  "
                  f"mask=0x{m:03x}  held={names_for(m)}", flush=True)

        await client.start_notify(CHAR_UUID, on_notify)
        try:
            while client.is_connected:
                await asyncio.sleep(0.3)
        except asyncio.CancelledError:
            pass
    return 0


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except KeyboardInterrupt:
        print("\nstopped")
