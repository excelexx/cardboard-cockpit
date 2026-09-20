import unittest
from unittest.mock import patch

from vision.camera_devices import camera_argument, resolve_camera
from vision import tracker


class CameraDeviceTests(unittest.TestCase):
    DEVICES = [{"index": 0, "name": "iPhone (2) Camera", "id": "phone"},
               {"index": 1, "name": "MacBook Air Camera", "id": "laptop"}]

    def test_names_and_unique_ids_select_the_requested_hardware(self):
        self.assertEqual(resolve_camera("iPhone (2) Camera", self.DEVICES), (0, "iPhone (2) Camera"))
        self.assertEqual(resolve_camera("macbook", self.DEVICES), (1, "MacBook Air Camera"))
        self.assertEqual(resolve_camera("phone", self.DEVICES), (0, "iPhone (2) Camera"))
        reordered = [dict(d, index=1-d["index"]) for d in self.DEVICES]
        self.assertEqual(resolve_camera("iPhone (2) Camera", reordered)[0], 1)

    def test_missing_or_ambiguous_names_do_not_fall_back(self):
        for selection in ("Disconnected phone", "Camera"):
            with self.assertRaisesRegex(ValueError, "no fallback"):
                resolve_camera(selection, self.DEVICES)

    def test_explicit_indices_keep_working_without_discovery(self):
        with patch("vision.camera_devices.list_cameras", side_effect=AssertionError("Do not probe devices")):
            self.assertEqual(resolve_camera(camera_argument("1")), (1, "Camera 1"))
        with self.assertRaises(ValueError):
            resolve_camera(-1)

    def test_parser_accepts_independent_camera_names(self):
        args = tracker.parser().parse_args(["--camera", "MacBook Air Camera", "--throttle-camera", "iPhone (2) Camera", "--paper-test"])
        self.assertEqual(args.camera, "MacBook Air Camera")
        self.assertEqual(args.throttle_camera, "iPhone (2) Camera")
