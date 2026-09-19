# Optional standalone USB firmware

`firmware/` is an independent badge-control program. It contains no game connection or simulator imports. It was **compiled successfully but not installed or tested on hardware** in this investigation. The physical demonstrations used the separate JTAG tools.

## Build

```sh
python -m pip install -r requirements-build.txt
python build_firmware.py
```

Pinned components:

- PlatformIO 6.1.19, Espressif32 platform 6.12.0.
- Arduino ESP32 2.0.17 / ESP-IDF 4.4.7, matching GCC 8.4 toolchain.
- ArduinoJson 6.21.5.
- Adafruit NeoPixel 1.12.3.
- Adafruit ST7735/ST7789 1.10.4, GFX 1.11.11, and BusIO 1.17.4.

On Apple Silicon the platform initially selected an Intel compiler and failed with `Bad CPU type in executable`. `build_firmware.py` replaces only its workspace-local compiler with Espressif's **matching ARM64 GCC release**, verifying the digest from ESP-IDF v4.4.7's tools manifest. It does not install Rosetta or change global compiler settings. Other hosts use the platform-selected toolchain. Downloads/build products stay in ignored directories.

The final build uses about 61 KB static RAM and 1.43 MB program space. Exact sizes and artifact SHA-256 values are in `../evidence/firmware-build.json`. Hashes describe that build; timestamps, compiler paths, or a different host may prevent byte-identical rebuilds despite the same versions.

## Flash-layout consequences

The original inspected replacement app slot was only `0x140000` bytes. This program is larger. Its supplied CSV therefore uses a factory app at `0x10000`, size `0x280000`, with NVS at `0x9000`, the recovered LittleFS extent at `0x2b0000` (size `0x140000`), and coredump space at `0x3f0000`. The build labels that filesystem partition `littlefs`; this is our chosen label, not a recovered factory-table label. A 128 KiB gap after the app region is left unallocated. **Do not write only this app into the old smaller slot.** A future installation needs a compatible bootloader/partition table and a complete pre-change backup.

The code never mounts or formats the existing filesystem. That does not guarantee preservation of all stock behavior: changing partitions changes how data is interpreted, and Arduino core startup can erase/reinitialize NVS if `nvs_flash_init()` reports no free pages or a newer unsupported version. The currently installed sketch uses a newer ESP-IDF than this optional build. Full backup and a deliberate installation decision are required in a future task. No upload command is included in the build script.

## Wire protocol

Native USB CDC, newline-delimited UTF-8 JSON. UART0 must remain unused because its GPIO20/21 signals are the button load/clock. Input lines are limited to 2047 bytes plus newline; overlong lines are discarded. Commands have a string `cmd` and may contain an `id`, which is echoed in a result:

```json
{"id":"request-1","cmd":"info"}
```

```json
{"type":"result","id":"request-1","ok":true,"firmware":"badge-control-bridge-1"}
```

That example is schematic; `info` also returns board, SDK, frequency, memory, display, and sensor fields. Failed/unsupported/busy commands return `ok:false`. Continuous state and radio scan observations are separate event objects. A command result is not physical confirmation of display output or RF function.

Use the host client only after intentionally installing the optional firmware:

```sh
python serial_tool.py --port /dev/cu.usbmodem2101
python serial_tool.py --port /dev/cu.usbmodem2101 --command '{"cmd":"stream","hz":25}' --listen 10
python serial_tool.py --port /dev/cu.usbmodem2101 --command '{"cmd":"fill","color":31}'
```

The client checks the exact firmware identity before forwarding a requested command. It will not work against the current pin-finder app or the stock Lua console. Opening serial can reset the board; ROM text is ignored until a matching JSON result arrives.

## Command reference

| Command | Fields | Behavior |
|---|---|---|
| `info` | none | Board/firmware/SDK, CPU MHz, flash/heap, sensor readiness, display size, LED count |
| `buttons`, `state` | none | Immediate raw shift byte, physical mask, motion sample/status |
| `stream` | `hz`: 0..100 | Set state-event target rate; 0 disables streaming |
| `led` | `pixels`: exactly six `[r,g,b]` arrays, channels 0..255 | Set all six pixels; direct brightness |
| `fill` | `color`: 0..65535 | Whole display, RGB565 |
| `rect` | integer `x,y,w,h,color` | In-bounds filled rectangle |
| `text` | integer `x,y,color,size`; `text` ≤80 bytes; size 1..4 | Built-in font text; not arbitrary Unicode typography |
| `accel` | none | Refresh/read motion; sensor axes in mg |
| `i2c.read` | `address`:8..119, `register`:0..255, `count`:1..64 | Register-pointer read |
| `i2c.write` | address/register plus `data`:1..64 bytes | Explicit peripheral-register write |
| `nfc.info` | none | Reader address and version; explicitly reports tag reading unverified |
| `wifi.scan` | none | Start asynchronous Wi-Fi scan; later `wifi.scan` event contains up to 20 networks |
| `ble.scan` | `seconds`:1..10 | Start passive BLE scan; observations followed by completion |
| `radio.stop` | none | Stop scans and turn Wi-Fi off |

The raw I²C interface can change device configuration beyond the high-level commands. Register validity and side effects are the caller's responsibility. No tag authentication, raw flash programming, eFuse write, or arbitrary memory-write command exists in this firmware's JSON API.

## State event

```json
{"type":"state","version":1,"sequence":12,"uptime_ms":1000,"shift_raw":254,"held_mask":0,"motion_ok":true,"accel_mg":[-122,148,-964]}
```

The normal target rate is 50 Hz. This has not been measured on the device. `uptime_ms` is device uptime, not Unix time. Host software should apply its own monotonic stale-data timeout and reset sequence expectations on reboot. Code 7 is filtered from `held_mask`. Button readings are raw samples rather than a guaranteed one-event-per-click debounce stream.

Motion is configured once and sampled in the loop. Display drawing can occupy the same loop briefly; scan events and USB buffering can also affect timing. No real-time latency guarantee is made by a successful build.

## Radio event behavior

Wi-Fi/BLE scans are explicit commands; neither runs on boot. Wi-Fi persistent credential storage and auto-reconnect are disabled before the scan, and no join command is supplied. BLE scanning is passive and bounded; its callback copies small observations into a queue, and the main loop serializes them. The firmware does not attempt simultaneous Wi-Fi/BLE scans.

These paths are compile-tested only. RF range, successful discovery, Bluetooth address presentation, interruption behavior, memory pressure over many scans, and coexistence need physical acceptance tests before production use.

## Required hardware acceptance before adopting it

After an intentional backed-up installation, verify: USB identity/handshake, all eight buttons and combinations, release events at the host, LCD orientation/color order, all six pixel positions/colors, motion axis calibration/data-ready behavior, NFC register state and a known test tag, explicit Wi-Fi/BLE scans, disconnect/reconnect, long runs, malformed commands, and power-loss recovery. Record those results rather than reusing the JTAG verification label for this separate firmware.
