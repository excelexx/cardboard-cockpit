#!/usr/bin/env python3
"""ESP32-C3 USB/JTAG controls. No third-party Python modules required.

Start start_debug.py --reset first. Button commands temporarily halt the current
firmware, use the recovered 74HC165 wiring, restore pin state, then resume.
"""
import argparse
import contextlib

try:
    import fcntl
except ImportError:
    fcntl = None
    import msvcrt
import getpass
import json
import math
import os
import re
import signal
import socket
import struct
import sys
import tempfile
import threading
import time

if __package__:
    from . import ram_io
else:
    import ram_io

GPIO = 0x60004000
IOMUX = 0x60009000
PL, CP, Q7, START = 20, 21, 7, 9
BUTTONS = {
    0: "A",
    1: "B",
    2: "HOME",
    3: "DOWN",
    4: "LEFT",
    5: "RIGHT",
    6: "UP",
    8: "START",
}


class Debugger:
    def __init__(self, port=16666):
        user_id = (
            str(os.getuid())
            if hasattr(os, "getuid")
            else re.sub(r"[^a-zA-Z0-9_-]", "_", getpass.getuser())
        )
        lock_path = os.path.join(
            tempfile.gettempdir(), f"cardboard-badge-{user_id}-{port}.lock"
        )
        self.lock = open(lock_path, "a+b")
        try:
            if fcntl is not None:
                fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            else:
                self.lock.seek(0)
                self.lock.write(b"0")
                self.lock.flush()
                self.lock.seek(0)
                msvcrt.locking(self.lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            self.lock.close()
            raise RuntimeError(
                "Another badge control process owns this device. Stop it before continuing."
            ) from None
        try:
            self.sock = socket.create_connection(("127.0.0.1", port), timeout=10)
        except BaseException:
            self.lock.close()
            raise
        self.sock.settimeout(15)
        self.resume_address = None
        self.resume_allowed = True

    def close(self):
        self.sock.close()
        self.lock.close()

    def __enter__(self):
        return self

    def __exit__(self, kind, value, traceback):
        self.close()

    def command(self, script):
        # Tcl catch distinguishes command errors from ordinary empty results.
        if "\x1a" in script:
            raise ValueError("Invalid Tcl terminator")
        wrapped = (
            "set _esp_rc [catch {"
            + script
            + "} _esp_result]; list $_esp_rc $_esp_result"
        )
        # Finish the current RPC before propagating Ctrl+C. Otherwise cleanup
        # could mistake a leftover reply for a GPIO/IRAM restoration response.
        interrupted = False
        previous_handler = None

        def defer_interrupt(signum, frame):
            nonlocal interrupted
            interrupted = True

        if threading.current_thread() is threading.main_thread():
            previous_handler = signal.getsignal(signal.SIGINT)
            if previous_handler == signal.SIG_IGN:
                previous_handler = None
            else:
                signal.signal(signal.SIGINT, defer_interrupt)
        try:
            self.sock.sendall(wrapped.encode() + b"\x1a")
            response = bytearray()
            while not response.endswith(b"\x1a"):
                chunk = self.sock.recv(65536)
                if not chunk:
                    raise ConnectionError("OpenOCD disconnected")
                response.extend(chunk)
        finally:
            if previous_handler is not None:
                signal.signal(signal.SIGINT, previous_handler)
            if interrupted:
                if callable(previous_handler):
                    previous_handler(signal.SIGINT, None)
                else:
                    raise KeyboardInterrupt
        text = response[:-1].decode()
        status, _, result = text.partition(" ")
        if result.startswith("{") and result.endswith("}"):
            result = result[1:-1]
        if status != "0":
            raise RuntimeError(result)
        return result

    def read(self, address, count=1):
        if (
            address % 4
            or not 0 <= address <= 0xFFFFFFFC
            or not 1 <= count <= 4096
            or address + count * 4 > 0x100000000
        ):
            raise ValueError("Use aligned addresses and 1..4096 words")
        result = self.command(f"read_memory {address:#x} 32 {count}")
        values = [int(x, 0) for x in result.split()]
        if len(values) != count:
            raise RuntimeError(f"Expected {count} words, got {result!r}")
        return values

    def write(self, address, value):
        if (
            address % 4
            or not 0 <= address <= 0xFFFFFFFC
            or not 0 <= value <= 0xFFFFFFFF
        ):
            raise ValueError("Use an aligned address and unsigned 32-bit value")
        self.command(f"write_memory {address:#x} 32 {{{value:#x}}}")

    @contextlib.contextmanager
    def halted(self):
        state = self.command("targets")
        running = bool(re.search(r"\besp32c3\s+little.*\brunning\b", state))
        if running:
            self.command("halt")
        elif "halted" not in state:
            raise RuntimeError("ESP32-C3 target is not running or halted")
        try:
            yield
        finally:
            if running and self.resume_allowed:
                self.command(
                    "resume"
                    + (
                        f" {self.resume_address:#x}"
                        if self.resume_address is not None
                        else ""
                    )
                )
                self.resume_address = None

    @contextlib.contextmanager
    def pins(self, outputs, inputs, open_drain=False):
        pins = sorted(set(outputs) | set(inputs))
        if set(outputs) & set(inputs) or any(
            p not in range(22) or 11 <= p <= 19 for p in pins
        ):
            raise ValueError("Conflicting or reserved flash/USB pins")
        mask = sum(1 << p for p in pins)
        with self.halted():
            out, enable = self.read(GPIO + 4)[0], self.read(GPIO + 0x20)[0]
            saved = {}
            for p in pins:
                for a in (IOMUX + 4 + p * 4, GPIO + 0x74 + p * 4, GPIO + 0x554 + p * 4):
                    saved[a] = self.read(a)[0]
            try:
                self.write(GPIO + 0x28, mask)
                for p in pins:
                    a = IOMUX + 4 + p * 4
                    mux = (saved[a] & ~0x7000) | 0x1200
                    if open_drain:
                        mux = (mux & ~0x80) | 0x100
                    self.write(a, mux)
                    self.write(
                        GPIO + 0x74 + p * 4,
                        (saved[GPIO + 0x74 + p * 4] & ~4) | (4 if open_drain else 0),
                    )
                    self.write(GPIO + 0x554 + p * 4, 0x280)
                for p, level in outputs.items():
                    self.level(p, level)
                self.write(GPIO + 0x24, sum(1 << p for p in outputs))
                yield
            finally:
                self.write(GPIO + 0x28, mask)
                self.write(GPIO + 0xC, mask)
                self.write(GPIO + 8, out & mask)
                for a, v in saved.items():
                    self.write(a, v)
                self.write(GPIO + 0x24, enable & mask)

    def level(self, pin, high):
        self.write(GPIO + (8 if high else 0xC), 1 << pin)

    def gpio(self):
        level = self.read(GPIO + 0x3C)[0]
        enable = self.read(GPIO + 0x20)[0]
        return {
            "raw": f"0x{level:08x}",
            "output_enable": f"0x{enable:08x}",
            "pins": {str(p): (level >> p) & 1 for p in range(22)},
        }

    def buttons(self):
        # Recover the exact stock sequence at IROM 0x4200af2a.
        # Execute one Tcl batch to avoid TCP round trips between clock edges.
        script = """
write_memory 0x6000400c 32 {0x100000}
write_memory 0x60004008 32 {0x100000}
set _raw 0
for {set _i 0} {$_i < 8} {incr _i} {
  set _pin [lindex [read_memory 0x6000403c 32 1] 0]
  set _raw [expr {($_raw << 1) | (($_pin >> 7) & 1)}]
  write_memory 0x60004008 32 {0x200000}
  write_memory 0x6000400c 32 {0x200000}
}
set _pin [lindex [read_memory 0x6000403c 32 1] 0]
list $_raw [expr {1-(($_pin >> 9) & 1)}]
"""
        raw, start = map(int, self.command(script).split())
        return decode_buttons(raw, bool(start))

    def i2c_setup(self):
        self.command(
            """
proc esp_sda {v} {
  if {$v} {write_memory 0x60004008 32 {0x20}} else {write_memory 0x6000400c 32 {0x20}}
}
proc esp_scl {v} {
  if {!$v} {write_memory 0x6000400c 32 {0x40}; return}
  write_memory 0x60004008 32 {0x40}
  for {set n 0} {$n < 50} {incr n} {
    if {[expr {[lindex [read_memory 0x6000403c 32 1] 0] & 0x40}]} {return}
    sleep 1
  }
  error "I2C clock held low"
}
proc esp_i2c_start {} {esp_sda 1; esp_scl 1; esp_sda 0; esp_scl 0}
proc esp_i2c_stop {} {esp_sda 0; esp_scl 1; esp_sda 1}
proc esp_i2c_byte {v} {
  for {set i 7} {$i >= 0} {incr i -1} {
    esp_sda [expr {($v >> $i) & 1}]; esp_scl 1; esp_scl 0
  }
  esp_sda 1; esp_scl 1
  set ack [expr {([lindex [read_memory 0x6000403c 32 1] 0] & 0x20) == 0}]
  esp_scl 0
  return $ack
}
proc esp_i2c_readbyte {ack} {
  esp_sda 1; set v 0
  for {set i 0} {$i < 8} {incr i} {
    esp_scl 1
    set v [expr {($v << 1) | (([lindex [read_memory 0x6000403c 32 1] 0] >> 5) & 1)}]
    esp_scl 0
  }
  esp_sda [expr {!$ack}]; esp_scl 1; esp_scl 0; esp_sda 1
  return $v
}
"""
        )

    def i2c_scan(self):
        result = self.command(
            """
set found {}
for {set a 8} {$a < 120} {incr a} {
  esp_i2c_start
  set ack [esp_i2c_byte [expr {$a << 1}]]
  esp_i2c_stop
  if {$ack} {lappend found $a}
}
set found
"""
        )
        return [int(v) for v in result.split()]

    def i2c_read(self, address, register, count):
        if not 8 <= address < 120 or not 0 <= register < 256 or not 1 <= count <= 256:
            raise ValueError("Invalid I2C address, register, or byte count")
        try:
            result = self.command(
                f"""
esp_i2c_start
if {{![esp_i2c_byte {address*2}]}} {{error "No address ACK"}}
if {{![esp_i2c_byte {register}]}} {{error "No register ACK"}}
esp_i2c_start
if {{![esp_i2c_byte {address*2+1}]}} {{error "No read ACK"}}
set result {{}}
for {{set i 0}} {{$i < {count}}} {{incr i}} {{
  lappend result [esp_i2c_readbyte [expr {{$i < {count-1}}}]]
}}
esp_i2c_stop
set result
"""
            )
            return [int(v) for v in result.split()]
        finally:
            self.command("esp_i2c_stop")

    def i2c_write(self, address, register, values):
        if not 8 <= address < 120 or any(not 0 <= v < 256 for v in [register, *values]):
            raise ValueError("Invalid I2C address, register, or value")
        try:
            sequence = [address * 2, register, *values]
            self.command(
                "esp_i2c_start; "
                + "; ".join(
                    f'if {{![esp_i2c_byte {v}]}} {{error "No ACK at byte {i}"}}'
                    for i, v in enumerate(sequence)
                )
                + "; esp_i2c_stop"
            )
        finally:
            self.command("esp_i2c_stop")

    def accelerometer(self):
        ident = self.i2c_read(0x19, 0x0F, 1)[0]
        if ident != 0x11:
            raise RuntimeError(f"Unexpected accelerometer identity: {ident:#x}")
        ctrl1 = self.i2c_read(0x19, 0x20, 1)[0]
        ctrl4 = self.i2c_read(0x19, 0x23, 1)[0]
        try:
            self.i2c_write(0x19, 0x23, [0x88])
            self.i2c_write(0x19, 0x20, [0x57])
            time.sleep(0.05)
            raw = bytes(self.i2c_read(0x19, 0xA8, 6))
            axes = struct.unpack("<hhh", raw)
            return {
                "who_am_i": "0x11",
                "raw_xyz": axes,
                "xyz_mg": [x >> 4 for x in axes],
                "orientation": "sensor axes; board orientation not calibrated",
            }
        finally:
            self.i2c_write(0x19, 0x20, [ctrl1])
            self.i2c_write(0x19, 0x23, [ctrl4])

    def nfc_info(self):
        names = {
            "command": 0x01,
            "error": 0x06,
            "fifo_level": 0x0A,
            "tx_control": 0x14,
            "rf_config": 0x26,
            "version": 0x37,
        }
        return {
            "address": "0x26",
            "family": "RC522-compatible; exact silicon not established",
            "registers": {
                name: f"0x{self.i2c_read(0x26, reg, 1)[0]:02x}"
                for name, reg in names.items()
            },
        }

    def nfc_crc(self, data):
        if not 1 <= len(data) <= 64:
            raise ValueError("RC522 FIFO accepts 1..64 bytes for this test")
        command = self.i2c_read(0x26, 0x01, 1)[0]
        mode = self.i2c_read(0x26, 0x11, 1)[0]
        if self.i2c_read(0x26, 0x0A, 1)[0] & 0x7F:
            raise RuntimeError(
                "NFC FIFO is not empty; refusing to discard pending data"
            )
        if command & 0xF:
            raise RuntimeError("NFC coprocessor is busy")
        try:
            # CommandReg bit 4 is PowerDown. It stays set while waking;
            # FIFO/register access alone does not establish oscillator readiness.
            self.i2c_write(0x26, 0x01, [command & 0x20])
            wake_deadline = time.monotonic() + 2
            while self.i2c_read(0x26, 0x01, 1)[0] & 0x10:
                if time.monotonic() > wake_deadline:
                    raise TimeoutError(
                        "NFC PowerDown bit did not clear during wake-up; CRC/RF engine readiness is unverified"
                    )
            self.i2c_write(0x26, 0x11, [0x3D])
            self.i2c_write(0x26, 0x05, [4])
            self.i2c_write(0x26, 0x0A, [0x80])
            for byte in data:
                self.i2c_write(0x26, 0x09, [byte])
            self.i2c_write(0x26, 0x01, [3])
            until = time.monotonic() + 0.5
            while not self.i2c_read(0x26, 0x05, 1)[0] & 4:
                if time.monotonic() > until:
                    raise TimeoutError("NFC CRC engine did not complete")
            high = self.i2c_read(0x26, 0x21, 1)[0]
            low = self.i2c_read(0x26, 0x22, 1)[0]
            expected = crc_a(data)
            hardware = low | (high << 8)
            return {
                "hardware_crc_a": f"0x{hardware:04x}",
                "software_crc_a": f"0x{expected:04x}",
                "match": hardware == expected,
                "rf_enabled_by_test": False,
            }
        finally:
            self.i2c_write(0x26, 0x01, [0])
            self.i2c_write(0x26, 0x0A, [0x80])
            self.i2c_write(0x26, 0x11, [mode])
            self.i2c_write(0x26, 0x01, [command])

    def spi_setup(self):
        self.command(
            """
proc esp_spi_byte {v} {
  for {set i 7} {$i >= 0} {incr i -1} {
    write_memory 0x6000400c 32 {0x2}
    if {[expr {($v >> $i) & 1}]} {
      write_memory 0x60004008 32 {0x400}
    } else {write_memory 0x6000400c 32 {0x400}}
    write_memory 0x60004008 32 {0x2}
    write_memory 0x6000400c 32 {0x2}
  }
}
"""
        )

    def display_command(self, command, data=()):
        data = tuple(data)
        if (
            not isinstance(command, int)
            or not 0 <= command <= 255
            or any(not isinstance(v, int) or not 0 <= v <= 255 for v in data)
        ):
            raise ValueError("LCD command and parameter bytes must be 0..255")
        self.level(2, 0)
        self.level(0, 0)
        self.command(f"esp_spi_byte {command}")
        if data:
            self.level(0, 1)
            self.command("; ".join(f"esp_spi_byte {int(v)}" for v in data))
        self.level(2, 1)

    def display_init(self):
        self.spi_setup()
        self.level(4, 0)
        time.sleep(0.02)
        self.level(4, 1)
        time.sleep(0.12)
        self.display_command(0x11)
        time.sleep(0.12)
        self.display_command(0x3A, [0x55])
        self.display_command(0x36, [0x60])
        self.display_command(0x21)
        self.display_command(0x13)
        self.display_command(0x29)

    def display_rectangle(self, x, y, width, height, colour):
        if not isinstance(colour, int) or not 0 <= colour <= 65535:
            raise ValueError("Expected an RGB565 integer colour")
        if not (
            0 <= x < 320
            and 0 <= y < 240
            and 1 <= width <= 320 - x
            and 1 <= height <= 240 - y
        ):
            raise ValueError("Rectangle outside 320x240 display")
        xe, ye = x + width - 1, y + height - 1
        self.display_command(0x2A, [x >> 8, x & 255, xe >> 8, xe & 255])
        self.display_command(0x2B, [y >> 8, y & 255, ye >> 8, ye & 255])
        self.level(2, 0)
        self.level(0, 0)
        self.command("esp_spi_byte 44")
        self.level(0, 1)
        try:
            ram_io.fill(self, colour, width * height)
        finally:
            self.level(2, 1)


def decode_buttons(raw, start):
    if (
        not isinstance(raw, int)
        or isinstance(raw, bool)
        or not 0 <= raw <= 255
        or not isinstance(start, bool)
    ):
        raise ValueError("Expected one raw byte and boolean Start level")
    logical = int(f"{raw ^ 255:08b}"[::-1], 2) | (int(start) << 8)
    physical = logical & 0x17F
    return {
        "shift_raw": f"0x{raw:02x}",
        "raw_held_mask": f"0x{logical:03x}",
        "held_mask": f"0x{physical:03x}",
        "held_codes": [p for p in BUTTONS if physical & (1 << p)],
        "held_buttons": [name for p, name in BUTTONS.items() if physical & (1 << p)],
        "start": start,
    }


def crc_a(data):
    crc = 0x6363
    for byte in data:
        x = byte ^ (crc & 0xFF)
        x ^= (x << 4) & 0xFF
        crc = ((crc >> 8) ^ (x << 8) ^ (x << 3) ^ (x >> 4)) & 0xFFFF
    return crc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=16666)
    parser.add_argument(
        "--hold",
        type=float,
        default=0,
        help="Keep output configuration and CPU halted this many seconds after an output test",
    )
    sub = parser.add_subparsers(dest="operation", required=True)
    sub.add_parser("gpio", help="Read GPIO levels without reconfiguring pins")
    sub.add_parser(
        "reset",
        help="Reset the CPU to its installed flash firmware; does not write flash",
    )
    read = sub.add_parser("read32", help="Read aligned memory/register words")
    read.add_argument("address", type=lambda s: int(s, 0))
    read.add_argument("count", type=int, nargs="?", default=1)
    sub.add_parser("cpu", help="Briefly halt to inspect registers; resume afterward")
    sub.add_parser("buttons", help="Read one byte from the recovered button circuit")
    sub.add_parser(
        "i2c-scan", help="Probe address ACKs on SDA=5/SCL=6; sends no payload"
    )
    sub.add_parser(
        "accel",
        help="Temporarily sample SC7A20 acceleration, then restore its settings",
    )
    sub.add_parser(
        "display-demo",
        help="Initialize LCD and draw red, green, blue bands using temporary RAM code",
    )
    sub.add_parser(
        "io-demo", help="LCD bands plus green LEDs on verified GPIO3, held together"
    )
    disp = sub.add_parser(
        "display-fill", help="Initialize LCD and fill it with an RGB565 colour"
    )
    disp.add_argument("colour", type=lambda s: int(s, 0))
    leds = sub.add_parser("leds", help="Send six RGB pixels using temporary RAM code")
    leds.add_argument(
        "--pin", type=int, choices=[3], default=3, help="Verified RGB LED data pin"
    )
    leds.add_argument(
        "--index",
        type=int,
        choices=range(1, 7),
        help="Light one LED (1..6); others off",
    )
    leds.add_argument("red", type=int)
    leds.add_argument("green", type=int)
    leds.add_argument("blue", type=int)
    sub.add_parser(
        "nfc-info", help="Read RC522-compatible reader status and version registers"
    )
    nfc_crc = sub.add_parser(
        "nfc-crc", help="Verify NFC hardware CRC engine without enabling its RF field"
    )
    nfc_crc.add_argument("hex_bytes", help="1..64 payload bytes in hexadecimal")
    i2c = sub.add_parser("i2c-read", help="Read an I2C register on the recovered bus")
    i2c.add_argument("address", type=lambda s: int(s, 0))
    i2c.add_argument("register", type=lambda s: int(s, 0))
    i2c.add_argument("count", type=int, nargs="?", default=1)
    i2cw = sub.add_parser(
        "i2c-write", help="Write explicit volatile device-register values"
    )
    i2cw.add_argument("address", type=lambda s: int(s, 0))
    i2cw.add_argument("register", type=lambda s: int(s, 0))
    i2cw.add_argument("values", type=lambda s: int(s, 0), nargs="+")
    watch = sub.add_parser(
        "watch-buttons", help="Log changes; firmware is halted during capture"
    )
    watch.add_argument("--seconds", type=float, default=30)
    write = sub.add_parser(
        "write32", help="Explicit raw memory/register write; know the target address"
    )
    write.add_argument("address", type=lambda s: int(s, 0))
    write.add_argument("value", type=lambda s: int(s, 0))
    args = parser.parse_args()
    if not math.isfinite(args.hold) or args.hold < 0:
        parser.error("--hold must be a finite, nonnegative duration")
    if args.operation == "display-fill" and not 0 <= args.colour <= 65535:
        parser.error("RGB565 colour must be 0..65535")
    if args.operation == "leds" and any(
        not 0 <= v <= 255 for v in (args.red, args.green, args.blue)
    ):
        parser.error("RGB channels must be 0..255")
    if args.operation == "watch-buttons" and (
        not math.isfinite(args.seconds) or args.seconds <= 0
    ):
        parser.error("--seconds must be a finite positive duration")
    dbg = Debugger(args.port)
    try:
        if args.operation == "gpio":
            print(json.dumps(dbg.gpio(), indent=2))
        elif args.operation == "reset":
            dbg.command("reset run")
            print("CPU reset; installed flash firmware resumed.")
        elif args.operation == "read32":
            for i, v in enumerate(dbg.read(args.address, args.count)):
                print(f"{args.address+4*i:#010x}: {v:#010x}")
        elif args.operation == "write32":
            with dbg.halted():
                dbg.write(args.address, args.value)
            print("Write completed (readback is register-dependent).")
        elif args.operation == "cpu":
            with dbg.halted():
                for name in ("pc", "ra", "sp", "mstatus"):
                    print(dbg.command("reg " + name))
        elif args.operation in ("display-demo", "display-fill", "io-demo"):
            pins = {0: 1, 1: 0, 2: 1, 4: 1, 10: 0}
            if args.operation == "io-demo":
                pins.update({3: 0})
            with dbg.pins(pins, []):
                dbg.display_init()
                if args.operation in ("display-demo", "io-demo"):
                    for y, colour in [(0, 0xF800), (80, 0x07E0), (160, 0x001F)]:
                        dbg.display_rectangle(0, y, 320, 80, colour)
                else:
                    dbg.display_rectangle(0, 0, 320, 240, args.colour)
                if args.operation == "io-demo":
                    ram_io.leds(dbg, 3, [(0, 24, 0)] * 6)
                print(
                    "Frame sent; holding outputs for", args.hold, "seconds.", flush=True
                )
                time.sleep(max(0, args.hold))
            print("LCD commands and pixel data sent; visual confirmation is required.")
        elif args.operation == "leds":
            colour = (args.red, args.green, args.blue)
            pixels = [
                colour if args.index is None or i == args.index else (0, 0, 0)
                for i in range(1, 7)
            ]
            with dbg.pins({args.pin: 0}, []):
                time.sleep(0.001)
                ram_io.leds(dbg, args.pin, pixels)
                time.sleep(0.001)
                print(
                    "LED frame sent; holding outputs for",
                    args.hold,
                    "seconds.",
                    flush=True,
                )
                time.sleep(max(0, args.hold))
            print("LED frame sent; visual confirmation is required.")
        elif args.operation in (
            "i2c-scan",
            "i2c-read",
            "i2c-write",
            "accel",
            "nfc-info",
            "nfc-crc",
        ):
            with dbg.pins({5: 1, 6: 1}, [], open_drain=True):
                dbg.i2c_setup()
                if args.operation == "i2c-scan":
                    print(
                        json.dumps(
                            {"addresses": [f"0x{x:02x}" for x in dbg.i2c_scan()]}
                        )
                    )
                elif args.operation == "accel":
                    print(json.dumps(dbg.accelerometer()))
                elif args.operation == "nfc-info":
                    print(json.dumps(dbg.nfc_info()))
                elif args.operation == "nfc-crc":
                    print(json.dumps(dbg.nfc_crc(bytes.fromhex(args.hex_bytes))))
                elif args.operation == "i2c-write":
                    dbg.i2c_write(args.address, args.register, args.values)
                    print("I2C register write acknowledged.")
                else:
                    print(
                        json.dumps(
                            {
                                "data": [
                                    f"0x{x:02x}"
                                    for x in dbg.i2c_read(
                                        args.address, args.register, args.count
                                    )
                                ]
                            }
                        )
                    )
        elif args.operation in ("buttons", "watch-buttons"):
            with dbg.pins({PL: 1, CP: 0}, [Q7, START]):
                if args.operation == "buttons":
                    print(json.dumps(dbg.buttons()))
                else:
                    began = time.monotonic()
                    previous = None
                    while time.monotonic() - began < args.seconds:
                        result = dbg.buttons()
                        if result != previous:
                            before = int(previous["held_mask"], 16) if previous else 0
                            after = int(result["held_mask"], 16)
                            print(
                                json.dumps(
                                    {
                                        "seconds": round(time.monotonic() - began, 3),
                                        **result,
                                        "pressed": [
                                            name
                                            for bit, name in BUTTONS.items()
                                            if (after & ~before) & (1 << bit)
                                        ],
                                        "released": [
                                            name
                                            for bit, name in BUTTONS.items()
                                            if (before & ~after) & (1 << bit)
                                        ],
                                    }
                                ),
                                flush=True,
                            )
                            previous = result
                        time.sleep(0.025)
    finally:
        dbg.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (OSError, RuntimeError, ValueError) as error:
        print(
            json.dumps({"error": str(error), "kind": type(error).__name__}),
            file=sys.stderr,
        )
        raise SystemExit(1)
