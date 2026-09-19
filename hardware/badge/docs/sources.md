# Sources and provenance

Local measurements and recovered instructions are the primary evidence for this exact unit. Vendor/maker documents explain interfaces and bounds; they are not a substitute for testing the device.

## Maker sources

- [Hack the North 2026 badge site](https://badge.hackthenorth.com/) — ESP32-C3, 320×240 color screen, eight buttons, six RGB LEDs, NFC, and public front/back photos.
- [Official close-up](https://badge.hackthenorth.com/closeup?side=front) — visible 74HC165 package and board layout. Photographs were inspected in the browser; they are not redistributed in this repository.
- [Public instruction manual](https://hackthenorth.notion.site/hacker-badge-instruction-manual) — controls, batteries/switch, USB power guidance, stock feature overview.
- [Badge IDE](https://badge.hackthenorth.com/ide/) and its [guide](https://badge.hackthenorth.com/ide/README.md) — documented Lua API, LED ordering, sandbox boundaries, upload/console model. The guide was read through the visible IDE editor when direct HTTP retrieval was blocked. It is summarized, not vendored wholesale.

## Espressif sources

- [ESP32-C3 datasheet](https://www.espressif.com/sites/default/files/documentation/esp32-c3_datasheet_en.pdf) — chip capabilities, electrical/pin constraints.
- [ESP32-C3 technical reference](https://www.espressif.com/sites/default/files/documentation/esp32-c3_technical_reference_manual_en.pdf) — memory/peripheral/register architecture.
- [Built-in JTAG configuration](https://docs.espressif.com/projects/esp-idf/en/latest/esp32c3/api-guides/jtag-debugging/configure-builtin-jtag.html) — USB D− GPIO18, D+ GPIO19, host setup.
- [USB Serial/JTAG controller](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-guides/usb-serial-jtag-console.html) — native serial/debug controller behavior and limits.
- [Esptool basic commands](https://docs.espressif.com/projects/esptool/en/latest/esp32c3/esptool/basic-commands.html) — chip/flash inspection, read/verify/write behavior. This package pins esptool 4.12.0 and uses that release's underscore command syntax.
- [OpenOCD release](https://github.com/espressif/openocd-esp32/releases/tag/v0.12.0-esp32-20260831) — tested debugger binaries; archive URLs/digests are in `toolchain-lock.json`.

Register definitions consulted at the pinned ESP-IDF v5.4.2 tag:

- [reg_base.h](https://github.com/espressif/esp-idf/blob/v5.4.2/components/soc/esp32c3/register/soc/reg_base.h)
- [gpio_reg.h](https://github.com/espressif/esp-idf/blob/v5.4.2/components/soc/esp32c3/register/soc/gpio_reg.h)
- [io_mux_reg.h](https://github.com/espressif/esp-idf/blob/v5.4.2/components/soc/esp32c3/register/soc/io_mux_reg.h)
- [gpio_sig_map.h](https://github.com/espressif/esp-idf/blob/v5.4.2/components/soc/esp32c3/include/soc/gpio_sig_map.h)
- [system_reg.h](https://github.com/espressif/esp-idf/blob/v5.4.2/components/soc/esp32c3/register/soc/system_reg.h)
- [soc.h](https://github.com/espressif/esp-idf/blob/v5.4.2/components/soc/esp32c3/include/soc/soc.h)
- [rv_utils.h](https://github.com/espressif/esp-idf/blob/v5.4.2/components/riscv/include/riscv/rv_utils.h) — ESP32-C3 performance-counter CSRs 0x7e0/0x7e1/0x7e2 and cycle-read selection.

## Component and build references

- [Silan SC7A20 manufacturer datasheet, distributor-hosted](https://datasheet.lcsc.com/lcsc/2208151830_Hangzhou-Silan-Microelectronics-SC7A20TR_C5126709.pdf) — WHO_AM_I=0x11, motion/configuration registers. Compatibility with this map and live gravity readings was verified; exact package marking was not read on the physical device.
- [NXP MFRC522 datasheet](https://www.nxp.com/docs/en/data-sheet/MFRC522.pdf) — family-level I²C/register/FIFO/CRC/power-down semantics. The observed version 0x82 does not establish exact NXP silicon. In CommandReg, bit 4 is PowerDown and remains high until wake-up finishes.
- [MFRC522 I²C library source](https://github.com/arozcan/MFRC522-I2C-Library) — corroborates register-pointer byte protocol. This repository's Python driver is an independent implementation.
- [Adafruit ST7789 driver](https://github.com/adafruit/Adafruit-ST7735-Library) and [NeoPixel](https://github.com/adafruit/Adafruit_NeoPixel) — pinned optional firmware libraries; their code is downloaded by PlatformIO, not vendored here.
- [Arduino ESP32 2.0.17 startup](https://github.com/espressif/arduino-esp32/blob/2.0.17/cores/esp32/esp32-hal-misc.c) — `nvs_flash_init()` error handling can erase/reinitialize NVS. This is why the optional firmware's build is not presented as a preservation-safe automatic upgrade.
- [ESP-IDF v4.4.7 tool manifest](https://github.com/espressif/esp-idf/blob/v4.4.7/tools/tools.json) — SHA-256 and URL for the matching native Apple Silicon GCC toolchain.

- [littlefs-python](https://github.com/jrast/littlefs-python) and its [0.15.0 API](https://littlefs-python.readthedocs.io/en/v0.15.0/api/index.html) — pinned offline filesystem decoder; the wrapper refuses program/erase operations.

## Evidence files

- `board-profile.json`: normalized facts and uncertainty flags.
- `evidence/button-calibration.jsonl`: raw physical press sequence.
- `evidence/recovered-functions.asm`: selected old-code instructions supporting pin assignments.
- `evidence/observations.json`: human confirmations and NFC round-trip results.
- `evidence/filesystem-summary.json`: mounted volume geometry and aggregate counts; no filenames or contents.
- `evidence/interrupt-recovery.json`: actual watcher interruption and GPIO-state restoration.
- `evidence/software-tests.txt`: standalone automated test results.
- `evidence/benchmarks.json`: measured tool throughput and representative sensor values.
- `evidence/flash-verification.txt`: redacted whole-flash verification output.
- `evidence/initial-flash-manifest.json`, `installed-firmware.json`, `security-info.json`, and `rom-boot.txt`: chip/image inspection results without private provisioning values.
- `evidence/initial-live-gpio-registers.json`: non-atomic live GPIO/mux snapshot; application state, not an independent schematic.
- `evidence/firmware-build.json`: successful optional build, sizes, hashes, and explicit not-flashed status.

None of these files is a substitute for the local full flash backup. Do not synthesize missing original firmware bytes from disassembly excerpts or confuse a reconstructed sketch with original source.
