# Coverage and continuation map

“Complete coverage” here means every identified subsystem has an inventory, access path, evidence level, and next verification step. It does **not** mean every electrical characteristic or optional radio mode has been proven. Unknowns are part of the handoff.

| Subsystem | Identification / decoding | Implemented access | Evidence / remaining work |
|---|---|---|---|
| USB enumeration | VID/PID, composite interfaces, 12 Mbit/s | `probe.py`, `start_debug.py` | Measured on Mac; Linux/Windows instructions not physically tested |
| ESP32-C3 | Revision/package, crystal, observed CPU clock | CPU/memory/register tools | Live identification and read/write/halt/resume tested |
| Debug security | Secure boot/encryption status, JTAG availability | Read-only esptool inspection | Disabled on this unit; no permanent changes |
| Flash | Full 4 MB backup, current partitions, image validity | Backup/analyze/disassemble/verify recipes | Whole-flash comparison passed; raw backup kept private |
| Filesystem | LittleFS 2.1, base 0x2b0000, 320 × 4096-byte blocks | Offline read-only inspection and opt-in private extraction | Mounted successfully; 12 files / 9,395 bytes; no installed Lua sources |
| Original firmware | Retained code segments and key functions | Reproducible disassembly + excerpts | Incomplete; original headers/constants overwritten before this task |
| Buttons | All eight labels, mask and bit order, unused bit | One-shot and JSONL edge stream; native firmware sampling | All eight physically calibrated; raw stream has no formal debounce |
| LCD | Pins, ST7789 driver, RGB565, command sequence | Full-screen fill, rectangles via Python; native text/rect API | Pattern visible when original firmware paused; no MISO/readback/colorimetry test |
| RGB LEDs | GPIO3, six-pixel chain | Individual/all-pixel raw frames; native API | Green confirmed; red/blue channel ordering and each physical index not separately tested |
| Shared I²C | SDA5/SCL6, open drain, addresses 0x19/0x26 | Scan, register read/write, clock-stretch checks | Bus transactions and specific register round-trips tested |
| Accelerometer | SC7A20-compatible, WHO_AM_I=0x11, XYZ format | Conservative restored sampling; native continuous sampling | Gravity vectors measured; mounting/debounce/motion calibration remains |
| NFC digital side | Address 0x26, RC522-like registers, version 0x82 | Status, raw registers, FIFO and experimental CRC | Mode/FIFO round-trips pass; wake/CRC readiness unresolved |
| NFC RF/tag side | Family architecture, documented stock reader API | Register primitives and continuation instructions | No suitable tag / no successful RF, UID, NDEF or write test |
| Wi-Fi | ESP32-C3 family capability | Optional firmware's explicit asynchronous scan | Compiled only; no actual scan/join/range test |
| Bluetooth LE | ESP32-C3 family capability | Optional firmware's explicit passive scan | Compiled only; no physical scan/GATT/pairing/HID test |
| Power/battery | Maker's AA/USB/switch guidance | Documentation | Rails/current/regulator/battery/backlight measurements missing |
| ADC/PWM/extra pads | Vendor capabilities and occupied-pin constraints | Vendor register/SDK references | No invented spare board pin; no analog/test-pad mapping |
| Stock Lua app layer | Public SDK and console documentation | Standalone diagnostic example | Reference-only; stock app not installed on this unit |
| Replacement USB app | Full source, protocol, pinned build | Standalone serial client | Compiles; never flashed, no game wiring |
| Recovery | Volatile-state restore, reset and full-backup recipe | Code guards, locks, restoration checks | Normal cleanup tested; force-disconnect cannot be guaranteed |

## Highest-value next work

1. **NFC wake/clock:** obtain the exact chip marking and power/oscillator measurements, then resolve the persistent PowerDown indication. A cold-power reset and a known test tag are useful when a person is available. Do not repeatedly change unrelated pins.
2. **Output calibration:** confirm red/blue channel order, every LED chain index/physical position, and LCD orientation/endpoints. A logic analyzer can measure LED and SPI timing.
3. **Motion performance:** configure the accelerometer once and read data-ready samples continuously in a chosen native runtime. Calibrate orientation, range, filtering and zero point. Current JTAG one-shot sampling is deliberately slow.
4. **Optional firmware acceptance:** if a future task chooses to install it, preserve the complete flash first, account for its changed app partition and NVS behavior, then run the acceptance list in `usb-firmware.md`. Its build success is not hardware acceptance.
5. **Radio verification:** test explicit Wi-Fi/BLE scans, repeated start/stop, heap stability and coexistence. No automatic pairing or network association is needed for basic diagnostics.
6. **Board engineering:** acquire the schematic/BOM or perform continuity/voltage/current measurements for power, backlight, NFC, unused GPIO8 and test pads. Software cannot establish every net or electrical rating.

## Scope boundary

The user explicitly deferred integration with Cardboard Cockpit. This package publishes information and independent tools only. There is no simulator input provider, WebSocket service, game startup hook, or gameplay modification in the contribution. Any later integration should use this evidence and have its own protocol, ownership, latency and acceptance tests.
