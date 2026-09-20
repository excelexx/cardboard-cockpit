#!/usr/bin/env python3
"""Local ArUco tracker. A webcam is accessed only with an explicit --camera.

Run from the repository: .venv/bin/python vision/tracker.py --simulate
Camera images remain in memory. A local preview is available to the game on
/preview for yoke recovery and /preview/<control> for the preflight tutorial.
Nothing is recorded or uploaded.
"""
import argparse
import asyncio
import collections
from dataclasses import replace
import json
import math
from pathlib import Path
import statistics
import sys
import time

if __package__:
    from .control_settings import ControlSettings
    from .neutral_calibration import NeutralCalibration
    from .camera_devices import camera_argument, list_cameras, resolve_camera
    from .background_camera import BackgroundCamera
    from .camera_calibration import LensProfile, run_lens_calibration, write_checkerboard
    from .pose_guard import PoseGuard
    from .preview_framer import PreviewFramer
    from .weapon_tags import WeaponTags, GUN_ID
    from .relative_throttle import RelativeThrottle, THROTTLE_IDLE_ID, THROTTLE_ID, THROTTLE_FULL_ID
    from .calibration import (AxisCalibration, Calibration, ControlFilter, ThrottleCalibration,
                              YokeObservation, clamp, simulated_calibration,
                              simulated_observations, wrap_degrees)
else:
    from control_settings import ControlSettings
    from neutral_calibration import NeutralCalibration
    from camera_devices import camera_argument, list_cameras, resolve_camera
    from background_camera import BackgroundCamera
    from camera_calibration import LensProfile, run_lens_calibration, write_checkerboard
    from pose_guard import PoseGuard
    from preview_framer import PreviewFramer
    from weapon_tags import WeaponTags, GUN_ID
    from relative_throttle import RelativeThrottle, THROTTLE_IDLE_ID, THROTTLE_ID, THROTTLE_FULL_ID
    from calibration import (AxisCalibration, Calibration, ControlFilter, ThrottleCalibration,
                             YokeObservation, clamp, simulated_calibration,
                             simulated_observations, wrap_degrees)

# Yoke stays separate from the relative throttle IDs 0, 1 and 2.
YOKE_ID = 7
DEFAULT_CALIBRATION = Path(__file__).resolve().with_name("calibration.local.json")
PREVIEW_TITLE = "Cardboard Cockpit - private local tracker"


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
    for marker_id, role, size_mm in ((YOKE_ID, "yoke", 70), (THROTTLE_IDLE_ID, "throttle-idle", 30),
                                     (THROTTLE_ID, "throttle", 30), (THROTTLE_FULL_ID, "throttle-full", 30),
                                     (GUN_ID, "gun", 40)):
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
    """Estimate yoke orientation and throttle position relative to live tags 0/2.

    Supply a measured LensProfile to correct camera geometry. Without one,
    the legacy approximate camera model remains available for quick testing.
    """
    def __init__(self, yoke_id: int = YOKE_ID, lens=None):
        self.cv2, self.np = load_cv()
        self.lens = lens
        self.pose_guard = PoseGuard()
        self.yoke_id = yoke_id
        if yoke_id in (THROTTLE_IDLE_ID, THROTTLE_ID, THROTTLE_FULL_ID):
            raise ValueError("Yoke ID must differ from throttle IDs 0, 1 and 2.")
        self.throttle = RelativeThrottle(self.cv2, self.np)
        dictionary = self.cv2.aruco.getPredefinedDictionary(self.cv2.aruco.DICT_4X4_50)
        parameters = self.cv2.aruco.DetectorParameters()
        parameters.cornerRefinementMethod = self.cv2.aruco.CORNER_REFINE_SUBPIX
        self.detector = self.cv2.aruco.ArucoDetector(dictionary, parameters)
        self.previous_pose = None
        self.previous_pose_time = 0.0

    def detect(self, frame, now: float, draw: bool = True):
        cv2, np = self.cv2, self.np
        height, width = frame.shape[:2]
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        corners, ids, _ = self.detector.detectMarkers(gray)
        yoke = None
        throttle = self.throttle.observe(corners, ids, frame if draw else None)
        if ids is None:
            return yoke, throttle
        if draw:
            cv2.aruco.drawDetectedMarkers(frame, corners, ids)
        # Approximate ~70-degree horizontal field of view. Recalibrate physical
        # ranges whenever camera placement, resolution or zoom changes.
        focal = width * 0.72
        matrix = np.array([[focal, 0, width / 2], [0, focal, height / 2], [0, 0, 1]], dtype=np.float64)
        distortion = np.zeros((5, 1), dtype=np.float64)
        if self.lens is not None:
            matrix = self.lens.camera_matrix(width, height)
            distortion = np.asarray(self.lens.distortion, dtype=np.float64)
        object_points = np.array([[-.5, .5, 0], [.5, .5, 0], [.5, -.5, 0], [-.5, -.5, 0]], dtype=np.float32)
        # Duplicated IDs are ambiguous; reject that control instead of choosing
        # whichever marker happens to be enumerated last.
        counts = collections.Counter(int(marker_id) for marker_id in ids.flatten())
        for marker_corners, marker_id in zip(corners, ids.flatten()):
            marker_id = int(marker_id)
            if counts[marker_id] != 1 or marker_id != self.yoke_id:
                continue
            points = marker_corners.reshape(4, 2)
            side = float(min(np.linalg.norm(points[(i + 1) % 4] - points[i]) for i in range(4)))
            if side < 24:
                continue
            confidence = clamp(side / 85, 0.25, 1.0)
            # IPPE provides both planar pose solutions; prioritize reprojection
            # error, with a small continuity preference near ambiguous head-on views.
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
                continuity = 0.0
                if self.previous_pose is not None and now - self.previous_pose_time < 0.4:
                    continuity = min(abs(wrap_degrees(pitch - self.previous_pose)), 45) * 0.01
                candidates.append((error + continuity, error, roll, pitch, rvec, tvec))
            if not candidates:
                continue
            _, error, roll, pitch, rvec, tvec = min(candidates, key=lambda value: value[0])
            rotation, _ = cv2.Rodrigues(rvec)
            if not math.isfinite(error) or error > 4.0:
                continue
            normal = rotation[:, 2] * (1 if rotation[2, 2] >= 0 else -1)
            yaw = math.degrees(math.atan2(float(normal[0]), float(normal[2])))
            if abs(yaw) > 65 or not self.pose_guard.accept((roll, pitch, yaw), now):
                continue
            confidence *= clamp(1 - error / 6, 0, 1)
            self.previous_pose = pitch
            self.previous_pose_time = now
            yoke = YokeObservation(roll, pitch, confidence, yaw=yaw)
            if draw:
                cv2.drawFrameAxes(frame, matrix, distortion, rvec, tvec, 0.6, 2)
        return yoke, throttle


class PaperController:
    """Single-marker yoke test using rotation and perspective tilt.

    The first stable second establishes neutral; space recenters. Rotation banks
    and forward/backward tilt pitches. Image translation is not an input.
    """
    def __init__(self, lens=None):
        self.lens = lens
        self.pose_guard = PoseGuard()
        self.cv2, self.np = load_cv()
        parameters = self.cv2.aruco.DetectorParameters()
        parameters.cornerRefinementMethod = self.cv2.aruco.CORNER_REFINE_SUBPIX
        self.detector = self.cv2.aruco.ArucoDetector(
            self.cv2.aruco.getPredefinedDictionary(self.cv2.aruco.DICT_4X4_50), parameters)
        self.throttle = RelativeThrottle(self.cv2, self.np)
        self.samples = collections.deque(maxlen=24)
        self.motion = collections.deque(maxlen=3)
        self.axis_active = [False, False, False]
        self.neutral = None
        self.yaw_neutral = 0.0
        self.raw_observation = None
        self.message = "Show the yoke tag and hold still for one second to center."

    def recenter(self):
        self.pose_guard.reset()
        self.neutral = None
        self.samples.clear()
        self.motion.clear()
        self.axis_active = [False, False, False]
        self.yaw_neutral = 0.0

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

    def map_observation(self, roll, tilt, confidence, yaw=0.0):
        if self.neutral is None:
            self.samples.append((roll, tilt, yaw))
            if len(self.samples) < 20:
                return None
            angles = [wrap_degrees(x[0] - self.samples[0][0]) for x in self.samples]
            heights = [x[1] for x in self.samples]
            swivels = [wrap_degrees(x[2]-self.samples[0][2]) for x in self.samples]
            if any(statistics.pstdev(values) > 2 for values in (angles, heights, swivels)):
                self.message = "Hold the yoke tag steady to center."
                return None
            self.neutral = (self.samples[0][0] + statistics.median(angles), statistics.median(heights))
            self.yaw_neutral = wrap_degrees(self.samples[0][2] + statistics.median(swivels))
            print("YOKE READY: rotate to bank, tilt to pitch, swivel to yaw.", flush=True)
        # Camera sees the opposite face from the person holding the card.
        # Full steering at 20 degrees bank / 25 degrees tilt; preserve the
        # downstream calibrated output ranges and existing jitter filtering.
        self.motion.append((wrap_degrees(roll-self.neutral[0]), wrap_degrees(tilt-self.neutral[1]), wrap_degrees(yaw-self.yaw_neutral)))
        bank_delta = statistics.median(x[0] for x in self.motion)
        pitch_delta = statistics.median(x[1] for x in self.motion)
        yaw_delta = statistics.median(x[2] for x in self.motion)
        bank = -self.stable_axis(bank_delta, 0, 1.8, 1.0, 20) * 35
        pitch = self.stable_axis(pitch_delta, 1, 5.0, 3.0, 25) * 25
        rudder = self.stable_axis(yaw_delta, 2, 4.0, 2.5, 25) * 25
        self.message = "LIVE: rotate = bank; tilt = pitch; swivel = yaw. SPACE centers."
        return YokeObservation(bank, pitch, confidence, yaw=rudder)

    def perspective_angles(self, points, width, height, mirrored=False):
        return self.orientation_angles(points, width, height, mirrored)[:2]

    def orientation_angles(self, points, width, height, mirrored=False):
        cv, np = self.cv2, self.np
        # Lens correction precedes the rigid-plane decomposition. Translation
        # in the image is never itself a pitch command.
        focal = width * .72
        k = np.array([[focal,0,width/2],[0,focal,height/2],[0,0,1]],float)
        points = np.asarray(points, dtype=np.float64).copy()
        if self.lens is not None:
            k = self.lens.camera_matrix(width, height).copy()
            if mirrored:
                # Fallback detection happens on a flipped frame. Undistort in
                # the original calibrated pixel coordinates before flipping back.
                points[:, 0] = width - 1 - points[:, 0]
            points = self.lens.undistort(points, width, height)
            if mirrored:
                points[:, 0] = width - 1 - points[:, 0]
                k[0, 2] = width - 1 - k[0, 2]
        square = np.array([[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]], np.float32)
        h = cv.getPerspectiveTransform(square, points.astype(np.float32))
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
        # A right swivel by the pilot tips the normal toward camera-image right.
        # Face normals keep the sign independent of sticker mounting rotation.
        yaw = math.degrees(math.atan2(rotation[0,2],rotation[2,2]))
        return roll, tilt, yaw

    def detect(self, frame, now, draw=True):
        self.raw_observation = None
        cv, np = self.cv2, self.np
        corners, ids, _ = self.detector.detectMarkers(frame)
        throttle = self.throttle.observe(corners, ids)
        mirrored = False
        if ids is None or YOKE_ID not in ids:
            corners, ids, _ = self.detector.detectMarkers(cv.flip(frame, 1))
            mirrored = True
            if throttle is None:
                throttle = self.throttle.observe(corners, ids)
        if ids is None or list(ids.flatten()).count(YOKE_ID) != 1:
            self.samples.clear()
            self.motion.clear()
            self.axis_active = [False, False, False]
            self.message = "Yoke tag not visible - flight holds. Keep all four black corners clear."
            return None, throttle
        points = corners[list(ids.flatten()).index(YOKE_ID)].reshape(4, 2).copy()
        side = min(float(np.linalg.norm(points[(i + 1) % 4] - points[i])) for i in range(4))
        if side < 70:
            self.samples.clear()
            self.message = "Move the yoke tag closer."
            return None, throttle
        try:
            roll, tilt, yaw = self.orientation_angles(points,frame.shape[1],frame.shape[0],mirrored)
        except (ValueError, np.linalg.LinAlgError, cv.error):
            return None, throttle
        if not all(math.isfinite(a) and abs(a)<=65 for a in (tilt, yaw)):
            self.message = "Face marker toward camera; avoid edge-on angles."
            return None, throttle
        if not self.pose_guard.accept((roll, tilt, yaw), now):
            self.samples.clear()
            self.message = "Checking a sudden angle change; keep marker steady."
            return None, throttle
        if mirrored:
            points[:, 0] = frame.shape[1] - 1 - points[:, 0]
        if draw:
            cv.polylines(frame, [points.astype(np.int32)], True, (60,240,90), 3)
        self.raw_observation = YokeObservation(roll, tilt, clamp(side / 120, .4, 1), yaw=yaw)
        return self.map_observation(roll, tilt, self.raw_observation.confidence, yaw), throttle


class ThrottleTracker:
    """The second camera contributes only tags 0/1/2, never steering or fire."""
    def __init__(self, cv2, np, idle_fraction=0.0, lens=None):
        self.lens = lens
        self.cv2 = cv2
        self.throttle = RelativeThrottle(cv2, np, idle_fraction=idle_fraction)
        parameters = cv2.aruco.DetectorParameters()
        parameters.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
        self.detector = cv2.aruco.ArucoDetector(cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50), parameters)

    def detect(self, frame):
        if frame is None:
            return self.throttle.observe([], None)
        for mirrored in (False, True):
            view = self.cv2.flip(frame, 1) if mirrored else frame
            corners, ids, _ = self.detector.detectMarkers(view)
            if self.lens is not None:
                height, width = frame.shape[:2]
                corrected = []
                for quad in corners:
                    points = quad.reshape(-1, 2).copy()
                    if mirrored:
                        points[:, 0] = width-1-points[:, 0]
                    corrected.append(self.lens.undistort(points, width, height).reshape(1, 4, 2))
                corners = corrected
            observation = self.throttle.observe(corners, ids)
            if observation is not None:
                return observation
        return None


class CameraSource:
    def __init__(self, camera_index: int, width: int, height: int, fps: int):
        # This is the only VideoCapture call in the project. Construction is
        # reachable only through the CLI's explicit --camera branch.
        self.cv2, _ = load_cv()
        self.capture = self.cv2.VideoCapture(camera_index, self.cv2.CAP_AVFOUNDATION if sys.platform == "darwin" else self.cv2.CAP_ANY)
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
    )

    def __init__(self, camera_index: int, width: int, height: int):
        self.index = 0
        self.samples = collections.deque(maxlen=24)
        self.values = {}
        self.camera_index, self.width, self.height = camera_index, width, height
        self.message = "Hold still for a second, then press SPACE to capture."
        print("Calibration: " + self.STEPS[0][1], flush=True)

    def observe(self, yoke, throttle):
        if yoke is None or yoke.confidence < 0.4:
            self.samples.clear()
        else:
            self.samples.append((yoke.roll, yoke.pitch))

    def capture(self):
        if len(self.samples) < 18:
            self.message = "Keep the active marker visible and still for one second."
            return None
        rows = tuple(zip(*self.samples))
        # Unwrap roll locally before taking a median near the +/-180 seam.
        first = rows[0][0]
        rows = (tuple(first + wrap_degrees(x - first) for x in rows[0]), rows[1])
        if any(statistics.pstdev(axis) > 4.0 for axis in rows):
            self.message = "Too much movement. Hold still, then press SPACE again."
            return None
        key = self.STEPS[self.index][0]
        self.values[key] = tuple(statistics.median(axis) for axis in rows)
        self.samples.clear()
        self.index += 1
        if self.index < len(self.STEPS):
            self.message = "Captured %s. Hold next position, then press SPACE." % key
            print("Calibration: " + self.STEPS[self.index][1], flush=True)
            return None
        try:
            result = Calibration(
                AxisCalibration(self.values["LEFT"][0], self.values["NEUTRAL"][0], self.values["RIGHT"][0]),
                AxisCalibration(self.values["FORWARD"][1], self.values["NEUTRAL"][1], self.values["BACKWARD"][1]),
                ThrottleCalibration((0.0, 0.0), (1.0, 0.0)),
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


def draw_preview(frame, packet, wizard, fps: float, throttle_status: str = "", lens_status: str = "", weapon_status=None):
    cv2, _ = load_cv()
    cv2.rectangle(frame, (0, 0), (frame.shape[1], 150 if wizard or throttle_status else 122), (26, 30, 32), -1)
    if wizard:
        title, instruction, _ = wizard.STEPS[wizard.index]
        lines = ["CALIBRATION %d/%d - %s" % (wizard.index + 1, len(wizard.STEPS), title), instruction,
                 wizard.message, "SPACE: capture  |  Q / ESC: quit  |  %d/18 samples" % len(wizard.samples)]
    else:
        yoke, throttle = packet["yoke"], packet["throttle"]
        lines = ["CARDBOARD COCKPIT | %.1f FPS | %s" % (fps, lens_status or "local camera only"),
                 "YOKE %s  ROLL %+.2f  PITCH %+.2f" % ("TRACKED" if yoke["confidence"] else "LOST", yoke["roll"], yoke["pitch"]),
                 "THROTTLE %3.0f%% %s  |  handle + both end tags  |  Q: quit" % (throttle["value"] * 100, "TRACKED" if throttle["confidence"] else "HOLDING / LOST")]
    if throttle_status and not wizard:
        lines.append(throttle_status)
    for index, line in enumerate(lines):
        cv2.putText(frame, line, (18, 28 + index * 32), cv2.FONT_HERSHEY_SIMPLEX, .62,
                    (115, 226, 247) if index == 0 else (235, 239, 240), 1, cv2.LINE_AA)
    weapons = packet["weapons"]
    height, width = frame.shape[:2]
    cv2.rectangle(frame, (0, height-66), (width, height), (26, 30, 32), -1)
    for row, (name, label) in enumerate((("gun", "GUN"),)):
        state = "FIRE" if weapons[name] else "OFF"
        reason = (weapon_status or {}).get(name, "")
        cv2.putText(frame, "%s: %s - %s" % (label, state, reason),
            (16, height-40+row*28), cv2.FONT_HERSHEY_SIMPLEX, .6, (115, 226, 247), 1, cv2.LINE_AA)
    cv2.imshow(PREVIEW_TITLE, frame)


async def run(args):
    try:
        from websockets.asyncio.server import serve
        from websockets.exceptions import ConnectionClosed
    except ImportError as error:
        raise RuntimeError("Install WebSockets: .venv/bin/python -m pip install -r vision/requirements.txt") from error

    source = detector = wizard = weapon_tags = framer = None
    throttle_feed = throttle_detector = throttle_framer = None
    primary_label = throttle_label = ""
    devices = list_cameras() if any(isinstance(value, str) for value in (args.camera, args.throttle_camera)) else None
    if args.camera is not None:
        args.camera, primary_label = resolve_camera(args.camera, devices)
    if args.throttle_camera is not None:
        args.throttle_camera, throttle_label = resolve_camera(args.throttle_camera, devices)
        if args.camera is None or args.simulate or args.throttle_only or args.throttle_camera == args.camera:
            raise ValueError("Use distinct yoke and throttle cameras with --camera and --throttle-camera.")
    calibration = simulated_calibration()
    lens = LensProfile.load(args.intrinsics) if args.intrinsics is not None else None
    lens_status = "LENS CALIBRATED" if lens is not None else "LENS APPROXIMATE"
    if args.camera is not None:
        if lens is not None and lens.camera_index != args.camera:
            raise ValueError("Lens profile camera index differs; select its camera or recalibrate the lens.")
        print(lens_status + ("; using " + str(args.intrinsics) if lens else "; use --calibrate-lens to measure this camera."), flush=True)
        detector = PaperController(lens=lens) if args.paper_test else ArucoTracker(lens=lens)
        detector.throttle = RelativeThrottle(detector.cv2, detector.np, idle_fraction=args.throttle_idle/100)
        weapon_tags = WeaponTags(detector.cv2, detector.np)
        framer = PreviewFramer(detector.cv2, detector.np)
        if args.paper_test or args.throttle_only:
            args.calibrate = False
            # Paper yoke returns normalized angle ranges. Live throttle fractions
            # bypass the legacy stored image endpoints in ControlFilter.
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
        print("%s camera: %s (index %d)" % ("Throttle" if args.throttle_only else "Yoke + shooting", primary_label, args.camera), flush=True)
        source = CameraSource(args.camera, args.width, args.height, args.fps)

    # Filter physical input first, then share live gains with the game and preview.
    controller = ControlFilter(calibration, args.smoothing, args.deadzone)
    control_settings = ControlSettings()
    neutral_calibration = NeutralCalibration()
    calibration_clients = set()
    clients = set()
    preview_clients = {focus: set() for focus in ("", "all", "laptop", "phone", *PreviewFramer.GROUPS)}
    preview_paths = {"/preview" + ("/" + focus if focus else ""): focus for focus in preview_clients}

    async def handler(connection):
        path = connection.request.path
        if path == "/settings":
            await settings_handler(connection)
            return
        if path == "/calibration":
            await calibration_handler(connection)
            return
        if path != "/" and path not in preview_paths:
            await connection.close(1008, "Unknown stream")
            return
        # Each client has a one-packet queue: slow consumers never build a stale
        # control backlog and never delay capture or other receivers.
        queue = asyncio.Queue(maxsize=1)
        subscribers = clients if path == "/" else preview_clients[preview_paths[path]]
        subscribers.add(queue)

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
            subscribers.discard(queue)
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    async def settings_handler(connection):
        try:
            async for message in connection:
                if not isinstance(message, str):
                    raise ValueError("Settings must be JSON text")
                reply = control_settings.accept(json.loads(message))
                await connection.send(json.dumps(reply, allow_nan=False))
        except (ValueError, TypeError):
            await connection.close(1008, "Invalid settings command")
        except ConnectionClosed:
            pass

    async def calibration_handler(connection):
        # A separate local endpoint leaves controls and camera streams read-only.
        # Exactly one start command per connection; closing it cancels a pending capture.
        request_id = None
        queue = asyncio.Queue(maxsize=1)
        tasks = []
        try:
            command = json.loads(await asyncio.wait_for(connection.recv(), 5))
            if not isinstance(command, dict) or set(command) != {"action", "request_id"} or command["action"] != "start":
                raise ValueError("Invalid calibration command")
            request_id = command["request_id"]
            if not isinstance(request_id, str) or not 1 <= len(request_id) <= 80:
                raise ValueError("Invalid calibration request")
            neutral_calibration.start(request_id)
            if args.throttle_only or wizard:
                neutral_calibration.state = "unavailable"
            calibration_clients.add(queue)

            async def sender():
                while True:
                    await connection.send(await queue.get())

            async def receiver():
                async for _ in connection:
                    await connection.close(1008, "One calibration per connection")
                    return

            tasks = [asyncio.create_task(sender()), asyncio.create_task(receiver())]
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        except (ValueError, TypeError, asyncio.TimeoutError):
            await connection.close(1008, "Invalid calibration command")
        except ConnectionClosed:
            pass
        finally:
            calibration_clients.discard(queue)
            if request_id == neutral_calibration.request_id and neutral_calibration.state != "complete":
                neutral_calibration.cancel()
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    try:
        if args.throttle_camera is not None:
            secondary = CameraSource(args.throttle_camera, args.width, args.height, args.fps)
            throttle_feed = BackgroundCamera(secondary, args.fps)
            throttle_lens_path = getattr(args, "throttle_intrinsics", None)
            throttle_lens = LensProfile.load(throttle_lens_path) if throttle_lens_path else None
            if throttle_lens is not None:
                throttle_lens.check_source(args.throttle_camera, args.width, args.height)
            throttle_detector = ThrottleTracker(detector.cv2, detector.np, idle_fraction=args.throttle_idle/100, lens=throttle_lens)
            throttle_framer = PreviewFramer(detector.cv2, detector.np)
            print("Throttle camera: %s (index %d)" % (throttle_label, args.throttle_camera), flush=True)
        async with serve(handler, "127.0.0.1", args.port, origins=[None], max_size=1024,
                         max_queue=2, compression=None, close_timeout=1):
            print("Cardboard controls: ws://127.0.0.1:%d [%s]" % (args.port, "SIMULATED" if args.simulate else "CAMERA"), flush=True)
            print("Ctrl+C to stop. Camera preview stays on this computer; no images are saved.", flush=True)
            start = previous = time.monotonic()
            frame_number = 0
            fps_estimate = float(args.fps)
            failure_count = 0
            checked_frame_size = False
            next_preview = 0.0
            while args.duration <= 0 or time.monotonic() - start < args.duration:
                frame_start = time.monotonic()
                frame = throttle_frame = None
                weapons = {"gun": False}
                if args.simulate:
                    yoke, throttle = simulated_observations(frame_number, args.fps, args.loss_demo)
                else:
                    # Capture can block briefly; keep socket handshakes alive.
                    frame = await asyncio.to_thread(source.read)
                    if frame is None:
                        yoke = throttle = None
                        weapon_tags.reset()
                        failure_count += 1
                        if failure_count in (1, args.fps * 3):
                            print("No camera frame. Yoke will neutralize; throttle holds. Use keyboard or restart the tracker.", file=sys.stderr, flush=True)
                    else:
                        failure_count = 0
                        if lens is not None:
                            lens.check_source(args.camera, frame.shape[1], frame.shape[0])
                        if not checked_frame_size:
                            checked_frame_size = True
                            if not (args.paper_test or args.throttle_only) and not wizard and (frame.shape[1], frame.shape[0]) != (calibration.width, calibration.height):
                                if args.no_preview:
                                    raise RuntimeError("Camera resolution changed. Restart without --no-preview to recalibrate.")
                                print("Camera resolution changed. Recalibration is required.", flush=True)
                                wizard = CalibrationWizard(args.camera, frame.shape[1], frame.shape[0])
                        if wizard:
                            wizard.width, wizard.height = frame.shape[1], frame.shape[0]
                            weapon_tags.reset()
                        else:
                            # Read the untouched camera image before the yoke
                            # or throttle draws any preview annotations.
                            weapons = weapon_tags.detect(frame, time.monotonic())
                        yoke, throttle = detector.detect(frame, frame_start, not args.no_preview)
                        if args.throttle_only:
                            yoke = None
                    if throttle_feed is not None:
                        throttle_frame = throttle_feed.snapshot()
                        # Never fall back to throttle tags seen by the laptop.
                        throttle = throttle_detector.detect(throttle_frame)
                if wizard:
                    wizard.observe(yoke, throttle)
                    yoke = throttle = None
                if neutral_calibration.state in ("waiting", "holding"):
                    raw = detector.raw_observation if isinstance(detector, PaperController) and frame is not None else yoke
                    neutral = neutral_calibration.observe(raw, time.monotonic())
                    if neutral is not None:
                        if isinstance(detector, PaperController):
                            detector.neutral = neutral[:2]
                            detector.yaw_neutral = neutral[2]
                            detector.samples.clear()
                            detector.motion.clear()
                            detector.axis_active = [False, False, False]
                        else:
                            def shifted(axis, center):
                                delta = wrap_degrees(center-axis.neutral)
                                return AxisCalibration(axis.negative+delta, center, axis.positive+delta)
                            controller.calibration = replace(controller.calibration,
                                roll=shifted(controller.calibration.roll, neutral[0]),
                                pitch=shifted(controller.calibration.pitch, neutral[1]))
                            controller.yaw_neutral = neutral[2]
                        print("YOKE CALIBRATED: three-second neutral captured.", flush=True)
                    # No stale steering or fire can escape during capture or its completion frame.
                    controller.roll = controller.pitch = controller.roll_target = controller.pitch_target = 0.0
                    controller.yaw = controller.yaw_target = 0.0
                    controller.last_yoke = float("-inf")
                    yoke = None
                    weapons = {"gun": False}
                calibration_packet = json.dumps(neutral_calibration.packet(), allow_nan=False)
                for queue in tuple(calibration_clients):
                    if queue.full():
                        queue.get_nowait()
                    queue.put_nowait(calibration_packet)
                packet = controller.step(time.monotonic(), int(time.time() * 1000), yoke, throttle)
                control_settings.apply(packet)
                # Fire is never smoothed or held through a missing detection.
                packet["weapons"] = weapons
                packet["yoke_enabled"] = not args.throttle_only
                serialized = json.dumps(packet, allow_nan=False, separators=(",", ":"))
                for queue in tuple(clients):
                    if queue.full():
                        queue.get_nowait()
                    queue.put_nowait(serialized)
                # Read-only local previews: encode only requested views at 10 FPS.
                # All roles keep the full, fixed camera frame; mirror only the display.
                if any(preview_clients.values()) and frame_start >= next_preview:
                    for focus, viewers in preview_clients.items():
                        if not viewers:
                            continue
                        preview = b""
                        if focus == "phone":
                            view = throttle_framer.render(throttle_frame, "throttle", frame_start, "PHONE / " + throttle_label) if throttle_feed is not None else None
                        elif focus == "laptop":
                            view = framer.render(frame, "yoke", frame_start, "LAPTOP / " + primary_label) if framer is not None and not args.throttle_only else None
                        elif focus == "all" and throttle_feed is not None:
                            view = framer.combined(frame, throttle_frame, "YOKE + SHOOTING / " + primary_label,
                                                   "THROTTLE / " + throttle_label)
                        elif focus == "throttle" and throttle_feed is not None:
                            view = throttle_framer.render(throttle_frame, focus, frame_start, "THROTTLE / " + throttle_label)
                        elif framer is not None:
                            view = framer.render(frame, focus, frame_start, (focus.upper() or "YOKE") + " / " + primary_label)
                        else:
                            view = None
                        if view is not None:
                            encoded, jpeg = detector.cv2.imencode(".jpg", view, [detector.cv2.IMWRITE_JPEG_QUALITY, 75])
                            if encoded:
                                preview = jpeg.tobytes()
                        for queue in tuple(viewers):
                            if queue.full():
                                queue.get_nowait()
                            queue.put_nowait(preview)
                    next_preview = frame_start + .1
                if args.print_json:
                    print(serialized, flush=True)
                if frame is not None and not args.no_preview:
                    interval = max(frame_start - previous, 0.001)
                    fps_estimate += .08 * ((1.0 / interval) - fps_estimate)
                    frame = detector.cv2.flip(frame, 1)
                    draw_preview(frame, packet, wizard, fps_estimate, (throttle_detector or detector).throttle.message, lens_status, weapon_tags.messages)
                    if args.paper_test:
                        detector.cv2.rectangle(frame, (0,0), (frame.shape[1],185), (26,30,32), -1)
                        for row, line in enumerate(["YOKE / " + primary_label + " | " + lens_status, detector.message,
                                "BANK %+.2f  PITCH %+.2f  YAW %+.2f  POWER %3.0f%% %s | Q quits" % (packet["yoke"]["roll"], packet["yoke"]["pitch"], packet["yoke"]["yaw"], packet["throttle"]["value"] * 100, "LIVE" if packet["throttle"]["confidence"] > .4 else "HELD"), (throttle_detector or detector).throttle.message + (" / " + throttle_label if throttle_feed else ""),
                                "SENSITIVITY  PITCH %.2fx  BANK %.2fx  YAW %.2fx" % tuple(packet["sensitivity"][axis] for axis in ("pitch", "bank", "yaw")) ]):
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
                    elif not (args.paper_test or args.throttle_only) and key == ord("c"):
                        wizard = CalibrationWizard(args.camera, frame.shape[1], frame.shape[0])
                    elif key == 32 and wizard:
                        calibrated = wizard.capture()
                        if calibrated is not None:
                            calibrated.save(args.calibration)
                            # Keep sequence monotonic and throttle safe across calibration.
                            next_controller = ControlFilter(calibrated, args.smoothing, args.deadzone)
                            next_controller.sequence = controller.sequence
                            next_controller.throttle = controller.throttle
                            controller = next_controller
                            wizard = None
                            print("Cockpit calibrated. Cleared for takeoff. Saved to %s" % args.calibration, flush=True)
                previous = frame_start
                frame_number += 1
                await asyncio.sleep(max(0.0, 1.0 / args.fps - (time.monotonic() - frame_start)))
    finally:
        if throttle_feed is not None:
            await throttle_feed.close()
        if source:
            source.close()


def parser():
    result = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = result.add_mutually_exclusive_group(required=True)
    mode.add_argument("--simulate", action="store_true", help="Serve deterministic controls without opening a camera")
    mode.add_argument("--camera", type=camera_argument, metavar="INDEX_OR_NAME", help="Yoke and shooting camera; macOS accepts an exact device name")
    mode.add_argument("--list-cameras", action="store_true", help="List macOS camera names and OpenCV indices without opening them")
    result.add_argument("--throttle-camera", type=camera_argument, metavar="INDEX_OR_NAME", help="Separate camera for throttle tracking and its tutorial view")
    result.add_argument("--throttle-idle", type=float, default=15.0, metavar="PERCENT", help="Rail position treated as 0%% throttle; default 15; full remains 100%%")
    mode.add_argument("--markers", type=Path, metavar="DIRECTORY", help="Generate printable marker SVG/PNG files; no camera")
    mode.add_argument("--checkerboard", type=Path, metavar="SVG", help="Write the lens calibration print target; no camera")
    result.add_argument("--calibrate-lens", action="store_true", help="Measure lens parameters using a printed checkerboard, then exit")
    result.add_argument("--intrinsics", type=Path, metavar="JSON", help="Load measured lens profile, or save here with --calibrate-lens")
    result.add_argument("--throttle-intrinsics", type=Path, metavar="JSON", help="Optional measured lens profile for the separate throttle camera")
    result.add_argument("--calibrate", action="store_true", help="Run the five-step yoke calibration; throttle endpoints are tracked live")
    result.add_argument("--paper-test", action="store_true", help="Auto-center yoke 7, with optional relative throttle tags 0/1/2")
    result.add_argument("--throttle-only", action="store_true", help="Track throttle 0/1/2 without yoke calibration; steer in game with keyboard")
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
    if not math.isfinite(args.throttle_idle) or not 0 <= args.throttle_idle < 100:
        argument_parser.error("Use a finite --throttle-idle percentage in [0, 100).")
    if any(isinstance(value, int) and value < 0 for value in (args.camera, args.throttle_camera)):
        argument_parser.error("Camera index cannot be negative.")
    if args.throttle_camera is not None and (args.camera is None or args.throttle_only or args.calibrate_lens):
        argument_parser.error("--throttle-camera requires --camera in yoke mode; omit --throttle-only and --calibrate-lens.")
    if args.calibrate and args.camera is None:
        argument_parser.error("--calibrate requires an explicit --camera INDEX.")
    if args.paper_test and (args.camera is None or args.calibrate or args.no_preview):
        argument_parser.error("--paper-test needs --camera and its preview; omit --calibrate.")
    if args.throttle_only and (args.camera is None or args.calibrate or args.paper_test):
        argument_parser.error("--throttle-only needs --camera; omit --calibrate and --paper-test.")
    if args.calibrate_lens and (args.camera is None or args.intrinsics is None or args.calibrate or args.paper_test or args.throttle_only or args.no_preview):
        argument_parser.error("--calibrate-lens needs --camera INDEX --intrinsics FILE and its preview; omit other calibration/control modes.")
    if args.intrinsics is not None and args.camera is None:
        argument_parser.error("--intrinsics requires --camera INDEX.")
    if args.loss_demo and not args.simulate:
        argument_parser.error("--loss-demo requires --simulate.")
    try:
        if args.list_cameras:
            for device in list_cameras():
                print("%d: %s" % (device["index"], device["name"]))
        elif args.checkerboard is not None:
            write_checkerboard(args.checkerboard)
            print("Print %s in landscape on flat paper; keep the white margin." % args.checkerboard)
        elif args.calibrate_lens:
            args.camera, _ = resolve_camera(args.camera)
            run_lens_calibration(args, CameraSource)
        elif args.markers is not None:
            generate_markers(args.markers)
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
