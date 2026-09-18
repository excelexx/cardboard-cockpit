# Cardboard Cockpit

A native desktop flight simulator inspired by the childhood cardboard cockpit.

**Status: Phase 0 — project setup and architecture. There is no playable application yet.**

Repository: [excelexx/cardboard-cockpit](https://github.com/excelexx/cardboard-cockpit) (private).

The latest request takes precedence over the original brief: build a native desktop client, pursue a realistic flight-simulator presentation, include an aircraft garage with the Airbus A380, F-35, B-2 Spirit, Boeing 737, and Boeing 747, and start with keyboard and mouse controls. Webcam-driven cardboard controls come later.

## Planned experience

Attract screen → aircraft hangar → flight briefing → runway start → takeoff → five valley checkpoints → landing approach → touchdown → flight results.

- A walk-around/orbit hangar with five recognizable aircraft, selection cards, and distinct flight tuning.
- Detailed mountain scenery, a runway and airport apron, water, clouds, atmospheric haze, and golden-hour lighting.
- First-person cockpit and third-person chase views, readable instruments, engine/wind audio, and immediate keyboard/mouse controls.
- An accessible flight model with momentum, speed-dependent lift, banking, drag, stall warnings, landing gear, and forgiving recovery assistance.
- A later, optional Python webcam service that tracks a cardboard yoke and throttle using ArUco markers.

The intended first release is a polished, finite flight experience. Microsoft Flight Simulator is a reference for presentation and atmosphere; global scenery, licensed airline systems, and study-level aircraft simulation are outside the first milestone.

## Proposed stack

| Component | Choice |
| --- | --- |
| Native client | Godot 4.7.2, standard edition, typed GDScript |
| First delivery target | macOS `.app`, tested on Apple Silicon |
| Renderer | Forward+ with Metal, quality settings tuned after profiling |
| Models | Licensed web assets, preferably glTF 2.0 / GLB, with per-asset attribution |
| World | Generated terrain and airfield layout with authored materials and licensed environment assets |
| Simulation | Fixed-step arcade flight model with a data-driven profile per aircraft |
| Input | Separate keyboard, mouse, and optional vision providers feeding one control state |
| Vision, later phase | Python 3.12, OpenCV contrib / ArUco, NumPy, and websockets, in an isolated environment |
| Vision connection | JSON over a loopback WebSocket, default `ws://127.0.0.1:8765` |
| Local settings | Godot user data for client settings; local JSON for tracker calibration |

Godot's official [macOS download](https://godotengine.org/download/macos/) lists 4.7.2. It supports [native macOS app exports](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html), [native WebSockets](https://docs.godotengine.org/en/stable/tutorials/networking/websocket.html), and [GLB/glTF import](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html). These sources were checked on September 18, 2026.

## Project layout

```text
cardboard-cockpit/
  simulator/
    scenes/                 # Attract, hangar, airfield, flight, results
    systems/                # Physics, controls, camera, audio, mission, vision client
    ui/                     # Menus, HUD, settings, calibration, spectator panel
    data/                   # Aircraft profiles, missions, quality presets
    assets/
      aircraft/
      environment/
      audio/
  vision/                   # Tracker and calibration service in a later phase
  shared/
    control-schema.md
  docs/
    phase-0.md
    architecture.md
    roadmap.md
    asset-sources.md
  tools/                    # Development and packaging helpers in Phase 1
  THIRD_PARTY_ASSETS.md
  README.md
```

`simulator/project.godot`, runnable scenes, and the launch/export helpers will be created in Phase 1. Empty directories are intentional at this checkpoint.

## Planned controls

| Control | Action |
| --- | --- |
| W / S | Increase / decrease throttle |
| Arrow keys | Pitch and roll |
| A / D | Rudder and ground steering |
| Mouse | Menus and hangar orbit; optional flight control mode |
| Right mouse + movement | Look around in cockpit/chase view |
| Space | Wheel brakes |
| G | Landing gear |
| V | Cockpit / chase camera |
| Tab | Spectator information |
| R | Reset aircraft |
| M | Mute / unmute |
| Enter | Select aircraft / start mission |
| Escape | Pause / release captured mouse |
| C | Calibration, once vision is implemented |

These controls are a design contract, not implemented functionality yet.

## What can be reviewed now

- [Environment findings and Phase 0 checkpoint](docs/phase-0.md)
- [Architecture and visual direction](docs/architecture.md)
- [Delivery phases and verification](docs/roadmap.md)
- [Aircraft asset research](docs/asset-sources.md)
- [Proposed control message contract](shared/control-schema.md)

There is no run command or game screenshot at Phase 0. The next checkpoint will include a native, keyboard-playable build and real screenshots.
