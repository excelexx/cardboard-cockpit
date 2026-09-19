# Remaining subsystems and boundaries

This page distinguishes the ESP32-C3's documented capabilities from functions demonstrated on the particular badge.

## CPU, clocks, memory, and debug

- One RISC-V core. Esptool reports revision 0.4; OpenOCD identified a 32-bit core and working built-in JTAG.
- 40 MHz crystal reported by esptool. The live clock registers selected PLL and the 160 MHz CPU setting during the RAM timing tests.
- The chip family provides 400 KB SRAM including cache allocation and 8 KB RTC memory. This is not the amount of free application heap. The optional build's static RAM and partition sizes are recorded separately.
- The observed flash is 4 MB. No external PSRAM was discovered or used; do not allocate as if an ESP32-S3 with PSRAM were present.
- Read/write memory, CPU halt/resume, register inspection, hardware breakpoints, and bounded RAM execution were exercised. Full source-level debugging needs the matching ELF; the original application's ELF was not recovered.
- GPIO, I²C, SPI, RMT, timers, DMA, watchdog, ADC, and power-management peripherals are described by Espressif's technical reference. Having a register address does not mean arbitrary writes are safe or that a board exposes that signal.

The detailed register map and memory-restoration contract are in [runtime.md](runtime.md). No permanent debug/security fuse changes are required.

## USB and UART

The observed USB interface is full-speed serial/JTAG. The C connector does not imply USB 3, USB-PD control, a general-purpose USB OTG peripheral, a HID gamepad, or mass storage. ESP32-C3's built-in serial/JTAG controller is fixed-function; use the supported serial interface or another appropriate transport for custom application messages.

There are two distinct serial paths:

1. **Native USB serial/JTAG**, using GPIO18/19 internally, available at the host's modem/COM device.
2. **UART0**, conventionally on GPIO20/21, which are wired here to the button register. Do not use UART0 for the replacement bridge.

The optional firmware sets `ARDUINO_USB_MODE=1` and `ARDUINO_USB_CDC_ON_BOOT=1`. Host baud selection is a CDC setting; the native USB link is not limited to a physical 115200-baud wire, though application buffering still limits throughput.

Opening/closing a host serial port and its DTR/RTS transitions can reset this chip. A reset was observed during the initial passive serial capture. The ROM banner identified `esp32c3-api1-20210207`. Avoid interpreting an empty application console as absent JTAG or absent firmware.

## Wi-Fi

ESP32-C3 provides 2.4 GHz 802.11 b/g/n Wi-Fi. No 5 GHz Wi-Fi capability is claimed. The chip feature report confirms the family capability; no Wi-Fi connection, throughput, antenna range, or coexistence test was performed in this investigation.

The optional firmware implements an **explicit** `wifi.scan` command using Arduino's asynchronous scan API. It does not automatically scan, join a network, request credentials, expose an access point, or start a network server. Scan results are local USB events. This path compiled successfully but has not run on the physical badge.

For lower-level native work, use ESP-IDF `esp_wifi` and the matching version's station/AP examples. Provisioning/authentication, packet modes, power saving, and coexistence are separate features that require their own tests. Raw flash can contain networking-related provisioning data; do not include it in research commits.

## Bluetooth LE

The chip family supports Bluetooth LE; it does not provide the classic Bluetooth profiles of the original ESP32. The stock badge uses a limited nearby-radio application interface, not unrestricted access to every BLE/GATT operation.

The optional firmware's `ble.scan` performs a duration-bounded **passive** advertisement scan, queues observations for the main loop, and reports address/RSSI/name over USB. No pairing, advertising, GATT server/client, HID profile, extended advertising, or connection performance was demonstrated. The scan code is build-verified only.

The optional firmware avoids overlapping its own Wi-Fi and BLE scan commands. That is an application policy, not a measurement of the silicon's full coexistence capability. SDK APIs remain the route for implementing and validating additional radio modes.

## Power, batteries, and screen backlight

The maker documents two AA alkaline batteries and a top power switch, plus USB operation. The official manual says to turn the battery switch off before connecting external USB power. This research did not measure rail voltages, current, efficiency, battery discharge, thermal behavior, USB-PD negotiation, or regulator part numbers.

The USB registry reported a 500 mA allocation. This is a descriptor/host allocation, **not** a measured current draw or a promise that every full-brightness LED/radio/display combination fits the board's supply limits. The stock LED API applies a curve/cap; raw commands bypass it.

No battery-voltage ADC connection or independently controllable LCD backlight pin was recovered. Do not invent one. Sleep/wake and wake sources require board-specific tests, especially with START on a boot strap and other inputs on a shift register. A soft CPU reset may leave external peripherals powered and in their previous state.

## ADC and other possible chip peripherals

The ESP32-C3 has ADC-capable pins, RMT, PWM, timers, and other standard peripherals, but most accessible GPIOs are already allocated to the display, LEDs, I²C, and buttons. Reconfiguring those pins for analog/PWM experiments can disconnect existing functions. There is no established spare analog input in this package.

No evidence was found for an onboard microphone, speaker, SD card, touchscreen, gyroscope, or magnetometer. This is an inventory statement based on the observed board/software, not a continuity-tested proof that every possible unpopulated pad is absent. Test-pad numbering, mechanical dimensions, regulator identity, and exact antenna matching remain schematic/bench work.

## Additional on-chip blocks

These are chip capabilities documented by Espressif, not newly verified badge features:

| Block | Access path / board constraint |
|---|---|
| I²S | Native SDK digital-audio interface; no audio codec/speaker/microphone identified |
| TWAI | Native SDK CAN-compatible controller; no CAN transceiver or connector identified |
| LED PWM | Native SDK PWM peripheral; occupied pins must not be repurposed accidentally |
| RMT | Native pulse generation/reception; optional NeoPixel library uses a supported driver |
| General/system/RTC timers | SDK timing and wake facilities; timing/power changes can affect USB |
| GDMA | SDK peripheral transfers; temporary debugging must not assume arbitrary RAM is unused |
| Die temperature | SDK sensor; not measured and not an ambient-temperature calibration |
| AES/SHA/RSA/HMAC/RNG/signature engines | SDK crypto facilities; no secret key material was exported |
| eFuse/boot security | Read-only inspection used here; permanent provisioning is outside these tools |
| Watchdogs/brownout/sleep domains | SDK/TRM controls; USB may disappear in sleep and require physical reconnection |

The source references describe register/API access. No claimed board capability should be inferred merely because a peripheral appears in the SoC block diagram.

## Software layers available to future work

| Layer | What it provides | Current evidence |
|---|---|---|
| ROM loader / esptool | Identification, backup, image inspection, verification, intentional future programming | Tested |
| Built-in USB JTAG | CPU/GPIO/memory access, temporary control | Tested |
| Retained stock binary | Pin/driver evidence, partial executable code | Decoded; not a bootable complete image |
| Stock Lua SDK | App widgets, LEDs, buttons, motion, restricted radio/NFC/storage | Maker-documented, not running on this unit now |
| Optional standalone USB firmware | Explicit command API and continuous input stream | Compiled, not flashed |
| Native ESP-IDF/Arduino SDK | Further GPIO, radio, power and peripheral programming | Available reference route, not exhaustive validation |

There is no single secret universal “input code” that controls all components. Buttons are captured bits, the LCD is an SPI command/pixel stream, LEDs are timed GRB frames, sensors/NFC use I²C registers, and integrated radios use the CPU's radio stack.
