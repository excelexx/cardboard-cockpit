"""Display mirroring and fixed framing must not alter tracking input."""
import unittest
import cv2
import numpy as np
from vision.preview_framer import PreviewFramer
from vision.tests.throttle_fixture import throttle_frame

class PreviewFramerTests(unittest.TestCase):
    def setUp(self):
        self.framer = PreviewFramer(cv2, np)

    def test_all_roles_keep_full_frame_and_mirror_once(self):
        for focus in ('', 'throttle', 'yoke', 'weapons', 'all'):
            for position in (0, .5, 1):
                with self.subTest(focus=focus, position=position):
                    frame = throttle_frame(position, yoke=True)
                    original = frame.copy()
                    view = self.framer.render(frame, focus, 0, 'CAMERA')
                    expected = cv2.resize(cv2.flip(original, 1), (960, 540), interpolation=cv2.INTER_AREA)
                    np.testing.assert_array_equal(view[:510], expected[:510])
                    np.testing.assert_array_equal(frame, original)
                    self.assertEqual(view.shape, (540, 960, 3))

    def test_raising_and_hiding_yoke_never_moves_background(self):
        frame = np.full((720, 1280, 3), 230, np.uint8)
        frame[:, :150] = (20, 50, 100)
        marker = cv2.aruco.generateImageMarker(cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50), 7, 120)
        baseline = self.framer.render(frame, 'yoke', 0, 'CAMERA')
        for y in (70, 280, 480):
            raised = frame.copy()
            raised[y:y+120, 580:700] = cv2.cvtColor(marker, cv2.COLOR_GRAY2BGR)
            view = self.framer.render(raised, 'yoke', 1, 'CAMERA')
            np.testing.assert_array_equal(view[:510, 800:], baseline[:510, 800:])
        self.assertIsNone(self.framer.render(None, 'yoke', 2, 'CAMERA'))

    def test_two_camera_ready_view_mirrors_each_camera_without_swapping_roles(self):
        primary = np.zeros((200, 400, 3), np.uint8)
        primary[:, :200] = (10, 20, 230)
        secondary = np.zeros_like(primary)
        secondary[:, :200] = (230, 20, 10)
        view = self.framer.combined(primary, secondary, 'LAPTOP', 'PHONE')
        self.assertEqual(view.shape, (540, 960, 3))
        np.testing.assert_array_equal(view[250, 400], (10, 20, 230))
        np.testing.assert_array_equal(view[250, 880], (230, 20, 10))
        np.testing.assert_array_equal(view[250, 50], (0, 0, 0))
        np.testing.assert_array_equal(view[250, 530], (0, 0, 0))
