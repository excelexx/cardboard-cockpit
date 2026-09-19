# Firmware preservation and reverse engineering

## Captured state

The starting image is 4,194,304 bytes with SHA-256:

```text
40c7491de4f3dbb34f7befce59eaca4db914848c5968c8395b486f83fb21c103
```

Secure boot and flash encryption were reported disabled, and live JTAG access worked. These are observations of this unit, not assumptions about every badge. No protection was bypassed or permanently changed.

The installed app at `0x10000` is an Arduino pin finder, built with Arduino core 3.3.11 / ESP-IDF v5.5.5. Its image checksum and appended validation hash were valid. Application metadata reported project `arduino-lib-builder`, version `ee57070`, compile timestamp `Jul 20 2026 10:50:59`. That metadata identifies the linked build, not the event's original firmware version.

Current replacement partition table:

| Label | Type/subtype | Offset | Size |
|---|---|---:|---:|
| nvs | data/nvs | `0x9000` | `0x5000` |
| otadata | data/ota | `0xe000` | `0x2000` |
| app0 | app/ota_0 | `0x10000` | `0x140000` |
| app1 | app/ota_1 | `0x150000` | `0x140000` |
| spiffs | data/spiffs | `0x290000` | `0x160000` |
| coredump | data/coredump | `0x3f0000` | `0x10000` |

Do not treat that table as the factory layout. The original badge application was larger and older sections survive across these nominal partitions. `app1` is **not** a bootable alternate image: its first byte is not an ESP image header. The surviving LittleFS volume was independently mounted offline at `0x2b0000`, size `0x140000`, ending at `0x3f0000`. It is LittleFS disk version 2.1 with 320 × 4096-byte blocks, containing 12 files totaling 9,395 bytes (one JSON, one TXT, ten CFG files). No installed Lua source files were present. Its input buffer remained unchanged. The original partition-table labels and complete stock application image remain unavailable.

## Why the old code could still be decoded

An app flash erased/replaced the new sketch's range without erasing all later old data. Two retained segment headers were identified:

| Header in flash | Load address | Data start | Length |
|---:|---:|---:|---:|
| `0x150018` | `0x42000020` | `0x150020` | `0x12c700` |
| `0x27dabc` | `0x40380000` | `0x27dac4` | `0x19bac` |

The old IROM bytes disassemble as RISC-V RV32 with compressed instructions. Old DROM references are consistent with `virtual_address = flash_offset + 0x3c120000`. Surviving assertion/function-name strings locate the ST7789, I²C, GPIO, LED strip, and RC522 implementations. Calls to those implementations locate the board initialization functions, whose literal arguments reveal the pin map.

Useful recovered addresses:

| Address | Interpretation |
|---:|---|
| `0x4200af2a` | Shift-register read: load=20, clock=21, data=7 |
| `0x4200afa8` | Reverse/invert bits, add GPIO9 as logical START bit 8 |
| `0x4200b254` | Button initialization |
| `0x4200df1a` | LCD/SPI initialization |
| `0x4200e408` | I²C bus initialization: SDA5/SCL6 |
| `0x4200f424` | LED strip initialization; its original config constant was overwritten |
| `0x4200fb9a` | NFC initialization; I²C address 0x26 |
| `0x42012438` | Custom NFC I²C read adapter |
| `0x42012480` | Custom NFC I²C write adapter |
| `0x420a48d2` | `esp_lcd_new_panel_st7789` |
| `0x420a5796` | `esp_lcd_new_panel_io_spi` |
| `0x420fbb86` | GPIO output level implementation |

The original LED configuration constant is no longer trustworthy because its flash location falls inside the replacement sketch. That is why the LED pin was physically tested instead of inferred from the overwritten bytes. Retained instructions do not constitute a complete recoverable stock image or original source tree.

## Reproduce without modifying flash

Stop OpenOCD and all serial clients first. Substitute the actual device port:

```sh
python -m esptool --port /dev/cu.usbmodem2101 --no-stub get_security_info
python -m esptool --port /dev/cu.usbmodem2101 flash_id
mkdir -p .private
python -m esptool --port /dev/cu.usbmodem2101 --baud 460800 read_flash 0 ALL .private/flash.bin
python investigation/analyze_flash.py .private/flash.bin --output .private/analysis --extract-images
python -m esptool --chip esp32c3 image_info --version 2 .private/analysis/app-app0-010000.bin
python investigation/disassemble_flash.py .private/flash.bin --output .private/disassembly
```

The disassembler deliberately accepts only the investigated hash. For a different image, parse its ESP headers and establish its segment mapping before changing the constants. Compiling bytes at the wrong virtual address produces misleading branches and cross-references.

After experiments, compare the whole device to its own backup:

```sh
python -m esptool --port /dev/cu.usbmodem2101 --baud 460800 verify_flash 0 .private/flash.bin
```

This exact whole-flash comparison passed after the recorded hardware investigation. Esptool uses a temporary RAM stub and resets the CPU; reading/verification does not flash a replacement app.

## Read the retained filesystem offline

```sh
python investigation/filesystem.py .private/flash.bin --summary .private/filesystem-summary.json
```

Default output includes only geometry, counts, extensions, and a volume hash. It never formats, writes the source image, or opens USB. A read-only block context rejects programming/erase callbacks, and the buffer is compared after unmount.

To inspect private paths or recover files locally, explicitly add `--private-inventory .private/files.json` and/or `--extract-to .private/recovered-files`. The extraction directory must be empty; paths are checked for traversal and files are created with private permissions. Those files include personal provisioning content and must not be committed wholesale. This does not reconstruct missing application code.

## Restoration is a deliberate future action

If a future task intentionally replaces firmware, retain its complete pre-change backup. A full restoration command is:

```sh
python -m esptool --port /dev/cu.usbmodem2101 write_flash 0 .private/flash.bin
python -m esptool --port /dev/cu.usbmodem2101 verify_flash 0 .private/flash.bin
```

Those commands **write flash** and are not part of normal inspection. Confirm that the backup belongs to this device and is complete. The investigation's backup restores the existing pin finder plus retained data; it cannot reconstruct stock bytes overwritten before the investigation began.

No eFuse burning, secure-boot change, encryption provisioning, mass erase, or factory reset is needed for these tools.
