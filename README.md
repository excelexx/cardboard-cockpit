# Goose Protocol — SPECTRE X-26

Version 0.6 is a native Mac aerial-combat game with **one fictional fighter, a permanent cannon and guided-missile loadout, and Waterloo Canada geese as enemies**. There are no aircraft choices, weapon upgrades, progression stages or plasma weapons.

Open **Launch Cardboard Cockpit.command** or **build/Cardboard Cockpit.app**, then press **Enter**. A sortie lasts three minutes; survive incoming missiles, intercept geese and manage ammunition, cannon heat and countermeasures. The flight deck also offers guided flight and landing practice.

![SPECTRE in the valley](docs/screenshots/spectre-flight.png)

## Fly

| Input | Action |
| --- | --- |
| Arrow keys | Pitch / roll |
| A / D | Rudder; steer during rollout |
| W / S | Increase / decrease power |
| Hold Shift | Afterburner |
| Space / left mouse | Cannon; Space brakes on the ground |
| T / right mouse | Guided missile; requires a stable lock |
| Z | Countermeasure burst |
| Q | Quick barrel roll, when altitude permits |
| V | Cockpit / chase camera |
| Hold X | Missile datalink inset while your missile is flying |
| Alt + mouse / middle drag | Look around |
| G / F | Gear / flap detent |
| B / J | Mouse yoke / weak aim assistance |
| H | Guided pilot on/off |
| Hold E | Eject |
| C / F1 | Cardboard setup / controls |
| Escape / R / M | Pause / restart / mute |
| F9 / F10 | Telemetry / graphics quality |

A teal bracket identifies the tracked contact. Keep it within the forward acquisition cone until the circle fills and the missile count turns green. The small diamond estimates the cannon lead point. Aim assistance only nudges the shot direction; it can miss. Red edge arrows show incoming missile bearings. Use countermeasures, acceleration and turns to defend.

Keyboard steering or power input immediately takes over from guided flight and cardboard input. Switching applications pauses flight. Help and setup overlays freeze the simulation. Guided use is recorded in the debrief; it receives no shield or special damage rules.

Landing practice begins on approach with gear and flaps selected. Reduce descent near the runway, keep the wings level, then hold Space to brake and A/D to maintain the centerline. Touchdown preserves position and attitude, followed by gradual settling and a physical rollout.

## Presentation and handling

SPECTRE adapts a detailed licensed FlightGear airframe with a graphite livery, widened silhouette, swept fore-chines, reflective canopy, animated control surfaces, folding gear and four weapon-bay doors. Cannon rounds use swept collision checks; missiles launch after the bay-opening interval and have limited turn rates. External stores disappear as they are used.

The flight model combines filtered angular rates, flight-path inertia, thrust spool, drag, stall behavior and afterburner acceleration. The camera adds speed-dependent FOV, local position lag, subtle recoil and near-ground movement. Missile view is a held inset that preserves the main flight view.

The mountain valley uses photographic terrain materials, a river, forests, airport buildings, cloud and mist volumes, nearby tree shadows, ambient occlusion and reflections. High quality is the default; F10 selects Balanced. Wing vapor, fading trails, heat distortion, afterburner exhaust and debris respond to flight and combat.

Audio combines licensed jet, wind, cannon, missile, impact, gear, tire and afterburner sounds with cockpit ambience and music. Fifteen licensed voice cues use radio filtering, queue priorities, cooldowns, subtitles and mix ducking. These are Kenney recordings, not ElevenLabs generations.

## Cardboard controls

Use [vision setup](docs/vision-setup.md) and the [construction guide](docs/cardboard-build-guide.md). Print the [build-guide PDF](docs/Cardboard%20Cockpit%20Build%20Guide.pdf) and [markers PDF](vision/Cardboard%20Cockpit%20Markers.pdf) at **100% / actual size**. The yoke uses ArUco ID 7 (70 mm), throttle ID 23 (50 mm), dictionary `DICT_4X4_50`.

```sh
./tools/setup_vision.sh
./tools/tracker.sh --simulate --loss-demo
# Explicitly open a webcam and calibrate when the props are ready:
./tools/tracker.sh --camera 0 --calibrate
```

Press C in the game and enable tracking. Capture the seven calibration poses in the separate tracker preview. The service stays on `127.0.0.1`; images are not uploaded or recorded. The native game works without Python or a camera. Physical cardboard/webcam operation remains unverified; synthetic tracking and the live local connection are tested.

## Develop and verify

The project pins Godot 4.7.2. Mac exports include Apple Silicon and Intel binaries; runtime verification is on Apple Silicon with Metal.

```sh
./tools/setup.sh
./tools/run.sh
./tools/verify.sh
./tools/package_mac.sh
```

Packaging creates `build/Cardboard Cockpit.app` and `build/Cardboard Cockpit Mac.zip`, including source and asset notices. The build is locally signed and is not Apple-notarized. See [verification](docs/verification.md), [demo runbook](docs/DEMO_RUNBOOK.md), and [asset credits](docs/demo-assets.md).

This remains a compact, game-tuned flight project. It does not provide certified aerodynamics, global scenery, a clickable avionics simulation or commercial AAA production assets. Terrain and major buildings collide; trees and small scenery are forgiving. Historical licensed aircraft files remain as source provenance and are excluded from the playable export.
