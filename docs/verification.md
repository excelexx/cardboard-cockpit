# Verification — September 18, 2026

Tested on Apple M4, 16 GiB RAM, macOS 27.0, Godot 4.7.2. This records actual checks rather than declaring untested hardware complete.

## Passed

- All five downloaded aircraft imported and rendered from front-quarter, side and top views. Correct Y-up / negative-Z-forward orientation, scale, materials and visible gear grouping were checked.
- 240 flight-model checks pass across all five profiles: takeoff threshold, gradual acceleration, turn direction, reset, braking, finite state under frame hitches, touchdown requirements and rejection of unsafe landings.
- Each aircraft completed a full deterministic mission with the training controller: five rings and destination runway touchdown. Initial A380 mission tuning exposed a missed-turn problem; the corrected steering, speed and ring clearance passed the complete route for all five aircraft.
- The Boeing 737 also completed the mission through physical keyboard-event inputs with the copilot disabled throughout. 35 input/UI checks include selection, briefing, pause/resume, reset, camera, steering, power, gear and brakes. Touchdown was within the runway and nearly centered.
- 23 Python vision tests pass, including synthetic ArUco detection and pose estimation, calibration ranges, independent tracking loss and real local WebSocket clients.
- The native Godot client received simulated control packets, handled disconnects and stale data, held safe throttle, reconnected, and returned to keyboard input. 62 malformed-packet cases were rejected without changing controls.
- Both runway decks sample at exactly zero altitude; five route targets clear the terrain. Collision sampling follows the rendered terrain triangles.
- Rendered the real hangar and flight scenes and inspected screenshots. Forward+ uses Metal on this Mac. An isolated world sample measured 60 FPS over 120 frames at 1280×800; a full flight screenshot also showed 60 FPS. These are local spot checks, not a sustained cross-device benchmark.
- Exported the universal native Mac application using the official release template and local ad-hoc signing. The packaged executable was tested independently of the editor.
- The staged bundle passes strict macOS code-signature verification. Packaging signs in the OS temporary directory and creates a metadata-free ZIP containing the app and source. The synced Documents folder was observed reattaching Finder metadata during signature checks, so verification happens before the archive is copied there.
- Both one-page A4 PDFs were rendered and visually inspected. Marker black squares measure 70 mm / 50 mm, and OpenCV detects the correct IDs 7 / 23 from the rendered marker PDF.

## Not claimed or still outstanding

- Real webcam capture, physical printed-marker calibration, cardboard ergonomics, lighting robustness and sustained webcam frame rate have not been tested. No webcam was opened during development.
- Native OS-driven mouse/keyboard inspection through Computer Use was unavailable because Accessibility/Screen Recording permissions were pending. In-engine rendering, keyboard-event integration tests and the packaged executable were used for verification.
- Intel Mac, Windows and Linux runtime behavior has not been tested.
- The app is not Apple-notarized for general public distribution.
- Flight behavior and the shared cockpit HUD are arcade approximations, not aircraft-system or aerodynamic validation.

A repeat Python test run performed during concurrent GPU imports hit its five-second subprocess-startup timeout. Re-running after those jobs finished passed all 23 tests in 0.85 seconds. No physical-camera result is inferred from that synthetic cadence test.
