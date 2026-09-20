#!/usr/bin/env python3
"""Local ArUco tracker. A webcam is accessed only with an explicit --camera.

Run from the repository: .venv/bin/python vision/tracker.py --simulate
All received camera images remain in memory; nothing is recorded or uploaded.
"""
import argparse
import asyncio
import collections
import json
import math
from pathlib import Path
import statistics
import sys
import time

if __package__:
    from .calibration import (AxisCalibration, Calibration, ControlFilter, ThrottleCalibration,
                              ThrottleObservation, YokeObservation, clamp, simulated_calibration,
                              simulated_observations, wrap_degrees)
    from .placement import PlacementCheck, format_report
else:
    from calibration import (AxisCalibration, Calibration, ControlFilter, ThrottleCalibration,
                             ThrottleObservation, YokeObservation, clamp, simulated_calibration,
                             simulated_observations, wrap_degrees)
    from placement import PlacementCheck, format_report

# Change these IDs and regenerate BOTH markers if another booth uses the same IDs.
YOKE_ID = 7
THROTTLE_ID = 23
if __package__:
    from .weapon_switches import WeaponSwitches
else:
    from weapon_switches import WeaponSwitches

DEFAULT_CALIBRATION = Path(__file__).resolve().with_name("calibration.local.json")
PREVIEW_TITLE = "Cardboard Cockpit - private local tracker"
# Planar-pose branch tracking: smoothed reprojection-error advantage (pixels at a
# 64 px marker side) the other solution needs before pitch is allowed to jump to it.
BRANCH_EVIDENCE_RATE = 0.12
BRANCH_SWITCH_PIXELS = 0.15
BRANCH_MERGE_DEGREES = 8.0
PITCH_RANGE_MARGIN = 8.0


def load_cv():
    try:
        import cv2
        import numpy as np
    except ImportError as error:
        raise RuntimeError("Install camera packages: .venv/bin/python -m pip install -r vision/requirements.txt") from error
    if not hasattr(cv2, "aruco"):
        raise RuntimeError("OpenCV has no ArUco module. Install vision/requirements.txt in a fresh venv.")
    return cv2, np


def generate_markers(directory: Path) -> None:
    """Vector print masters plus PNG previews, with a full white quiet margin."""
    cv2, np = load_cv()
    dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
    directory.mkdir(parents=True, exist_ok=True)
    for marker_id, role, size_mm in ((YOKE_ID, "yoke", 70), (THROTTLE_ID, "throttle", 50), (31,"primary-on",35),(32,"primary-off",35),(41,"salvo-on",35),(42,"salvo-off",35)):
        # Six cells = four data cells + one-cell black border on each side.
        cells = cv2.aruco.generateImageMarker(dictionary, marker_id, 6)
        rects = ['<rect width="8" height="8" fill="white"/>']
        for y in range(6):
            for x in range(6):
                if cells[y, x] == 0:
                    rects.append('<rect x="%s" y="%s" width="1" height="1" fill="black"/>' % (x + 1, y + 1))
        outer_mm = size_mm * 8 / 6
        svg = '<svg xmlns="http://www.w3.org/2000/svg" width="%.3fmm" height="%.3fmm" viewBox="0 0 8 8" shape-rendering="crispEdges">\n%s\n</svg>\n' % (outer_mm, outer_mm, "\n".join(rects))
        stem = directory / ("%s-id-%s" % (role, marker_id))
        stem.with_suffix(".svg").write_text(svg, encoding="utf-8")
        preview = np.full((800, 800), 255, dtype=np.uint8)
        preview[100:700, 100:700] = cv2.aruco.generateImageMarker(dictionary, marker_id, 600)
        if not cv2.imwrite(str(stem.with_suffix(".png")), preview):
            raise RuntimeError("Could not write marker PNG.")
        print("%s: black marker square %s mm; print SVG at 100%%, keep white margin." % (stem, size_mm))


class ArucoTracker:
    """Estimate yoke orientation and a throttle's normalized image position.

    Approximate intrinsics are sufficient for relative arcade control. This is
    not metric pose measurement. Calibration absorbs camera mounting offsets.
    """
    def __init__(self, yoke_id: int = YOKE_ID, throttle_id: int = THROTTLE_ID):
        self.cv2, self.np = load_cv()
        self.yoke_id = yoke_id
        self.throttle_id = throttle_id
        dictionary = self.cv2.aruco.getPredefinedDictionary(self.cv2.aruco.DICT_4X4_50)
        parameters = self.cv2.aruco.DetectorParameters()
        parameters.cornerRefinementMethod = self.cv2.aruco.CORNER_REFINE_SUBPIX
        self.detector = self.cv2.aruco.ArucoDetector(dictionary, parameters)
        self.weapon_observations = {}
        self.previous_pose = None
        self.previous_pose_time = 0.0
        self.branch_evidence = 0.0
        self.last_corners = {}
        self.rescue_calls = 0
        # Optional (low, high) raw pitch degrees from calibration. The mirrored
        # planar-pose solution usually falls outside it and can be discarded.
        self.pitch_range = None

    def set_pitch_range(self, calibration) -> None:
        """Use a saved calibration's pitch endpoints as a prior. None clears it."""
        if calibration is None:
            self.pitch_range = None
            return
        axis = calibration.pitch
        ends = [axis.neutral + wrap_degrees(v - axis.neutral) for v in (axis.negative, axis.positive)]
        self.pitch_range = (min(ends) - PITCH_RANGE_MARGIN, max(ends) + PITCH_RANGE_MARGIN)

    def _outside_range(self, pitch: float) -> float:
        if self.pitch_range is None:
            return 0.0
        return max(self.pitch_range[0] - pitch, pitch - self.pitch_range[1], 0.0)

    def _choose_pose(self, candidates, now: float, side: float):
        """Pick one of the two planar-pose solutions without frame-to-frame flips.

        Each candidate is (error, roll, pitch, rvec, tvec). With a small or
        noisy marker the wrong solution often has the lower reprojection error
        in a single frame, so error alone makes pitch jump by 40+ degrees. The
        correct branch still wins on average: follow the previous branch and
        change only on sustained evidence or when the calibrated range says so.
        """
        best = min(candidates, key=lambda value: value[0])
        recent = self.previous_pose is not None and now - self.previous_pose_time < 0.4
        if len(candidates) == 1:
            self.branch_evidence = 0.0
            return best
        if not recent:
            self.branch_evidence = 0.0
            return min(candidates, key=lambda value: value[0] + 0.05 * self._outside_range(value[2]))
        stay = min(candidates, key=lambda value: abs(value[2] - self.previous_pose))
        other = candidates[1] if stay is candidates[0] else candidates[0]
        if abs(stay[2] - other[2]) < BRANCH_MERGE_DEGREES:
            # Near head-on both solutions agree; nothing to disambiguate.
            self.branch_evidence *= 1 - BRANCH_EVIDENCE_RATE
            return best
        # Reprojection error grows with marker size in pixels; compare it at a
        # reference 64 px side so one threshold serves every distance and resolution.
        advantage = (stay[0] - other[0]) * 64.0 / side
        self.branch_evidence += BRANCH_EVIDENCE_RATE * (advantage - self.branch_evidence)
        out_of_range = self._outside_range(stay[2]) > 0 and self._outside_range(other[2]) == 0
        if out_of_range or self.branch_evidence > BRANCH_SWITCH_PIXELS:
            self.branch_evidence = 0.0
            return other
        return stay

    def _detect_wanted(self, image, offset=(0.0, 0.0), scale: float = 1.0):
        """Map wanted marker ID -> 4x2 corners in frame pixels; None marks a duplicated ID."""
        corners, ids, _ = self.detector.detectMarkers(image)
        found = {}
        if ids is None:
            return found
        for marker_corners, marker_id in zip(corners, ids.flatten()):
            marker_id = int(marker_id)
            if marker_id not in (self.yoke_id, self.throttle_id) and marker_id not in WeaponSwitches.IDS:
                continue
            # Duplicated IDs are ambiguous; reject that control instead of
            # choosing whichever marker happens to be enumerated last.
            found[marker_id] = None if marker_id in found else marker_corners.reshape(4, 2) / scale + offset
        return found

    def _rescue(self, gray, marker_id: int, now: float):
        """Second chance for one missing marker, near where it was last seen.

        Measured on physically sized synthetic frames: sharpening recovers
        motion/defocus blur and small markers, contrast stretch recovers dark
        rooms, and both are harmful as a first pass because they amplify noise.
        Without a recent position the whole frame is searched only on every
        sixth call, so a permanently absent marker cannot cost the frame rate.
        """
        cv2, np = self.cv2, self.np
        height, width = gray.shape
        x0, y0, x1, y1 = 0, 0, width, height
        last = self.last_corners.get(marker_id)
        if last is not None and now - last[1] < 1.0:
            points = last[0]
            reach = 1.5 * float(max(points[:, 0].max() - points[:, 0].min(), points[:, 1].max() - points[:, 1].min()))
            x0, y0 = max(int(points[:, 0].min() - reach), 0), max(int(points[:, 1].min() - reach), 0)
            x1, y1 = min(int(points[:, 0].max() + reach), width), min(int(points[:, 1].max() + reach), height)
        else:
            self.rescue_calls += 1
            if self.rescue_calls % 6:
                return None
        crop = gray[y0:y1, x0:x1]
        if crop.shape[0] < 24 or crop.shape[1] < 24:
            return None
        # Small crops are doubled so a distant 50 mm marker keeps whole-pixel cells.
        scale = 2.0 if max(crop.shape) <= 360 else 1.0
        if scale != 1.0:
            crop = cv2.resize(crop, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
        sharpened = cv2.addWeighted(crop, 2.5, cv2.GaussianBlur(crop, (0, 0), 3 * scale), -1.5, 0)
        low, high = np.percentile(crop[::2, ::2], (1, 99))
        stretched = np.clip((crop.astype(np.float32) - low) * (255.0 / max(high - low, 8.0)), 0, 255).astype(np.uint8)
        for enhanced in (sharpened, cv2.GaussianBlur(stretched, (0, 0), 1.5 * scale)):
            points = self._detect_wanted(enhanced, (x0, y0), scale).get(marker_id)
            if points is not None:
                return points
        return None

    def detect(self, frame, now: float, draw: bool = True):
        cv2, np = self.cv2, self.np
        height, width = frame.shape[:2]
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        # Thresholds are tuned at 1280 px wide and follow the actual frame size.
        frame_scale = width / 1280.0
        # Light denoising first: sensor noise otherwise produces thousands of
        # candidate contours, which is both slower and less reliable in dim rooms.
        found = self._detect_wanted(cv2.GaussianBlur(gray, (0, 0), max(1.1 * frame_scale, 0.5)))
        for marker_id in (self.yoke_id, self.throttle_id):
            if marker_id not in found:
                points = self._rescue(gray, marker_id, now)
                if points is not None:
                    found[marker_id] = points
        seen = set(found)  # includes duplicated IDs, which still block their opposite switch tag
        found = {marker_id: points.astype(np.float32) for marker_id, points in found.items() if points is not None}
        yoke = throttle = None
        self.weapon_observations = {}
        if not found:
            return yoke, throttle
        if draw:
            cv2.aruco.drawDetectedMarkers(frame, [points.reshape(1, 4, 2) for points in found.values()],
                                          np.array([[marker_id] for marker_id in found], dtype=np.int32))
        # Approximate ~70-degree horizontal field of view. Recalibrate physical
        # ranges whenever camera placement, resolution or zoom changes.
        focal = width * 0.72
        matrix = np.array([[focal, 0, width / 2], [0, focal, height / 2], [0, 0, 1]], dtype=np.float64)
        distortion = np.zeros((5, 1), dtype=np.float64)
        if getattr(self,"lens",None) is not None:
            matrix=self.lens.camera_matrix(width,height)
            distortion=np.asarray(self.lens.distortion,dtype=np.float64)
        object_points = np.array([[-.5, .5, 0], [.5, .5, 0], [.5, -.5, 0], [-.5, -.5, 0]], dtype=np.float32)
        for key, points in found.items():
            if key not in WeaponSwitches.IDS:
                continue
            role, value = WeaponSwitches.IDS[key]
            other = 32 if key == 31 else 31 if key == 32 else 42 if key == 41 else 41
            side = float(min(np.linalg.norm(points[(i + 1) % 4] - points[i]) for i in range(4)))
            if other not in seen and side >= 24 * frame_scale:
                self.weapon_observations[role] = (value, clamp(side / (75 * frame_scale), .3, 1.0))
        for marker_id, points in found.items():
            if marker_id not in (self.yoke_id, self.throttle_id):
                continue
            side = float(min(np.linalg.norm(points[(i + 1) % 4] - points[i]) for i in range(4)))
            # The throttle needs only a centre, so it may be smaller than the
            # yoke, whose corners must also carry an orientation estimate.
            if side < (14 if marker_id == self.throttle_id else max(24 * frame_scale, 16)):
                continue
            self.last_corners[marker_id] = (points, now)
            confidence = clamp(side / (85 * frame_scale), 0.25, 1.0)
            center = points.mean(axis=0)
            if marker_id == self.throttle_id:
                throttle = ThrottleObservation((float(center[0] / width), float(center[1] / height)), confidence)
                if draw:
                    cv2.circle(frame, tuple(center.astype(int)), 5, (50, 210, 255), -1)
                continue
            # IPPE provides both planar pose solutions; _choose_pose keeps the
            # branch stable over time instead of trusting one frame's error.
            result = cv2.solvePnPGeneric(object_points, points, matrix, distortion, flags=cv2.SOLVEPNP_IPPE_SQUARE)
            if not result[0]:
                continue
            candidates = []
            for rvec, tvec in zip(result[1], result[2]):
                if float(tvec[2, 0]) <= 0:
                    continue
                projected, _ = cv2.projectPoints(object_points, rvec, tvec, matrix, distortion)
                error = float(np.sqrt(np.mean((projected.reshape(4, 2) - points) ** 2)))
                rotation, _ = cv2.Rodrigues(rvec)
                edge = points[1] - points[0]
                roll = math.degrees(math.atan2(float(edge[1]), float(edge[0])))
                # Local marker Y axis out-of-plane tilt, independent of image roll.
                pitch = math.degrees(math.asin(clamp(float(rotation[2, 1]), -1, 1)))
                candidates.append((error, roll, pitch, rvec, tvec))
            if not candidates:
                continue
            error, roll, pitch, rvec, tvec = self._choose_pose(candidates, now, side)
            if not math.isfinite(error) or error > 4.0:
                continue
            confidence *= clamp(1 - error / 6, 0, 1)
            self.previous_pose = pitch
            self.previous_pose_time = now
            rotation, _ = cv2.Rodrigues(rvec)
            normal = rotation[:, 2] * (1 if rotation[2, 2] >= 0 else -1)
            yaw = math.degrees(math.atan2(float(normal[0]), float(normal[2])))
            yoke = YokeObservation(roll, pitch, confidence, yaw=yaw)
            if draw:
                cv2.drawFrameAxes(frame, matrix, distortion, rvec, tvec, 0.6, 2)
        return yoke, throttle


class PaperController:
    """Single-marker yoke test using rotation and perspective tilt.

    The first stable second establishes neutral; space recenters. Rotation banks
    and forward/backward tilt pitches. Image translation is not an input.
    """
    def __init__(self):
        self.cv2, self.np = load_cv()
        parameters = self.cv2.aruco.DetectorParameters()
        parameters.cornerRefinementMethod = self.cv2.aruco.CORNER_REFINE_SUBPIX
        self.detector = self.cv2.aruco.ArucoDetector(
            self.cv2.aruco.getPredefinedDictionary(self.cv2.aruco.DICT_4X4_50), parameters)
        self.samples = collections.deque(maxlen=24)
        self.motion = collections.deque(maxlen=3)
        self.axis_active = [False, False]
        self.neutral = None
        self.message = "Show marker 7 and hold still for one second to center."

    def recenter(self):
        self.neutral = None
        self.samples.clear()
        self.motion.clear()
        self.axis_active = [False, False]

    def stable_axis(self, value, index, enter, leave, full):
        # Schmitt neutral zone: don't repeatedly change signs at rest.
        # Do not move the neutral anchor while the user is deliberately steering.
        if abs(value) <= leave:
            self.axis_active[index] = False
        elif abs(value) >= enter:
            self.axis_active[index] = True
        if not self.axis_active[index]:
            return 0.0
        return math.copysign(clamp((abs(value)-leave)/(full-leave), 0, 1), value)

    def map_observation(self, roll, tilt, confidence):
        if self.neutral is None:
            self.samples.append((roll, tilt))
            if len(self.samples) < 20:
                return None
            angles = [wrap_degrees(x[0] - self.samples[0][0]) for x in self.samples]
            heights = [x[1] for x in self.samples]
            if statistics.pstdev(angles) > 2 or statistics.pstdev(heights) > 2:
                self.message = "Hold marker 7 steady to center."
                return None
            self.neutral = (self.samples[0][0] + statistics.median(angles), statistics.median(heights))
            print("YOKE READY: centered marker 7; rotate to bank, tilt to pitch.", flush=True)
        # Camera sees the opposite face from the person holding the card.
        # Full steering at 20 degrees bank / 25 degrees tilt; preserve the
        # downstream calibrated output ranges and existing jitter filtering.
        self.motion.append((wrap_degrees(roll-self.neutral[0]), wrap_degrees(tilt-self.neutral[1])))
        bank_delta = statistics.median(x[0] for x in self.motion)
        pitch_delta = statistics.median(x[1] for x in self.motion)
        bank = -self.stable_axis(bank_delta, 0, 1.8, 1.0, 20) * 35
        pitch = self.stable_axis(pitch_delta, 1, 5.0, 3.0, 25) * 25
        self.message = "LIVE: rotate to bank; tilt top toward you to climb. SPACE centers."
        return YokeObservation(bank, pitch, confidence)

    def perspective_angles(self, points, width, height):
        cv, np = self.cv2, self.np
        # Decompose the signed projective square, not its bounding-box aspect
        # ratio. Intrinsics are approximate; this is a relative controller,
        # not a calibrated metric pose measurement.
        square = np.array([[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]], np.float32)
        h = cv.getPerspectiveTransform(square, points.astype(np.float32))
        focal = width * .72
        k = np.array([[focal,0,width/2],[0,focal,height/2],[0,0,1]],float)
        basis = np.linalg.solve(k,h)
        scale = 2 / (np.linalg.norm(basis[:,0])+np.linalg.norm(basis[:,1]))
        if basis[2,2] < 0: scale = -scale
        x, y = basis[:,0]*scale, basis[:,1]*scale
        u, _, vt = np.linalg.svd(np.column_stack((x,y,np.cross(x,y))))
        rotation = u @ np.diag([1,1,np.linalg.det(u @ vt)]) @ vt
        roll = math.degrees(math.atan2(rotation[1,0],rotation[0,0]))
        # The face normal does not depend on which way the sticker was taped
        # (including upside down). Positive: top away from camera/toward pilot.
        tilt = math.degrees(math.atan2(rotation[1,2],rotation[2,2]))
        return roll, tilt

    def detect(self, frame, now, draw=True):
        cv, np = self.cv2, self.np
        corners, ids, _ = self.detector.detectMarkers(frame)
        mirrored = False
        if ids is None or YOKE_ID not in ids:
            corners, ids, _ = self.detector.detectMarkers(cv.flip(frame, 1))
            mirrored = True
        if ids is None or list(ids.flatten()).count(YOKE_ID) != 1:
            self.samples.clear()
            self.motion.clear()
            self.axis_active = [False, False]
            self.message = "Marker 7 not visible - flight holds. Keep all four black corners clear."
            return None, None
        points = corners[list(ids.flatten()).index(YOKE_ID)].reshape(4, 2).copy()
        side = min(float(np.linalg.norm(points[(i + 1) % 4] - points[i])) for i in range(4))
        if side < 70:
            self.samples.clear()
            self.message = "Move marker 7 closer."
            return None, None
        try:
            roll, tilt = self.perspective_angles(points,frame.shape[1],frame.shape[0])
        except (ValueError, np.linalg.LinAlgError, cv.error):
            return None, None
        if not math.isfinite(tilt) or abs(tilt)>65:
            self.message = "Face marker toward camera; avoid edge-on angles."
            return None, None
        if mirrored:
            points[:, 0] = frame.shape[1] - 1 - points[:, 0]
        if draw:
            cv.polylines(frame, [points.astype(np.int32)], True, (60,240,90), 3)
        return self.map_observation(roll, tilt, clamp(side / 120, .4, 1)), None


class CameraSource:
    def __init__(self, camera_index: int, width: int, height: int, fps: int):
        # This is the only VideoCapture call in the project. Construction is
        # reachable only through the CLI's explicit --camera branch.
        self.cv2, _ = load_cv()
        self.capture = self.cv2.VideoCapture(camera_index)
        if not self.capture.isOpened():
            self.capture.release()
            raise RuntimeError("Cannot open camera %d. Close other camera apps and allow camera access for your terminal." % camera_index)
        self.capture.set(self.cv2.CAP_PROP_FRAME_WIDTH, width)
        self.capture.set(self.cv2.CAP_PROP_FRAME_HEIGHT, height)
        self.capture.set(self.cv2.CAP_PROP_FPS, fps)
        self.capture.set(self.cv2.CAP_PROP_BUFFERSIZE, 1)

    def read(self):
        ok, frame = self.capture.read()
        return frame if ok else None

    def close(self):
        self.capture.release()
        self.cv2.destroyAllWindows()


class CalibrationWizard:
    STEPS = (
        ("NEUTRAL", "Hold the yoke centered, marker facing camera.", "yoke"),
        ("LEFT", "Roll fully LEFT. Hold still.", "yoke"),
        ("RIGHT", "Roll fully RIGHT. Hold still.", "yoke"),
        ("FORWARD", "Tilt yoke FORWARD for nose down. Hold still.", "yoke"),
        ("BACKWARD", "Tilt yoke BACK toward you for nose up. Hold still.", "yoke"),
        ("IDLE", "Slide throttle to IDLE. Keep marker visible.", "throttle"),
        ("FULL", "Slide throttle to FULL. Keep marker visible.", "throttle"),
    )

    def __init__(self, camera_index: int, width: int, height: int, base=None):
        # With a base calibration only NEUTRAL is captured and the saved travel
        # is kept: a two-second handover between pilots instead of seven poses.
        self.base = base
        self.steps = self.STEPS if base is None else self.STEPS[:1]
        self.index = 0
        self.samples = collections.deque(maxlen=24)
        self.values = {}
        self.camera_index, self.width, self.height = camera_index, width, height
        self.message = "Hold still for a second, then press SPACE to capture."
        print("%s: %s" % ("Calibration" if base is None else "Re-center", self.STEPS[0][1]), flush=True)

    def observe(self, yoke, throttle):
        kind = self.STEPS[self.index][2]
        observation = yoke if kind == "yoke" else throttle
        if observation is None or observation.confidence < 0.4:
            self.samples.clear()
        elif kind == "yoke":
            self.samples.append((yoke.roll, yoke.pitch))
        else:
            self.samples.append(throttle.position)

    def capture(self):
        if len(self.samples) < 18:
            self.message = "Keep the active marker visible and still for one second."
            return None
        rows = tuple(zip(*self.samples))
        kind = self.STEPS[self.index][2]
        # Unwrap roll locally before taking a median near the +/-180 seam.
        if kind == "yoke":
            first = rows[0][0]
            rows = (tuple(first + wrap_degrees(x - first) for x in rows[0]), rows[1])
        threshold = 4.0 if kind == "yoke" else 0.015
        if any(statistics.pstdev(axis) > threshold for axis in rows):
            self.message = "Too much movement. Hold still, then press SPACE again."
            return None
        key = self.STEPS[self.index][0]
        self.values[key] = tuple(statistics.median(axis) for axis in rows)
        self.samples.clear()
        self.index += 1
        if self.base is not None:
            self.index = 0
            try:
                return self.base.recentered(*self.values["NEUTRAL"])
            except ValueError as error:
                self.message = str(error)
                return None
        if self.index < len(self.STEPS):
            self.message = "Captured %s. Hold next position, then press SPACE." % key
            print("Calibration: " + self.STEPS[self.index][1], flush=True)
            return None
        try:
            result = Calibration(
                AxisCalibration(self.values["LEFT"][0], self.values["NEUTRAL"][0], self.values["RIGHT"][0]),
                AxisCalibration(self.values["FORWARD"][1], self.values["NEUTRAL"][1], self.values["BACKWARD"][1]),
                ThrottleCalibration(self.values["IDLE"], self.values["FULL"]),
                self.camera_index, self.width, self.height,
            )
            result.validate()
            return result
        except ValueError as error:
            self.message = str(error)
            print("Calibration needs another try: " + self.message, flush=True)
            self.index = 0
            self.values.clear()
            return None


def draw_preview(frame, packet, wizard, fps: float):
    cv2, _ = load_cv()
    cv2.rectangle(frame, (0, 0), (frame.shape[1], 150 if wizard else 122), (26, 30, 32), -1)
    if wizard:
        title, instruction, _ = wizard.steps[wizard.index]
        heading = "RE-CENTER FOR NEW PILOT" if wizard.base is not None else "CALIBRATION %d/7 - %s" % (wizard.index + 1, title)
        lines = [heading, instruction,
                 wizard.message, "SPACE: capture  |  Q / ESC: quit  |  %d/18 samples" % len(wizard.samples)]
    else:
        yoke, throttle = packet["yoke"], packet["throttle"]
        lines = ["CARDBOARD COCKPIT  |  %.1f FPS  |  local camera only" % fps,
                 "YOKE %s  ROLL %+.2f  PITCH %+.2f" % ("TRACKED" if yoke["confidence"] else "LOST", yoke["roll"], yoke["pitch"]),
                 "THROTTLE %3.0f%% %s  |  N: new pilot  C: calibrate  Q: quit" % (throttle["value"] * 100, "TRACKED" if throttle["confidence"] else "HOLDING / LOST")]
    draw_lines(frame, lines)


def draw_lines(frame, lines):
    cv2, _ = load_cv()
    for index, line in enumerate(lines):
        cv2.putText(frame, line, (18, 28 + index * 32), cv2.FONT_HERSHEY_SIMPLEX, .62,
                    (115, 226, 247) if index == 0 else (235, 239, 240), 1, cv2.LINE_AA)
    cv2.imshow(PREVIEW_TITLE, frame)


def run_check(args) -> int:
    """Measure what this camera position can see; no socket, nothing saved."""
    detector = ArucoTracker()
    source = CameraSource(args.camera, args.width, args.height, args.fps)
    check = None
    # Without a window nobody can press Q, so a headless check is always bounded.
    duration = args.duration if args.duration > 0 else (15.0 if args.no_preview else 0.0)
    print("Placement check: hold the yoke still for two seconds, then bank fully left and right, tilt fully forward and back, slide the throttle "
          "IDLE to FULL, then %s." % ("wait %.0f s" % duration if args.no_preview else "press Q"), flush=True)
    try:
        start = time.monotonic()
        while duration <= 0 or time.monotonic() - start < duration:
            frame_start = time.monotonic()
            frame = source.read()
            if frame is None:
                if frame_start - start > 3 and check is None:
                    raise RuntimeError("Camera %d opened but delivers no frames." % args.camera)
                time.sleep(0.02)
                continue
            if check is None:
                check = PlacementCheck(frame.shape[1])
            yoke, throttle = detector.detect(frame, frame_start, not args.no_preview)
            sides = {}
            for marker_id, (points, seen) in detector.last_corners.items():
                if seen == frame_start:
                    sides[marker_id] = float(min(math.dist(points[i], points[(i + 1) % 4]) for i in range(4)))
            check.add(frame_start, yoke, throttle, sides.get(detector.yoke_id), sides.get(detector.throttle_id))
            if not args.no_preview:
                detector.cv2.rectangle(frame, (0, 0), (frame.shape[1], 122), (26, 30, 32), -1)
                draw_lines(frame, check.live_lines())
                key = detector.cv2.waitKey(1) & 0xFF
                try:
                    closed = detector.cv2.getWindowProperty(PREVIEW_TITLE, detector.cv2.WND_PROP_VISIBLE) < 1
                except detector.cv2.error:
                    closed = True
                if closed or key in (27, ord("q")):
                    break
            time.sleep(max(0.0, 1.0 / args.fps - (time.monotonic() - frame_start)))
    finally:
        source.close()
    rows = check.report() if check else [("FAIL", "Frames", "No camera frames arrived.")]
    print(format_report(rows), flush=True)
    return 1 if any(row[0] == "FAIL" for row in rows) else 0


async def run(args):
    try:
        from websockets.asyncio.server import serve
        from websockets.exceptions import ConnectionClosed
    except ImportError as error:
        raise RuntimeError("Install WebSockets: .venv/bin/python -m pip install -r vision/requirements.txt") from error

    source = detector = wizard = None
    calibration = simulated_calibration()
    if args.camera is not None:
        detector = PaperController() if args.paper_test else ArucoTracker()
        if args.paper_test:
            args.calibrate = False
            # Relative image-space units, not a fabricated saved physical calibration.
            calibration = Calibration(AxisCalibration(-35,0,35), AxisCalibration(-25,0,25),
                                      ThrottleCalibration((.75,.8),(.75,.4)))
        elif args.calibration.exists() and not args.calibrate:
            calibration = Calibration.load(args.calibration)
            if calibration.camera_index != args.camera:
                print("Camera settings changed. Recalibration is required.", flush=True)
                args.calibrate = True
        else:
            args.calibrate = True
        if args.calibrate and args.no_preview:
            raise RuntimeError("Calibration needs its window. Remove --no-preview for the first run.")
        if args.calibrate:
            wizard = CalibrationWizard(args.camera, args.width, args.height)
        elif not args.paper_test:
            detector.set_pitch_range(calibration)
        source = CameraSource(args.camera, args.width, args.height, args.fps)

    controller = ControlFilter(calibration, args.smoothing, args.deadzone)
    weapon_switches = WeaponSwitches()
    clients = set()

    async def handler(connection):
        # Each client has a one-packet queue: slow consumers never build a stale
        # control backlog and never delay capture or other receivers.
        queue = asyncio.Queue(maxsize=1)
        clients.add(queue)

        async def sender():
            while True:
                await connection.send(await queue.get())

        async def receiver():
            async for _ in connection:
                await connection.close(1008, "Read-only control stream")
                return

        tasks = [asyncio.create_task(sender()), asyncio.create_task(receiver())]
        try:
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        except ConnectionClosed:
            pass
        finally:
            clients.discard(queue)
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    try:
        async with serve(handler, "127.0.0.1", args.port, origins=[None], max_size=1024,
                         max_queue=2, compression=None, close_timeout=1):
            print("Cardboard controls: ws://127.0.0.1:%d [%s]" % (args.port, "SIMULATED" if args.simulate else "CAMERA"), flush=True)
            print("Ctrl+C to stop. No images are sent to the game or saved.", flush=True)
            start = previous = time.monotonic()
            frame_number = 0
            fps_estimate = float(args.fps)
            failure_count = 0
            checked_frame_size = False
            while args.duration <= 0 or time.monotonic() - start < args.duration:
                frame_start = time.monotonic()
                frame = None
                if args.simulate:
                    yoke, throttle = simulated_observations(frame_number, args.fps, args.loss_demo)
                else:
                    # Capture can block briefly; keep socket handshakes alive.
                    frame = await asyncio.to_thread(source.read)
                    if frame is None:
                        yoke = throttle = None
                        failure_count += 1
                        if failure_count in (1, args.fps * 3):
                            print("No camera frame. Yoke will neutralize; throttle holds. Use keyboard or restart the tracker.", file=sys.stderr, flush=True)
                    else:
                        failure_count = 0
                        if not checked_frame_size:
                            checked_frame_size = True
                            if not args.paper_test and not wizard and (frame.shape[1], frame.shape[0]) != (calibration.width, calibration.height):
                                if args.no_preview:
                                    raise RuntimeError("Camera resolution changed. Restart without --no-preview to recalibrate.")
                                print("Camera resolution changed. Recalibration is required.", flush=True)
                                wizard = CalibrationWizard(args.camera, frame.shape[1], frame.shape[0])
                                detector.set_pitch_range(None)
                        if wizard:
                            wizard.width, wizard.height = frame.shape[1], frame.shape[0]
                        yoke, throttle = detector.detect(frame, frame_start, not args.no_preview)
                if wizard:
                    wizard.observe(yoke, throttle)
                    yoke = throttle = None
                packet = controller.step(time.monotonic(), int(time.time() * 1000), yoke, throttle)
                weapons = weapon_switches.step(getattr(detector,"weapon_observations",{}) if frame is not None and not wizard else {}, time.monotonic())
                if weapon_switches.configured and not wizard:
                    packet['weapons'] = weapons
                serialized = json.dumps(packet, allow_nan=False, separators=(",", ":"))
                for queue in tuple(clients):
                    if queue.full():
                        queue.get_nowait()
                    queue.put_nowait(serialized)
                if args.print_json:
                    print(serialized, flush=True)
                if frame is not None and not args.no_preview:
                    interval = max(frame_start - previous, 0.001)
                    fps_estimate += .08 * ((1.0 / interval) - fps_estimate)
                    draw_preview(frame, packet, wizard, fps_estimate)
                    if args.paper_test:
                        detector.cv2.rectangle(frame, (0,0), (frame.shape[1],122), (26,30,32), -1)
                        for row, line in enumerate(["YOKE CONTROLLER - ID 7 - KEEP OPEN WHILE PLAYING", detector.message,
                                "BANK %+.2f  PITCH %+.2f   |   Q quits" % (packet["yoke"]["roll"], packet["yoke"]["pitch"]) ]):
                            detector.cv2.putText(frame,line,(16,28+row*33),detector.cv2.FONT_HERSHEY_SIMPLEX,.55,(110,240,160),1,detector.cv2.LINE_AA)
                        detector.cv2.imshow(PREVIEW_TITLE,frame)
                    key = detector.cv2.waitKey(1) & 0xFF
                    if key in (27, ord("q")):
                        break
                    # Closing the native window is also an explicit stop. Do
                    # not silently reopen it and keep the webcam running.
                    try:
                        if detector.cv2.getWindowProperty(PREVIEW_TITLE, detector.cv2.WND_PROP_VISIBLE) < 1:
                            break
                    except detector.cv2.error:
                        # Some backends destroy the window before it can be queried.
                        break
                    if args.paper_test and key in (32, ord("c")):
                        detector.recenter()
                    elif not args.paper_test and key == ord("c"):
                        wizard = CalibrationWizard(args.camera, frame.shape[1], frame.shape[0])
                        detector.set_pitch_range(None)
                    elif key == ord("n") and not wizard and not args.paper_test:
                        wizard = CalibrationWizard(args.camera, frame.shape[1], frame.shape[0], base=controller.calibration)
                    elif key == 32 and wizard:
                        calibrated = wizard.capture()
                        if calibrated is not None:
                            calibrated.save(args.calibration)
                            # Keep sequence monotonic and throttle safe across calibration.
                            next_controller = ControlFilter(calibrated, args.smoothing, args.deadzone)
                            next_controller.sequence = controller.sequence
                            next_controller.throttle = controller.throttle
                            controller = next_controller
                            detector.set_pitch_range(calibrated)
                            print("%s Cleared for takeoff. Saved to %s" % (
                                "Re-centered for the new pilot." if wizard.base is not None else "Cockpit calibrated.",
                                args.calibration), flush=True)
                            wizard = None
                previous = frame_start
                frame_number += 1
                await asyncio.sleep(max(0.0, 1.0 / args.fps - (time.monotonic() - frame_start)))
    finally:
        if source:
            source.close()


def parser():
    result = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = result.add_mutually_exclusive_group(required=True)
    mode.add_argument("--simulate", action="store_true", help="Serve deterministic controls without opening a camera")
    mode.add_argument("--camera", type=int, metavar="INDEX", help="Explicitly open this webcam, usually 0")
    mode.add_argument("--markers", type=Path, metavar="DIRECTORY", help="Generate printable marker SVG/PNG files; no camera")
    result.add_argument("--calibrate", action="store_true", help="Run the seven-step calibration before camera control")
    result.add_argument("--paper-test", action="store_true", help="Control with marker 7 only: auto-center, rotate to bank, tilt to pitch; no throttle marker")
    result.add_argument("--check", action="store_true", help="Measure camera placement and print PASS/WARN/FAIL advice; serves no controls")
    result.add_argument("--calibration", type=Path, default=DEFAULT_CALIBRATION)
    result.add_argument("--no-preview", action="store_true", help="Hide camera/debug window after calibration")
    result.add_argument("--print-json", action="store_true", help="Print every normalized packet for inspection")
    result.add_argument("--loss-demo", action="store_true", help="In simulated mode, hide yoke at 8-11s and throttle at 13-16s per 20s cycle")
    result.add_argument("--port", type=int, default=8765)
    result.add_argument("--fps", type=int, choices=(24, 25, 30), default=30)
    result.add_argument("--width", type=int, default=1280)
    result.add_argument("--height", type=int, default=720)
    result.add_argument("--smoothing", type=float, default=.10, metavar="SECONDS")
    result.add_argument("--deadzone", type=float, default=.06, metavar="FRACTION")
    result.add_argument("--duration", type=float, default=0, metavar="SECONDS", help="Stop after a duration; 0 runs until quit")
    return result


def main():
    argument_parser = parser()
    args = argument_parser.parse_args()
    if not 1 <= args.port <= 65535 or args.width < 320 or args.height < 240 or args.duration < 0:
        argument_parser.error("Invalid port, frame dimensions, or duration.")
    if not math.isfinite(args.duration) or not 0.01 <= args.smoothing <= 2 or not 0 <= args.deadzone < 0.5:
        argument_parser.error("Use finite duration, smoothing in [0.01, 2], and deadzone in [0, 0.5).")
    if args.camera is not None and args.camera < 0:
        argument_parser.error("Camera index cannot be negative.")
    if args.calibrate and args.camera is None:
        argument_parser.error("--calibrate requires an explicit --camera INDEX.")
    if args.paper_test and (args.camera is None or args.calibrate or args.no_preview):
        argument_parser.error("--paper-test needs --camera and its preview; omit --calibrate.")
    if args.check and (args.camera is None or args.calibrate):
        argument_parser.error("--check requires --camera INDEX and cannot be combined with --calibrate.")
    if args.loss_demo and not args.simulate:
        argument_parser.error("--loss-demo requires --simulate.")
    try:
        if args.markers is not None:
            generate_markers(args.markers)
        elif args.check:
            return run_check(args)
        else:
            asyncio.run(run(args))
    except KeyboardInterrupt:
        print("\nTracker stopped. Keyboard flight remains available.")
    except (RuntimeError, ValueError, OSError) as error:
        print("Tracker: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
