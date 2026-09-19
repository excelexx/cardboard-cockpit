# Standalone badge research handoff

This directory is intentionally separate from the game. The user asked for reverse-engineered knowledge, code, documentation, and reproducible controls to be committed here, and explicitly deferred game integration. Do not wire this package into simulator startup, gameplay, networking, or input ownership as part of maintaining the research package. A subsequent explicit integration request can change that scope.

1. Read `README.md`, `board-profile.json`, `docs/runtime.md`, and `docs/verification.md` before touching hardware.
2. Distinguish **measured**, **human-confirmed**, **derived from retained firmware**, **documented by the maker**, **build-only**, and **unverified**. Never promote a successful USB transaction or firmware build into a claim of physical function.
3. Use one owner for the device. All JTAG clients use the same localhost OpenOCD server and an exclusive local lock. Do not run esptool, another OpenOCD, the browser IDE, or another hardware process against it concurrently.
4. Preserve flash and provisioning. The complete local backup is not a factory firmware image. Raw flash, full string dumps, identity/contact data, and credentials do not belong in commits. Use `.private/` for them.
5. Use native USB CDC for serial firmware. GPIO20 and GPIO21 are the button shift register's load and clock, so UART0 there conflicts with input scanning.
6. Code 7 is an unused, permanently-low shift input. Filter it with physical mask `0x17f`. START is GPIO9 and also a boot strap.
7. The fast JTAG routines temporarily replace a small IRAM region. Their signature guard deliberately rejects unknown firmware. Re-evaluate memory layout before adapting it; never just remove that guard.
8. `ram_io.py` uses ESP32-C3 CSR `0x7e2` for cycle timing. Standard `mcycle` failed on this chip. RTC memory worked for data but not for executing the experimental helper under the installed runtime.
9. GPIO11–17 are reserved/internal flash-related; GPIO18/19 are the live USB connection. GPIO8 is unassigned in this research and is a strap. No exploratory all-pin scan is needed: the working board map is known.
10. Keep NFC tag/RF operation and optional firmware radio scans marked unverified until actual hardware tests support them. A software CRC test is not an NFC RF test.
11. Run `python -m unittest discover -s tests -v` after decoder/runtime edits. Build optional firmware after C++/PlatformIO changes. Update evidence only with actual results.
12. Keep examples low-brightness. The stock Lua LED API applies its own output curve; raw JTAG/native output does not. Actual current and battery limits have not been measured.

Unresolved work and a prioritized continuation procedure are in `docs/coverage.md`. Do not modify simulator files merely to demonstrate a badge feature.
