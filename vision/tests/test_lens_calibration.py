"""Synthetic optics: exercise non-default focal lengths and real distortion."""
import asyncio
from dataclasses import replace
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import cv2
import numpy as np

from vision.camera_calibration import LensCalibrator, LensProfile, run_lens_calibration, write_checkerboard
from vision.pose_guard import PoseGuard
from vision.tracker import PaperController, parser, run


def profile():
    return LensProfile(1, 1280, 720,
                       [[1050., 0, 607.], [0, 1030., 348.], [0, 0, 1]],
                       [-.18, .045, .002, -.001, -.005], .15, 20)


class LensTests(unittest.TestCase):
    def test_profile_round_trip_and_source_mismatch(self):
        expected = profile()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "iphone.lens.local.json"
            expected.save(path)
            self.assertEqual(LensProfile.load(path), expected)
            path.write_text('{"matrix": []}')
            with self.assertRaisesRegex(ValueError, "Cannot use lens profile"):
                LensProfile.load(path)
        for source in ((0, 1280, 720), (1, 640, 480), (1, 1920, 1080)):
            with self.assertRaisesRegex(ValueError, "Lens profile is for"):
                expected.check_source(*source)
        for bad in (replace(expected, rms=1.5), replace(expected, rms=float('nan')),
                    replace(expected, distortion=[1, 2]), replace(expected, views=2),
                    replace(expected, matrix=[[0, 0, 0]] * 3)):
            with self.assertRaises(ValueError):
                bad.validate()

    def test_calibrated_tilt_stays_constant_when_marker_moves_in_image(self):
        measured = PaperController(lens=profile())
        approximate = PaperController()
        k = np.array(profile().matrix)
        d = np.array(profile().distortion)
        square = np.array([[-.5, -.5, 0], [.5, -.5, 0], [.5, .5, 0], [-.5, .5, 0]])
        approximate_errors = []
        for tilt in (-25, 0, 25):
            for bank in (-20, 0, 20):
                rx = cv2.Rodrigues(np.array([np.deg2rad(tilt), 0, 0]))[0]
                rz = cv2.Rodrigues(np.array([0, 0, np.deg2rad(bank)]))[0]
                rvec = cv2.Rodrigues(rz @ rx)[0]
                expected = -np.rad2deg(np.arctan2(np.cos(np.deg2rad(bank)) * np.sin(np.deg2rad(tilt)), np.cos(np.deg2rad(tilt))))
                for position in ((0, 0, 4), (-1, -.7, 4), (1, .7, 4), (.7, -.8, 6)):
                    points = cv2.projectPoints(square, rvec, np.array(position, float), k, d)[0].reshape(4, 2)
                    roll, pitch = measured.perspective_angles(points, 1280, 720)
                    self.assertAlmostEqual(roll, bank, delta=.002)
                    self.assertAlmostEqual(pitch, expected, delta=.002)
                    approximate_errors.append(abs(approximate.perspective_angles(points, 1280, 720)[1] - expected))
        self.assertGreater(max(approximate_errors), 3, "Fixture must expose the old approximate model's error")

    def test_mirrored_detection_uses_native_lens_coordinates(self):
        p = profile()
        # A mirrored native camera has mirrored principal point and p2 sign.
        k = np.array(p.matrix)
        mirrored_k = k.copy(); mirrored_k[0, 2] = 1279 - k[0, 2]
        mirrored_d = np.array(p.distortion); mirrored_d[3] *= -1
        native = replace(p, matrix=mirrored_k.tolist(), distortion=mirrored_d.tolist())
        square = np.array([[-.5, -.5, 0], [.5, -.5, 0], [.5, .5, 0], [-.5, .5, 0]])
        points = cv2.projectPoints(square, np.array([-.3, .1, .2]), np.array([.6, -.4, 4.]), k, np.array(p.distortion))[0].reshape(4, 2)
        normal = PaperController(lens=p).perspective_angles(points, 1280, 720)
        # detectMarkers has flipped the mirrored native frame back for decoding.
        mirrored = PaperController(lens=native).perspective_angles(points, 1280, 720, mirrored=True)
        np.testing.assert_allclose(normal, mirrored, atol=.002)

    def test_solve_recovers_camera_from_varied_checkerboard_views(self):
        p = profile()
        calibrator = LensCalibrator(1, 1280, 720)
        objects = LensCalibrator.object_points()
        rng = np.random.default_rng(2026)
        for _ in range(100):
            rotation = np.array([rng.uniform(-.5, .5), rng.uniform(-.5, .5), rng.uniform(-.2, .2)])
            translation = np.array([rng.uniform(-8, 0), rng.uniform(-5, 0), rng.uniform(18, 25)])
            points = cv2.projectPoints(objects, rotation, translation, np.array(p.matrix), np.array(p.distortion))[0]
            points += rng.normal(0, .06, points.shape)
            try:
                calibrator.add(points)
            except ValueError:
                continue
            if len(calibrator.image_points) == 25:
                break
        result = calibrator.solve()
        self.assertLess(result.rms, .15)
        np.testing.assert_allclose(np.array(result.matrix)[:2, :2], np.array(p.matrix)[:2, :2], atol=5)
        np.testing.assert_allclose(np.array(result.matrix)[:2, 2], np.array(p.matrix)[:2, 2], atol=5)

    def test_capture_rejects_duplicates_small_board_and_insufficient_views(self):
        calibrator = LensCalibrator(1, 1280, 720)
        points = LensCalibrator.object_points()[:, :2] * 30 + [200, 150]
        calibrator.add(points)
        for repeated in (points, points[::-1], points + 1):
            with self.assertRaisesRegex(ValueError, "Already captured"):
                calibrator.add(repeated)
        with self.assertRaisesRegex(ValueError, "closer"):
            calibrator.add(points * .2)
        with self.assertRaisesRegex(ValueError, "at least 15"):
            calibrator.solve()

    def test_pattern_and_board_detector_agree(self):
        # Same 10x7 parity/white border as the vector print target.
        board = np.full((640, 880), 255, np.uint8)
        for y in range(7):
            for x in range(10):
                if (x + y) % 2 == 0:
                    board[40+y*80:40+(y+1)*80, 40+x*80:40+(x+1)*80] = 0
        found, corners = cv2.findChessboardCornersSB(board, LensCalibrator.PATTERN)
        self.assertTrue(found)
        self.assertEqual(len(corners), 54)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "board.svg"
            write_checkerboard(path)
            self.assertEqual(path.read_text().count('fill="black"'), 35)

    def test_cancel_closes_camera_without_saving(self):
        class Camera:
            closed = False
            def read(self): return np.full((720, 1280, 3), 255, np.uint8)
            def close(self): self.closed = True
        camera = Camera()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "lens.json"
            args = parser().parse_args(['--camera', '1', '--calibrate-lens', '--intrinsics', str(path)])
            with patch.object(cv2, 'imshow'), patch.object(cv2, 'waitKey', return_value=ord('q')), \
                    patch.object(cv2, 'getWindowProperty', return_value=1):
                run_lens_calibration(args, lambda *unused: camera)
            self.assertTrue(camera.closed)
            self.assertFalse(path.exists())


class LensPipelineTests(unittest.IsolatedAsyncioTestCase):
    async def test_wrong_camera_rejected_before_camera_access(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "lens.json"
            profile().save(path)
            args = parser().parse_args(['--camera', '0', '--paper-test', '--intrinsics', str(path)])
            with patch('vision.tracker.CameraSource', side_effect=AssertionError("Do not open camera")):
                with self.assertRaisesRegex(ValueError, "camera index differs"):
                    await run(args)


class PoseGuardTests(unittest.TestCase):
    def test_isolated_spike_rejected_but_consistent_step_accepted(self):
        guard = PoseGuard()
        self.assertTrue(guard.accept((0, 0), 0))
        self.assertFalse(guard.accept((0, 45), 1/30))
        self.assertTrue(guard.accept((0, 0), 2/30))
        self.assertFalse(guard.accept((0, 45), 3/30))
        self.assertFalse(guard.accept((0, 45), 4/30))
        self.assertTrue(guard.accept((0, 45), 5/30))

    def test_steady_rotation_wraparound_and_reacquisition(self):
        guard = PoseGuard()
        for frame in range(90):
            angle = (175 + frame * 2 + 180) % 360 - 180
            self.assertTrue(guard.accept((angle, 0), frame / 30))
        self.assertTrue(guard.accept((0, -40), 5))
        self.assertFalse(guard.accept((float('nan'), 0), 5.1))


if __name__ == '__main__':
    unittest.main()
