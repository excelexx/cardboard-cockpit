# Cardboard camera controls

The Python tracker reads ArUco `DICT_4X4_50` markers and sends controls to the native game at `ws://127.0.0.1:8765`. Images stay local in memory. Cameras open only when you explicitly launch the tracker or select a camera command.


## Default: laptop yoke and phone throttle

Run `./tools/setup_vision.sh` once, connect the phone as a camera, then open **Launch Two-Camera Cockpit.command** to start both the tracker and game. **Launch Cardboard Tracker.command** starts the same two-camera tracker without launching the game. Both identify the laptop and phone by device name; ambiguous or unavailable devices fail with instructions instead of substituting one camera for the other.

```sh
./tools/dual_camera_tracker.sh --list-cameras
./tools/dual_camera_tracker.sh --yoke-camera 0 --throttle-camera 1
```

The indices are examples; use your camera listing. Choose **Set up cardboard** in the game, hold the yoke steady for the three-second neutral capture, and follow the guided checks. Laptop: yoke ID 7 and gun ID 4. Phone: relative throttle IDs 0, 1, and 2. A visible, readable gun tag fires; cover the printed pattern to stop. There are no two-sided weapon switches.

The explicit `/preview/laptop` and `/preview/phone` streams always represent their named cameras. An absent, disconnected, or stale phone produces an empty phone frame, never the laptop image. Camera capture runs independently so phone loss cannot block the yoke. Settings sensitivity is reapplied after reconnect. Closing the combined launcher releases both cameras.

All automated camera tests use synthetic images. Physical placement and camera availability still require a real setup check.

## Relative throttle: your three tags

| Tag | Placement | Meaning |
| --- | --- | --- |
| **0 / 00** | Fixed at the start of travel | 0% / idle |
| **1 / 01** | On the moving throttle | Current power |
| **2 / 02** | Fixed at the end of travel | 100% / full |
| **4 / 04** | Above the yoke, facing the camera | Uncovered = gun |
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

**Current idle adjustment:** the previous 15% rail position is now 0% throttle. Positions at or below 15% give zero; the remaining travel is scaled as `(rail_fraction - 0.15) / 0.85`, so the previous 57.5% position gives 50% and the full end still gives 100%. This applies before smoothing, including in the tutorial and actual game controls. The tracker defaults to `--throttle-idle 15`; use `--throttle-idle 0` to restore the original range.

The tracker uses tag 0's corners to correct perspective, then projects tag 1's center along the line from 0 to 2. Thus translating, rotating or scaling the board in the camera view does not intentionally change power. It also compensates for perspective when the tags are coplanar. Lens distortion, bent paper, blurry corners or a moving tag above the reference plane can still cause error.

Use the updated [print sheet](../vision/printable-cockpit.html) at **100% / actual size**. Throttle black squares are 30 mm with a 5 mm white margin on every side. Increase their size or move the camera closer if needed; aim for at least 40–85 pixels across each tag in the preview. Keep the complete white margins visible. Old ID 23 throttle sheets/PDFs are legacy and do not control this tracker.

## Shooting tags

Mount **04 for the gun** above the yoke, reachable with your right pointer finger. Keep yoke 7 clear and leave your left hand free for the throttle. Use the [gun print sheet](../vision/printable-weapons.html) at 100% / actual size: the black square is 40 mm with a white margin. No extra calibration or option is needed.

Expose ID 04 for about **0.1 seconds** to fire continuously. Clearly cover it to stop new shots. Already-fired rounds continue normally. The preview shows `04 GUN` as FIRE/OFF. Aim assistance never starts camera gunfire by itself. Keyboard Space / left mouse remains available.

Shooting tags now work down to about **24 pixels across each black square**, rather than 60. Use flat matte prints with enough light for the pattern to remain recognisable. Dimmer images, small print variations and minor fingertip overlaps are tolerated; covering the paper margin alone does not stop firing.

To release a weapon, **clearly cover a substantial part of its printed pattern**. The detector allows normal dictionary error correction and scores the whole square, rather than rejecting a few bad pixels in any single cell. If the tag is no longer recognisable or has substantial pattern damage, that trigger switches off on the next processed frame. Losing the camera or socket also releases the gun trigger (150 ms timeout for a stalled stream). Expose the tag again for about 0.1 seconds to resume.

The preview explains OFF states: `not seen`, `tag too small`, `edge out of frame`, `needs clearer light`, or `covered / unclear`; `checking` means it is waiting for enough consecutive clear frames. Small overlaps are deliberately ignored. Severe blur or glare can still make an exposed tag unreadable, so test both controls with the physical build.

Implementation reference: [OpenCV detector parameters](https://docs.opencv.org/4.10.0/d1/dcd/structcv_1_1aruco_1_1DetectorParameters.html) describes the dictionary correction and border-bit tolerance used alongside the whole-pattern check.

## Run with the game

For the two-camera setup, use the **phone for the throttle** and the **laptop webcam for the yoke and shooting tags**. From the repository folder:

```sh
./tools/tracker.sh --list-cameras
./tools/tracker.sh --camera "MacBook Air Camera" --throttle-camera "iPhone (2) Camera" --paper-test
./tools/run.sh -- --stickers
```

Use the device names returned by `--list-cameras`; names are resolved on each launch. Missing or ambiguous names stop startup instead of opening another camera. Listing reads device metadata without opening a camera. Numeric indices still work, but may change when devices reconnect. OpenCV 4.11 sorts macOS cameras by unique ID ([source](https://github.com/opencv/opencv/blob/4.11.0/modules/videoio/src/cap_avfoundation_mac.mm)); discovery order is not its index order. In the currently connected setup, 0 is the iPhone and 1 is the MacBook webcam.

Throttle detection and the throttle tutorial use only `--throttle-camera`. Yoke, shooting, and lost-yoke recovery use only `--camera`. Each preview names its source, and the final ready screen shows both cameras side by side. A missing or stalled phone holds throttle; yoke and shooting continue on the laptop. The preview keeps its last image through a brief gap (up to 700 ms), then shows the waiting screen if no valid image arrives. Empty packets never extend that display grace period. No fallback to the other camera occurs. Omit `--throttle-camera` for a single camera tracking all controls.

The game always opens its main menu, including launches with `--stickers`, `--combat`, `--flight` or `--paper-test`. Mode flags select the eventual flight; only automated tests and explicit screenshot captures bypass the menu.

Choose **Play** for the guided preflight check. It enables camera control and verifies, in order:

1. Hold the yoke upright in your normal flying position for **three seconds**. The live laptop camera and countdown show calibration progress. All raw angles from that steady interval establish neutral; a missing tag, camera gap of 150 ms or movement over 4° restarts the countdown. Each new Play and calibration Retry takes a fresh measurement.
2. Throttle at 0%, then 100%, then back to 0%, with all three tags visible.
3. A four-second yoke overview explains banking, pitch and yaw. No movement or centering exercise is required; it advances automatically.
4. Shooting grip: right middle finger on the green elastic band, ring finger on the blue band. Show the gun tag, cover it with your pointer finger to stop, then lift that finger to fire. Keep the yoke visible; your left hand stays free.

The instruction and live camera view change for each control. Hold each requested position briefly; the step turns green and advances automatically. Missing tags or disconnected/stale camera data cannot complete a check. Losing the yoke view cannot pass the gun-cover instruction. Retry repeats the current step; Back or Escape returns to the menu. Nothing flies or fires during the tutorial.

After calibration, throttle checks, the yoke overview and gun checks, centre the yoke, leave the throttle at 0%, and cover the gun tag. Flight starts **automatically after one steady second** with fresh tracking and a live picture. The aircraft starts stationary on the runway with the wheels down and zero throttle, including combat and paper modes; increase power and pitch up at takeoff speed. The ready message stays stable between packets. Losing tracking cancels the ready hold; each new Play repeats the checks.

The tutorial shows a fixed, mirrored camera view across the screen, with instructions near the centre and arrows for each movement. A labelled throttle rail diagram shows the direction toward 0% or 100%; the yoke overview explains how to turn, tilt and swivel. Detecting, raising, hiding or moving a tag never zooms or recentres the image. The screen uses a fixed aspect-fill fit, so a different window aspect ratio can trim the outer edges. The final ready screen shows both camera frames side by side; lost-yoke recovery fits the whole laptop frame in a small inset over the paused flight. All displayed camera views, including the Python window, are mirrored horizontally; text stays readable and tracking uses unchanged camera pixels. No camera frames are saved or uploaded.

Hold yoke tag 7 still for a second to centre; rotate like a steering wheel to bank, tilt forward/backward to pitch, and swivel the whole face left/right to yaw (rudder). Keep the grips level when swivelling. Space or C in the Python tracker window recentres it. The tutorial takes a fresh three-second neutral measurement before checking the throttle. **Settings** on the main menu or **Esc → Settings** has independent **Pitch**, **Bank** and **Yaw** sliders from **0.25× to 3.00×** in 0.05 increments. Defaults are pitch **1.2×**, bank **1.0×**, yaw **1.0×**. Changes apply immediately, save between launches, and Reset restores these defaults. Each slider also supports arrow keys after clicking it. Sensitivity updates the Python tracker live through a dedicated local settings connection. The tracker preview and game show the same adjusted input, with gain applied only once; all axes stay bounded at full input. Settings shows a live input meter and confirms when the tracker has applied the change. Physical input is also transmitted separately so game changes are immediate while an update is in flight, and the latest gains are restored after a tracker restart. Keyboard controls are unchanged. The informational yoke overview does not require any movement or sensitivity threshold. The three-second calibration also captures yaw neutral, and its countdown restarts if you swivel significantly. Physical lifting/lowering is not mapped to pitch. For measured camera geometry, see [camera lens calibration](camera-calibration.md).

Settings pairs each sensitivity slider with its own **Pitch agility**, **Bank agility** or **Yaw agility** slider (0.5×–3×, each default **1.3×**). Pitch agility changes nose up/down and vertical response, bank agility changes wing rotation and banked turns, and yaw agility changes rudder and ground steering speed. Existing shared agility preferences migrate to all three axes. Yoke sensitivity and thrust remain separate. **Auto-aim** (Off–3×, default **1.4×**) remains independent. Auto-aim scales the target acquisition/retention angles, locking speed and gun/reticle tracking. At 1.4×, acquire is 8.4° and retention is 10.5°. Changes save automatically; Reset restores all seven defaults. Combat clocks and encounters wait until the aircraft is airborne. Explicit landing practice still begins on final approach.

**Keyboard / mouse** on the main menu starts assisted flight without camera checks. For the optional throttle-only setup, run `./tools/tracker.sh --camera "iPhone (2) Camera" --throttle-only`, choose Keyboard / mouse, then press **C** and enable tracking. Arrow keys steer while camera throttle stays active; **W/S** takes over power and disables camera controls. The full Play tutorial requires the yoke and shooting tags too.

## Calibration and tracking loss

The three throttle tags are **self-referencing**: no manual idle/full capture and no saved image positions. All three must be visible in the same frame. Missing, duplicated, too-small or degenerate tags give zero throttle confidence and hold the exact current game power. If you move the slider from X to Y while a tag is hidden, power stays at X until all three tags return, then smoothly approaches Y. The game blends with a 0.25-second response and an 80-percentage-point/second cap, using a bounded time step so a long pause cannot create a jump. Throttle loss alone does not pause flight.

**Losing yoke tag 7 pauses flight and shooting in every yoke-control mode**, including normal `--stickers` gameplay. The paused flight remains visible behind a translucent warning, with a small mirrored camera inset to help you bring the yoke tag back into view. Flight resumes from the same position after half a second of continuous tracking; a brief reappearance does not resume it. Manual pause remains manual. Choose **USE KEYBOARD** to leave camera control if needed. The explicit Python `--throttle-only` mode does not require a yoke and does not trigger this screen.

The recovery camera inset stays local: the game opens `ws://127.0.0.1:8765/preview` while this screen is visible; the tutorial ready screen uses `/preview/all`. It receives at most 10 JPEG frames/second (up to 960×540); the whole image is fitted on screen so the edges remain visible. Brief missing frames keep the last picture for up to 700 ms from the last valid image, preventing flashes between video and the waiting screen. A sustained loss clears the image; camera-control freshness remains independent and still expires after 150 ms. No recording or upload is added. `--no-preview` hides the separate Python window but still permits the game's recovery view.

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
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --script res://tests/test_weapon_controls.gd
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --script res://tests/test_control_tutorial.gd -- --stickers --combat
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --script ../tools/test_relative_throttle_game.gd
.tools/Godot.app/Contents/MacOS/Godot --headless --path simulator --script ../tools/test_yoke_recovery_game.gd
```

Tests render real ArUco markers and cover 0/25/50/75/100% travel, clamping, rotation/scale/translation, perspective, missing/duplicate tags, smoothing, independent loss and the local WebSocket stream. The game integration check feeds a rendered 75% slider through the Python camera loop and socket into actual game throttle/engine physics. No physical camera is opened. Real cardboard feel, lighting and camera performance still need a hands-on check.

To inspect the existing simulated connection: `./tools/tracker.sh --simulate --loss-demo`. To regenerate print assets: `./tools/tracker.sh --markers vision/markers`.

Shooting tests cover ID 04, ignoring spare IDs, small overlaps, substantial covers, margins, duplicates, 24–60 pixel tags, dim/mirrored images, rearming, camera failure and socket timeouts. Game tests check actual gun counters, cooldowns, pause and covered-tag behavior with target lock.

The supplied photograph of the real 04 print is also a regression fixture, including reduced-size, rotated, mirrored, darker and JPEG-compressed variants, plus partial covers on each tag.

Perspective implementation reference: [OpenCV's planar homography tutorial](https://github.com/opencv/opencv/blob/4.x/doc/tutorials/features2d/homography/homography.markdown).

## Optional old single-camera cards

Only the explicit `vision/legacy_tracker.py --camera INDEX` command supports the old ID 7 / ID 23 endpoint-calibrated cards and `--check` placement report. It is not used by either default launcher or by `vision/tracker.py`. Its optional gun uses the same visible ID 4 / cover-to-stop behavior. The old desk-robustness and placement tests remain scoped to that module; the active tracker has separate pose guard, measured lens, relative-throttle, and dual-camera coverage.
