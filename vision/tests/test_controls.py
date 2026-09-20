import json
import math
from pathlib import Path
import tempfile
import unittest

from vision.calibration import (AxisCalibration, Calibration, ControlFilter,
    ThrottleCalibration, ThrottleObservation, YokeObservation, RelativeThrottleObservation, dead_zone,
    simulated_calibration, simulated_observations)
from vision.tracker import CalibrationWizard, parser


class CalibrationTests(unittest.TestCase):
    def test_asymmetric_ranges(self):
        axis = AxisCalibration(-40, 10, 40)
        axis.validate("Roll")
        self.assertAlmostEqual(axis.normalize(-15), -.5)
        self.assertAlmostEqual(axis.normalize(25), .5)
        self.assertEqual(axis.normalize(10), 0)
        self.assertEqual(axis.normalize(-90), -1)
        self.assertEqual(axis.normalize(90), 1)

    def test_reversed_camera_sign(self):
        axis = AxisCalibration(50, 10, -30)
        axis.validate("Roll")
        self.assertAlmostEqual(axis.normalize(30), -.5)
        self.assertAlmostEqual(axis.normalize(-10), .5)

    def test_wrap_at_180(self):
        axis = AxisCalibration(150, 175, -160)
        axis.validate("Roll")
        self.assertAlmostEqual(axis.normalize(-172.5), .5)

    def test_bad_endpoints(self):
        for axis in (AxisCalibration(0, 0, 30), AxisCalibration(10, 0, 20),
                     AxisCalibration(-1, 0, 1), AxisCalibration(-30, 0, math.inf),
                     AxisCalibration(False, 0, 30)):
            with self.subTest(axis=axis), self.assertRaises(ValueError):
                axis.validate("Roll")

    def test_throttle_diagonal_projection(self):
        axis = ThrottleCalibration((.1, .8), (.9, .2))
        axis.validate()
        self.assertAlmostEqual(axis.normalize((.5, .5)), .5)
        self.assertEqual(axis.normalize((.1, .8)), 0)
        self.assertEqual(axis.normalize((.9, .2)), 1)

    def test_throttle_reverse(self):
        axis = ThrottleCalibration((.8, .4), (.2, .4))
        axis.validate()
        self.assertAlmostEqual(axis.normalize((.5, .4)), .5)

    def test_throttle_span_rejection(self):
        for endpoints in (((.4, .4), (.41, .4)), ((.4, .4), (.4, .4)), ((.4, .4), (math.nan, .4))):
            with self.subTest(endpoints=endpoints), self.assertRaises(ValueError):
                ThrottleCalibration(*endpoints).validate()

    def test_round_trip_and_invalid_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "calibration.json"
            expected = simulated_calibration()
            expected.save(path)
            self.assertEqual(Calibration.load(path), expected)
            path.write_text('{"version":1}', encoding="utf-8")
            with self.assertRaises(ValueError):
                Calibration.load(path)

    def test_wizard_full_flow_and_distinct_pitch_spans(self):
        wizard = CalibrationWizard(0, 1280, 720)
        captures = [YokeObservation(4, 5, 1), YokeObservation(35, 5, 1),
                    YokeObservation(-40, 5, 1), YokeObservation(4, -20, 1),
                    YokeObservation(4, 28, 1)]
        result = None
        for index in range(5):
            throttle = ThrottleObservation((.75, .8 if index == 5 else .4), 1)
            for _ in range(20):
                wizard.observe(captures[index], throttle)
            result = wizard.capture()
        self.assertIsInstance(result, Calibration)
        self.assertEqual(result.pitch.negative, -20)
        self.assertEqual(result.pitch.positive, 28)
        self.assertEqual(result.roll.normalize(35), -1)
        self.assertEqual(result.pitch.normalize(-20), -1)

    def test_wizard_rejects_missing_or_moving_marker(self):
        wizard = CalibrationWizard(0, 1280, 720)
        self.assertIsNone(wizard.capture())
        for i in range(20):
            wizard.observe(YokeObservation(i * 3, 0, 1), None)
        self.assertIsNone(wizard.capture())
        self.assertEqual(wizard.index, 0)
        wizard.observe(None, None)
        self.assertEqual(len(wizard.samples), 0)


class FilterTests(unittest.TestCase):
    def make(self):
        return ControlFilter(simulated_calibration())

    def warm(self, controller, yoke=None, throttle=None):
        for i in range(90):
            packet = controller.step(i / 30, 1000 + i * 33, yoke, throttle)
        return packet

    def test_deadzone_continuity(self):
        self.assertEqual(dead_zone(.04, .06), 0)
        self.assertEqual(dead_zone(-.06, .06), 0)
        self.assertAlmostEqual(dead_zone(1, .06), 1)
        self.assertAlmostEqual(dead_zone(-1, .06), -1)

    def test_pitch_gain_is_1_2_in_both_directions_without_changing_other_controls(self):
        for tilt in (-25, -8, -1, 0, 1, 8, 25):
            with self.subTest(tilt=tilt):
                baseline = self.warm(self.make(), YokeObservation(9, tilt, 1), RelativeThrottleObservation(.35, 1))
                boosted = self.warm(ControlFilter(simulated_calibration(), pitch_gain=1.2),
                                    YokeObservation(9, tilt, 1), RelativeThrottleObservation(.35, 1))
                self.assertAlmostEqual(boosted["yoke"]["pitch"], max(-1, min(1, baseline["yoke"]["pitch"]*1.2)), places=4)
                self.assertEqual(boosted["yoke"]["roll"], baseline["yoke"]["roll"])
                self.assertEqual(boosted["throttle"], baseline["throttle"])

    def test_packet_contract_and_limits(self):
        controller = self.make()
        packet = self.warm(controller, YokeObservation(100, -100, 1), ThrottleObservation((.75, -2), 1))
        self.assertEqual(set(packet), {"version", "sequence", "timestamp", "tracking", "yoke", "throttle"})
        self.assertEqual(packet["version"], 1)
        self.assertEqual(packet["sequence"], 89)
        self.assertIs(type(packet["tracking"]), bool)
        self.assertAlmostEqual(packet["yoke"]["roll"], 1)
        self.assertAlmostEqual(packet["yoke"]["pitch"], -1)
        self.assertAlmostEqual(packet["throttle"]["value"], 1)
        json.dumps(packet, allow_nan=False)

    def test_yaw_is_independent_bounded_and_expires_with_yoke(self):
        for yaw in (-60,-12,0,12,60):
            controller = self.make()
            result = self.warm(controller,YokeObservation(0,0,1,yaw=yaw))
            self.assertAlmostEqual(result["yoke"]["yaw"],dead_zone(max(-1,min(1,yaw/25)),.06),places=4)
            self.assertEqual((result["yoke"]["roll"],result["yoke"]["pitch"]),(0,0))
            for i in range(90): result = controller.step(3+i/30,4000+i*33,None,None)
            self.assertEqual(result["yoke"]["confidence"],0)
            self.assertAlmostEqual(result["yoke"]["yaw"],0,places=3)
    def test_startup_is_neutral(self):
        packet = self.make().step(1, 1000, None, None)
        self.assertFalse(packet["tracking"])
        self.assertEqual(packet["yoke"], {"roll": 0, "pitch": 0, "yaw": 0, "confidence": 0})
        self.assertEqual(packet["throttle"], {"value": 0, "confidence": 0})

    def test_yoke_loss_then_neutral(self):
        controller = self.make()
        self.warm(controller, YokeObservation(35, 25, 1))
        held = controller.step(3.05, 4050, None, None)
        self.assertGreater(held["yoke"]["roll"], .95)
        self.assertEqual(held["yoke"]["confidence"], 0)
        for i in range(60):
            packet = controller.step(3.1 + i / 30, 4100 + i * 33, None, None)
        self.assertLess(abs(packet["yoke"]["roll"]), .001)
        self.assertLess(abs(packet["yoke"]["pitch"]), .001)

    def test_throttle_loss_holds_power_independently(self):
        controller = self.make()
        initial = self.warm(controller, YokeObservation(0, 0, 1), ThrottleObservation((.75, .5), 1))
        for i in range(90):
            packet = controller.step(3 + i / 30, 5000 + i * 33, YokeObservation(35, 0, 1), None)
        self.assertEqual(packet["throttle"]["value"], initial["throttle"]["value"])
        self.assertEqual(packet["throttle"]["confidence"], 0)
        self.assertEqual(packet["yoke"]["confidence"], 1)
        self.assertAlmostEqual(packet["yoke"]["roll"], 1)
        self.assertFalse(packet["tracking"])

    def test_low_confidence_nan_and_infinity_rejected(self):
        controller = self.make()
        for yoke in (YokeObservation(35, 25, .1), YokeObservation(math.nan, 0, 1), YokeObservation(0, math.inf, 1)):
            packet = controller.step(1, 1000, yoke, ThrottleObservation((math.nan, .5), 1))
            self.assertFalse(packet["tracking"])
            self.assertEqual(packet["yoke"]["confidence"], 0)
            self.assertEqual(packet["throttle"]["confidence"], 0)
            json.dumps(packet, allow_nan=False)

    def test_slew_limit_on_reacquisition(self):
        controller = self.make()
        controller.step(0, 1000, None, None)
        packet = controller.step(1 / 30, 1033, YokeObservation(35, 25, 1), ThrottleObservation((.75, .4), 1))
        self.assertLessEqual(packet["yoke"]["roll"], 3.5 / 30 + .00001)
        self.assertLessEqual(packet["throttle"]["value"], 1.5 / 30 + .00001)

    def test_relative_throttle_ignores_saved_pixels_and_holds_on_loss(self):
        controller = self.make()
        initial = self.warm(controller, throttle=RelativeThrottleObservation(.75, 1))
        self.assertAlmostEqual(initial["throttle"]["value"], .75, places=4)
        for observation in (None, RelativeThrottleObservation(math.nan, 1),
                            RelativeThrottleObservation(.2, .1)):
            packet = controller.step(4, 5000, None, observation)
            self.assertEqual(packet["throttle"]["value"], initial["throttle"]["value"])
            self.assertEqual(packet["throttle"]["confidence"], 0)

    def test_hidden_slider_move_holds_then_blends_both_directions(self):
        for start, end in ((.2, .9), (.9, .2)):
            controller = self.make()
            initial = self.warm(controller, throttle=RelativeThrottleObservation(start, 1))
            for i in range(30):
                hidden = controller.step(4+i/30, 5000+i*33, None, None)
                self.assertEqual(hidden["throttle"]["value"], initial["throttle"]["value"])
            previous = hidden["throttle"]["value"]
            for i in range(60):
                packet = controller.step(5+i/30, 6000+i*33, None, RelativeThrottleObservation(end, 1))
                value = packet["throttle"]["value"]
                self.assertLessEqual(abs(value-previous), 1.5/30+.00001)
                self.assertLessEqual(abs(value-end), abs(previous-end)+.00001)
                previous = value
            self.assertAlmostEqual(value, end, places=4)

    def test_simulated_stream_deterministic_and_loss(self):
        a, b = self.make(), self.make()
        for i in range(600):
            observations = simulated_observations(i, 30, True)
            self.assertEqual(a.step(i / 30, i * 33, *observations), b.step(i / 30, i * 33, *observations))
        self.assertIsNone(simulated_observations(270, 30, True)[0])
        self.assertIsNotNone(simulated_observations(270, 30, True)[1])
        self.assertIsNone(simulated_observations(420, 30, True)[1])

    def test_no_implicit_camera_mode(self):
        self.assertIsNone(parser().parse_args(["--simulate"]).camera)
        with self.assertRaises(SystemExit):
            parser().parse_args([])


if __name__ == "__main__":
    unittest.main()
