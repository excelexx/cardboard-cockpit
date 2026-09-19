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


@unittest.skipIf(cv2 is None, "Optional OpenCV/NumPy packages not installed")
class ArucoTests(unittest.TestCase):
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

    def test_weapon_faces_and_ambiguity(self):
        def image_with(ids):
            frame=np.full((720,1280,3),255,dtype=np.uint8)
            for i,marker_id in enumerate(ids):
                m=cv2.aruco.generateImageMarker(self.dictionary,marker_id,100)
                frame[280:380,100+i*200:200+i*200]=cv2.cvtColor(m,cv2.COLOR_GRAY2BGR)
            return frame
        self.tracker.detect(image_with([7,23,31,41]),0,False)
        self.assertTrue(self.tracker.weapon_observations['primary'][0])
        self.assertTrue(self.tracker.weapon_observations['salvo'][0])
        self.tracker.detect(image_with([31,32,42]),1,False)
        self.assertNotIn('primary',self.tracker.weapon_observations)
        self.assertFalse(self.tracker.weapon_observations['salvo'][0])
        self.tracker.detect(image_with([31,31,41]),2,False)
        self.assertNotIn('primary',self.tracker.weapon_observations)

if __name__ == "__main__":
    unittest.main()
