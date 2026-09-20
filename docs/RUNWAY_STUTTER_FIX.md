# Runway motion fix

Takeoff and landing moved the camera directly to the latest 60 Hz flight position on each rendered frame. When rendering and physics ticks did not coincide, the camera repeated a position and then jumped forward. Disabling shake did not address this motion stepping.

The renderer now interpolates two fixed-step snapshots for the aircraft, camera, exhaust, and wind effects. Controls, collision, scoring, and weapon simulation retain the authoritative flight state. Weapon mounts are restored to the authoritative pose before each physics step. Teleports snap immediately, heading interpolation handles wraparound, and crash/ejection presentation remains on its existing path.

## Verification

The deterministic 120 Hz test changed from 118 stationary frames alternating with 1.5 m jumps to zero stationary frames and uniform 0.75 m steps, in both camera views. It also checks state isolation, teleport resets, and heading wraparound.

Native moving-game measurements at the same settings:

| Phase | Stationary camera frames before | After | Before frame p99 | After frame p99 |
|---|---:|---:|---:|---:|
| Takeoff | 16 / 255 | 0 / 249 | 24.36 ms | 22.14 ms |
| Approach | 22 / 202 | 0 / 197 | 23.27 ms | 21.32 ms |
| Rollout | 8 / 130 | 0 / 124 | 23.95 ms | 22.17 ms |

These are local measurements; the fix addresses uneven movement between frames rather than promising a particular frame rate on every machine.

Passing checks: runway render motion, camera comfort, judge landing (23), landing button/recovery, adaptive plasma (36), and controls (27). `tools/profile_runway_motion.gd` reproduces the native moving-game measurements.
