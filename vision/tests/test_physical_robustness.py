"""Conditions a real desk produces: distance, low resolution, dim light, blur, new pilots."""
import math
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import cv2
import numpy as np

from vision import legacy_tracker as tracker
from vision.calibration import AxisCalibration, Calibration, ThrottleCalibration, YokeObservation, ThrottleObservation
from vision.placement import FAIL, PASS, WARN, PlacementCheck, format_report
from vision.tests.synthetic import cockpit

# What the guided calibration would capture for the synthetic desk (camera tilted 20 degrees).
DESK = Calibration(AxisCalibration(30, 0, -30), AxisCalibration(5, -20, -45), ThrottleCalibration((.67, .6), (.65, .5)))


def fly(frames, prior=True, **conditions):
    """Sweep pitch, roll and throttle; return (yoke seen, throttle seen, wrong pitch, 20-degree jumps)."""
    rng = np.random.default_rng(5)
    detector = tracker.ArucoTracker()
    if prior:
        detector.set_pitch_range(DESK)
    width, height = conditions.pop("size", (1280, 720))
    seen_yoke = seen_throttle = wrong = jumps = 0
    previous = None
    for index in range(frames):
        seconds = index / 30
        pitch = 25 * math.sin(seconds * 2.2)
        frame = cockpit(width, height, rng, pitch, 30 * math.sin(seconds * 1.7), .5 + .5 * math.sin(seconds * 1.1), **conditions)
        yoke, throttle = detector.detect(frame, seconds, False)
        seen_throttle += throttle is not None
        if yoke is not None:
            seen_yoke += 1
            wrong += abs(yoke.pitch + pitch + 20) > 12
            jumps += previous is not None and abs(yoke.pitch - previous) > 20
        previous = None if yoke is None else yoke.pitch
    return seen_yoke / frames, seen_throttle / frames, wrong / frames, jumps


class DetectionTests(unittest.TestCase):
    def test_throttle_survives_documented_low_resolution_at_one_metre(self):
        # The 50 mm marker is about 23 px here; a fixed 24 px floor lost it entirely.
        yoke, throttle, wrong, _ = fly(45, size=(640, 480))
        self.assertGreaterEqual(yoke, .97)
        self.assertGreaterEqual(throttle, .97)
        self.assertLessEqual(wrong, .08)

    def test_confidence_follows_resolution_so_low_resolution_can_calibrate(self):
        detector = tracker.ArucoTracker()
        frame = cockpit(640, 480, np.random.default_rng(1), distance=.7)
        yoke, throttle = detector.detect(frame, 0, False)
        # The calibration wizard ignores observations under 0.4.
        self.assertGreaterEqual(throttle.confidence, .4)
        self.assertGreaterEqual(yoke.confidence, .4)

    def test_blurred_throttle_is_rescued_near_its_last_position(self):
        _, throttle, _, _ = fly(45, blur=3.5)
        self.assertGreaterEqual(throttle, .8)

    def test_dim_room_keeps_both_markers_without_pitch_flips(self):
        yoke, throttle, wrong, jumps = fly(60, light=.35, noise=9)
        self.assertEqual((yoke, throttle), (1.0, 1.0))
        self.assertEqual(wrong, 0)
        self.assertEqual(jumps, 0)

    def test_very_dim_room_pitch_does_not_buck(self):
        yoke, throttle, wrong, jumps = fly(90, light=.2, noise=12)
        self.assertGreaterEqual(min(yoke, throttle), .95)
        # Residual errors are confined to the head-on zone at the nose-down end,
        # which this sweep crosses often; they must not become 40-degree bucking.
        self.assertLessEqual(wrong, .15)
        self.assertLessEqual(jumps, 2)

    def test_absent_marker_does_not_cost_the_frame_rate(self):
        detector = tracker.ArucoTracker()
        frame = np.full((720, 1280, 3), 170, np.uint8)
        with patch.object(detector, "_detect_wanted", wraps=detector._detect_wanted) as calls:
            for index in range(12):
                detector.detect(frame, index / 30, False)
        # One primary pass per frame, plus whole-frame rescues only on every sixth miss.
        self.assertLessEqual(calls.call_count, 12 + 2 * 2 * 4)


class PoseBranchTests(unittest.TestCase):
    def setUp(self):
        self.detector = tracker.ArucoTracker()

    def choose(self, now, *candidates):
        chosen = self.detector._choose_pose([(error, 0.0, pitch, None, None) for error, pitch in candidates], now, 64.0)
        self.detector.previous_pose, self.detector.previous_pose_time = chosen[2], now
        return chosen[2]

    def test_single_noisy_frame_cannot_flip_pitch(self):
        self.assertEqual(self.choose(0, (.2, -20), (.6, 24)), -20)
        self.assertEqual(self.choose(.03, (.7, -21), (.3, 25)), -21, "One frame of better mirror error is noise")
        self.assertEqual(self.choose(.06, (.2, -22), (.6, 26)), -22)

    def test_sustained_evidence_recovers_from_a_wrong_branch(self):
        self.choose(0, (.3, 24), (.31, -20))
        picks = [self.choose(.03 * (index + 1), (.2, -20), (.7, 24)) for index in range(12)]
        self.assertEqual(picks[-1], -20)
        self.assertLessEqual(picks.index(-20), 8, "Recovery within about a quarter second")

    def test_calibrated_range_rejects_the_mirrored_solution(self):
        self.detector.set_pitch_range(DESK)
        self.assertEqual(self.choose(0, (.4, -20), (.2, 24)), -20, "A fresh sighting prefers the calibrated range")
        self.detector.previous_pose = 24
        self.assertEqual(self.choose(.03, (.4, -20), (.2, 24)), -20, "An out-of-range branch is left immediately")

    def test_stale_history_is_ignored(self):
        self.choose(0, (.2, -20), (.6, 24))
        self.assertEqual(self.choose(5, (.6, -20), (.2, 24)), 24)


class RecenterTests(unittest.TestCase):
    def test_recenter_shifts_neutral_and_keeps_travel(self):
        moved = DESK.recentered(6, -14)
        self.assertAlmostEqual(moved.roll.normalize(6), 0)
        self.assertAlmostEqual(moved.pitch.normalize(-14), 0)
        self.assertAlmostEqual(moved.roll.normalize(6 - 30), 1)
        self.assertAlmostEqual(moved.pitch.normalize(-14 - 25), 1)
        self.assertEqual(moved.throttle, DESK.throttle)

    def test_recenter_rejects_a_moved_camera(self):
        with self.assertRaisesRegex(ValueError, "full calibration"):
            DESK.recentered(40, -20)
        with self.assertRaises(ValueError):
            DESK.recentered(float("nan"), 0)

    def test_one_step_wizard(self):
        wizard = tracker.CalibrationWizard(0, 1280, 720, base=DESK)
        self.assertIsNone(wizard.capture(), "Needs a still second first")
        for _ in range(20):
            wizard.observe(YokeObservation(-5, -17, .9), None)
        result = wizard.capture()
        self.assertAlmostEqual(result.roll.neutral, -5)
        self.assertAlmostEqual(result.pitch.neutral, -17)
        with tempfile.TemporaryDirectory() as directory:
            result.save(Path(directory) / "calibration.json")


class PlacementTests(unittest.TestCase):
    def collect(self, frames=120, fps=30.0, pitch_center=-25.0, travel=.2, flip_every=0, throttle=True):
        check = PlacementCheck(1280)
        for index in range(frames):
            phase = max(index - 30, 0) / (frames - 30) * 2 * math.pi  # a still second, then one full sweep
            pitch = pitch_center + 22 * math.sin(phase)
            if flip_every and index % flip_every == 0:
                pitch = -pitch
            yoke = YokeObservation(35 * math.sin(phase * 2), pitch, .9)
            slider = ThrottleObservation((.7, .6 - travel * index / frames), .8) if throttle else None
            check.add(index / fps, yoke, slider, 64.0, 46.0)
        return {label: (status, detail) for status, label, detail in check.report()}

    def test_good_placement_passes(self):
        rows = self.collect()
        self.assertTrue(all(status == PASS for status, _ in rows.values()), rows)
        self.assertIn("Ready", format_report([(s, l, d) for l, (s, d) in rows.items()]))

    def test_head_on_geometry_and_flips_are_reported_with_the_fix(self):
        rows = self.collect(pitch_center=0, flip_every=17)
        self.assertEqual(rows["Pitch flips"][0], FAIL)
        self.assertEqual(rows["Pitch geometry"][0], WARN)
        self.assertIn("lean the marker plate", rows["Pitch geometry"][1])

    def test_throttle_moving_toward_the_lens_fails(self):
        rows = self.collect(travel=.03)
        self.assertEqual(rows["Throttle travel"][0], FAIL)
        self.assertIn("Raise or offset", rows["Throttle travel"][1])

    def test_missing_marker_and_slow_camera(self):
        rows = self.collect(throttle=False, fps=15.0)
        self.assertEqual(rows["Throttle (ID 23)"][0], FAIL)
        self.assertEqual(rows["Frame rate"][0], FAIL)

    def test_check_mode_reads_frames_reports_and_releases_camera(self):
        class Camera:
            def __init__(self):
                self.rng, self.index, self.closed = np.random.default_rng(3), 0, False

            def read(self):
                self.index += 1
                moving = max(self.index - 20, 0)  # hold still first, as the instructions ask
                return cockpit(1280, 720, self.rng, 20 * math.sin(moving / 5), 25 * math.sin(moving / 7), (moving % 40) / 40)

            def close(self):
                self.closed = True

        camera = Camera()
        args = tracker.parser().parse_args(["--camera", "0", "--check", "--no-preview", "--duration", "2.5"])
        with patch.object(tracker, "CameraSource", return_value=camera), \
                patch.object(cv2, "VideoCapture", side_effect=AssertionError("No real camera allowed")), \
                patch("builtins.print") as printed:
            status = tracker.run_check(args)
        report = printed.call_args_list[-1].args[0]
        self.assertIn("Throttle travel", report)
        self.assertIn("Yoke (ID 7) visibility", report)
        self.assertEqual(status, 0, report)
        self.assertTrue(camera.closed)


if __name__ == "__main__":
    unittest.main()
