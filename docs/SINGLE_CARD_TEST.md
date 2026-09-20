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
The Python preview needs no throttle card or stored multi-step calibration. The game’s Play tutorial now checks all controls, so it also requires throttle tags 0/1/2 and gun tag 04. Optional throttle tags 0 (idle), 1 (moving) and 2 (full) now supply relative power; see [setup](vision-setup.md).

Optional shooting tag **04 (gun)** fires when exposed and stops when covered. Mount it above the yoke, keeping ID 7 visible. Use the [gun sheet](../vision/printable-weapons.html) and [visibility requirements](vision-setup.md#shooting-tags). Aim assistance never fires automatically.

From the project folder, use two terminals:

```sh
./tools/tracker.sh --camera 0 --paper-test
./tools/run.sh -- --stickers
```

The game opens its main menu. Choose Play and follow the complete control check before starting the flight. For a single card alone, use the Python preview to inspect the following movements.

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
4. Hide the card to pause flight and display the full-screen live camera view.
   Bring the whole tag back and hold it visible for half a second to resume.
   Choose USE KEYBOARD on that screen to leave camera controls.

After the checks pass, hold the yoke centred, throttle at 0% and code 04 covered for one second. Flight starts automatically.
