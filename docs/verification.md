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
