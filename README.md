# Cardboard Cockpit

A native Mac flight game with five real aircraft models, a cinematic mountain valley, and optional cardboard controls.

**Version 0.2 — native keyboard/mouse flight prototype.** Choose a valley mission, landing practice, or free flight. Fly from detailed cockpits with live instruments, animated aircraft controls, selectable sky conditions, and a landing rollout. This is a standalone Godot application; it does not run in a browser or require an internet connection to fly.

![The aircraft hangar](docs/screenshots/hangar.png)

## Play on this Mac

Double-click **Launch Cardboard Cockpit.command** in this folder, or open **build/Cardboard Cockpit.app** directly. The packaged app needs neither Godot nor Python installed. The local build is ad-hoc signed, not Apple-notarized for public distribution.

1. Choose the A380, F-35, B-2, 737, or 747 in the hangar.
2. Click **Prepare flight**. Choose **Valley mission**, **Landing practice**, or **Free flight**, and select **Golden hour**, **Clear midday**, or **High overcast** conditions. Start the flight. Enter also advances these screens.
3. Hold **W** for power. At the indicated rotation speed, gently hold **↑** to lift off.
4. Follow the amber rings. Use **V** to switch between cockpit and chase views.
5. After the fifth ring, reduce power with **S**, lower gear with **G**, and press **F** to select approach flaps. Follow the approach diamonds toward runway 36 at North Field, using the aircraft's indicated speed target. Keep the wings level and descend gently.
6. After touchdown, hold **Space** to brake to a stop and use **A / D** to stay on the runway. Results appear after stopping. Landing score reflects descent rate, speed, bank and distance from the centerline; a runway overrun fails the landing.

**Landing practice** starts airborne on the North Field approach with gear and approach flaps selected. **Free flight** removes the checkpoint requirement and lets you explore the fictional valley and land at either airport. The numbered instructions above describe the valley mission.

**H** engages an optional training copilot that can fly the route and brake after landing. Steering or changing power with the keyboard immediately returns control to you. Results disclose when the copilot was used. **R** restarts the selected flight mode; **Escape** pauses.

## Controls

| Input | Action |
| --- | --- |
| W / S | Increase / decrease throttle |
| ↑ / ↓ | Nose up / nose down |
| ← / → | Bank left / right |
| A / D | Rudder and ground steering |
| Space | Wheel brakes |
| G | Command landing gear; visible wheels/struts animate over two seconds |
| F | Cycle assisted flap settings: up / takeoff 15° / approach 30° |
| V | Cockpit / chase camera |
| Right mouse + drag | Look around; returns forward when released |
| B | Toggle mouse yoke; cursor displacement controls pitch/roll |
| H | Training copilot on/off |
| R | Restart the selected flight mode |
| Escape | Pause, resume, or close the current overlay |
| F1 | Controls and credits |
| F2 | Compact / expanded instrument overlay |
| M | Mute/unmute |
| Q | Balanced/high graphics quality |
| Tab | Spectator information panel |
| C | Optional camera setup panel; calibration itself runs in tracker preview |
| 1–5 | Select aircraft in the hangar |
| Left drag / scroll | Orbit / zoom in the hangar |

## What is included

- Five externally sourced FlightGear aircraft, with original geometry, textures, source files, attribution, licenses, and reproducible conversion tools.
- A native hangar, aircraft selection, three flight modes, briefing, cockpit/chase views, pause/reset/help/credits and synthesized engine audio.
- Original cockpit interiors tailored to the aircraft, including a panoramic fighter display, flight/navigation/engine displays, moving yokes or sticks, and throttle levers. Instruments show airspeed, altitude, attitude, heading, climb, gear, flaps and engine power.
- Animated landing gear and control surfaces, navigation lights, strobes, beacons and an F-35 exhaust effect. Original imported aircraft source geometry remains included.
- Two detailed airports with runway markings, approach lighting, terminals, hangars and control towers; a mountain corridor, river, forests, village, photographic materials and sky.
- Three visual environment presets: warm golden hour, clear midday and hazy high overcast. Selection changes sky, cloud cover, sun direction, exposure and fog; the scenery and flight model stay the same.
- Gradual engine power, airspeed-dependent takeoff, pitch/roll/yaw, banking turns, flap-assisted lift and drag, stalls, low-altitude warnings, geometric approach guidance, forgiving touchdown checks, braking rollout and landing scores.
- Terrain contact and collision with major airport buildings, including hangars, terminals, tower structures and jet bridges.
- Optional Python/OpenCV ArUco tracking, seven-step calibration, local WebSocket connection, smoothing, separate yoke/throttle confidence, safe tracking loss and keyboard takeover.
- Printable markers, a cardboard build guide, a spectator panel and a short demo pitch.

![Live cockpit instruments on approach](docs/screenshots/cockpit.png)

![Choose a flight and sky conditions](docs/screenshots/briefing.png)

## Scope and known limits

This is an arcade flight prototype inspired by the presentation of larger flight simulators. It does not include global streamed scenery, real navigation databases, full airliner procedures, clickable aircraft-specific cockpit systems, weapons, or certified aerodynamics. The original cockpit designs are aircraft-inspired interpretations with simplified instruments, rather than faithful system replicas. Engine displays share a single simulated power state. All aircraft use the same assisted flight model with different handling profiles.

Weather presets are visual only: there is no wind, turbulence, precipitation, real weather feed or advancing day/night cycle. The approach diamonds follow a geometric three-degree path to North Field; they are training aids, not a simulated radio navigation system. Flap angles and their handling effects are generic training settings. Gear folding and control-surface motion are approximate visual animations; touchdown checks use the commanded gear state rather than a full hydraulic or gear-lock simulation.

Collision uses the rendered terrain and simple bounds for major airport buildings. Trees, poles and small furniture remain forgiving, and aircraft-wide wing collision is not modeled. Landing limits are deliberately generous and do not represent real operating speeds or limits for these aircraft. Free flight remains within the same bounded fictional valley.

The optional tracker has passed synthetic detection and live local connection tests. **Real webcam tracking with physical cardboard props has not been validated.** The game starts in keyboard mode and never opens a webcam. The tracker opens a camera only when explicitly launched with `--camera`.

## Develop from source

The engine is pinned to **Godot 4.7.2**, standard edition. The Mac setup script downloads the official prebuilt editor into the ignored `.tools/` folder.

```sh
./tools/setup.sh
./tools/run.sh
```

For the standalone Mac app:

```sh
./tools/package_mac.sh
```

The first export downloads the official export-template archive (about 1.2 GB) and extracts its Mac template. The output is `build/Cardboard Cockpit.app`. Both Apple Silicon and Intel code are included; this build has only been exercised on Apple Silicon with Metal. The code does not require Xcode compilation.

Packaging also creates `build/Cardboard Cockpit Mac.zip`, containing the app and its source, including the original licensed aircraft files. The signature is verified before archiving outside the synced Documents folder; Finder metadata in a synced folder can otherwise interfere with strict signature checks.

Other platforms can open `simulator/project.godot` in Godot 4.7.2 and create an appropriate export preset; they have not been tested. A lower-feature renderer can be tested with `./tools/run.sh --rendering-method gl_compatibility`.

## Optional cardboard controls

Read [vision setup and calibration](docs/vision-setup.md) and the [construction guide](docs/cardboard-build-guide.md). The printed yoke uses **ArUco ID 7**, and the throttle **ID 23**, both in `DICT_4X4_50`.

Print the [one-page construction PDF](docs/Cardboard%20Cockpit%20Build%20Guide.pdf) and [marker/keyboard-panel PDF](vision/Cardboard%20Cockpit%20Markers.pdf) on A4 at **100% / actual size**. The black yoke marker is 70 mm and the throttle marker is 50 mm; both were measured and detected in the rendered PDF.

A ready-to-use local `.venv` was created on this Mac. From a fresh clone, create it and install `vision/requirements.txt` as described in the setup guide.

```sh
# Test the native connection without a webcam:
.venv/bin/python vision/tracker.py --simulate --loss-demo

# When real controls are ready, explicitly choose a camera and calibrate:
.venv/bin/python vision/tracker.py --camera 0 --calibrate
```

In the game press **C**, enable vision, and return to flight. Calibration poses are captured with Space in the separate tracker preview. Press C in that preview to recalibrate. The client uses `ws://127.0.0.1:8765`; images are neither uploaded nor recorded.

## Verification

[Verification notes](docs/verification.md) distinguish automated software checks from physical testing still outstanding.

```sh
# Flight behavior checks for all five profiles:
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --script res://tests/test_flight.gd

# Weather, rendered terrain contact, and airport building collision:
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --script res://tests/test_weather.gd

# Aircraft animations, reset and imported-geometry preservation:
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --script res://tests/test_aircraft_visuals.gd

# Landing, flaps, runway rollout and approach guidance:
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --script res://tests/test_landing.gd

# Full mission driven through keyboard events, copilot disabled:
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --fixed-fps 60 --script res://tests/test_keyboard_mission.gd

# Complete-route checks for any aircraft index, 0–4:
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --fixed-fps 60 -- --plane=0 --autotest

# Tracker and native WebSocket integration:
.venv/bin/python -m unittest discover -s vision/tests -v
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --script ../tools/test_vision_client.gd
```

## Files and credits

```text
simulator/          Native Godot project, UI, flight systems, scenery, models, tests
vision/             Optional tracker, calibration, printed markers and Python tests
shared/             Versioned control message contract
tools/              Setup, run, package, asset download/conversion and integration tests
docs/               Build guide, setup, verification, screenshots and planning history
build/              Local standalone app (not committed)
```

[Third-party assets](THIRD_PARTY_ASSETS.md) records aircraft authors and licensing. [Environment credits](simulator/assets/environment/README.md) records the CC0 Poly Haven materials and sky. Godot's MIT notice is bundled in the client. Original aircraft sources and their licenses remain in this repository, and should accompany redistribution of the converted models.

Repository: [excelexx/cardboard-cockpit](https://github.com/excelexx/cardboard-cockpit) (private).
