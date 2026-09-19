# Native simulator architecture

This document specifies intended behavior. No systems described here are implemented at Phase 0.

## Product direction

The presentation should read as a flight game from across a room: a large aircraft in a lit hangar, clear plane selection, a cinematic airfield, believable silhouettes and materials, and a calm, readable cockpit. Use a restrained charcoal/off-white UI with amber highlights. Keep diagnostics inside an optional panel.

The first world is a bounded mountain valley with a long main runway sized for the largest aircraft, apron and hangar, water, foothills, distant terrain, and a checkpoint route that leads back to a safe landing. Large airliners need wider turns and larger rings than the F-35. Aircraft profiles must control these assistance and mission parameters instead of forcing every plane through one fighter-sized course.

## Client layers

| Layer | Responsibility |
| --- | --- |
| Application state | Attract, hangar, briefing, runway, flight, approach, results, pause |
| Aircraft definition | Display name, model path, cockpit layout, handling, engine response, lift and drag, ground clearance, camera offsets |
| Control providers | Keyboard, mouse, and later webcam input; each emits normalized controls |
| Input router | Chooses the active source, applies dead zones and smoothing, and supports immediate keyboard takeover |
| Flight model | Fixed physics timestep, gradual engine power, lift, pitch/roll/yaw response, speed, ground motion, gear, and landing evaluation |
| Mission director | Takeoff gates, five ring checkpoints, route assistance, approach and touchdown, score and result |
| World | Terrain, runway, collision, water, sky, atmospheric lighting, clouds, and environment detail |
| Camera director | Cockpit, chase, hangar orbit, camera shake and look controls |
| Presentation | HUD, readable prompts, instruments, sounds, success feedback, settings and spectator state |
| Persistence | Aircraft selection, sensitivity, audio and graphics preferences; no secrets in the project |

Rendering interpolates the simulated pose. Gameplay uses meters, seconds, and radians internally; the HUD converts to knots, feet, and degrees. Explicit conversion helpers prevent different displays from disagreeing.

## Aircraft scope

- Airbus A380: heavy four-engine airliner; slower acceleration and roll; double-deck silhouette.
- Boeing 747: heavy four-engine airliner with recognizable upper-deck hump.
- Boeing 737: twin-engine narrow-body airliner with more responsive handling than the two large aircraft.
- F-35: single-engine fighter, higher responsiveness and a fighter-oriented HUD.
- B-2 Spirit: flying-wing aircraft with a distinctive planform and damped handling.

Profiles are arcade approximations, not validated real aircraft performance models. Rotation prompts should use each profile's tuned speed; the brief's 90-knot cue can be retained for an assisted demo preset, but should not be presented as a real-world A380 procedure. Military aircraft are used for flying only.

Use downloaded external models where licensing and quality checks pass. Exterior models do not imply an accurate cockpit is included. A purposeful custom cockpit shell and instruments may be necessary until suitable interior assets are available.

## Rendering and asset pipeline

- Begin with Godot Forward+ and Metal on this Mac. Target a responsive 60 FPS at a moderate internal resolution; measure before promising a result.
- Budget shadows, terrain density, cloud layers, water reflections, and texture resolution independently. Offer a lower-cost graphics preset.
- Prefer GLB for self-contained import. Keep original source information, license text, author credit, and edits for every imported asset.
- Normalize model dimensions, axis orientation, pivots, materials, and collision bounds. Create simplified collision shapes and lower-detail meshes as needed.
- Keep downloads and generated cache files out of normal commits. Use Git LFS or a documented download step if model files become too large for ordinary Git.
- Blender is optional for model conversion and cleanup. It is never responsible for vision processing.

## Vision integration, later

The separate Python service owns capture, marker detection, physical calibration, and tracking confidence. It binds only to the local loopback interface by default and emits the shared JSON contract. The game remains playable when the service is absent.

Use independent confidence and age for yoke and throttle. Smooth the axes, hold brief dropouts, then return yoke controls gradually toward neutral. A lost throttle marker should briefly preserve the last safe power and transition to keyboard control without abruptly cutting thrust. Bound all values and discard non-finite or malformed input.

The calibration flow will store neutral, left/right, forward/back, and idle/full ranges, rejecting spans too small to be usable. The camera orientation and actual cardboard prop geometry will be validated when physical controls are available.

## Sources

- [Godot macOS exports](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html)
- [Godot renderers](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html)
- [Godot 3D import formats](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)
- [Godot WebSockets](https://docs.godotengine.org/en/stable/tutorials/networking/websocket.html)
