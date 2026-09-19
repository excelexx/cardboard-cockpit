# I²C, motion, and NFC

## Shared bus

SDA is GPIO5 and SCL is GPIO6. Both must be open drain, with high meaning **release**, not push-pull high. The tools preserve the existing mux/pad/output settings, enable input sensing, use pull-ups, check for clock stretching, and restore the previous state on exit.

The live address scan acknowledged **0x19 and 0x26**. These are 7-bit I²C addresses. Their bus address bytes are respectively `0x32/0x33` and `0x4c/0x4d` for write/read. The recovered native NFC adapter uses 100 kHz; the shared stock bus configuration requests a 10 MHz controller resolution, which is not the wire's I²C bit rate.

```sh
python esp_control.py i2c-scan
python esp_control.py i2c-read 0x19 0x0f
python esp_control.py i2c-read 0x26 0x37
```

`i2c-read ADDRESS REGISTER COUNT` writes the register pointer, issues repeated START, then reads bytes, ACKing all but the final byte. `i2c-write` sends the register followed by explicit byte values. Register side effects belong to the addressed device; restoring ESP32 GPIO settings does not undo arbitrary peripheral writes.

The scan sends only an address probe and STOP; it does not send arbitrary register payloads. A bus ACK identifies an address, not a chip model. Chip identity conclusions below also use register behavior and retained firmware.

## Accelerometer at 0x19

`WHO_AM_I` at register `0x0f` returned **0x11**, consistent with SC7A20. The measured register layout and approximately 1 g vector confirm an SC7A20-compatible motion device. No magnetometer or gyroscope was identified.

| Register | Meaning / tested use |
|---:|---|
| `0x0f` | Identity, read `0x11` |
| `0x20` | CTRL_REG1; use `0x57` for 100 Hz, axes enabled |
| `0x23` | CTRL_REG4; use `0x88` for BDU, ±2 g, high resolution |
| `0x27` | Status, available for more rigorous data-ready handling |
| `0x28..0x2d` | X/Y/Z little-endian signed samples |
| `0xa8` | `0x28` with auto-increment bit for a six-byte burst |

For the tested ±2 g high-resolution configuration, decode each little-endian signed 16-bit value and arithmetic-shift right by four to obtain approximately milligravity units. One measured sample was `[-122, 148, -964] mg`; a later sample was `[-350, 73, -916] mg`. Values change with orientation. These are **sensor axes**, not calibrated screen/pilot axes.

```sh
python esp_control.py accel
```

This command checks identity, saves CTRL_REG1/CTRL_REG4, configures the measurement, waits 50 ms, reads XYZ, then restores both controls. This conservative procedure measured only about **0.66 complete samples/s** over five calls. It is an inspection tool, not a low-latency motion stream. A continuous implementation should configure once, read data-ready samples in bursts, and restore on session exit. The optional native firmware implements continuous sampling; its actual rate/behavior is not yet hardware-verified.

Calibration should establish axis permutation/signs, neutral orientation, movement range, and dead zone. Estimate gravity with a low-pass filter; accelerometer-only tilt becomes unreliable under strong linear acceleration. No gyro-derived orientation should be claimed. Shake/tap/temperature/FIFO/interrupt features in the sensor family were not characterized on this board.

## NFC reader at 0x26

The retained original firmware contains RC522 functions and a custom I²C adapter explicitly instantiated at `0x26`. The live register layout agrees. `VersionReg` (`0x37`) returned **0x82**. That is not enough to name the exact silicon manufacturer, and it should not be presented as a verified genuine NXP MFRC522 or a specific compatible clone.

Observed baseline:

| Register | Name | Value |
|---:|---|---:|
| `0x01` | Command | `0x30` |
| `0x06` | Error | `0x00` |
| `0x0a` | FIFO level | `0x00` |
| `0x11` | Mode | `0x3f` |
| `0x14` | TX control | `0x80` |
| `0x26` | RF configuration | `0x44` |
| `0x37` | Version | `0x82` |

Verified independent write/read behavior:

- Mode register was written `0x3d` and read back as `0x3d`.
- FIFO was cleared, `0x12` was written to FIFO data register `0x09`, the level became one, and reading the FIFO returned `0x12`.
- The previous mode/command were restored and the test FIFO was emptied.

```sh
python esp_control.py nfc-info
python esp_control.py nfc-crc 12345678
```

The CRC command is **experimental and currently fails on this unit**. The expected calculation is ISO14443 CRC_A, seed `0x6363`, reflected polynomial `0x8408`, no final XOR. The software implementation passes the `123456789 → 0xbf05` reference vector. The hardware test writes the FIFO, starts CalcCRC (`Command=3`), and polls `DivIrq & 4`. It timed out with no CRC-ready indication. A subsequent soft-reset experiment also did not show normal command completion. The chip still acknowledged register accesses. A follow-up bounded wake test found that CommandReg bit 4 (PowerDown) did not clear after requesting wake-up. Under the NXP family semantics, that bit remains set until the chip is ready; this narrows the unresolved issue to wake/clock readiness before CRC/RF operation. The exact compatible silicon is still unknown. The prior power-down/idle state was restored afterward.

This does **not** establish that the reader is broken. Power/oscillator state, compatible-silicon behavior, initialization, and the physical unit still need investigation. No suitable tag was available for a verified RF/UID/NDEF test. No successful NFC tag read, tag write, authentication, or RF field measurement is claimed.

## NFC continuation procedure

1. Record power arrangement and reader registers before changes. Begin with a cold-power cycle when a person is available; a CPU reset alone may not reset external ICs.
2. Verify Mode/FIFO write/read and identify oscillator/power-down transitions. Compare the retained RC522 initialization path with the silicon's actual markings and datasheet.
3. Resolve CalcCRC or document a silicon-specific alternative before claiming the command engine works.
4. Enable the RF field explicitly and test a known ordinary NFC test tag. Record REQA/ATQA, anticollision/UID, and SELECT/SAK separately. Support cascade levels for 7-/10-byte UIDs rather than assuming four bytes.
5. Test NDEF reads independently. Do not equate a UID with authentication or infer write/auth capabilities from a successful read.

NXP's register documentation is a useful family reference, not proof that every feature/reset value applies to the observed `0x82` device. The stock Lua API offers UID/NDEF reads but not arbitrary tag-writing APIs.
