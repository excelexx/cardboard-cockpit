"""Bounded RV32I helpers for fast SPI and addressable LEDs over JTAG.

Temporarily saves/replaces a small existing IRAM region while the CPU is
halted. Restores IRAM and registers before the caller resumes firmware.
No flash writes. Use only with this investigated ESP32-C3 firmware.
"""

import struct
import hashlib

SCRATCH_SHA256 = "041ae4f5dbd98e534d9781d1395909c3b77885bc3e3ec3bd24ddf59948a8e2fc"


class Assembler:
    def __init__(self):
        self.words, self.labels, self.fixups = [], {}, []

    def emit(self, word):
        self.words.append(word & 0xFFFFFFFF)

    def label(self, name):
        self.labels[name] = len(self.words) * 4

    def addi(self, rd, rs, imm):
        assert -2048 <= imm < 2048
        self.emit(((imm & 0xFFF) << 20) | (rs << 15) | (rd << 7) | 0x13)

    def li(self, rd, value):
        if -2048 <= value < 2048:
            self.addi(rd, 0, value)
        else:
            value &= 0xFFFFFFFF
            hi = (value + 0x800) >> 12
            self.emit((hi << 12) | (rd << 7) | 0x37)
            lo = value & 0xFFF
            self.addi(rd, rd, lo - 4096 if lo >= 2048 else lo)

    def slli(self, rd, rs, bits):
        self.emit((bits << 20) | (rs << 15) | (1 << 12) | (rd << 7) | 0x13)

    def sw(self, rs, base, offset):
        self.emit(
            ((offset >> 5) << 25)
            | (rs << 20)
            | (base << 15)
            | (2 << 12)
            | ((offset & 31) << 7)
            | 0x23
        )

    def lbu(self, rd, base, offset=0):
        self.emit((offset << 20) | (base << 15) | (4 << 12) | (rd << 7) | 0x03)

    def sub(self, rd, a, b):
        self.emit((0x20 << 25) | (b << 20) | (a << 15) | (rd << 7) | 0x33)

    def cycle(self, rd):
        # ESP32-C3 uses Espressif's PCCR_MACHINE, not standard mcycle.
        self.emit((0x7E2 << 20) | (2 << 12) | (rd << 7) | 0x73)

    def branch(self, kind, a, b, label):
        self.fixups.append((len(self.words), kind, a, b, label))
        self.emit(0)

    def finish(self):
        for index, kind, a, b, label in self.fixups:
            delta = self.labels[label] - index * 4
            assert -4096 <= delta < 4096 and delta % 2 == 0
            v = delta & 0x1FFF
            self.words[index] = (
                (((v >> 12) & 1) << 31)
                | (((v >> 5) & 63) << 25)
                | (b << 20)
                | (a << 15)
                | (kind << 12)
                | (((v >> 1) & 15) << 8)
                | (((v >> 11) & 1) << 7)
                | 0x63
            )
        return self.words


def fill_program():
    # a0=RGB565 colour; a1=pixel count. Pins: MOSI=10, SCLK=1.
    a = Assembler()
    a.li(5, 0x60004000)
    a.li(6, 1024)
    a.li(7, 2)
    a.label("pixel")
    a.slli(12, 10, 16)
    a.li(13, 16)
    a.label("bit")
    a.sw(7, 5, 12)
    a.branch(5, 12, 0, "zero")
    a.sw(6, 5, 8)
    a.branch(0, 0, 0, "clock")
    a.label("zero")
    a.sw(6, 5, 12)
    a.label("clock")
    a.sw(7, 5, 8)
    a.sw(7, 5, 12)
    a.slli(12, 12, 1)
    a.addi(13, 13, -1)
    a.branch(1, 13, 0, "bit")
    a.addi(11, 11, -1)
    a.branch(1, 11, 0, "pixel")
    a.emit(0x00100073)
    return a.finish()


def led_program():
    # a0=bytes ptr; a1=byte count; a2=pin bitmask;
    # a3=zero high cycles; a4=one high cycles; a5=bit period cycles.
    a = Assembler()
    a.li(5, 0x60004000)
    a.label("byte")
    a.lbu(6, 10)
    a.slli(6, 6, 24)
    a.li(7, 8)
    a.label("bit")
    a.addi(28, 13, 0)
    a.branch(5, 6, 0, "zero")
    a.addi(28, 14, 0)
    a.label("zero")
    a.cycle(29)
    a.sw(12, 5, 8)
    a.label("high")
    a.cycle(30)
    a.sub(30, 30, 29)
    a.branch(6, 30, 28, "high")
    a.sw(12, 5, 12)
    a.label("low")
    a.cycle(30)
    a.sub(30, 30, 29)
    a.branch(6, 30, 15, "low")
    a.slli(6, 6, 1)
    a.addi(7, 7, -1)
    a.branch(1, 7, 0, "bit")
    a.addi(10, 10, 1)
    a.addi(11, 11, -1)
    a.branch(1, 11, 0, "byte")
    a.emit(0x00100073)
    return a.finish()


def run(dbg, words, args, data=b""):
    base = 0x40381000
    data_base = 0x50001000
    if not words or len(words) > 128 or len(data) > 512:
        raise ValueError("RAM helper exceeds bounded scratch region")
    names = [
        "pc",
        "mstatus",
        "dcsr",
        "mepc",
        "mcause",
        "mtval",
        "t0",
        "t1",
        "t2",
        "t3",
        "t4",
        "t5",
        "t6",
        "a0",
        "a1",
        "a2",
        "a3",
        "a4",
        "a5",
        "a6",
        "a7",
    ]

    def reg(name):
        return int(dbg.command("reg " + name).split(":")[-1].strip(), 16)

    with dbg.halted():
        signature_words = dbg.read(base, 128)
        signature = hashlib.sha256(struct.pack("<128I", *signature_words)).hexdigest()
        if signature != SCRATCH_SHA256:
            raise RuntimeError(
                "IRAM does not match the investigated firmware; refusing temporary code replacement. See docs/runtime.md."
            )
        saved = {name: reg(name) for name in names}
        original = dbg.read(base, len(words))
        padded = data + bytes((-len(data)) % 4)
        data_words = (
            list(struct.unpack("<" + "I" * (len(padded) // 4), padded))
            if padded
            else []
        )
        original_data = dbg.read(data_base, len(data_words)) if data_words else []
        resume_allowed = dbg.resume_allowed
        dbg.resume_allowed = False
        completed = False
        try:
            dbg.command(
                f"write_memory {base:#x} 32 {{" + " ".join(hex(x) for x in words) + "}"
            )
            if dbg.read(base, len(words)) != words:
                raise RuntimeError(
                    "IRAM write was not accepted. Original memory is being restored; run esp_control.py reset after attaching OpenOCD, then retry. No helper was executed."
                )
            if data_words:
                dbg.command(
                    f"write_memory {data_base:#x} 32 {{"
                    + " ".join(hex(x) for x in data_words)
                    + "}"
                )
                if dbg.read(data_base, len(data_words)) != data_words:
                    raise RuntimeError("RAM payload verification failed")
            for name, value in args.items():
                if name not in names:
                    raise ValueError("Unsupported helper argument")
                dbg.command(f"reg {name} {value & 0xffffffff:#x}")
            dbg.command(f'reg mstatus {saved["mstatus"] & ~8:#x}')
            dbg.command(f'reg dcsr {saved["dcsr"] | (1<<15):#x}')
            dbg.command(f"resume {base:#x}")
            dbg.command("wait_halt 4000")
            pc = reg("pc")
            if pc != base + (len(words) - 1) * 4:
                raise RuntimeError(f"Helper stopped unexpectedly at {pc:#x}")
            completed = True
        finally:
            dbg.command("halt")
            dbg.command(
                f"write_memory {base:#x} 32 {{"
                + " ".join(hex(x) for x in original)
                + "}"
            )
            if original_data:
                dbg.command(
                    f"write_memory {data_base:#x} 32 {{"
                    + " ".join(hex(x) for x in original_data)
                    + "}"
                )
            for name, value in saved.items():
                dbg.command(f"reg {name} {value:#x}")
            if dbg.read(base, len(original)) != original:
                raise RuntimeError(
                    "IRAM restoration verification failed; target left halted"
                )
            if (
                original_data
                and dbg.read(data_base, len(original_data)) != original_data
            ):
                raise RuntimeError(
                    "RTC data restoration verification failed; target left halted"
                )
            dbg.resume_address = saved["pc"]
            if completed:
                dbg.resume_allowed = resume_allowed


def fill(dbg, colour, count):
    if not 0 <= colour <= 65535 or not 1 <= count <= 76800:
        raise ValueError("Invalid RGB565 colour or pixel count")
    run(dbg, fill_program(), {"a0": colour, "a1": count})


def leds(dbg, pin, colours):
    if pin != 3 or len(colours) != 6:
        raise ValueError("Expected six LEDs on the verified GPIO3 data pin")
    if ((dbg.read(0x600C0058)[0] >> 10) & 3) != 1:
        raise RuntimeError("LED timing requires PLL CPU clock")
    period = dbg.read(0x600C0008)[0] & 3
    if period not in (0, 1):
        raise RuntimeError("Unrecognized CPU clock divider")
    mhz = 80 if period == 0 else 160
    payload = bytearray()
    for r, g, b in colours:
        if any(not 0 <= x <= 255 for x in (r, g, b)):
            raise ValueError("RGB channels must be 0..255")
        payload.extend((g, r, b))
    run(
        dbg,
        led_program(),
        {
            "a0": 0x50001000,
            "a1": len(payload),
            "a2": 1 << pin,
            "a3": round(mhz * 0.35),
            "a4": round(mhz * 0.7),
            "a5": round(mhz * 1.25),
        },
        payload,
    )
