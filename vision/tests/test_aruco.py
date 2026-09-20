"""Synthetic images exercise actual ArUco detection without opening a camera."""
import math
import unittest

try:
    import cv2
    import numpy as np
except ImportError:
    cv2 = np = None

from vision.tracker import ArucoTracker
from vision.tests.throttle_fixture import throttle_frame
from vision.tests.yoke_fixture import yoke_frame


@unittest.skipIf(cv2 is None, "Optional OpenCV/NumPy packages not installed")
class ArucoTests(unittest.TestCase):
    def test_yaw_uses_the_selected_pose_and_sticker_mounting_does_not_reverse_it(self):
        for mounting in (0,180):
            for yaw in (-20,20):
                tracker = ArucoTracker()
                result,_ = tracker.detect(yoke_frame(yaw=yaw,mounting=mounting),0,False)
                self.assertIsNotNone(result)
                self.assertAlmostEqual(result.yaw,yaw,delta=1)

    def setUp(self):
        self.tracker = ArucoTracker()
        self.dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)

    def test_two_markers_and_independent_loss(self):
        frame = throttle_frame(.5, yoke=True)
        yoke, throttle = self.tracker.detect(frame, 0, False)
        self.assertIsNotNone(yoke)
        self.assertIsNotNone(throttle)
        self.assertAlmostEqual(yoke.roll, 0, delta=.2)
        self.assertAlmostEqual(throttle.value, .5, places=3)
        frame[280:440, 220:380] = 255
        yoke, throttle = self.tracker.detect(frame, 1, False)
        self.assertIsNone(yoke)
        self.assertIsNotNone(throttle)

    def test_projected_pitch_and_roll_are_measured(self):
        width, height = 1280, 720
        matrix = np.array([[width * .72, 0, width / 2], [0, width * .72, height / 2], [0, 0, 1]], dtype=np.float64)
        objects = np.array([[-.5, .5, 0], [.5, .5, 0], [.5, -.5, 0], [-.5, -.5, 0]], dtype=np.float32)
        pitch, roll = math.radians(25), math.radians(15)
        rx = np.array([[1, 0, 0], [0, math.cos(pitch), -math.sin(pitch)], [0, math.sin(pitch), math.cos(pitch)]])
        rz = np.array([[math.cos(roll), -math.sin(roll), 0], [math.sin(roll), math.cos(roll), 0], [0, 0, 1]])
        rotation = rz @ rx @ np.diag([1., -1., -1.])
        rvec, _ = cv2.Rodrigues(rotation)
        target, _ = cv2.projectPoints(objects, rvec, np.array([0., 0., 4.]), matrix, np.zeros(5))
        target = target.reshape(4, 2).astype(np.float32)
        marker = cv2.aruco.generateImageMarker(self.dictionary, 7, 400)
        transform = cv2.getPerspectiveTransform(np.array([[0, 0], [399, 0], [399, 399], [0, 399]], np.float32), target)
        image = cv2.warpPerspective(marker, transform, (width, height), borderValue=255)
        yoke, _ = self.tracker.detect(cv2.cvtColor(image, cv2.COLOR_GRAY2BGR), 0, False)
        self.assertIsNotNone(yoke)
        self.assertAlmostEqual(yoke.roll, 15, delta=2)
        self.assertAlmostEqual(yoke.pitch, -25, delta=3)

    def test_duplicate_marker_rejected(self):
        image = np.full((720, 1280, 3), 255, dtype=np.uint8)
        marker = cv2.cvtColor(cv2.aruco.generateImageMarker(self.dictionary, 7, 160), cv2.COLOR_GRAY2BGR)
        image[300:460, 200:360] = marker
        image[300:460, 800:960] = marker
        yoke, throttle = self.tracker.detect(image, 0, False)
        self.assertIsNone(yoke)
        self.assertIsNone(throttle)


if __name__ == "__main__":
    unittest.main()
