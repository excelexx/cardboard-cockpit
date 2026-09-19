#!/usr/bin/env python3
"""Live button tester for the Hack the North badge over BLE.

Connects to the badge's custom GATT service, subscribes to button
notifications, and lights up an on-screen pad so you can confirm each
physical button end to end.

Bit order and names come from hardware/badge/docs/buttons.md.

  ./uivenv/bin/python badge_tester.py
  ./uivenv/bin/python badge_tester.py --address <UUID>   # skip the scan
"""

import argparse
import asyncio
import queue
import threading
import time
import tkinter as tk
from tkinter import font as tkfont

SERVICE_UUID = "5f1d0000-9c2b-4e7a-a3d6-0b8e1c4f2a71"
CHAR_UUID = "5f1d0001-9c2b-4e7a-a3d6-0b8e1c4f2a71"
DEVICE_NAME = "HTN Badge Buttons"

# Logical code -> label. Code 7 (AUX1) is the unused input and never reported.
BUTTONS = [
    (0, "A"), (1, "B"), (2, "HOME"), (3, "DOWN"),
    (4, "LEFT"), (5, "RIGHT"), (6, "UP"), (8, "START"),
]

# Physical arrangement: d-pad left, actions right. (column, row) in a grid.
LAYOUT = {
    "UP": (1, 0), "LEFT": (0, 1), "RIGHT": (2, 1), "DOWN": (1, 2),
    "HOME": (4, 0), "START": (5, 0), "B": (4, 1), "A": (5, 1),
}

BG = "#11141a"
IDLE = "#232833"
IDLE_TEXT = "#6b7385"
LIVE = "#2ce08a"
LIVE_TEXT = "#08110c"
ACCENT = "#9aa4bb"


class BleWorker(threading.Thread):
    """Runs bleak on its own asyncio loop, pushes events to the UI queue."""

    def __init__(self, events, address=None):
        super().__init__(daemon=True)
        self.events = events
        self.address = address
        self._stop = threading.Event()

    def stop(self):
        self._stop.set()

    def run(self):
        try:
            asyncio.run(self._main())
        except Exception as exc:  # surfaced in the status bar
            self.events.put(("status", f"BLE thread failed: {exc}"))

    async def _main(self):
        from bleak import BleakClient, BleakScanner

        while not self._stop.is_set():
            address = self.address
            if address is None:
                self.events.put(("status", "Scanning for the badge..."))
                device = await BleakScanner.find_device_by_filter(
                    lambda d, ad: (d.name or "") == DEVICE_NAME
                    or SERVICE_UUID.lower() in [u.lower() for u in ad.service_uuids],
                    timeout=12.0,
                )
                if device is None:
                    self.events.put(("status", "Badge not found; retrying..."))
                    await asyncio.sleep(2.0)
                    continue
                address = device.address

            try:
                self.events.put(("status", f"Connecting to {address}..."))
                async with BleakClient(address) as client:
                    self.events.put(("connected", address))

                    def on_notify(_handle, data: bytearray):
                        if len(data) < 3:
                            return
                        mask = data[0] | (data[1] << 8)
                        self.events.put(("mask", (mask, data[2], time.time())))

                    # Render whatever state the badge is already holding.
                    try:
                        current = await client.read_gatt_char(CHAR_UUID)
                        on_notify(0, bytearray(current))
                    except Exception:
                        pass

                    await client.start_notify(CHAR_UUID, on_notify)
                    while client.is_connected and not self._stop.is_set():
                        await asyncio.sleep(0.2)
                    await client.stop_notify(CHAR_UUID)
            except Exception as exc:
                self.events.put(("status", f"Connection lost: {exc}"))

            self.events.put(("disconnected", None))
            if self._stop.is_set():
                return
            await asyncio.sleep(1.5)


class TesterUI:
    def __init__(self, root, events, worker):
        self.root = root
        self.events = events
        self.worker = worker
        self.counts = {name: 0 for _, name in BUTTONS}
        self.prev_mask = 0
        self.tiles = {}
        self.count_labels = {}

        root.title("Badge Input Tester")
        root.configure(bg=BG)
        root.minsize(720, 470)

        self.mono = tkfont.Font(family="Menlo", size=12)
        big = tkfont.Font(family="Helvetica Neue", size=15, weight="bold")
        small = tkfont.Font(family="Menlo", size=10)

        header = tk.Frame(root, bg=BG)
        header.pack(fill="x", padx=18, pady=(16, 6))
        tk.Label(header, text="BADGE INPUT TESTER", bg=BG, fg="#eef2ff",
                 font=tkfont.Font(family="Helvetica Neue", size=17,
                                  weight="bold")).pack(side="left")
        self.status = tk.Label(header, text="Starting...", bg=BG, fg=ACCENT,
                               font=small)
        self.status.pack(side="right")

        pad = tk.Frame(root, bg=BG)
        pad.pack(padx=18, pady=10)
        for _, name in BUTTONS:
            col, row = LAYOUT[name]
            cell = tk.Frame(pad, bg=IDLE, width=104, height=76,
                            highlightthickness=2, highlightbackground=IDLE)
            cell.grid(row=row, column=col, padx=7, pady=7)
            cell.grid_propagate(False)
            label = tk.Label(cell, text=name, bg=IDLE, fg=IDLE_TEXT, font=big)
            label.place(relx=0.5, rely=0.40, anchor="center")
            count = tk.Label(cell, text="0", bg=IDLE, fg=IDLE_TEXT, font=small)
            count.place(relx=0.5, rely=0.76, anchor="center")
            self.tiles[name] = (cell, label)
            self.count_labels[name] = count
        # Spacer so the d-pad and action cluster stay visually separate.
        pad.grid_columnconfigure(3, minsize=46)

        readout = tk.Frame(root, bg=BG)
        readout.pack(fill="x", padx=18, pady=(2, 4))
        self.raw = tk.Label(readout, text="raw 0xfe   mask 0x000   held: none",
                            bg=BG, fg="#c7d0e4", font=self.mono, anchor="w")
        self.raw.pack(side="left")

        self.log = tk.Text(root, height=8, bg="#0b0e13", fg="#9fb0cc",
                           font=small, relief="flat", highlightthickness=1,
                           highlightbackground="#232833", padx=10, pady=8)
        self.log.pack(fill="both", expand=True, padx=18, pady=(4, 16))
        self.log.insert("end", "Waiting for the badge...\n")
        self.log.configure(state="disabled")

        root.protocol("WM_DELETE_WINDOW", self.close)
        self.poll()

    def write_log(self, text):
        self.log.configure(state="normal")
        self.log.insert("end", text + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def set_tile(self, name, active):
        cell, label = self.tiles[name]
        bg = LIVE if active else IDLE
        fg = LIVE_TEXT if active else IDLE_TEXT
        cell.configure(bg=bg, highlightbackground=LIVE if active else IDLE)
        label.configure(bg=bg, fg=fg)
        self.count_labels[name].configure(bg=bg, fg=fg)

    def apply_mask(self, mask, raw):
        held = []
        for code, name in BUTTONS:
            active = bool(mask & (1 << code))
            was = bool(self.prev_mask & (1 << code))
            self.set_tile(name, active)
            if active:
                held.append(name)
            if active and not was:
                self.counts[name] += 1
                self.count_labels[name].configure(text=str(self.counts[name]))
                self.write_log(f"{time.strftime('%H:%M:%S')}  "
                               f"{name:<6} pressed    raw=0x{raw:02x}")
            elif was and not active:
                self.write_log(f"{time.strftime('%H:%M:%S')}  "
                               f"{name:<6} released   raw=0x{raw:02x}")
        self.prev_mask = mask
        self.raw.configure(
            text=f"raw 0x{raw:02x}   mask 0x{mask:03x}   "
                 f"held: {', '.join(held) if held else 'none'}")

    def poll(self):
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "status":
                    self.status.configure(text=payload, fg=ACCENT)
                elif kind == "connected":
                    self.status.configure(text=f"connected  {payload}", fg=LIVE)
                    self.write_log(f"Connected to {payload}")
                elif kind == "disconnected":
                    self.status.configure(text="disconnected", fg="#e0655f")
                    self.write_log("Disconnected")
                    self.apply_mask(0, 0xfe)
                elif kind == "mask":
                    mask, raw, _ = payload
                    self.apply_mask(mask, raw)
        except queue.Empty:
            pass
        self.root.after(16, self.poll)

    def close(self):
        self.worker.stop()
        self.root.destroy()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", help="Skip scanning and use this BLE address")
    args = parser.parse_args()

    events = queue.Queue()
    worker = BleWorker(events, args.address)
    worker.start()

    root = tk.Tk()
    TesterUI(root, events, worker)
    root.mainloop()


if __name__ == "__main__":
    main()
