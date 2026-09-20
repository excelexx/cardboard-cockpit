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
