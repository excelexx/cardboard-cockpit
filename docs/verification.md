# SPECTRE verification — 2026-09-19

The version 0.6 suite replaces obsolete multi-aircraft/campaign tests with tests of the permanent fighter and its current scene flow. Run `./tools/verify.sh` from the repository root.

Verified locally with Godot 4.7.2 on Apple M5 Pro / Metal:

- **24 flight-model checks:** thrust spool, rotation speed, symmetric banking, angular decay, velocity inertia, afterburner acceleration, inverted flight, quick-roll limits, touchdown continuity, braking to rest, unsafe touchdown rejection and reset.
- **27 scene checks:** one airframe and loadout, no selection/progression API, restart/store stability, keyboard takeover, pause/resume, missile lock and bay launch, held missile view, bounded aim assistance, cannon ammo, flare decoy behavior, finite camera transforms, spaced hostile launches and complete landing.
- **41 radio checks:** bounded priority queue, cue availability, expiry/cooldowns, subtitles, pause, mute, ducking and reset.
- **Complete guided combat:** 179.98 seconds, 3 intercepts, 76% hull remaining. The pilot uses the same weapons, ammo, countermeasures, terrain and damage rules as manual flight.
- **Complete approach and rollout:** 59.32 seconds; ends on runway at `(0, 3, -14836.62)`, speed zero, with continuous touchdown and settling.
- **27 Python tests:** marker detection/filter/calibration, data contract, service cadence/reconnection and shipped radio WAV integrity/peak checks.
- **Native WebSocket integration:** 62 malformed packets rejected without state mutation, live synthetic controls received, stale yoke neutralized while throttle holds, and reconnection after service restart.

Rendered chase and cockpit views were inspected. The livery, terrain textures, control surfaces, stores and HUD resolve. A 300-frame High-quality benchmark measured median **16.653 ms**, p95 **17.564 ms**, and 584 draw calls in the opening flight scene at the default 1280×800 window size. This short scene benchmark is not a worst-case performance guarantee.

The malformed-number test intentionally triggers Godot's “Exponent too high” parsing warning; the packet is rejected. No webcam is opened by this suite.

Physical webcam/cardboard tracking, Intel runtime behavior, other platforms and public notarized distribution remain unverified. The simulation is game-tuned; these tests are software checks, not validation of real aircraft aerodynamics.

The exported native executable also completed the three-minute combat sortie and the 59.32-second landing check. The locally signed app was opened through the Mac UI; Enter launch, Escape pause/resume, F1 controls, V cockpit switching and H guided flight were exercised. Its strict code signature was verified by the packaging script.
