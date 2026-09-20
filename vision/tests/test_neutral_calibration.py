import unittest

from vision.calibration import YokeObservation, wrap_degrees
from vision.neutral_calibration import NeutralCalibration


class NeutralCalibrationTests(unittest.TestCase):
    def test_three_seconds_use_whole_window_and_wrap_upside_down_roll(self):
        capture = NeutralCalibration()
        capture.start("first")
        for i in range(90):
            # Median of the entire window differs from the final sample.
            tilt = 12 if i < 65 else 14
            self.assertIsNone(capture.observe(YokeObservation(179+(-1)**i, tilt, 1), i/30))
        neutral = capture.observe(YokeObservation(-180, 14, 1), 3)
        self.assertAlmostEqual(wrap_degrees(neutral[0]+180), 0)
        self.assertEqual(neutral[1], 12)
        self.assertEqual(capture.packet()["elapsed"], 3)
        self.assertEqual(capture.state, "complete")
        self.assertIsNone(capture.observe(YokeObservation(20, 30, 1), 4))

    def test_loss_motion_and_capture_gaps_restart_full_window(self):
        for interruption in ("loss", "motion", "gap", "weak"):
            with self.subTest(interruption=interruption):
                capture = NeutralCalibration(); capture.start(interruption)
                for i in range(81): capture.observe(YokeObservation(0, 0, 1), i/30)
                sample = None if interruption == "loss" else YokeObservation(15 if interruption == "motion" else 0, 0, .3 if interruption == "weak" else 1)
                now = 3 if interruption == "gap" else 2.71
                self.assertIsNone(capture.observe(sample, now))
                self.assertEqual(capture.elapsed, 0)
                for i in range(89):
                    self.assertIsNone(capture.observe(YokeObservation(10, 12, 1), now+.01+i/30))
                self.assertEqual(capture.observe(YokeObservation(10, 12, 1), now+3.02), (10, 12, 0))

    def test_swivelling_restarts_calibration_and_captures_yaw_neutral(self):
        capture = NeutralCalibration(); capture.start("yaw")
        for i in range(80): capture.observe(YokeObservation(0,0,1,yaw=3),i/30)
        self.assertIsNone(capture.observe(YokeObservation(0,0,1,yaw=12),80/30))
        self.assertEqual(capture.elapsed,0)
        for i in range(1,90): capture.observe(YokeObservation(0,0,1,yaw=12),80/30+i/30)
        neutral = capture.observe(YokeObservation(0,0,1,yaw=12),80/30+3.01)
        self.assertEqual(neutral,(0,0,12))

    def test_cancel_and_new_request_cannot_reuse_old_samples(self):
        capture = NeutralCalibration(); capture.start("first")
        for i in range(60): capture.observe(YokeObservation(10, 12, 1), i/30)
        capture.cancel()
        self.assertIsNone(capture.observe(YokeObservation(10, 12, 1), 3))
        capture.start("second")
        self.assertIsNone(capture.observe(YokeObservation(30, 25, 1), 4))
        self.assertEqual(capture.elapsed, 0)
        self.assertEqual(capture.request_id, "second")
