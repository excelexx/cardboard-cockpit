# Verification — September 18, 2026

Tested on Apple M4, 16 GiB RAM, macOS 27.0, Godot 4.7.2. This records actual checks rather than declaring untested hardware complete.

## Version 0.3 camera checks

- **1,081 camera checks passed** across all five aircraft, seven views and three aircraft attitudes. The tests check finite transforms, camera direction, imported aircraft bounds fitting neutral exterior views, look-around behavior, direct keys, cycling, picker routing and preservation of the complete flight state.
- **Four startup-option checks passed** for the new `--view=top` option and existing `--chase` alias.
- **79 keyboard/UI checks passed**, including the complete seven-view cycle and a manual 737 mission through five checkpoints, touchdown and a full stop on North Field. Copilot remained disabled. Tests restore the user's saved settings.

- Rendered and inspected all seven A380 views, top/tail views of the B-2, side views of the 737, the camera picker and the updated controls panel. The top-down camera centers the aircraft above the instruction panel. These are staged camera-framing captures, not additional completed flight missions.

## Version 0.2 checks

- **Weather and scenery: 94/94 checks passed** using `simulator/tests/test_weather.gd`. Coverage includes selecting a preset before world construction, preset fallback, metadata isolation, distinct fog/exposure/sun angles, shadow restoration, and switching without adding scene geometry or changing sampled terrain elevations.
- Independently sampled 32 rendered terrain triangles and compared their heights with collision queries. Both runway decks remain exactly at zero. Contact checks cover major buildings at both airports, a hangar roof, building-edge aircraft radius, and clear runway/taxiway/air positions.
- Rendered and visually inspected golden hour, clear midday and high overcast at 1280×800 on the M4 using Metal. All three spot checks reported 60 FPS after settling. The scenic camera saw both airports; total draw-call readings were 108 for golden/clear and 65 for overcast, including shadow passes. New clouds add no scene geometry; overcast disables hard directional shadows. These are local spot checks, not sustained performance or a 40-draw-call guarantee.
- The updated Boeing 737 completed the full valley route and landing rollout with the training copilot. The integrated cockpit was rendered and spot-checked at 60 FPS. Landing completion now waits for a full stop, clamping the final speed to zero below 0.1 m/s.
- **240/240 flight behavior checks and 126/126 landing/approach checks passed** across all five aircraft. New checks cover flap lift/drag, braking distance, steering, full stop, touchdown score, guidance direction, reset, and rejection of runway exits even at low speed.
- **625/625 aircraft presentation checks passed**, preserving imported geometry while testing gear cycles/reversal/reset, light effects and available control-surface pivots. Extended/half/stowed screenshots were inspected for all five aircraft.
- **73 keyboard/UI checks passed**, including weather and mission selection, approach/free initial state, F/F2, pause/resume during rollout and a complete manual 737 route. Real engine key events drove W/S, arrows, G, F and Space; the copilot stayed off. The aircraft stopped at zero speed on North Field at approximately x −0.06 m, z −14,821 m.
- **11 full flight scenarios passed:** each of the five aircraft completed both the valley route and landing practice with the training controller; the 737 also completed free flight. All stopped on the destination runway. Approach and free modes displayed no checkpoint rings.
- All five cockpit layouts were rendered and inspected. Assertions checked live flight values, gear/flaps, throttle counts and motion, navigation context for every mode/checkpoint, and safe rebuilding. The integrated cockpit, fighter cockpit and briefing were captured from the running native renderer; the 737 approach spot check showed 60 FPS at 1280×800.
- Exported version 0.2.0 as a universal Mac app. The staged bundle passed strict code-signature verification; its packaged executable independently completed a 747 landing-practice scenario through a full stop. The archive includes the application and source, including original aircraft assets and licenses. A separate native B-2/overcast render showed 61 FPS after 15 seconds; its first startup capture briefly showed 3 FPS, so these figures do not promise hitch-free startup.

Version 0.2 adds aircraft-inspired cockpit layouts with live displays, animated controls and throttles, approximate gear/control-surface motion, aircraft lighting, three visual weather presets, generic flap detents, landing practice and free flight, geometric approach guidance, building collision, braking rollout and landing scoring. These additions are training/game approximations, not validation against aircraft manuals or actual weather/avionics behavior.

## Previously passed — version 0.1 baseline

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
- Flight behavior and the aircraft-inspired cockpits are arcade approximations, not aircraft-system or aerodynamic validation. Cockpit controls are not clickable procedures; multiple engine indications share one simulated power state.
- Weather only changes visual sky, cloud cover, light and haze. Wind, turbulence, rain, cloud penetration, live weather and a continuous day/night cycle are not simulated.
- Gear animation uses approximate folding and the commanded gear state for flight checks; it is not a hydraulic or gear-lock model. Generic flap detents, control-surface motion and the geometric approach display are not validated aircraft-specific systems.
- Major airport structures use simple collision bounds. Full aircraft-wing collision, trees, poles and small airport furniture are not modeled as obstacles.

A repeat Python test run performed during concurrent GPU imports hit its five-second subprocess-startup timeout. Re-running after those jobs finished passed all 23 tests in 0.85 seconds. No physical-camera result is inferred from that synthetic cadence test.
