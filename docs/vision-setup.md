# Cardboard camera controls

The Python tracker reads ArUco `DICT_4X4_50` markers and sends controls to the native game at `ws://127.0.0.1:8765`. Images stay local in memory. Cameras open only when you launch a tracker or the two-camera launcher.

## Laptop yoke + phone throttle

Connect the phone as Apple Continuity Camera or a webcam app. Open **Launch Two-Camera Cockpit.command** to run the source game in airborne paper-test mode with both trackers and previews. Automatic selection recognizes the MacBook/FaceTime camera and one iPhone. For other apps, multiple phones, or manual selection:

```sh
./tools/dual_camera_tracker.sh --list-cameras
./"Launch Two-Camera Cockpit.command" --yoke-camera 1 --throttle-camera 0
```

Those indices are an example: this Mac currently lists iPhone at 0 and MacBook Air at 1. Device order can change, so prefer automatic selection or check the list after reconnecting cameras. Camera indices must differ. The phone sees throttle tags 0/1/2; the laptop sees yoke 7 and the optional weapon switches. Tags seen by the wrong camera cannot take over the other control.

For an ordinary mission, run these in separate terminals:

```sh
./tools/dual_camera_tracker.sh
./tools/run.sh -- --dual-cameras --stickers
```

The laptop sends controls and its preview on port 8765; the phone uses 8766. The game shows **YOKE / LAPTOP** and **THROTTLE / PHONE** cards. Green indicates tracked control; amber means waiting or holding. Video disappears after a second without fresh frames. Phone loss does not interrupt laptop input. Game sockets reconnect automatically when a tracker returns; if a camera worker exits, the other stays running and the terminal tells you to restart the launcher. Q in the Python window stops both cameras; closing the combined launcher's game also releases them.

Optional measured lens profiles are separate: `./tools/dual_camera_tracker.sh --yoke-intrinsics laptop.json --throttle-intrinsics phone.json`. Use profiles calibrated for each selected camera and resolution; see [lens calibration](camera-calibration.md).

## Relative throttle: your three tags

| Tag | Placement | Meaning |
| --- | --- | --- |
| **0 / 00** | Fixed at the start of travel | 0% / idle |
| **1 / 01** | On the moving throttle | Current power |
| **2 / 02** | Fixed at the end of travel | 100% / full |
| **7** | On the yoke | Bank and pitch; separate from the throttle |

Leading zeros are labels: ID 01 is numeric ID 1. The supplied reference image uses the correct dictionary and IDs.

For a roughly **10 cm slider**, place the fixed tag centers about 10 cm apart along the direction of travel. Put the moving tag beside that line, on a parallel track, so it never covers the fixed tags. At each stop its center must line up with the corresponding endpoint perpendicular to travel:

```text
       fixed 0                          fixed 2
          +-------------------------------+     ~10 cm
                    direction of travel
          <----------- [moving 1] -------->
             parallel lane beside the fixed tags
```

**Keep all three tag faces in the same flat plane**, including the moving tag. A grip can stand above that plane, but its tag should sit flat alongside it. This implementation measures a linear slider, not a pivoting lever's angle. Tilt the complete board toward the camera if necessary. The 10 cm length is not hard-coded; the two fixed tags define the range every frame.

The tracker uses tag 0's corners to correct perspective, then projects tag 1's center along the line from 0 to 2. Thus translating, rotating or scaling the board in the camera view does not intentionally change power. It also compensates for perspective when the tags are coplanar. Lens distortion, bent paper, blurry corners or a moving tag above the reference plane can still cause error.

Use the updated [print sheet](../vision/printable-cockpit.html) at **100% / actual size**. Throttle black squares are 30 mm with a 5 mm white margin on every side. Increase their size or move the camera closer if needed; aim for at least 40–85 pixels across each tag in the preview. Keep the complete white margins visible. Old ID 23 throttle sheets/PDFs are legacy and do not control this tracker.

## Run with the game

From the repository folder:

```sh
./tools/setup_vision.sh
# Throttle alone: no yoke or saved calibration required.
./tools/tracker.sh --camera 0 --throttle-only
```

In a second terminal, launch the updated game:

```sh
./tools/run.sh -- --stickers
```

Return from the setup panel and choose Play. Tracking is already enabled by `--stickers`; alternatively press **C** in an ordinary game launch and enable tracking. **Arrow keys steer while camera throttle stays active. W/S explicitly takes over power and disables camera controls.** Re-enable tracking in the setup panel to use the physical throttle again.

For a legacy single-camera setup with both the yoke and relative throttle:

```sh
./tools/tracker.sh --camera 0 --paper-test
./tools/run.sh -- --stickers
```

Hold yoke tag 7 still for a second to center; rotate to bank and tilt forward/backward to pitch. Space or C in the tracker recenters the yoke. Physical lifting/lowering is not mapped to pitch.

If lifting/lowering still causes unwanted pitch, use the new [camera lens calibration](camera-calibration.md). It measures the real camera geometry using a temporary checkerboard and loads it with `--intrinsics`; the yoke still uses only ID 7. The preview explicitly labels calibrated versus approximate lens parameters.

The game's separate `--paper-test` flight mode still starts airborne with automatic speed when no throttle has been used. Once it receives the three-tag throttle, the physical slider owns power for that flight. Losing a tag holds the last power instead of restoring automatic speed. In that diagnostic mode hiding the yoke freezes flight; use normal `--stickers` gameplay for throttle-only operation.

## Calibration and tracking loss

The three throttle tags are **self-referencing**: no manual idle/full capture and no saved image positions. All three must be visible in the same frame. Missing, duplicated, too-small or degenerate tags give zero throttle confidence and hold the last power. Reacquisition is smoothed. The game uses throttle confidence independently of the yoke.

For manually calibrated yoke ranges instead of auto-centering:

```sh
./tools/tracker.sh --camera 0 --calibrate
```

Hold each of five poses for one second and press Space: neutral, left, right, forward tilt, backward tilt. The yoke settings are stored in `vision/calibration.local.json`. Existing valid yoke calibration files remain usable; their old throttle pixel positions are ignored by the new relative tracker. Normal calibrated mode requires yoke recalibration after camera index/resolution changes. Throttle-only mode does not.

Default smoothing is 0.10 seconds; try `--smoothing 0.16` for more damping. The 6% dead zone affects the yoke, not the throttle range. Stop with Q/Escape in the preview or Ctrl+C in the terminal. `--no-preview` works for throttle-only mode or a previously calibrated yoke. No camera device is probed automatically.

## Verify without a webcam

```sh
.venv/bin/python -m unittest discover -s vision/tests -v
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --script res://tests/test_sticker_controls.gd
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --script ../tools/test_relative_throttle_game.gd
```

Tests render real ArUco markers and cover 0/25/50/75/100% travel, clamping, rotation/scale/translation, perspective, missing/duplicate tags, smoothing, independent loss and the local WebSocket stream. The game integration check feeds a rendered 75% slider through the Python camera loop and socket into actual game throttle/engine physics. No physical camera is opened. Real cardboard feel, lighting and camera performance still need a hands-on check.

To inspect the existing simulated connection: `./tools/tracker.sh --simulate --loss-demo`. To regenerate print assets: `./tools/tracker.sh --markers vision/markers`.

Perspective implementation reference: [OpenCV's planar homography tutorial](https://github.com/opencv/opencv/blob/4.x/doc/tutorials/features2d/homography/homography.markdown).
