# Version 0.8.2 verification

Run `./tools/verify.sh` for syntax, flight, arcade control feel, scene integration, full-demo, ballistics, radio and synthetic tracker tests. Headless checks never open a webcam.

The suite checks held steering and release-to-level behavior, bounded pitch, short taps, continuous terrain recovery, simultaneous sustained Gatling/missile firing beyond the former ammunition limits, generous aim correction, automatic missile targeting, no goose attacks, streak scoring, projectile gravity/drag, swept target and terrain collision, missile separation/acceleration/burnout, cached terrain consistency, and complete takeoff-to-landing continuity.

Native Mac playtesting uses the Computer Use plugin. Earlier runs exposed excessive fog brightness and approximately 20 FPS in an expanded Retina window; corrected fog and internal render scaling subsequently showed approximately 60 FPS during combat. A complete native takeoff, combat, approach and landing run reached the secured-aircraft debrief. The current arcade rules are also checked in a complete automated sortie; final native evidence is recorded with the release screenshots.

Physical cardboard/webcam operation, Intel runtime behavior, other platforms and Apple notarization remain unverified. Terrain and major buildings collide; trees and small scenery remain forgiving. These are game-tuned mechanics, not certified flight or weapon simulation.

Final suite (2026-09-19): 24 flight, 8 arcade controls, 27 scene, 41 radio, 13 full-demo/input and 24 ballistics/weapon/texture checks passed; 27 Python tests, 62 malformed-packet cases and WebSocket restart/reconnect passed. The continuous demo completed in 142.23 simulated seconds with 137 intercepts, no goose attacks, and no position resets. Held Space+T produced 1,976 rounds and 30 missiles over 25 seconds. No Godot ERROR entries occurred in the full run. The intentionally malformed numeric packet emits the expected parser warning.

The rotary model was inspected in rendered idle/firing close-ups. The gun retains its animated rotor and physical muzzle; release extinguishes the flash and lets the rotor coast down. Missile exhaust now tapers away from the nozzle without covering the airframe.

Native 0.8.2 evidence: [departure](screenshots/arcade-01-departure.jpg), [combat](screenshots/arcade-02-combat.jpg), [final approach](screenshots/arcade-03-approach.jpg), and [cannon close-up](screenshots/rotary-cannon.png). The latest final-approach telemetry showed 41 FPS in Balanced mode; the earlier 60 FPS observation is not a guarantee throughout the larger forest scene.

The native 0.8.2 Watch demo also completed without interruption: 138 geese cleared, 66,400 points, and [Aircraft secured](screenshots/arcade-04-landed.jpg) after the landing rollout. Differences from the headless interception count reflect render/physics scheduling.
