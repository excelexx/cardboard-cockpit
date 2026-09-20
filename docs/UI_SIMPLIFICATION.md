# Demo spacing and UI cleanup — 0.22.2

- Flock spacing is now 600–1,500 metres, exactly three times the previous 200–500 metres. Per-flock and per-wave counts are unchanged.
- The objective is a single `WAVE N · kills/total` readout, without a progress bar.
- The top-right clock is hidden during ordinary flight/combat and remains available during landing/rollout.
- Main-menu subtitle: “Fly and shoot Geese Gods in this cardboard cockpit simulator.” The main-menu Next Pilot button is removed.
- Pause no longer shows the badge shortcut/footer text.
- Quick calibration removes the top headings, Live Camera Checks label, explanatory paragraphs, status/progress strip and Checks Advance footer. Its card retains the upright-yoke instruction and throttle/bank/pitch/yaw values.
- Full setup retains its step navigation and one necessary instruction per step; its duplicate explanatory copy is removed. Calibration and input validation behavior are unchanged.

Verification: directional wave spacing (34 checks), endless waves (253), HUD readouts (75), control tutorial (75): **437 checks passed**. Native UI captures use simulated camera images with badge communication disabled; no new physical camera/badge acceptance is claimed.

## Center HUD follow-up

The flight aiming area now contains only the crosshair and its hit confirmation. Target labels, distances, brackets, guide lines, waypoint overlays, and reward popups are removed. Alerts and captions are moved to the left; landing guidance and a three-mark pitch ladder with altitude are on the right. Goose model scale increases from 3 to 6 (twice the linear size). Flock counts and spacing are unchanged.

Validation: HUD readouts (75 checks) and combat feel (16 checks) pass; native flight screenshot inspected.

## Low-detail geese

Goose meshes now use 512 / 240 / 152 triangles, down from 7,808 / 1,232 / 376. Plumage uses vertex colors with simple lighting, no noise texture, feather shading, rim effects, or goose shadows. Size and animation are preserved. Red target brackets are restored without labels or distances. Geometry budget and combat checks pass; this verifies rendering workload reduction, not a measured whole-game FPS gain.

## Altitude, scale, and settings

Geese spawn at the aircraft altitude, subject to terrain clearance; horizontal placement and flock spacing are unchanged. Model scale is now 12, twice the preceding build. Control ceilings are 6x, music gain reaches 4x, and other mixer channels reach 2x. The Python tracker accepts the same extended input range. Music no longer ducks during instructor or radio speech.

Validation: directional wave checks (72), mixer/settings checks (32), and Python control-settings tests (3) pass.

## Slow focused encounters

Waves alternate between one and two geese. Arrivals are one at a time, ten seconds apart (including between waves), starting ten seconds after takeoff. This replaces distance-based arrival spacing. Each living goose has a health ring outside its red brackets. Both plasma emitters focus one goose and deal 100 health over 1.5 seconds; ordinary hits do not trigger camera shake.

Validation: 49 timed/altitude checks, 253 endless-wave checks, 28 plasma checks (including survival before 1.5 seconds and death at 1.5 seconds), and 19 combat checks pass.

## Eight-second arrivals and lighter rendering

Waves now alternate between two and three geese with one arrival every eight seconds. Goose scale doubles again to 24. Mesh detail is 176 / 96 / 64 triangles; shared meshes prewarm at startup. The transparent spectral overlay formerly allocated per spawn is removed, and goose colors use unshaded rendering. Laser widths double in cockpit and chase views. Calibration replaces the existing heading with “Set throttle to 0%” while throttle is nonzero, and restores the three-second progress bar without another text line.

Validation: 64 arrival/altitude checks, 253 endless-wave checks, 75 calibration checks, 19 combat checks, and actual mesh triangle budgets pass.

## Ten-second waves and quick kills

Full waves of two or three geese arrive every ten seconds, slightly offset left/right from the camera sightline. Geese spawn no lower than 1,300 feet even when the player is below that altitude, and remain clear of terrain. The player must aim within five degrees of a wave goose before assistance damages it. Focused plasma destroys a goose in 1 second; its mesh hides immediately and is removed on the next projectile cleanup, leaving a brief warm explosion. Red health circles replace brackets. Only cockpit lasers retain the doubled width; external-view lasers return to their original width.

## Landing performance

First touchdown allocated two GPU particle emitters, their curves, meshes, and materials on the contact frame. The native rendered probe reproduced a 3,043.7 ms first-touchdown peak, versus 24.5 ms on a repeat landing. Tyre smoke now uses eight shared-mesh quads created during aircraft setup, animated and faded without touchdown allocations or a particle compute pipeline. The same probe measured 26.1 ms on first touchdown and 20.1 ms on repeat, with 0.67 ms touchdown CPU work. These are local probe measurements, not a universal frame-rate guarantee.

Validation: 39 wave/altitude checks, 253 endless-wave checks, 34 plasma/laser-width checks, 19 combat checks, and 21 judge-landing checks pass. tools/profile_touchdown.gd reproduces the native measurement and checks smoke pool reuse.

## Staggered distant waves and steadier runway camera

Wave geese now appear at 2.2, 2.6, and 3.0 km along the camera sightline (two-bird waves use the first two slots), with alternating small lateral offsets of 90–120 m. Laser and acquisition range extends to 3.5 km, and managed waves are excluded from the old ambient-distance retirement rule so distant geese remain visible. The 1,300-foot floor and ten-second wave interval are preserved.

Within 120 m of terrain and during rollout, the camera damps rapid attitude and height changes, reduces chase acceleration/yaw offsets, and lowers shake amplitude by 80%. Normal airborne kill shake is unchanged. A synthetic jitter check measured 1.294° source movement versus 0.152° cockpit and 0.023° chase movement. Wave, laser-range, camera, and landing tests pass.

## Working aim slider and one automatic wave missile

Plasma now uses the same slider-scaled acquisition angle as the aiming reticle. The fixed five-degree wave-target restriction and five-degree minimum are removed, so lower settings require precision, higher settings widen acquisition, and zero disables assistance. Slider endpoint labels reflect the actual 6x maximum.

Each three-goose cinematic wave schedules exactly one guided missile, usually against the farthest goose not already under plasma fire. Its target is reserved while the missile is queued or flying, leaving the other two for the pilot. Two-goose waves do not launch one. Wave missiles have no collateral damage and expire when their wave ends; repeated frames cannot schedule another. They reuse the normal goose explosion rather than layering the heavy area blast.

Validation: 18 real-slider targeting checks, 13 wave-missile checks (including continuous plasma, no splash, and no carryover), 36 plasma regression checks, and 27 control checks pass. Native rendering also verified one launch and one kill.
