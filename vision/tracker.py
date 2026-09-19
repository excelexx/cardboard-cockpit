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
    from .camera_calibration import LensProfile, run_lens_calibration, write_checkerboard
    from .pose_guard import PoseGuard
    from .relative_throttle import RelativeThrottle, THROTTLE_IDLE_ID, THROTTLE_ID, THROTTLE_FULL_ID
    from .calibration import (AxisCalibration, Calibration, ControlFilter, ThrottleCalibration,
                              YokeObservation, clamp, simulated_calibration,
                              simulated_observations, wrap_degrees)
else:
    from camera_calibration import LensProfile, run_lens_calibration, write_checkerboard
    from pose_guard import PoseGuard
    from relative_throttle import RelativeThrottle, THROTTLE_IDLE_ID, THROTTLE_ID, THROTTLE_FULL_ID
    from calibration import (AxisCalibration, Calibration, ControlFilter, ThrottleCalibration,
                             YokeObservation, clamp, simulated_calibration,
                             simulated_observations, wrap_degrees)

# Yoke stays separate from the relative throttle IDs 0, 1 and 2.
YOKE_ID = 7
if __package__:
    from .weapon_switches import WeaponSwitches
else:
    from weapon_switches import WeaponSwitches

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
                                     (31,"primary-on",35),(32,"primary-off",35),(41,"salvo-on",35),(42,"salvo-off",35)):
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
        self.weapon_observations = {}
        self.previous_pose = None
        self.previous_pose_time = 0.0

    def detect(self, frame, now: float, draw: bool = True):
        cv2, np = self.cv2, self.np
        height, width = frame.shape[:2]
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        corners, ids, _ = self.detector.detectMarkers(gray)
        yoke = None
        throttle = self.throttle.observe(corners, ids, frame if draw else None)
        self.weapon_observations = {}
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
            key = int(marker_id)
            if key in WeaponSwitches.IDS and counts[key] == 1:
                role, value = WeaponSwitches.IDS[key]
                other = 32 if key == 31 else 31 if key == 32 else 42 if key == 41 else 41
                points = marker_corners.reshape(4, 2)
                side = float(min(np.linalg.norm(points[(i+1)%4]-points[i]) for i in range(4)))
                if other not in counts and side >= 24:
                    self.weapon_observations[role] = (value, clamp(side/75,.3,1.0))
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
            if not math.isfinite(error) or error > 4.0:
                continue
            if not self.pose_guard.accept((roll, pitch), now):
                continue
            confidence *= clamp(1 - error / 6, 0, 1)
            self.previous_pose = pitch
            self.previous_pose_time = now
            yoke = YokeObservation(roll, pitch, confidence)
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
        self.axis_active = [False, False]
        self.neutral = None
        self.message = "Show marker 7 and hold still for one second to center."

    def recenter(self):
        self.pose_guard.reset()
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

    def perspective_angles(self, points, width, height, mirrored=False):
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
        return roll, tilt

    def detect(self, frame, now, draw=True):
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
            self.axis_active = [False, False]
            self.message = "Marker 7 not visible - flight holds. Keep all four black corners clear."
            return None, throttle
        points = corners[list(ids.flatten()).index(YOKE_ID)].reshape(4, 2).copy()
        side = min(float(np.linalg.norm(points[(i + 1) % 4] - points[i])) for i in range(4))
        if side < 70:
            self.samples.clear()
            self.message = "Move marker 7 closer."
            return None, throttle
        try:
            roll, tilt = self.perspective_angles(points,frame.shape[1],frame.shape[0],mirrored)
        except (ValueError, np.linalg.LinAlgError, cv.error):
            return None, throttle
        if not math.isfinite(tilt) or abs(tilt)>65:
            self.message = "Face marker toward camera; avoid edge-on angles."
            return None, throttle
        if not self.pose_guard.accept((roll, tilt), now):
            self.samples.clear()
            self.message = "Checking a sudden angle change; keep marker steady."
            return None, throttle
        if mirrored:
            points[:, 0] = frame.shape[1] - 1 - points[:, 0]
        if draw:
            cv.polylines(frame, [points.astype(np.int32)], True, (60,240,90), 3)
        return self.map_observation(roll, tilt, clamp(side / 120, .4, 1)), throttle


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


def draw_preview(frame, packet, wizard, fps: float, throttle_status: str = "", lens_status: str = ""):
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
                 "THROTTLE %3.0f%% %s  |  tags 0/1/2  |  Q: quit" % (throttle["value"] * 100, "TRACKED" if throttle["confidence"] else "HOLDING / LOST")]
    if throttle_status and not wizard:
        lines.append(throttle_status)
    for index, line in enumerate(lines):
        cv2.putText(frame, line, (18, 28 + index * 32), cv2.FONT_HERSHEY_SIMPLEX, .62,
                    (115, 226, 247) if index == 0 else (235, 239, 240), 1, cv2.LINE_AA)
    cv2.imshow(PREVIEW_TITLE, frame)


def encode_camera_preview(frame):
    """Small mirrored self-view, encoded before detection draws on the frame."""
    cv2, _ = load_cv()
    height, width = frame.shape[:2]
    scale = min(320 / width, 240 / height, 1.0)
    small = cv2.resize(frame, (max(1, round(width * scale)), max(1, round(height * scale))),
                       interpolation=cv2.INTER_AREA)
    ok, jpeg = cv2.imencode(".jpg", cv2.flip(small, 1), [cv2.IMWRITE_JPEG_QUALITY, 65])
    return jpeg.tobytes() if ok and jpeg.size <= 65536 else None


async def run(args):
    try:
        from websockets.asyncio.server import serve
        from websockets.exceptions import ConnectionClosed
    except ImportError as error:
        raise RuntimeError("Install WebSockets: .venv/bin/python -m pip install -r vision/requirements.txt") from error

    source = detector = wizard = None
    calibration = simulated_calibration()
    lens = LensProfile.load(args.intrinsics) if args.intrinsics is not None else None
    lens_status = "LENS CALIBRATED" if lens is not None else "LENS APPROXIMATE"
    if args.camera is not None:
        if lens is not None and lens.camera_index != args.camera:
            raise ValueError("Lens profile camera index differs; select its camera or recalibrate the lens.")
        print(lens_status + ("; using " + str(args.intrinsics) if lens else "; use --calibrate-lens to measure this camera."), flush=True)
        detector = PaperController(lens=lens) if args.paper_test else ArucoTracker(lens=lens)
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
        source = CameraSource(args.camera, args.width, args.height, args.fps)

    controller = ControlFilter(calibration, args.smoothing, args.deadzone)
    weapon_switches = WeaponSwitches()
    clients = set()
    preview_clients = set()
    last_preview = 0.0

    async def handler(connection):
        # Each client has a one-packet queue: slow consumers never build a stale
        # control backlog and never delay capture or other receivers.
        queue = asyncio.Queue(maxsize=1)
        subscribers = preview_clients if connection.request.path == "/preview" else clients
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

    try:
        async with serve(handler, "127.0.0.1", args.port, origins=[None], max_size=1024,
                         max_queue=2, compression=None, close_timeout=1):
            print("Cardboard controls: ws://127.0.0.1:%d [%s]" % (args.port, "SIMULATED" if args.simulate else "CAMERA"), flush=True)
            print("Ctrl+C to stop. Camera preview stays on this computer; no images are saved or uploaded.", flush=True)
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
                        if preview_clients and frame_start - last_preview >= .1:
                            jpeg = encode_camera_preview(frame)
                            if jpeg is not None:
                                for queue in tuple(preview_clients):
                                    if queue.full():
                                        queue.get_nowait()
                                    queue.put_nowait(jpeg)
                            last_preview = frame_start
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
                        yoke, throttle = detector.detect(frame, frame_start, not args.no_preview)
                # Roles are enforced before filtering, even if the other tags are visible.
                if args.throttle_only:
                    yoke = None
                if args.yoke_only:
                    throttle = None
                if wizard:
                    wizard.observe(yoke, throttle)
                    yoke = throttle = None
                packet = controller.step(time.monotonic(), int(time.time() * 1000), yoke, throttle)
                # Apply gain once, before both the Python readout and socket send.
                # Keep neutral filtering and throttle behavior independent of gain.
                for axis in ("roll", "pitch"):
                    gain = args.yoke_sensitivity * (args.bank_scale if axis == "roll" else 1.0)
                    packet["yoke"][axis] = clamp(packet["yoke"][axis] * gain, -1, 1)
                weapons = weapon_switches.step(getattr(detector,"weapon_observations",{}) if frame is not None and not wizard and not args.throttle_only else {}, time.monotonic())
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
                    draw_preview(frame, packet, wizard, fps_estimate, detector.throttle.message, lens_status)
                    if args.paper_test:
                        detector.cv2.rectangle(frame, (0,0), (frame.shape[1],150), (26,30,32), -1)
                        for row, line in enumerate(["YOKE ID 7 | " + lens_status + " | KEEP OPEN", detector.message,
                                "BANK %+.2f  PITCH %+.2f  POWER %3.0f%% %s | Q quits" % (packet["yoke"]["roll"], packet["yoke"]["pitch"], packet["throttle"]["value"] * 100, "LIVE" if packet["throttle"]["confidence"] > .4 else "HELD"), detector.throttle.message ]):
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
        if source:
            source.close()


def parser():
    result = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = result.add_mutually_exclusive_group(required=True)
    mode.add_argument("--simulate", action="store_true", help="Serve deterministic controls without opening a camera")
    mode.add_argument("--camera", type=int, metavar="INDEX", help="Explicitly open this webcam, usually 0")
    mode.add_argument("--markers", type=Path, metavar="DIRECTORY", help="Generate printable marker SVG/PNG files; no camera")
    mode.add_argument("--checkerboard", type=Path, metavar="SVG", help="Write the lens calibration print target; no camera")
    result.add_argument("--calibrate-lens", action="store_true", help="Measure lens parameters using a printed checkerboard, then exit")
    result.add_argument("--intrinsics", type=Path, metavar="JSON", help="Load measured lens profile, or save here with --calibrate-lens")
    result.add_argument("--calibrate", action="store_true", help="Run the five-step yoke calibration; throttle endpoints are tracked live")
    result.add_argument("--paper-test", action="store_true", help="Auto-center yoke 7, with optional relative throttle tags 0/1/2")
    roles = result.add_mutually_exclusive_group()
    roles.add_argument("--yoke-only", action="store_true", help="Ignore throttle tags; use a separate camera for power")
    roles.add_argument("--throttle-only", action="store_true", help="Track throttle 0/1/2 without yoke calibration; steer in game with keyboard")
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
    result.add_argument("--yoke-sensitivity", type=float, default=2.0, metavar="GAIN",
                        help="Bank/pitch gain shared by the preview and game (default: 2)")
    result.add_argument("--bank-scale", type=float, default=.7, metavar="SCALE",
                        help="Bank-only multiplier on yoke sensitivity (default: 0.7)")
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
    if not math.isfinite(args.yoke_sensitivity) or not 0 < args.yoke_sensitivity <= 10:
        argument_parser.error("Yoke sensitivity must be finite and in (0, 10].")
    if not math.isfinite(args.bank_scale) or not 0 < args.bank_scale <= 10:
        argument_parser.error("Bank scale must be finite and in (0, 10].")
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
        if args.checkerboard is not None:
            write_checkerboard(args.checkerboard)
            print("Print %s in landscape on flat paper; keep the white margin." % args.checkerboard)
        elif args.calibrate_lens:
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
