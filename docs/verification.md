# Version 0.10.1 aerial photography and rendering verification

- All 23 terrain photographs load and are bound to their geographic terrain meshes; `test_sf_assets.gd` passes. Original JPEG SHA-256 hashes and returned extents are retained.
- Added 4,807 LOD levels across 1,874 city/road scenes. The compiler asserted that every original full-detail vertex array remained identical.
- Repeated the same native High-quality camera checks: Golden Gate 120 FPS, downtown 120 FPS, SFO 120 FPS, cockpit 76 FPS on this Mac. Earlier corresponding samples were 70, 56, 65 and 42 FPS. These are observed samples, not constant-framerate guarantees.
- Inspected actual aerial street/terrain alignment and preserved water/runway geometry. Terrain vertices and flight collision grids are unchanged.

# Version 0.10 San Francisco verification

- Full `tools/verify.sh`: PASS (flight, assisted controls, scene, audio, both legacy routes, SF route, ballistics, combat feel, balance, city grounding, vision validation and reconnect).
- SF round trip: 459.85 simulated seconds, 14/14 waypoints, safe SFO 28R stop, no terrain-recovery position corrections; 1180 cannon rounds, 23 missiles, 23 geese cleared; 89.93 seconds in the city/bridge corridor.
- Native packaged flight, observed with Computer Use: **Aircraft secured**, 23 geese, best streak 4, score 2700; continuous takeoff/intercept/landing complete.
- Live cockpit city sample was 27 FPS during streaming in Balanced mode; final Balanced mode shortens distant building/tree draw ranges.
- Native visual checks: Golden Gate 70 FPS, downtown 56 FPS, SFO 65 FPS, cockpit 42 FPS on this Mac. These are observed samples, not a constant-framerate guarantee.
- New source cockpit uses live 2D flight instruments, correct SF compass offset and SFO navigation labels. Final scene check: 27/27 PASS.
- Original source archives and SHA-256 manifests are included; no runtime map service is required.
- Regional buildings are visual scenery; terrain contact uses a 50 m raster of the actual source terrain. Physical cardboard hardware remains untested.

Previous verification history follows.

# Version 0.9.1 verification

Run `./tools/verify.sh` for flight, controls, both routes, weapons, targeting, city grounding, radio and synthetic tracker verification. No webcam opens in these checks.

The complete suite includes 24 flight, 8 angle-control, 27 scene, 41 radio, 13 alpine sortie/input, 24 ballistics/weapon/texture, 17 combat-feel and 7 balance-profile checks, plus the coastal route, 108 city checks, 13,638 airport grounding samples, 27 Python tests and malformed-packet/reconnect coverage.

The alpine demo completes in 138.2 simulated seconds with 23 interceptions. The integrated Azure Coast tour reaches all eleven landmarks, spends 40.18 seconds above the city, peaks at 1,047 m and stops on the arrival runway after 179.15 simulated seconds. Both preserve continuous motion and harmless geese. City testing sampled 55,543 vertices with no terrain intrusion. Both the 128 base and 256 detail tiles and all 60 village homes are present.

The [balance report](balance.md) documents the external reference, adapted values and measured weapon/handling timings. Small-cone acquisition, retention tolerance, crosshair convergence, unlocked-missile acceleration, no hidden retargeting, persistent smoke and frame-rate-independent speed response are tested. Holding both fire controls continues to use unlimited ammunition.

Earlier 0.8 native runs and screenshots remain historical evidence. The old graphics-branch M4 timing report is not a measurement of this integrated revision. Physical cardboard/webcam operation, Intel runtime behavior, other platforms and Apple notarization remain unverified. Trees remain forgiving; buildings and terrain collide. This is an arcade game, not certified simulation.

The packaged native coastal PLAY run was inspected through the Computer Use plugin: takeoff, staggered contacts, route navigation and the photogrammetry city were visible. The player took manual control during the run; the automated full-route checks above supply the uninterrupted landing evidence. Native runtime frame rate has not been re-benchmarked for this combined revision.

The concurrent `integration/coastal-sortie` merge is reconciled as well: its updated scenery evidence, lighter HUD text shadow and shorter Balanced coastal shadow distance are retained alongside the two-route selector and current combat balance.

## 0.11.0 — SF boss demo, September 19, 2026

- Full `tools/verify.sh` regression suite passed: aircraft 24, arcade controls 8, scene integration 27, radio 41, mission 13, ballistics, combat feel 17, balance 7, legacy scenic fixture, SF route, spectral run, badge protocol, spectral controls, source assets, city grounding, combat/landing autotests, Python and live local WebSocket reconnect.
- Latest targeted controls suite: **19 checks, zero failures**. Includes latched combined primary, repeated quad salvos, four hardpoints, divergent trajectories, roll recovery/target retention, pause, replay pool reset, cardboard boost/brake ownership, adaptive help and single-count boss death.
- Camera/relay Python suite: **33 tests passed**. Imported badge research suite: 27 tests, 5 optional-dependency skips. The actual camera was not tested: macOS initially blocked capture, then the user explicitly deferred webcam work.
- Automated SF win: **99.68 seconds**, five waypoints, ~46 seconds over the city, zero discontinuous position corrections. Automated no-fire run: **146 seconds**, no fabricated victory or shots.
- Native Computer Use observed launch, assisted/player combat, both cameras, repeated firing, missile inset, complete boss outcomes, pause and replay. Normal native play displayed **59–60 FPS** on Apple M5 Pro. Native shader log had no shader/runtime errors.
- A controlled native High-quality matrix rendered sky, fog, dark exposure, city/text-off, sun, far/close targets, crossing, roll, boost and boss load. Its loop measured 33–54 FPS including capture overhead; displayed frame telemetry often read 60. A cold first frame took substantial warm-up, so it is not a steady-state benchmark. Screenshots are under `docs/screenshots/spectral`. Maximum observed live shots 66, pooled sprites 63, pooled event lights 4; configured limits 220/96/8. An abrupt matrix shutdown reported pending ObjectDB resources; this diagnostic does not establish a gameplay memory leak. A repeat matrix was stopped to honor the shorter deadline.
- Actual BLE: all eight physical buttons plus A+B and releases observed. The bundled executable connected to the installed firmware and read back idle `[0]`, takeoff `[1]` and sky `[2]`. No firmware was flashed. Physical LED appearance was not independently assessed.
- **Packaged app launch verified:** `build/Cardboard Cockpit.app` started through native UI and displayed **BADGE CONNECTED**; its own bundled helper ran with the app's parent PID, with no standalone relay process required. App signature and source-inclusive archive were verified by packaging.

The user explicitly deferred the webcam/printed-marker test and the design polish. Steering/throttle/switch software paths are tested with synthetic observations; that is not physical cardboard validation. Basic rendering uses composed existing systems rather than every optional renderer technique in the supplied vision documents.

Claude's work from `origin/main` through `0a1a4ef` was merged, including perspective yoke input, printable marker sheets and cockpit/instrument refinements. Legacy coastal scenery remains available only as source/test fixtures; the SF combat menu and timed boss flow are preserved. The integrated tracker handles the single-card detector without requiring weapon-switch observations.

Final integrated verification: `tools/verify.sh` passed after the merge, including Claude's sticker input and urban fixture checks. The combined Python suite now contains **41 passing tests**. Camera access remains deferred by the user; no webcam tracker is running.

Final wireless recheck: after restarting the signed release, its own child `BadgeBridge` connected to the real badge and read back phase `[0]`. A local diagnostic log is now retained at `~/Library/Logs/Cardboard Cockpit/badge.log` to diagnose intermittent startup/reconnect delays. No standalone relay or webcam process is required or left running. PR #8 passed both GitHub checks and was merged into `main`.

## 0.11.1 — one-button landing ending

Badge B, keyboard L and the on-screen LAND AT SFO button now start one assisted landing action: safe weapons, deploy gear/flaps, transfer through a brief visual transition to SFO final, approach, touchdown and automatic braking. Score is retained and repeated presses do not restart the approach. The ending begins landing automatically after its seven-second prompt. Guided full run: 125.72 seconds; no-fire full run: 140.20 seconds, both landed and stopped. The no-fire run still reports an incomplete intercept. The explicit return transition is exempt from the continuous-flight displacement test.
