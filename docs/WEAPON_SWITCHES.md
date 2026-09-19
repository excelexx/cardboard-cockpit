# Cardboard yoke switches and wireless badge

The cardboard controls own steering, throttle and firing. The badge is a secondary panel. Keep both hands on the yoke during normal engagements.

Build two **latched flip tabs**, each with one marker on each face, using the printable [switch sheet](../vision/markers/weapon-switches.html). Print at actual size, turn off browser headers/footers, and check the 50 mm calibration line with a ruler. Glue ON and OFF back-to-back; a tape hinge with two stops should leave exactly one face visible to the webcam. A finger/thumb flip changes state; no holding or repeated tapping is required. Mount both beside the yoke grips without hiding ID 7 or the throttle's ID 23. Keep every marker at least 24 image pixels across (larger is better).

| Switch | ON marker | OFF marker | Behavior |
|---|---|---|---|
| Primary | 31 | 32 | Continuous minigun and energy cannon together |
| Quad salvo | 41 | 42 | Four missiles per salvo, repeated while ON |

Use the existing `DICT_4X4_50` tracker. A face must remain stable for 90 ms to switch. Brief occlusion retains its latched state; after 0.8 seconds unseen the switch turns off. Transport loss stops physical weapon commands within 350 ms. Contradictory ON/OFF faces or duplicate IDs are rejected. Move a switch OFF and ON again after loss. The two physical switches work independently and together. Keyboard Space and T provide equivalent toggles for development or fallback.

## Badge buttons

| Button | Secondary function |
|---|---|
| START | Start, replay, resume |
| HOME | Pause / resume |
| A | Gear |
| B | Deploy gear/flaps and start assisted SFO landing |
| LEFT | Cockpit / chase view |
| RIGHT | Missile camera inset |
| UP | Route assistance |
| DOWN | Text HUD on / off |

The release app starts its bundled BLE relay automatically. Turn on the existing **HTN Badge Buttons** firmware and wait for **BADGE CONNECTED** on the flight deck. There is no OS-wide keyboard injection. Badge loss releases its buttons; reconnect requires neutral buttons before another action. The relay retries automatically and exits with the app. One relay owns Bluetooth; another copy exits if the local phase port is occupied.

For source development: `./tools/build_badge_helper.sh`, then `build/helpers/BadgeBridge/BadgeBridge`. Do not start this separately while the release app already owns the badge. The native helper is built for the build host's architecture (this release: Apple Silicon); Intel users can rebuild the helper locally. Game binaries themselves are universal.

Existing service `5f1d0000-9c2b-4e7a-a3d6-0b8e1c4f2a71`, three-byte button characteristic `0001`, phase characteristic `0002`: idle 0, takeoff 1, sky 2, landing 3. Host loopback ports are 8770/8771. The installed device supports phase readback; the archived button-only source sketch predates that installed extension. **No firmware was flashed**, and LED brightness/pins/provisioning were left untouched.

Evidence: all eight physical buttons, A+B together, and releases were observed over live BLE. Idle, takeoff and sky phase writes were read back from the device. Automated tests cover masks, stale packets, sequence replay, reconnect neutrality, synthetic marker detection, debounce and independent loss. Actual printed switch faces and camera placement still need an on-prop test; no synthetic test proves physical ergonomics or LED appearance.

If initial connection is delayed, leave the badge powered on while the relay retries. The bundled helper writes a fresh local diagnostic log to `~/Library/Logs/Cardboard Cockpit/badge.log` each launch. This log stays on the laptop and is not part of the Git repository or release archive.
