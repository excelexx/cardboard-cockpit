# Version 0.9.1 verification

Run `./tools/verify.sh` for flight, controls, both routes, weapons, targeting, city grounding, radio and synthetic tracker verification. No webcam opens in these checks.

The complete suite includes 24 flight, 8 angle-control, 27 scene, 41 radio, 13 alpine sortie/input, 24 ballistics/weapon/texture, 17 combat-feel and 7 balance-profile checks, plus the coastal route, 108 city checks, 13,638 airport grounding samples, 27 Python tests and malformed-packet/reconnect coverage.

The alpine demo completes in 138.2 simulated seconds with 23 interceptions. The integrated Azure Coast tour reaches all eleven landmarks, spends 40.18 seconds above the city, peaks at 1,047 m and stops on the arrival runway after 179.15 simulated seconds. Both preserve continuous motion and harmless geese. City testing sampled 55,543 vertices with no terrain intrusion. Both the 128 base and 256 detail tiles and all 60 village homes are present.

The [balance report](balance.md) documents the external reference, adapted values and measured weapon/handling timings. Small-cone acquisition, retention tolerance, crosshair convergence, unlocked-missile acceleration, no hidden retargeting, persistent smoke and frame-rate-independent speed response are tested. Holding both fire controls continues to use unlimited ammunition.

Earlier 0.8 native runs and screenshots remain historical evidence. The old graphics-branch M4 timing report is not a measurement of this integrated revision. Physical cardboard/webcam operation, Intel runtime behavior, other platforms and Apple notarization remain unverified. Trees remain forgiving; buildings and terrain collide. This is an arcade game, not certified simulation.

The packaged native coastal PLAY run was inspected through the Computer Use plugin: takeoff, staggered contacts, route navigation and the photogrammetry city were visible. The player took manual control during the run; the automated full-route checks above supply the uninterrupted landing evidence. Native runtime frame rate has not been re-benchmarked for this combined revision.

The concurrent `integration/coastal-sortie` merge is reconciled as well: its updated scenery evidence, lighter HUD text shadow and shorter Balanced coastal shadow distance are retained alongside the two-route selector and current combat balance.
