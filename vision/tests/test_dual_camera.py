import argparse
import cv2
import unittest
from vision.dual_camera import select_cameras, worker_commands
from vision.tests import test_camera_pipeline as pipeline
from vision import tracker
import asyncio
import json
from unittest.mock import patch
from websockets.asyncio.client import connect


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

    def test_worker_roles_ports_and_lens_profiles_stay_separate(self):
        yoke, throttle = worker_commands(argparse.Namespace(yoke_intrinsics='laptop.json', throttle_intrinsics='phone.json'), (1, 0))
        self.assertIn('--yoke-only', yoke)
        self.assertEqual(yoke[yoke.index('--camera')+1], '1')
        self.assertIn('8765', yoke)
        self.assertIn('laptop.json', yoke)
        self.assertIn('--throttle-only', throttle)
        self.assertEqual(throttle[throttle.index('--camera')+1], '0')
        self.assertIn('8766', throttle)
        self.assertIn('phone.json', throttle)


class RoleIsolationTests(unittest.IsolatedAsyncioTestCase):
    setUp = pipeline.CameraPipelineTests.setUp

    async def check_role(self, role):
        setattr(self.args, role, True)
        dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
        for marker_id, x in [(31, 100), (41, 300)]:
            marker = cv2.aruco.generateImageMarker(dictionary, marker_id, 100)
            self.camera.frame[50:150, x:x+100] = cv2.cvtColor(marker, cv2.COLOR_GRAY2BGR)
        with patch.object(tracker, 'CameraSource', return_value=self.camera):
            service = asyncio.create_task(tracker.run(self.args))
            connection = None
            try:
                for _ in range(40):
                    try:
                        connection = await connect('ws://127.0.0.1:%d' % self.port, proxy=None)
                        break
                    except OSError:
                        await asyncio.sleep(.025)
                self.assertIsNotNone(connection)
                for _ in range(8):
                    packet = json.loads(await asyncio.wait_for(connection.recv(), 1))
                if role == 'yoke_only':
                    self.assertGreater(packet['yoke']['confidence'], .4)
                    self.assertEqual(packet['throttle']['confidence'], 0)
                    self.assertTrue(packet['weapons']['primary'])
                    self.assertTrue(packet['weapons']['salvo'])
                else:
                    self.assertEqual(packet['yoke']['confidence'], 0)
                    self.assertGreater(packet['throttle']['confidence'], .4)
                    self.assertNotIn('weapons', packet)
            finally:
                if connection:
                    await connection.close()
                service.cancel()
                await asyncio.gather(service, return_exceptions=True)

    async def test_laptop_ignores_visible_throttle_tags(self):
        await self.check_role('yoke_only')

    async def test_phone_ignores_visible_yoke(self):
        await self.check_role('throttle_only')
