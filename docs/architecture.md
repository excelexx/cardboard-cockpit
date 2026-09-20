# Runtime architecture — SPECTRE

`main.gd` coordinates flight deck, combat flight, approach, rollout, pause, ejection, crash and debrief. `data/aircraft.gd` exposes one profile. No campaign or selection controller exists.

- `flight_dynamics.gd`: bounded physics substeps, angular response, thrust, velocity inertia, terrain contact and continuous landing rollout.
- `combat.gd`: contact tracking, projectile sweeps, cannon heat, delayed missile launch, limited guidance, countermeasures, spaced hostile attacks and optional guided pilot.
- `fighter_model.gd`, `aircraft_visuals.gd`, `fighter_effects.gd`: licensed airframe adaptation, gear/control/bay animations, exhaust, heat distortion, trails, stores and debris.
- `camera_rig.gd`: cockpit/chase framing, FOV, shake, local lag and an on-demand missile viewport.
- `world.gd`: shared rendered/contact terrain, buildings, forests, environment lighting and quality controls.
- `hud.gd`: contextual avionics, target/lead/threat marks, radar, radio subtitles and overlays.
- `engine_audio.gd`, `radio_director.gd`: layered playback, pause/mute, filtered voices, bounded priority queue and mix ducking.
- `vision_client.gd`: versioned local WebSocket input, independent confidence, tracking-loss behavior and explicit keyboard takeover.

Physics runs at fixed ticks; presentation updates independently. Tests cover component behavior, native scene integration, complete guided combat and landing, and synthetic tracker/WebSocket behavior. Physical webcam testing is separate.
