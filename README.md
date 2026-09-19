# Goose Protocol — SPECTRE X-26

Version 0.8.2 is a relaxed native Mac arcade flight game: **one SPECTRE fighter, unlimited Gatling fire and guided missiles, and large Waterloo geese to clear from the valley**. The geese do not attack. There are no upgrades, reloads, heat limits or steady-lock requirements.

Open **Launch Cardboard Cockpit.command**. Previously packaged apps must be rebuilt to include this integration. Choose **Play** (or Enter): flight assistance handles takeoff and the route so you can concentrate on shooting. Hold **Space + T**, or both mouse buttons, to fire both weapons together. **Watch demo** runs the entire takeoff → flock-clearing → landing sequence automatically in about 2 minutes 45 seconds.

![SPECTRE in the valley](docs/screenshots/spectre-flight.png)

## Fly

| Input | Action |
| --- | --- |
| Arrow keys | Smooth bank / pitch; release to level |
| A / D | Rudder; steer during rollout |
| W / S | Increase / decrease power |
| Hold Shift | Afterburner |
| Hold Space / left mouse | Unlimited Gatling fire; Space brakes on the ground |
| Hold T / right mouse | Unlimited guided missiles; automatic target selection |
| Z | Optional flare effects |
| Q | Quick barrel roll, when altitude permits |
| V | Cockpit / chase camera |
| X | Toggle missile datalink inset |
| Alt + mouse / middle drag | Look around |
| G / F | Gear / flap detent |
| B / J | Mouse yoke / generous aim assistance |
| H | Route flight assistance on/off |
| Hold E | Eject |
| C / F1 | Cardboard setup / controls |
| Escape / R / M | Pause / restart / mute |
| F9 / F10 | Telemetry / graphics quality |

Aim generally toward the geese and keep firing. Generous aim assistance helps Gatling rounds connect; missiles select and follow targets automatically. Large markers, projectiles, trails and impact effects keep the action readable. Clears within five seconds build a streak and increase points. Personal best scores are saved for player-controlled shooting runs; Watch demo does not set your record.

Keyboard steering or power input takes over from route assistance. The manual controller maps inputs to a controlled bank or pitch angle; releasing settles the aircraft toward level flight. A gentle terrain guard pulls up through the physics model when needed. H rejoins the guided route. Switching applications pauses flight, and help/setup overlays freeze the simulation.

Landing practice starts on final with gear and flaps selected. With neutral pitch input, landing assistance follows the descent and flare; neutral power input uses approach-speed assistance. After touchdown, Space brakes and A/D steers. The complete assisted sortie lands and brakes automatically. Touchdown preserves position and attitude and settles through a physical rollout.

## Presentation and handling

SPECTRE refines a licensed FlightGear airframe with a clean graphite livery, corrected hardpoint/exhaust placement, reflective canopy, animated control surfaces, folding gear and weapon-bay doors. The M-26 missile is an original Blender model with beveled fins, a ceramic seeker, collars, nozzle and service details. Its editable source is in `docs/source/M26.blend`; `tools/build_m26_blender.py` rebuilds the GLB using Blender 4.5.

Cannon rounds inherit aircraft velocity and include gravity, drag and swept collision checks. Missiles separate before motor ignition, accelerate, follow curved guidance paths, retarget cleared flockmates and burn out. Their visual size is deliberately exaggerated for readability. Ammunition is unlimited; external stores replenish as a presentation effect.

The valley uses generated sunset-cloud, conifer, granite and explosion textures alongside the licensed environment sources. Tall varied forests, lake islands, wet shoreline boulders, reflective rippled water, cloud/mist volumes, shadows and ambient occlusion build depth. Wing vapor, wind streaks, trails, heat distortion and correctly positioned afterburner exhaust respond to flight. The sky and lighting follow the title artwork's warm/cool palette; this remains a real-time game environment rather than a reproduction of every detail in that generated still.

High quality is the default. F10 selects Balanced. Internal 3D resolution is budgeted to 1600 pixels wide in High and 1280 in Balanced, with spatial upscaling; the HUD stays at window resolution. This keeps large Retina windows responsive. High uses temporal antialiasing to reduce foliage shimmer.

Audio combines licensed engine, wind, weapon, impact, gear and tire sounds with cockpit ambience and music. Radio cues use filtering, priority/expiry, subtitles and ducking; these are Kenney recordings, not ElevenLabs generations. Escalating confirmation tones and streak feedback reinforce successful clears.

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

This remains a compact, game-tuned flight project. It does not provide certified aerodynamics, global scenery, a clickable avionics simulation or commercial AAA production assets. Terrain and major buildings collide; trees and small scenery are forgiving. Historical licensed aircraft files remain as source provenance and are excluded from the playable export. Large geese, generous aim assistance and unlimited weapons are intentional arcade choices.

## Coastal integration verification

The combined guided sortie completes in 165 seconds, visits all eleven scenic waypoints, spends 31 seconds above the city and finishes with a full-stop landing. Legacy six-aircraft campaign scripts are retired; the single SPECTRE loadout, unlimited weapons and current radio/landing systems remain active.
