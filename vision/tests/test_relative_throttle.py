import unittest

import cv2
import numpy as np

from vision.tracker import ArucoTracker, PaperController
from vision.relative_throttle import RelativeThrottle
from vision.tests.throttle_fixture import throttle_frame


class RelativeThrottleTests(unittest.TestCase):
    def setUp(self):
        self.tracker = ArucoTracker()

    def test_actual_detection_idle_half_full_and_clamping(self):
        for fraction in (-.2, 0, .25, .5, .75, 1, 1.2):
            with self.subTest(fraction=fraction):
                _, observed = self.tracker.detect(throttle_frame(fraction), 0, False)
                self.assertIsNotNone(observed)
                self.assertAlmostEqual(observed.value, min(1, max(0, fraction)), delta=.004)
                self.assertGreater(observed.confidence, .4)

    def test_rendered_board_rotation_scale_and_translation(self):
        source = throttle_frame(.25)
        for angle, scale, dx, dy in ((15, .8, -70, 10), (-35, .65, -100, -25), (180, .8, 0, 0)):
            matrix = cv2.getRotationMatrix2D((640, 360), angle, scale)
            matrix[:, 2] += (dx, dy)
            frame = cv2.warpAffine(source, matrix, (1280, 720), borderValue=(255, 255, 255))
            _, observed = self.tracker.detect(frame, 0, False)
            self.assertIsNotNone(observed)
            self.assertAlmostEqual(observed.value, .25, delta=.025)

    def test_perspective_corrects_fraction_instead_of_using_pixel_distance(self):
        source = throttle_frame(.25)
        transform = np.array([[.9, .1, 50], [.02, 1, 0], [.00065, .00015, 1]], np.float64)
        frame = cv2.warpPerspective(source, transform, (1280, 720), borderValue=(255, 255, 255))
        _, observed = self.tracker.detect(frame, 0, False)
        self.assertIsNotNone(observed)
        self.assertAlmostEqual(observed.value, .25, delta=.035)

    def test_each_missing_or_duplicate_tag_stops_throttle_only(self):
        for marker_id, x, y in ((0, 600, 300), (1, 900, 500), (2, 1000, 300)):
            for duplicate in (False, True):
                frame = throttle_frame(.75, yoke=True)
                if duplicate:
                    frame[100:200, 100:200] = frame[y:y + 100, x:x + 100]
                else:
                    frame[y:y + 100, x:x + 100] = 255
                yoke, throttle = self.tracker.detect(frame, 0, False)
                self.assertIsNotNone(yoke)
                self.assertIsNone(throttle)
        _, restored = self.tracker.detect(throttle_frame(.25), 1, False)
        self.assertAlmostEqual(restored.value, .25, delta=.004)

    def test_paper_mode_throttle_does_not_need_visible_or_centered_yoke(self):
        for mirrored in (False, True):
            frame = throttle_frame(.75)
            if mirrored:
                frame = cv2.flip(frame, 1)
            yoke, observed = PaperController().detect(frame, 0, False)
            self.assertIsNone(yoke)
            self.assertIsNotNone(observed)
            self.assertAlmostEqual(observed.value, .75, delta=.004)

    def test_degenerate_small_and_nonfinite_geometry_rejected(self):
        square = np.array([[100, 100], [200, 100], [200, 200], [100, 200]], np.float32)
        tracker = RelativeThrottle(cv2, np)
        ids = np.array([[0], [1], [2]])
        for corners in ([square, square, square],
                        [square * .1, square + 200, square + 400],
                        [square * np.nan, square + 200, square + 400]):
            self.assertIsNone(tracker.observe(corners, ids))


if __name__ == "__main__":
    unittest.main()
