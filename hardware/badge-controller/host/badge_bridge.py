#!/usr/bin/env python3
"""Relay the sim's flight phase to the badge over BLE.

The simulator sends one UDP datagram per phase change (and a heartbeat) to
127.0.0.1:8770; this forwards it to the badge's phase characteristic.

  .venv/bin/python badge_bridge.py
  .venv/bin/python badge_bridge.py --demo    # cycle phases, no sim needed
"""

import argparse
import asyncio
import socket
import time

SERVICE_UUID = "5f1d0000-9c2b-4e7a-a3d6-0b8e1c4f2a71"
PHASE_UUID = "5f1d0002-9c2b-4e7a-a3d6-0b8e1c4f2a71"
DEVICE_NAME = "HTN Badge Buttons"

PHASES = {"idle": 0, "takeoff": 1, "sky": 2, "landing": 3}
NAMES = {v: k for k, v in PHASES.items()}

# The badge reverts to idle by itself if it hears nothing for 5 s, so resend
# the current phase comfortably inside that window.
HEARTBEAT_S = 1.5


async def find_badge():
    from bleak import BleakScanner
    return await BleakScanner.find_device_by_filter(
        lambda d, ad: (d.name or "") == DEVICE_NAME
        or SERVICE_UUID.lower() in [u.lower() for u in ad.service_uuids],
        timeout=12.0,
    )


async def run(source):
    from bleak import BleakClient

    while True:
        print("scanning for the badge ...", flush=True)
        device = await find_badge()
        if device is None:
            print("  not found; retrying", flush=True)
            await asyncio.sleep(2.0)
            continue
        try:
            async with BleakClient(device) as client:
                print(f"connected to {device.address}", flush=True)
                last_sent = None
                last_at = 0.0
                while client.is_connected:
                    phase = source()
                    now = time.monotonic()
                    if phase != last_sent or now - last_at >= HEARTBEAT_S:
                        # write_gatt_char without response: fire-and-forget
                        # keeps the sim's frame rate out of BLE's hands.
                        await client.write_gatt_char(
                            PHASE_UUID, bytes([phase]), response=False)
                        if phase != last_sent:
                            print(f"  -> {NAMES.get(phase, phase)}", flush=True)
                        last_sent, last_at = phase, now
                    await asyncio.sleep(0.1)
        except Exception as exc:
            print(f"connection lost: {exc}", flush=True)
        await asyncio.sleep(1.5)


def udp_source(port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
    sock.setblocking(False)
    state = {"phase": 0, "at": 0.0}
    print(f"listening for the sim on udp 127.0.0.1:{port}", flush=True)

    def read():
        while True:
            try:
                data, _ = sock.recvfrom(64)
            except BlockingIOError:
                break
            except OSError:
                break
            text = data.decode("utf-8", "ignore").strip().lower()
            if text in PHASES:
                state["phase"], state["at"] = PHASES[text], time.monotonic()
            elif text.isdigit() and int(text) in NAMES:
                state["phase"], state["at"] = int(text), time.monotonic()
        # The sim going quiet should darken the badge, not freeze it lit.
        if state["phase"] and time.monotonic() - state["at"] > 3.0:
            state["phase"] = 0
        return state["phase"]

    return read


def demo_source():
    order = [1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 0, 0]
    start = time.monotonic()
    return lambda: order[int((time.monotonic() - start) / 2.0) % len(order)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8770)
    ap.add_argument("--demo", action="store_true",
                    help="Cycle takeoff/sky/landing without the sim")
    args = ap.parse_args()
    source = demo_source() if args.demo else udp_source(args.port)
    try:
        asyncio.run(run(source))
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
