# SPECTRE live badge instrument

The existing 320×240 ST7789 now renders a flight instrument locally. Bluetooth carries compact game state, not RGB video. The default identity is **PILOT / SPECTRE-01**. Use **Next Pilot** on the flight deck or result screen to increment the callsign; Replay keeps the current pilot.

## Display states

- **Ready:** large projected and shaded fighter model, contextual connection status, SPECTRE identity and START hint.
- **Launch:** synchronized three-second 03/02/01 departure sequence, perspective runway illustration, blue bloom, progressive LEDs and laptop cues. Flight physics waits during this native demo introduction.
- **Flight:** interpolated bank/pitch artificial horizon, airspeed in knots, altitude in feet, true SF heading and a heading-up 3 km radar. Geese are green, the boss amber, friendly missiles white and hostile missiles red. The selected contact uses acquiring corner marks. Proportional type, a moving compass, actual velocity flight-path marker, G-load, engine/afterburner state and weapon readiness support the full-screen HUD. Contacts outside the scale stay at the edge.
- **Action:** brief TARGET LOCKED cue, actual hostile-missile warning, weapon status, B - LAND AT SFO, and landing-assistance status. A warning is never invented just for decoration.
- **Paused:** frozen flight data with FLIGHT PAUSED.
- **Results:** score, geese cleared and actual landing/mission result. Safe landing without the boss remains MISSION INCOMPLETE.
- **Link loss:** retain the last valid page with LINK LOST - DATA HELD after stale telemetry or disconnect; WAITING FOR COCKPIT appears only before the first valid state. Buttons and BLE reconnect remain available.

Buttons retain their existing eight-bit physical mapping (`0x17f`, code 7 unused). Button sampling runs in a separate 5 ms task so screen transfers do not block debouncing. UART0 stays unused because GPIO20/21 are the shift-register load/clock. LED firmware 2.1 uses brighter concentrated highlights: peak raw channel 64 (formerly 14), a raw-channel total budget of 240 across all six RGB pixels, and rainbow level 48. These are software output limits, not measured current ratings. Blue flight LEDs carry a cyan bank indicator; a brief cyan lock pulse and alternating red real-missile warning take priority. Takeoff/landing uses a red chase, successful results a green sweep, and readiness a restrained blue breath. The button rainbow remains available in idle. No NFC or accelerometer behavior is changed.

## Transport

Existing service `5f1d0000-9c2b-4e7a-a3d6-0b8e1c4f2a71`:

| Characteristic suffix | Role |
|---|---|
| 0001 | Existing three-byte button read/notify |
| 0002 | Existing phase read/write: idle 0, takeoff 1, sky 2, landing 3 |
| 0003 | Instrument fragments, write with or without response |
| 0004 | Read-only firmware/render/protocol health JSON |

Headless tests never send telemetry. When launched by the game, the relay accepts only snapshots carrying that parent process ID, including their phase; unrelated test/game instances and legacy anonymous phase messages cannot override the live page. Standalone relay mode retains legacy compatibility.

Game sends validated snapshots to localhost UDP 8770 at up to 20 Hz. The relay sends the newest snapshot to BLE and continues delivering buttons to UDP 8771. Older badge firmware without 0003 retains button and phase support.

Binary version 1 has a 44-byte little-endian header, zero to twelve 6-byte contacts, and a CRC-16/CCITT (initial `0xffff`). Maximum frame: 118 bytes. Header layout is defined in `host/instrument_protocol.py`: magic `SI`, version, mode, flags, contact count, sequence; roll/pitch in hundredths of a degree; heading, knots, feet, score, kills, pilot number, landing result, 12-byte ASCII pilot name, selected range and reserved byte. Contacts contain right/forward metres, kind and selection flag.

Each GATT write starts with `a7`, frame ID, offset and total size, then payload. The relay fragments to the negotiated write size, including 20-byte payload compatibility. The receiver rejects malformed lengths, CRC, value ranges, out-of-order fragments and expired assemblies. An 118-byte snapshot at 20 Hz is **18.9 kbit/s before fragment/link overhead**. This is a design payload rate, not a measured radio maximum.

Hold DOWN for 0.65 seconds to toggle the expanded tactical view; a short press toggles the laptop text HUD on release. Tilt controls are not enabled. Tactical contacts carry actual relative velocity vectors and altitude offsets; real hostile missiles take priority over ordinary contacts in the 12-track budget. Threat overlays dominate the HUD and point toward the nearest hostile missile. `CLOSE ~` is a straight-line range/closing-speed estimate, not a guaranteed impact time.

Debriefs animate the real score, reveal a landing grade derived from the game’s landing score, and display a sampled real flight trace with intercept markers, gun accuracy, flight duration and peak reported G-load. Samples are retained in RAM for the current sortie; no invented geography or heat values are drawn.

The display targets a steady 15 FPS at 40 MHz SPI, using a 76,800-byte indexed framebuffer plus a 5,120-byte RGB565 transfer stripe. Attitude is interpolated independently from telemetry updates. Changed 32×8 tiles select bounded stripe spans for bulk SPI writes, with no intermediate display clear. A thin navy perimeter leaves the interior free of decorative frames; large primary text uses Adafruit’s proportional FreeSans fonts. Small machine labels retain the compact bitmap face. Actual rate is exposed as `fps10` in 0004; do not infer physical frame rate from the target alone.

## Reproduce the build

Tested dependencies: Arduino ESP32 **3.3.11**, NimBLE-Arduino **2.5.0**, Adafruit GFX **1.12.6**, ST7735/ST7789 **1.11.0**, NeoPixel **1.15.2**, BusIO **1.17.4**. Board: `esp32:esp32:esp32c3:CDCOnBoot=cdc`.

Run `hardware/badge-controller/firmware/build_instrument.sh`. It only builds. The implementation is `firmware/badge_controller/instrument.cpp`; the empty primary `.ino` avoids Arduino-generated prototypes for custom C++ types.

On this Apple Silicon Mac, the bundled Arduino ctags executable was Intel-only. A native build of `arduino/ctags` commit `abc8fca7499f44c725122881cd380a88c37abe0e` was used through the `runtime.tools.ctags.path` build property. Rename its private `__unused__` macro to `CTAGS_UNUSED` in its `.c/.h` files before compiling to avoid collision with modern macOS SDK headers. The downloaded toolchain is local under ignored `.tools`.

## Preservation and flashing

The user explicitly authorized this firmware update. A fresh complete 4 MB backup was retained privately before flashing. Only the application at **0x10000** was programmed; the 648,512-byte initial build fits the existing 0x140000-byte app slot. Bootloader, partition table, NVS, OTA data and retained provisioning were compared after programming and remained byte-for-byte unchanged. See `evidence/instrument-verification.json` for hashes and measured acceptance results. Raw backups and unrestricted hardware logs are intentionally excluded from Git and app packages.

For a later update, stop the game/helper and any serial/JTAG owner, make a fresh private backup, confirm the partition layout and app size, then write and verify only the app partition. Do not erase the device or overwrite its partition/provisioning regions. To roll back, restore the old app region from that device's private backup; preserve the rest of flash.

`host/test_instrument_live.py` is an explicit physical BLE acceptance test with synthetic readiness, moving horizon/radar, warning and scorecard states. It never flashes or touches USB. Do not run it alongside the game relay. The test also disconnects and reconnects BLE, checks that firmware counters did not reset, reads the buttons, and sends a fresh Ready frame. Afterward, run the actual game for the real telemetry test. The LCD has no MISO connection, so a successful transfer/render counter is not a substitute for human visual confirmation.

## Wireless handoff

After the final application flash/readback and Bluetooth acceptance test, USB is no longer needed for gameplay data. Keep the battery switch **off while USB is connected**, as the maker instructs. Unplug USB-C, then turn on the badge's two-AA battery supply. Leave laptop Bluetooth enabled and the game running; its helper scans again and reconnects automatically. Battery runtime and operation at low battery voltage have not been measured. No speaker, microphone, gyroscope, touchscreen or vibration motor has been identified on this board; audio cues can be played by the laptop. Accelerometer measurements are verified, while NFC tag reading remains an experiment.

## Extended telemetry (binary version 2)

Version 1 remains accepted. Version 2 retains the 44-byte base header and uses its former reserved byte for presentation detail: low four bits are lock quality, bit 4 requests tactical view, bits 5–6 identify the launch stage. In results mode that byte is the actual 0–100 landing score instead. A 26-byte `<BBhhhHBBiihhh` extension adds engine percent, afterburner/countermeasure/missile-ready flags, relative flight-path yaw/pitch in centidegrees, climb rate in feet/minute, flight seconds, gun accuracy (255 means unavailable), throttle percent, world X/Z metres G-load in hundredths, and the actual game targeting solution’s relative yaw/pitch in centidegrees. Each contact expands to 12 bytes `<hhBBhhh`: relative right/forward metres, kind, selection, relative right/forward velocity in m/s, and altitude offset in metres. The maximum frame is 216 bytes including CRC, fragmented across negotiated GATT writes. The bridge reads the firmware protocol capability and falls back to version 1 for older badges.

Automated cross-language tests compile the actual C++ receiver and feed it Python-encoded legacy and maximum-size extended frames. They check byte offsets, CRC failures, truncation, unknown versions and semantic bounds without accessing hardware.
