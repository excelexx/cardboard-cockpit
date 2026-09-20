import copy
import unittest

from vision.control_settings import ControlSettings


class ControlSettingsTests(unittest.TestCase):
    def test_independent_gains_preserve_physical_input_confidence_and_throttle(self):
        settings = ControlSettings()
        command = {"action": "set_sensitivity", "request_id": "drag", "sensitivity": {"pitch": 2, "bank": .5, "yaw": 3}}
        self.assertEqual(settings.accept(command), {"request_id": "drag", "sensitivity": command["sensitivity"]})
        packet = {"yoke": {"roll": .4, "pitch": -.3, "yaw": .6, "confidence": .8}, "throttle": {"value": .7, "confidence": .9}}
        settings.apply(packet)
        self.assertEqual(packet["yoke"], {"roll": .2, "pitch": -.6, "yaw": 1, "confidence": .8})
        self.assertEqual(packet["raw_yoke"], {"roll": .4, "pitch": -.3, "yaw": .6})
        self.assertEqual(packet["throttle"], {"value": .7, "confidence": .9})

    def test_extended_gain_range(self):
        settings = ControlSettings()
        gains = {"pitch": 6, "bank": 5, "yaw": 4}
        settings.accept({"action": "set_sensitivity", "request_id": "extended", "sensitivity": gains})
        self.assertEqual(settings.sensitivity, gains)

    def test_invalid_commands_are_atomic(self):
        settings = ControlSettings()
        before = dict(settings.sensitivity)
        command = {"action": "set_sensitivity", "request_id": "drag", "sensitivity": {"pitch": 2, "bank": .5, "yaw": 3}}
        invalid = [None, [], {}, dict(command, action="start"), dict(command, request_id=""), dict(command, extra=True)]
        for value in [True, "1", None, float("nan"), float("inf"), .24, 6.01]:
            bad = copy.deepcopy(command)
            bad["sensitivity"]["yaw"] = value
            invalid.append(bad)
        for bad in invalid:
            with self.subTest(command=bad), self.assertRaises(ValueError):
                settings.accept(bad)
            self.assertEqual(settings.sensitivity, before)
