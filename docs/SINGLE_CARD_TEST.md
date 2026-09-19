# One-card flight test

A built-in laptop camera and printed ArUco 4x4 marker 7 are sufficient.
The camera controller turns marker rotation and perspective tilt into flight
inputs. Leave that window open, then play in the separate simulator window.
It estimates relative orientation using approximate camera intrinsics; it is
not a calibrated depth sensor. Lifting the marker is no longer a pitch command.

For measured focal lengths and lens-distortion correction, follow
[camera lens calibration](camera-calibration.md), then add
`--intrinsics vision/iphone.lens.local.json` to the tracker command. Without
that option the preview is labelled LENS APPROXIMATE. Sudden angle jumps now
require three agreeing observations; the usual median filtering remains.
No throttle card or stored multi-step calibration is required. Optional throttle tags 0 (idle), 1 (moving) and 2 (full) now supply relative power; see [setup](vision-setup.md).

From the project folder, use two terminals:

```sh
./tools/tracker.sh --camera 0 --paper-test
./tools/run.sh -- --paper-test
```

1. Keep the entire marker and its white margin visible. Hold it flat and still
   until the camera preview says LIVE (the terminal prints YOKE READY).
2. Turn the card like a steering wheel to bank. Tilt the top toward yourself
   (away from the camera) to pitch up, and away from yourself to pitch down.
   Hold near the centered pose for neutral controls.
   Sensitivity defaults to 2x for pitch and 1.4x for bank (70% of the previous
   bank sensitivity). The tracker applies this
   once after filtering; its readout and the game's YOKE readout show the same
   normalized command. Use `--yoke-sensitivity 1 --bank-scale 1` for the original response
   (full input at 20 degrees of rotation or 25 degrees of estimated tilt).
   Small movements around center are intentionally ignored: steering engages
   beyond 1.8 degrees bank or 5 degrees tilt, and returns to neutral within
   1 degree bank or 3 degrees tilt. A three-frame median rejects isolated
   detection jumps. The neutral anchor never drifts during a held command.
3. Press Space or C **in the camera preview window** to recenter.
4. Hide the card to hold flight still. Show it again to resume.

The aircraft starts airborne in chase view with automatic speed so you can
see steering immediately. Once the three-tag throttle is visible, it replaces automatic speed and holds its last power if hidden. This is a diagnostic flight, not the takeoff mission.
The chase camera follows the aircraft's nose up and down with a short, smooth
response, keeping its position behind the aircraft through climbs and dives.
Restart preserves this mode. Keyboard override leaves marker control.
The game shows a small mirrored webcam preview in the bottom-right corner.
Its YOKE PITCH value is the incoming command, while AIRCRAFT PITCH is the actual
nose angle in degrees. The aircraft takes time to reach the demanded angle;
terrain protection can also limit a nose-down command near the ground.
It stays visible even while the marker is lost, so you can adjust your framing.
The camera stays local; preview images are sent only to the game on this computer
and are never saved or uploaded. Disabling tracking clears the inset.
Tape the marker flat on rigid cardboard, with the white margin exposed. Keep
it at least 70 pixels wide in the camera view and avoid edge-on poses. Real
lens distortion, blur and flexible paper can still cause orientation error.
