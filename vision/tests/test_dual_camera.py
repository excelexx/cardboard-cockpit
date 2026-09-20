import argparse
import unittest
from vision.dual_camera import select_cameras, worker_commands
from vision import tracker


class CameraSelectionTests(unittest.TestCase):
    def test_roles_follow_names_in_either_device_order(self):
        self.assertEqual(select_cameras(['iPhone Camera', 'MacBook Air Camera']), (1, 0))
        self.assertEqual(select_cameras(['MacBook Air Camera', 'iPhone Camera']), (0, 1))

    def test_webcam_app_can_be_selected_explicitly(self):
        self.assertEqual(select_cameras(['Built-in Camera', 'Camo'], throttle=1), (0, 1))

    def test_missing_ambiguous_and_same_cameras_are_rejected(self):
        for names, yoke, throttle in [(['MacBook Camera'], None, None),
                (['MacBook Camera', 'iPhone A', 'iPhone B'], None, None),
                (['Laptop', 'Phone'], 0, 0), (['Laptop', 'Phone'], 0, 2)]:
            with self.assertRaises(ValueError):
                select_cameras(names, yoke, throttle)

    def test_combined_worker_preserves_camera_roles_and_lens_profiles(self):
        commands = worker_commands(argparse.Namespace(yoke_intrinsics='laptop.json', throttle_intrinsics='phone.json'), (1, 0))
        self.assertEqual(len(commands), 1)
        command = commands[0]
        self.assertEqual(command[command.index('--camera')+1], '1')
        self.assertEqual(command[command.index('--throttle-camera')+1], '0')
        self.assertEqual(command[command.index('--intrinsics')+1], 'laptop.json')
        self.assertEqual(command[command.index('--throttle-intrinsics')+1], 'phone.json')
        parsed = tracker.parser().parse_args(command[2:])
        self.assertEqual(parsed.throttle_idle, 15)
