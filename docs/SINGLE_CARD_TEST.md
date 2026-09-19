# One-card flight test

A built-in laptop camera and printed ArUco 4x4 marker 7 are sufficient.
The camera controller turns marker rotation and perspective tilt into flight
inputs. Leave that window open, then play in the separate simulator window.
It estimates relative orientation using approximate camera intrinsics; it is
not a calibrated depth sensor. Lifting the marker is no longer a pitch command.
No throttle card or stored multi-step calibration is required.

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
   Full input takes 20 degrees of rotation or 25 degrees of estimated tilt.
   Small movements around center are intentionally ignored: steering engages
   beyond 1.8 degrees bank or 5 degrees tilt, and returns to neutral within
   1 degree bank or 3 degrees tilt. A three-frame median rejects isolated
   detection jumps. The neutral anchor never drifts during a held command.
3. Press Space or C **in the camera preview window** to recenter.
4. Hide the card to hold flight still. Show it again to resume.

The aircraft starts airborne in chase view with automatic speed so you can
see steering immediately. This is a diagnostic flight, not the takeoff mission.
Restart preserves this mode. Keyboard override leaves marker control.
The camera stays local; images are not saved or sent to the game.
Tape the marker flat on rigid cardboard, with the white margin exposed. Keep
it at least 70 pixels wide in the camera view and avoid edge-on poses. Real
lens distortion, blur and flexible paper can still cause orientation error.
