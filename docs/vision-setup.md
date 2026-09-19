# Optional cardboard camera controls

The native flight simulator works with keyboard and mouse by itself. This optional Python service tracks two printed ArUco markers and sends normalized controls locally. Camera images stay in memory on your computer; the service does not record or upload them. The webcam is opened only when you explicitly run a command containing `--camera`.

## Install once

Use Python 3.9–3.12. From the `cardboard-cockpit` project folder:

```sh
./tools/setup_vision.sh
```

This selects a supported Python interpreter (or uses installed `uv`) and installs the pinned dependencies without opening a camera. `./tools/tracker.sh` then runs the tracker with the correct environment. Manual installation also works:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r vision/requirements.txt
```

On this Mac, if `python3` reports an Xcode license/setup error, the verified developer-tools interpreter is available directly:

```sh
/Library/Developer/CommandLineTools/usr/bin/python3 -m venv .venv
.venv/bin/python -m pip install -r vision/requirements.txt
```

The installed `.venv` is local and ignored by Git. The tested dependency versions are pinned. Godot does not load or depend on them.

## Try the connection without a camera

```sh
.venv/bin/python vision/tracker.py --simulate --loss-demo
```

This sends a smooth, repeating test signal at `ws://127.0.0.1:8765`. Enable the simulator's vision input to see control values change. This is a connection test; the generated motions are not an autopilot or a mission-completion demonstration. In each 20-second cycle the yoke disappears during seconds 8–11 and the throttle disappears during seconds 13–16. Keyboard controls remain available.

For a bounded terminal-only check, add `--duration 5 --print-json`. Stop a long-running tracker with **Ctrl+C**. Running a second tracker on the same port produces an address-in-use message; stop the first process before restarting.

## Print and build

The ready-to-print files are in `vision/markers/`; open `vision/printable-cockpit.html` in a browser and print at **100% / actual size**, with headers and footers disabled. The yoke's black square must measure **70 mm** across, and the throttle's **50 mm**. Preserve the white margin, keep the paper flat, and use matte tape only outside the marker area.

To regenerate the originals without opening a webcam:

```sh
.venv/bin/python vision/tracker.py --markers vision/markers
```

The dictionary is `DICT_4X4_50`; **ID 7 is the yoke** and **ID 23 is the throttle**. Do not exchange them or display spare copies in the camera view. Follow the [cardboard build guide](cardboard-build-guide.md) for cut sizes and placement.

## Check the camera position first

Before calibrating, let the tracker measure what this camera position can actually see:

```sh
.venv/bin/python vision/tracker.py --camera 0 --check
```

Hold the yoke still for two seconds, bank fully left and right, tilt fully forward and back, slide the throttle from IDLE to FULL, then press **Q**. The terminal prints one PASS / WARN / FAIL line per item with the fix beside it: real frame rate, how often each marker was seen, marker size in pixels, yoke jitter at rest, sudden pitch flips, whether the pitch travel crosses the head-on angle, and how much of the image the throttle travels through. Nothing is saved or served while checking. `--check --no-preview --duration 15` runs the same measurement without a window. Move the camera or props and repeat until nothing says FAIL; that is much quicker than discovering a bad position halfway through calibration.

The most common WARN is **Pitch geometry**. A flat square marker seen exactly head-on has two mirrored pose solutions, so keep the yoke's whole pitch travel on one side of head-on: mount the webcam higher and aim it down, or lean the yoke's marker plate back 10–15° (top edge away from the camera). Leaning further than about 15° starts to cost detection range at the nose-up end, especially at 640×480.

## First camera run and calibration

Mount the webcam in front of the controls, about 70–100 cm away and 25–40 cm above the desk, angled slightly downward. A completely level camera looking directly along the throttle's travel cannot measure enough screen movement: raise it or shift it to the side. Keep both markers clearly visible and avoid bright windows behind the pilot. Marker faces point toward the webcam, not the pilot. The preview is intentionally **not mirrored**.

```sh
.venv/bin/python vision/tracker.py --camera 0 --calibrate
```

Allow your terminal to use the camera if macOS asks. If camera 0 is unavailable, close other camera apps or select another index explicitly, such as `--camera 1`. This service never probes camera devices without an explicit choice.

The tracker window walks through seven poses. For each, hold still for about a second and press **Space** while the tracker window has focus:

1. Neutral yoke: centered, hands comfortable, marker visible.
2. Full left roll, about 30–40°.
3. Full right roll, about 30–40°.
4. Tilt the top of the yoke forward, about 20–30°, for nose down.
5. Tilt the top of the yoke backward toward you, about 20–30°, for nose up.
6. Slide throttle to IDLE, nearest the pilot.
7. Slide throttle to FULL, away from the pilot.

At least 18 consecutive valid observations are required for a capture; the latest 24 are median-filtered. Wobbly captures, endpoints on the same side of neutral, and insufficient movement are rejected with an explanation. After success the terminal says **“Cockpit calibrated. Cleared for takeoff.”** and stores `vision/calibration.local.json`. The live tracker immediately begins producing usable controls. Re-center the yoke and set the throttle to idle before taking off.

Later runs load the saved calibration:

```sh
.venv/bin/python vision/tracker.py --camera 0
```

**Next pilot:** press **N** in the tracker preview, hold the yoke centered for a second, and press **Space**. This re-centers roll and pitch around the new pilot's natural grip and keeps the calibrated travel and throttle, so a handover takes two seconds rather than seven poses. It refuses shifts over 25°, which mean the camera or props moved: use **C** then.

Press **C** in the tracker preview to recalibrate; press **Q** or **Escape**, or close the window, to stop the service and release the camera. Recalibrate whenever the webcam or prop mounting moves. Changing camera index or actual frame dimensions requires recalibration. Use `--no-preview` only after calibration to keep the spectator display unobtrusive. A webcam or permission change requires stopping and restarting the service.

## Tuning and recovery

| Symptom | Action |
| --- | --- |
| Not sure what is wrong | Run `--camera 0 --check`; it measures each of the rows below and names the fix. |
| Marker remains LOST | Improve light; flatten the paper; move the camera closer; keep the whole white margin visible. Hands must not cover any corner. |
| Roll/pitch jitters | Try `--smoothing 0.16 --deadzone 0.09`; shorten the camera distance and avoid nearly edge-on yoke angles. |
| Pitch range fails calibration | Tilt the actual marker plane forward/backward, rather than translating the whole yoke. Keep each pose still. |
| Pitch occasionally flips or sticks at the nose-down end | The marker passes head-on to the lens there. Raise the camera or lean the marker plate back 10–15°, confirm with `--check`, then recalibrate. The tracker already holds its pose branch over time and discards solutions outside the calibrated travel, so what remains is geometry. |
| Throttle calibration fails | Raise or offset the webcam so the marker visibly travels at least 6% of the image; keep the grip from occluding it. |
| Tracker below 24 FPS | Increase diffuse light (webcams lengthen exposure in dim rooms), close other heavy apps, or use `--width 640 --height 480 --fps 24` and recalibrate. Size and confidence thresholds follow the frame width, so in good light 640×480 works out to the full 100 cm. |
| Markers become hidden | Yoke returns toward neutral after 250 ms. Throttle holds its last setting; take over with keyboard and show the marker again. |
| Service disconnects | Keyboard remains available. Restart the tracker and reselect vision in the simulator if needed. |

Default smoothing is 0.10 seconds and the yoke dead zone is 6%. The target capture rate is 30 FPS, with 24 and 25 also available. End-to-end latency and actual capture rate depend on the webcam, exposure, CPU load, and the receiving client. Confidence is a geometric quality indicator, not a calibrated probability.

## Verification and current limits

```sh
.venv/bin/python -m unittest discover -s vision/tests -v
```

Tests cover sign and range mapping, reversed mounting, angle wrapping, bad calibration rejection, seven-stage calibration, packet shape, clipping, smoothing, independent marker loss, synthetic marker detection, projected yoke pose, duplicate marker rejection, and a real loopback WebSocket service with two clients and reconnection. Synthetic tests do not open a webcam.

`vision/tests/test_physical_robustness.py` renders both markers at their printed size and distance through a pinhole camera (`vision/tests/synthetic.py`): grey background, paper-like contrast, sensor noise, dimness and blur. It covers the 50 mm throttle at 100 cm in 640×480, confidence at low resolution, a blurred throttle recovered near its last position, dim and very dim rooms without pitch bucking, the bounded cost of an absent marker, pose-branch selection, next-pilot re-centering, and every placement-check verdict including a full `--check` run on a fake camera. Detection first runs on a lightly denoised frame, which measured several times faster than the raw frame because sensor noise otherwise produces thousands of candidate contours; a marker that is still missing gets a sharpened and then a contrast-stretched second look around its last position.

The camera-mode pipeline is also exercised with rendered marker frames: detection → calibration/filtering → live WebSocket packets, independent marker loss, resolution-change rejection, preview closure, and capture cleanup. A fake camera supplies those frames; this is software coverage, not physical-camera validation.

The native receiver also has an integration check. From the repository root, run your Godot executable with:

```sh
Godot --headless --path simulator --script ../tools/test_vision_client.gd
```

This starts and stops its own simulated service on port 8765, so stop other tracker instances first. It checks 62 malformed payloads, receives changing controls in Godot, confirms yoke neutralization and preserved throttle after disconnect, reconnects to a restarted service, and checks that keyboard takeover clears active vision state. Godot may print an expected exponent warning for the deliberately invalid `1e999` test value. A passing run ends with `VISION INTEGRATION PASS` and exit status zero.

Physical webcam capture, lighting tolerance, cardboard feel, and sustained real-camera 24–30 FPS have **not** been validated on this build. The detector estimates relative pitch with approximate camera intrinsics; it is for arcade controls, not precise pose measurement. A single square marker can be ambiguous when nearly head-on, so final physical positioning and calibration still matter. No claim of a fully validated cardboard demonstration is made until two real markers visibly control the game.

Implementation references: [OpenCV's ArUco detection and pose tutorial](https://docs.opencv.org/4.11.0/d5/dae/tutorial_aruco_detection.html) and [the websockets asyncio server API](https://websockets.readthedocs.io/en/15.0/reference/asyncio/server.html).
