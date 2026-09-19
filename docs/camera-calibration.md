# Calibrate the camera for yoke ID 7

The yoke still needs only **one rigid, visible tag: ID 7**. This measures the
camera's lens geometry so a translated tag is less likely to look tilted.
It is separate from centering the yoke with Space/C and does not use LiDAR.

## What changed

- A guided checkerboard capture measures focal lengths, the image centre and
  five distortion coefficients. It saves numeric values, never camera images.
- The tracker can load that profile with `--intrinsics`. Paper mode corrects
  tag corners before calculating orientation; the manually calibrated mode
  passes measured camera parameters into its pose solver.
- A sudden angle jump requires three consistent observations before it is
  accepted. Ordinary continuous motion passes immediately. Existing median
  filtering, neutral dead zones and output smoothing remain in place.
- The preview says **LENS CALIBRATED** or **LENS APPROXIMATE**. An explicitly
  requested invalid profile fails instead of silently using guessed values.
  Camera-index or actual-frame-size mismatches are rejected.

## One-time physical capture

1. Print [the checkerboard](../vision/camera-checkerboard.svg) in **landscape**
   on A4 or Letter, preserving its white border. It has 10 by 7 squares and
   9 by 6 internal intersections. Mount it flat on rigid cardboard. Uniform
   print scaling is fine for lens calibration; do not stretch just one axis.
   The checkerboard is only a temporary setup target, not an extra yoke tag.
2. Stop the running tracker with Q so the camera is free. Use the same iPhone
   rear camera, lens, resolution and zoom you will play with. Turn off automatic
   framing/Center Stage, Portrait blur and other geometric/background effects.
3. From the repository folder, start the calibration tool. **Replace `1` with
   the camera index that shows your iPhone feed**; indices can change when
   devices reconnect.

   ```sh
   ./tools/tracker.sh --camera 1 --calibrate-lens --intrinsics vision/iphone.lens.local.json
   ```

4. Hold the board still and press **Space** for each capture. Collect **20–25
   views** (minimum 15): move it left/right, up/down, nearer/farther, and tilt
   it in both directions. Keep the complete board in view. Repeated positions
   and boards that appear too small are rejected.
5. Press **Enter** to calculate and save. The tool checks view coverage, tilt
   variety and reprojection error. If it asks for more variety, capture more
   positions. **R** resets the samples; **Q** cancels without changing a file.

The target can be regenerated without opening a camera:

```sh
./tools/tracker.sh --checkerboard vision/camera-checkerboard.svg
```

## Play with measured camera parameters

```sh
./tools/tracker.sh --camera 1 --paper-test --intrinsics vision/iphone.lens.local.json
```

Confirm **LENS CALIBRATED**, then hold tag 7 steady to centre as before. Keep
the camera fixed. Physically raise/lower the yoke without changing its angle:
pitch should remain near neutral. Tilt it deliberately to command pitch.

Profiles are explicit rather than automatically chosen. The index/frame-size
checks cannot detect swapping cameras at the same index or changing digital
zoom. Use the correct named profile and recalibrate when the camera, lens,
crop/zoom or capture resolution changes. If the camera negotiates a different
size, use `--width`/`--height` matching the dimensions printed at calibration.
Lens profiles named `vision/*.lens.local.json` are ignored by Git.

Without `--intrinsics`, the existing approximate camera model remains
available and is clearly labelled. A profile from synthetic tests is not a
measurement of your actual iPhone and must not be used for play.

## Verification and limits

Software tests cover recovery of camera parameters from varied checkerboard
poses, corrected orientation under translation/depth changes and lens
distortion, mirrored frames, bad profile rejection, camera mismatch, cancelled
capture cleanup, isolated pose spikes, sustained movement and reacquisition.

Physical calibration and before/after play testing are still required. One
small planar tag remains sensitive to blur, paper bending, shallow viewing
angles and corner-detection noise. Lens calibration reduces model error; it
does not eliminate those sources of uncertainty. The relative throttle and
the game control packet format are unchanged by this camera calibration work.

Method: [OpenCV camera calibration tutorial](https://github.com/opencv/opencv/blob/4.x/doc/py_tutorials/py_calib3d/py_calibration/py_calibration.markdown).
