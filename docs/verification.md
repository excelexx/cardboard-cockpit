# Goose Protocol 0.3 — demo verification

The latest source combines the upstream cockpit/weather/rollout changes with the earlier fixes, adds the An-225 at a shared meter scale, and centers the new game on a six-stage, three-minute Waterloo-geese showcase.

Passed locally: the showcase completes all six stages in 180.1 simulated seconds; its progression/one-weapon/developer-control/cardboard-takeover tests pass; the underlying interception, homing-projectile, damage, flare, barrel-roll and ejection checks pass. All six aircraft also pass valley, approach and keyboard-mission checks, including the upstream landing, weather and aircraft-animation tests. Python tracker and native WebSocket integration checks are retained.

Native rendered screenshots verified the generated title art, goose encounters, upgrade HUD and finale. The showcase discloses guided piloting, aim assistance, timed progression and a training shield. It is a presentation mode, not an assertion of unassisted campaign completion. Actual cardboard tracking automatically takes over from the guided pilot.

The game's goose and sci-fi ship assets are credited in `demo-assets.md` and in the packaged `DEMO_CREDITS.txt`. The final ship is a fan-made Falcon-style interpretation, not an official Star Wars asset. The physically printed cardboard/webcam setup remains untested and should be rehearsed before judging.

## Previous verification record

# Verification — version 0.2, September 18, 2026

Verified from a fresh clone on Apple M5 Pro, 24 GiB RAM, macOS 26.5 (arm64), Godot 4.7.2, Python 3.12.13. No webcam was opened. Run `./tools/verify.sh` to reproduce the automated software checks.

## Passed in this revision

- **242 flight-model checks** across all five profiles: rotation thresholds, progressive thrust, banked turns, reset, braking, bounded state during frame hitches, touchdown requirements, unsafe-landing rejection, and touchdown-sensitive scoring.
- **12 interaction regressions**: overlays block hidden flight/hangar actions, keyboard steering takes over from mouse yoke (including taps between physics frames), app focus loss pauses flight, new flights clear overlays, rings work in either direction, and touchdown uses the current runway/terrain position.
- **Five complete copilot missions**, one per aircraft: takeoff, all five rings, and a successful landing at North Field.
- **Five complete keyboard-event missions**, one per aircraft, with the copilot disabled. Each run also performs 35 input/UI checks. The test controller injects W/S, arrows and G through Godot's input system; it uses the existing pilot as a target oracle, not as the active controller. These are deterministic software tests, not five human-flown missions.
- **26 Python tests**, including actual OpenCV detection of rendered ArUco markers, projected pose, duplicate IDs, calibration and filtering, independent marker loss, two real loopback WebSocket clients and reconnects. Camera-mode tests feed synthetic frames through detection, filtering and the socket; they verify resolution-change rejection, preview closure and resource cleanup using a fake capture source.
- **Native tracker integration**: changing simulated controls arrive in Godot; stale/disconnected yoke neutralizes, throttle holds, restarted services reconnect, and keyboard takeover clears active vision state. All 62 malformed-packet cases are rejected without mutating controls. The deliberately invalid exponent test emits an expected Godot warning.
- **Standalone exported app**: all five complete copilot missions also pass from the packaged executable. The application runs from its bundled resources without the editor.
- **Native desktop interaction** through OS clicks/keypresses: aircraft selection, briefing, flight start, copilot, pause and controls screens. Both the development executable and the packaged application were inspected. The packaged setup panel displayed live simulated yoke/throttle values over its real WebSocket connection.
- **Visual checks**: Metal Forward+ hangar, cockpit and chase scenes; camera setup readouts; long debrief text wrapping; a smaller window; and OpenGL Compatibility rendering. Metal remains the default. Observed FPS readings are spot checks, not a sustained cross-device benchmark.
- **Packaging**: universal Apple Silicon/Intel executable exported, locally ad-hoc signed, and verified with `codesign --verify --deep --strict`. The ZIP includes the app plus source and original licensed aircraft assets. The local app bundle also passed strict signature verification after copying out of staging.
- Shell syntax, Python compilation and `git diff --check` pass. The complete software suite also passed in GitHub Actions on a clean macOS runner; the workflow runs on pushes and pull requests.

## Fixes exercised

Help/camera overlays no longer allow hidden gear, copilot, restart or hangar shortcuts. Switching between overlays clears obscured panels. Switching apps pauses flight. Keyboard steering disables the mouse yoke. Restart clears overlays. Checkpoints can be recovered from either direction. Collision resolves against the surface reached during the current step. Landing smoothness now includes touchdown speed, sink and bank. Closing the tracker preview stops the service and releases capture. Setup and verification have dedicated scripts.

## Limits

- Physical printed-marker calibration, real webcam capture, lighting tolerance, cardboard ergonomics and sustained camera frame rate remain untested; the user chose software-only verification because physical props were unavailable.
- The Mac package includes Intel code, but Intel desktop, Windows and Linux runtime behavior have not been exercised in this session.
- The app is locally signed, not Apple-notarized for public distribution.
- This remains an arcade simulator with shared cockpit instruments. Global scenery, real airliner systems, weather, and aircraft-specific cockpit interaction are outside the documented project scope. Buildings are visual scenery; terrain and runways determine collision.

The original version's verification also recorded printable-PDF measurements, asset attribution and model orientation checks. Those artifacts were not changed in this revision; no new physical-print or hardware result is inferred from them.
