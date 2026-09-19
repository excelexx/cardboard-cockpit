# Hack the North 2026 badge research

This is a **standalone hardware research and control package** inside the Cardboard Cockpit repository. It does not import simulator code, start a game connection, change game controls, or run automatically with the game.

The connected badge was investigated on 2026-09-19. Its existing application was an Arduino **74HC165 pin finder**, replacing the original badge application. USB/JTAG access, flash backup, button decoding, LCD output, RGB LED output, and accelerometer measurements were demonstrated on that physical unit. NFC register/FIFO access works; NFC CRC/tag operation remains unresolved. An optional replacement USB firmware builds successfully, but **was not flashed or tested on the badge**.

**Non-exhaustive capabilities:** **eight-button decoding; full-screen RGB565 graphics; six RGB LEDs; three-axis motion; I²C and NFC register access; flash analysis; CPU/register/RAM debugging; optional standalone USB firmware.**

## Start here

| Need | Read / run |
|---|---|
| Exact connections and component inventory | [Hardware map](docs/hardware.md), [machine-readable profile](board-profile.json) |
| Button codes, raw bytes, masks, events | [Buttons](docs/buttons.md), `esp_control.py watch-buttons` |
| LCD commands and LED timing | [Display and LEDs](docs/display-leds.md) |
| Motion and NFC registers | [I²C, accelerometer, NFC](docs/sensors-nfc.md) |
| JTAG ownership, temporary RAM code, recovery | [Runtime and debugging](docs/runtime.md) |
| Boot/flash layout, preservation, reverse-engineering recipe | [Firmware forensics](docs/forensics.md) |
| Wi-Fi, BLE, power, USB, ADC, limits | [Remaining subsystems](docs/subsystems.md) |
| Independent replacement firmware and JSON API | [Standalone USB firmware](docs/usb-firmware.md) |
| Stock firmware's Lua surface | [Stock SDK](docs/stock-sdk.md), [diagnostic app](examples/stock_diagnostics.lua) |
| What actually passed and what remains unknown | [Verification](docs/verification.md), [coverage matrix](docs/coverage.md) |
| Instructions for another agent | [Agent handoff](AGENTS.md) |
| Sources and addresses supporting conclusions | [Sources](docs/sources.md), [assembly excerpts](evidence/recovered-functions.asm) |

## Use the tested JTAG tools

From this directory, with Python 3.9 or newer:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python setup_tools.py
.venv/bin/python probe.py
.venv/bin/python start_debug.py --reset
```

Keep OpenOCD running. In another terminal in this directory:

```sh
.venv/bin/python esp_control.py buttons
.venv/bin/python esp_control.py watch-buttons --seconds 30
.venv/bin/python esp_control.py accel
.venv/bin/python esp_control.py i2c-scan
.venv/bin/python esp_control.py nfc-info
.venv/bin/python esp_control.py --hold 30 io-demo
```

The combined demo holds the installed program paused, displays red/green/blue bands, and sends green to the LEDs on GPIO3. The **hold matters**: the installed pin finder can reconfigure peripheral pins and destroy the output after it resumes. Each operation restores GPIO configuration and resumes a previously running CPU on normal completion. Temporary RAM routines also restore their code/data scratch areas and CPU registers. A failed RAM recovery keeps the CPU halted.

Only one control process should own the badge. The Python tools enforce a local lock. Stop a watcher before running another command. `Ctrl+C` follows normal Python cleanup; a force-kill, cable removal, or host crash cannot guarantee restoration. See [recovery](docs/runtime.md#recovery).

The serial console at `/dev/cu.usbmodem2101` and the USB descriptor serial were observed on one Mac; neither is universal. `start_debug.py` selects a unique attached Espressif device or accepts `--serial`. It binds its debug service only to localhost. See the platform notes for Windows and Linux.

## Preservation and repository contents

A complete 4,194,304-byte backup was made before peripheral experiments. Its SHA-256 is:

```text
40c7491de4f3dbb34f7befce59eaca4db914848c5968c8395b486f83fb21c103
```

After the tests, `esptool verify_flash` compared all 4 MB against that backup and reported a matching digest. No flash programming or eFuse burning was performed in the investigation. Volatile CPU/peripheral state was changed, and several resets occurred during probing.

The raw backup contains personal badge provisioning data. It and unrestricted string dumps remain local, under ignored/private storage, rather than being committed. This repository contains reproducible scripts, hashes, redacted evidence, relevant assembly excerpts, code, and documentation. Restoring this backup restores the **pin-finder state at the start of this investigation**, not a complete original Hack the North application.

## Tests and build

```sh
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python -m pip install -r requirements-build.txt
.venv/bin/python build_firmware.py
```

`build_firmware.py` compiles only. It never uploads. Read the partition/NVS consequences in [usb-firmware.md](docs/usb-firmware.md) before choosing to install that separate firmware in a future task.

The hardware package is independent of the simulator. Any future game integration is a separate task.
