"""Lens calibration, separate from the yoke's neutral/range calibration.

Only numerical calibration data is saved. Camera frames are never recorded.
The profile is opt-in, and must match the selected camera and frame size.
"""
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class LensProfile:
    camera_index: int
    width: int
    height: int
    matrix: list
    distortion: list
    rms: float
    views: int
    version: int = 1

    def validate(self):
        import numpy as np
        if type(self.version) is not int or self.version != 1:
            raise ValueError("Unsupported lens calibration version.")
        if any(type(v) is not int for v in (self.camera_index, self.width, self.height, self.views)):
            raise ValueError("Lens profile dimensions, camera index and view count must be integers.")
        if self.camera_index < 0 or self.width < 320 or self.height < 240 or self.views < 15:
            raise ValueError("Invalid lens profile dimensions or too few calibration views.")
        k, d = np.asarray(self.matrix, float), np.asarray(self.distortion, float)
        if k.shape != (3, 3) or d.shape != (5,) or not np.isfinite(k).all() or not np.isfinite(d).all():
            raise ValueError("Lens matrix/distortion must contain finite numbers with the expected shape.")
        if not np.allclose(k[2], [0, 0, 1]) or abs(k[0, 1]) > 1e-8 or abs(k[1, 0]) > 1e-8:
            raise ValueError("Invalid pinhole camera matrix.")
        if not (.15 * self.width < k[0, 0] < 5 * self.width and
                .15 * self.width < k[1, 1] < 5 * self.width and
                0 < k[0, 2] < self.width and 0 < k[1, 2] < self.height):
            raise ValueError("Implausible lens calibration; capture more varied checkerboard angles.")
        if isinstance(self.rms, bool) or not isinstance(self.rms, (int, float)) or not math.isfinite(self.rms) or not 0 <= self.rms <= 1.0:
            raise ValueError("Lens reprojection error must be at most 1 pixel; retake sharper views.")

    def check_source(self, camera_index, width, height):
        if (camera_index, width, height) != (self.camera_index, self.width, self.height):
            raise ValueError("Lens profile is for camera %d at %dx%d, not camera %d at %dx%d. "
                             "Select the matching camera/resolution or recalibrate the lens." %
                             (self.camera_index, self.width, self.height, camera_index, width, height))

    def camera_matrix(self, width, height):
        import numpy as np
        self.check_source(self.camera_index, width, height)
        return np.asarray(self.matrix, dtype=np.float64)

    def undistort(self, points, width, height):
        import cv2
        import numpy as np
        k = self.camera_matrix(width, height)
        # More iterations than undistortPoints' default for off-centre points.
        return cv2.undistortPointsIter(np.asarray(points, np.float64).reshape(-1, 1, 2), k,
                                      np.asarray(self.distortion, float), None, k,
                                      (cv2.TERM_CRITERIA_COUNT | cv2.TERM_CRITERIA_EPS, 30, 1e-10)).reshape(-1, 2)

    def save(self, path):
        self.validate()
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(json.dumps(asdict(self), indent=2, allow_nan=False) + "\n", encoding="utf-8")
        temporary.replace(path)

    @classmethod
    def load(cls, path):
        try:
            profile = cls(**json.loads(Path(path).read_text(encoding="utf-8")))
            profile.validate()
            return profile
        except (OSError, ValueError, TypeError, KeyError) as error:
            raise ValueError("Cannot use lens profile %s: %s" % (path, error)) from error


class LensCalibrator:
    # 10 x 7 printed squares produce 9 x 6 internal intersections.
    PATTERN = (9, 6)
    MIN_VIEWS = 15

    def __init__(self, camera_index, width, height):
        self.camera_index, self.width, self.height = camera_index, width, height
        self.image_points = []

    @classmethod
    def object_points(cls):
        import numpy as np
        points = np.zeros((cls.PATTERN[0] * cls.PATTERN[1], 3), np.float32)
        points[:, :2] = np.mgrid[0:cls.PATTERN[0], 0:cls.PATTERN[1]].T.reshape(-1, 2)
        return points

    def add(self, corners):
        import numpy as np
        points = np.asarray(corners, np.float32).reshape(-1, 2)
        if points.shape != (54, 2) or not np.isfinite(points).all():
            raise ValueError("The complete checkerboard must be visible.")
        if np.any(points < 8) or np.any(points[:, 0] > self.width - 8) or np.any(points[:, 1] > self.height - 8):
            raise ValueError("Keep the complete checkerboard inside the camera image.")
        grid = points.reshape(6, 9, 2)
        cell = min(np.linalg.norm(np.diff(grid, axis=0), axis=2).min(),
                   np.linalg.norm(np.diff(grid, axis=1), axis=2).min())
        if cell < 12:
            raise ValueError("Move the board closer so its corners are easier to measure.")
        scale = np.array([self.width, self.height])
        if any(min(np.sqrt(np.mean(((points - old) / scale) ** 2)),
                       np.sqrt(np.mean(((points[::-1] - old) / scale) ** 2))) < .025
               for old in self.image_points):
            raise ValueError("Already captured this view. Move or tilt the board before capturing again.")
        self.image_points.append(points.copy())

    def solve(self):
        import cv2
        import numpy as np
        if len(self.image_points) < self.MIN_VIEWS:
            raise ValueError("Capture at least 15 distinct checkerboard views; 20-25 is better.")
        centers = np.array([p.mean(axis=0) for p in self.image_points])
        if np.ptp(centers[:, 0]) < self.width * .25 or np.ptp(centers[:, 1]) < self.height * .20:
            raise ValueError("Move the board across the left/right and upper/lower parts of the image.")
        points = [self.object_points() for _ in self.image_points]
        rms, k, distortion, rvecs, tvecs = cv2.calibrateCamera(
            points, self.image_points, (self.width, self.height), None, None,
            criteria=(cv2.TERM_CRITERIA_COUNT | cv2.TERM_CRITERIA_EPS, 100, 1e-9))
        normals = np.array([cv2.Rodrigues(r)[0][:, 2] for r in rvecs])
        if np.ptp(normals[:, 0]) < .25 or np.ptp(normals[:, 1]) < .25:
            raise ValueError("Add views tilted left/right AND forward/backward, not just flat translations.")
        # One blurry view should not be hidden by a low average error.
        for objects, image, rotation, translation in zip(points, self.image_points, rvecs, tvecs):
            projected, _ = cv2.projectPoints(objects, rotation, translation, k, distortion)
            error = np.sqrt(np.mean(np.sum((projected.reshape(-1, 2) - image) ** 2, axis=1)))
            if error > 1.5:
                raise ValueError("A captured view is too inaccurate. Reset and capture sharp, still views.")
        profile = LensProfile(self.camera_index, self.width, self.height,
                              k.tolist(), distortion.reshape(-1).tolist(), float(rms), len(points))
        profile.validate()
        return profile


def write_checkerboard(path):
    """A4/Letter-compatible vector print target, 20 mm squares with margins."""
    rects = ['<rect width="220" height="160" fill="white"/>']
    for row in range(7):
        for col in range(10):
            if (row + col) % 2 == 0:
                rects.append('<rect x="%d" y="%d" width="20" height="20" fill="black"/>' %
                             (10 + col * 20, 10 + row * 20))
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="220mm" height="160mm" '
                    'viewBox="0 0 220 160" shape-rendering="crispEdges">\n' + "\n".join(rects) + '\n</svg>\n', encoding="utf-8")


def run_lens_calibration(args, camera_factory):
    import cv2
    source = camera_factory(args.camera, args.width, args.height, args.fps)
    title = "Camera lens calibration - checkerboard"
    calibrator = None
    message = "Hold board still; SPACE captures, ENTER saves, R resets, Q quits."
    print("Lens calibration: use the 10x7-square board in vision/camera-checkerboard.svg.", flush=True)
    try:
        while True:
            frame = source.read()
            if frame is None:
                raise RuntimeError("No camera frame during lens calibration. Close other camera apps and retry.")
            height, width = frame.shape[:2]
            if calibrator is None:
                calibrator = LensCalibrator(args.camera, width, height)
            elif (width, height) != (calibrator.width, calibrator.height):
                raise RuntimeError("Camera resolution changed during calibration. Restart capture.")
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            found, corners = cv2.findChessboardCornersSB(gray, LensCalibrator.PATTERN,
                                                        flags=cv2.CALIB_CB_NORMALIZE_IMAGE)
            if found:
                cv2.drawChessboardCorners(frame, LensCalibrator.PATTERN, corners, found)
            # Instructions are in a separate strip, never over the board corners.
            display = cv2.copyMakeBorder(frame, 110, 0, 0, 0, cv2.BORDER_CONSTANT, value=(26, 30, 32))
            lines = ["LENS CALIBRATION | %d views (minimum 15)" % len(calibrator.image_points),
                     message, "Move across the image; vary distance and tilt in BOTH directions."]
            for row, line in enumerate(lines):
                cv2.putText(display, line, (12, 26 + row * 31), cv2.FONT_HERSHEY_SIMPLEX,
                            min(.55, width / 1600), (235, 239, 240), 1, cv2.LINE_AA)
            cv2.imshow(title, display)
            key = cv2.waitKey(1) & 0xff
            try:
                closed = cv2.getWindowProperty(title, cv2.WND_PROP_VISIBLE) < 1
            except cv2.error:
                closed = True
            if key in (27, ord('q')) or closed:
                print("Lens calibration cancelled; no profile changed.", flush=True)
                return
            if key == ord('r'):
                calibrator = LensCalibrator(args.camera, width, height)
                message = "Reset. SPACE captures; ENTER calculates and saves."
            elif key == 32:
                try:
                    if not found:
                        raise ValueError("Show the full checkerboard, hold still, then press SPACE.")
                    calibrator.add(corners)
                    message = "View captured. Move/tilt before SPACE again; ENTER saves when ready."
                except ValueError as error:
                    message = str(error)
            elif key in (10, 13):
                try:
                    profile = calibrator.solve()
                    profile.save(args.intrinsics)
                    print("Saved lens profile to %s (%dx%d, %d views, %.3f px RMS)." %
                          (args.intrinsics, width, height, profile.views, profile.rms), flush=True)
                    return
                except (ValueError, cv2.error) as error:
                    message = str(error)
                    print("Calibration needs more work: " + message, flush=True)
    finally:
        source.close()
