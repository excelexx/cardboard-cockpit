> Updated behavior: [XLX parity 0.16.0](XLX_PARITY.md). The entries below describe the preceding selective merge; gun-only controls now supersede its legacy switch and missile compatibility.

# Team integration — 0.15.0

The integration branch starts from GitHub main `64011f3` (excelex), which includes `5737463` (Festyve / Michael Zhang) and the dual-camera work. Commit `a5af9f0` preserves the current local visual build, including its uncommitted work at the integration snapshot, on that shared history. Feature changes are applied on top. The original working directory remains available for concurrent visual work.

## Selected changes

- Separate Tutorial: takeoff, sixteen actual target kills, longer return route, approach, touchdown and stopped landing. Existing Play retains the current SF route and flock rules.
- Badge coaching: A configures tutorial gear/flaps; B enables landing assistance once combat is complete; HOME closes an overlay before resuming flight. View controls and the existing live instrument firmware remain compatible.
- Independent laptop/yoke/weapons and phone/throttle previews in setup, flight and pause. Stale images expire independently; a disconnected phone cannot show the laptop feed.
- Team pause and settings interactions restyled with the current Saira/IBM Plex typography, charcoal panels and green highlights. Independent pitch/bank/yaw sensitivity and agility, aim assistance, preview visibility and badge hints persist locally. Defaults preserve current handling and aim strength.
- Two-camera launcher, three-tag relative throttle, optional lens calibration and three-second neutral capture. The original calibrated detector and two latched weapon switches remain supported, as do keyboard missiles alongside the gun-only tag.

The current aircraft, world, weapons, energy cannon, visual effects, audio and normal encounter balance are preserved. A small compatibility fix adapts the existing flock heading call to its current signature. Existing regression assertions now read the current packet/drag tuning and flock outcome instead of obsolete boss and durability values. Serial editor importing avoids a Godot threaded font-import crash observed on a fresh checkout; runtime rendering is unchanged.

## Verification

`COCKPIT_DISABLE_BADGE=1 ./tools/verify.sh` runs offline game and camera regressions, including the full SF route, full sixteen-target tutorial sortie, simulated badge masks, settings widgets and persistence, WebSocket settings acknowledgments/reconnect, independent preview freshness and camera pipeline tests. `tools/review_team_ui.gd` captures native Metal UI screenshots using explicitly simulated camera images and the badge disabled.

Physical dual-camera use and a new badge demonstration are not part of this verification. No badge firmware change is needed. The packaged app is version 0.15.0; see the normal packaging instructions in the README.

Latest offline results: 113 Python tests passed; the SF route completed in 138.02 simulated seconds and the Tutorial completed all sixteen targets and stopped at the airfield in 296.92 seconds. Live sensitivity transport passed 17 checks. A weapon-format transition regression also verifies that switching from a gun-only tag back to two off switches clears both latches. Native screenshots use simulated checkerboard camera images.

## 0.15.1 — restored guided cardboard setup

The original integration omitted excelex’s `control_tutorial.gd` and its instructional screen, leaving only neutral calibration and previews. This follow-up restores the original three-second neutral capture, throttle idle/full/idle checks, yoke overview, shooting-grip explanation and gun cover/uncover checks. It keeps both independent camera panels visible and uses the current fonts and colours. **Set up cardboard**, C, the two-camera launcher, and camera-enabled Play/Tutorial enter this flow. Mid-flight setup pauses and resumes the current sortie; keyboard play remains available. Progress requires fresh camera observations and the correct camera image for the current step; the final ready state requires both images. No physical capture is started by the game itself: use the two-camera launcher as documented.

The restored controller’s automated tests cover calibration freshness, repeated packets, camera/marker loss, gun on/off, ready pose, cancellation, keyboard fallback and entry into the sixteen-target flight. Native screenshots use simulated camera images with badge communication disabled.
