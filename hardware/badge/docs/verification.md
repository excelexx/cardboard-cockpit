# Verification record

Investigation date: **2026-09-19**. Host: Apple Silicon macOS, Python 3.9. Physical target: the single connected ESP32-C3 badge described in `board-profile.json`.

## Hardware checks that passed

- USB registry and serial enumeration identified Espressif `303a:1001` with serial/JTAG interfaces.
- Esptool identified revision 0.4, 4 MB flash, 40 MHz crystal, and disabled secure boot/flash encryption.
- A full 4 MB backup was captured. The current application image had a valid checksum/validation hash.
- The retained LittleFS volume mounted offline with programming/erase callbacks disabled. It contained 12 files totaling 9,395 bytes, no installed Lua sources, and the input buffer remained identical.
- OpenOCD connected to the RISC-V TAP, read live GPIO/mux/memory, halted/resumed the CPU, and used hardware breakpoints.
- All eight physical button presses/releases were captured in the requested order. The replay test checks the raw evidence against the final decoder.
- LCD pattern output was human-confirmed while the installed scanner was paused.
- Green LED output on GPIO3 was human-confirmed. GPIO8 was eliminated as the intended LED data pin in that test.
- I²C acknowledged 0x19/0x26. Accelerometer identity was 0x11 and gravity vectors were plausible.
- NFC Mode register round-trip and one-byte FIFO write/level/read passed; version remained 0x82.
- A real watcher was interrupted with SIGINT; its owned GPIO configuration was restored exactly, an existing halted state was preserved, and the CPU was explicitly resumed afterward (`evidence/interrupt-recovery.json`).
- Bounded IRAM helpers executed and restored their overwritten regions. Generated code was independently decoded and its branch/store bounds checked.
- `esptool verify_flash` compared all **4,194,304 bytes** against the initial backup and reported **verify OK (digest matched)** after the investigation's peripheral experiments. See the redacted console evidence.

## Measurements

`evidence/benchmarks.json` contains the measured wall-clock values:

| Operation | Sample count | Observed rate |
|---|---:|---:|
| 74HC165 + START JTAG read | 30 | about 31.9 reads/s |
| Accelerometer one-shot including configure/wait/restore | 5 | about 0.66 samples/s |

These are short measurements on one host, not sustained throughput or worst-case latency guarantees. The button watcher adds a 25 ms pacing delay, so its event-loop rate is lower than the raw-read benchmark. The optional native firmware's configured rates were not measured on the badge.

## Software checks

All 27 automated tests passed. The hardware package's automated tests cover captured button decoding, simultaneous keys, unused-bit filtering, input validation, reserved-pin rejection, halt/resume behavior on errors, retained halt on unsafe recovery, process locking, CRC_A software vectors, host toolchain selection, machine-code decoding, bounded branch targets, restricted helper stores, and the chip-specific cycle counter.

Run them with:

```sh
python -m unittest discover -s tests -v
```

The optional Arduino firmware was compiled with the pinned dependency set. The first compiler attempt used the wrong host architecture; the native ARM64 workaround is reproduced by `build_firmware.py`. The successful build and artifact hashes are in `evidence/firmware-build.json`.

Standalone tools were also exercised against the connected device after installation of the package-local OpenOCD archive. The archive's SHA-256 was checked against the pinned lock file. The Python source contains no game imports or game-facing service. The localhost OpenOCD RPC service is strictly for independent hardware debugging.

## Failures and limits retained in the record

- The original pin-finder's exactly-one-low-bit predicate rejects a real key plus the unused low input. Its UART0 pin use also conflicts with the shift register.
- The initial output test was not visible after CPU resumption; a held test was visible.
- RTC execution at 0x50001000 and standard `mcycle` CSR use failed. They were replaced with an existing IRAM region and CSR 0x7e2. Some development probes reset the CPU.
- A fresh OpenOCD attachment after ROM-loader verification once rejected an IRAM write despite a successful command return. Readback prevented execution. An OpenOCD reset restored the same write/read path. This is documented rather than silently ignored.
- NFC CRC-ready was not observed. A power-down/wake transition remained unresolved; no tag/RF operation is verified.
- No additional interactive tests were requested after the user became unavailable. Red/blue LED order, individual LED locations, exact display orientation/color fidelity, NFC tags, power measurements, and physical radio tests remain open.
- The optional firmware and stock Lua example were **not flashed/deployed**. Their presence in this repository is not evidence that they ran on the badge.
- There is no complete original stock firmware image, schematic, original source/ELF, or electrical characterization.

## Preservation and privacy

The complete backup and unrestricted extracted strings contain personal provisioning content and remain local. Repository evidence omits those values. CPU resets and volatile register changes occurred; no flash programming/eFuse burning was performed. The final active application remains the pre-existing pin-finder image.

## Isolation from the game

All contribution files live under `hardware/badge/`. No simulator, vision, shared control schema, game launch script, or game networking code is modified. This is an independent research artifact, as requested.
