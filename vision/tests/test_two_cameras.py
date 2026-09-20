"""Exercise two independent cameras through the real tracker/socket pipeline."""
import asyncio
import json
from pathlib import Path
import socket
import tempfile
import time
import unittest
from unittest.mock import patch

import cv2
import numpy as np
from websockets.asyncio.client import connect

from vision import tracker
from vision.calibration import simulated_calibration
from vision.tests.test_camera_pipeline import SyntheticCamera
from vision.tests.throttle_fixture import throttle_frame


class SlowCamera(SyntheticCamera):
    delay = 0

    def read(self):
        time.sleep(self.delay)
        return super().read()


class TwoCameraTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        calibration = Path(self.directory.name)/"calibration.json"
        simulated_calibration().save(calibration)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            self.port = probe.getsockname()[1]
        self.args = tracker.parser().parse_args(["--camera", "0", "--throttle-idle", "0", "--throttle-camera", "1",
                       "--calibration", str(calibration), "--no-preview", "--port", str(self.port)])
        self.laptop = SyntheticCamera()
        self.laptop.frame = throttle_frame(.05, yoke=True)
        dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
        for tag, x in ((3, 90), (4, 350)):
            self.laptop.frame[60:180, x:x+120] = cv2.cvtColor(cv2.aruco.generateImageMarker(dictionary, tag, 120), cv2.COLOR_GRAY2BGR)
        self.phone = SlowCamera()
        self.phone.frame = throttle_frame(.8, yoke=True)
        self.phone.frame[60:180] = self.laptop.frame[60:180]

    async def test_phone_owns_throttle_and_preview_while_laptop_owns_yoke_and_fire(self):
        def source(index, *_):
            return self.laptop if index == 0 else self.phone
        with patch.object(tracker, "CameraSource", side_effect=source), \
                patch.object(cv2, "VideoCapture", side_effect=AssertionError("No hardware in tests")):
            service = asyncio.create_task(tracker.run(self.args))
            url = "ws://127.0.0.1:%d" % self.port
            connection = None
            try:
                for _ in range(40):
                    try:
                        connection = await connect(url, proxy=None)
                        break
                    except OSError:
                        await asyncio.sleep(.025)
                self.assertIsNotNone(connection)

                async def receive(count):
                    for _ in range(count):
                        packet = json.loads(await asyncio.wait_for(connection.recv(), 1))
                    return packet

                packet = await receive(25)
                self.assertGreater(packet["yoke"]["confidence"], .4)
                self.assertAlmostEqual(packet["throttle"]["value"], .8, delta=.03)
                self.assertEqual(packet["weapons"], {"gun": True})
                async with connect(url+"/preview/throttle", proxy=None) as preview:
                    image = cv2.imdecode(np.frombuffer(await preview.recv(), np.uint8), cv2.IMREAD_COLOR)
                    observation = tracker.ThrottleTracker(cv2, np).detect(image)
                    self.assertIsNotNone(observation)
                    self.assertAlmostEqual(observation.value, .8, delta=.03)
                async with connect(url+"/preview/weapons", proxy=None) as preview:
                    image = cv2.imdecode(np.frombuffer(await preview.recv(), np.uint8), cv2.IMREAD_COLOR)
                    tags = tracker.WeaponTags(cv2, np)
                    for i in range(5): result = tags.detect(image, i/30)
                    self.assertEqual(result, {"gun": True})
                async with connect(url+"/preview/all", proxy=None) as preview:
                    image = cv2.imdecode(np.frombuffer(await preview.recv(), np.uint8), cv2.IMREAD_COLOR)
                    self.assertEqual(image.shape[:2], (540, 960))
                    self.assertGreater(image[100:400, :480].mean(), 100)
                    self.assertGreater(image[100:400, 480:].mean(), 100)

                # A slow/disconnected phone must not block yoke/fire packets or
                # switch to the .05 slider visible in the laptop's image.
                self.phone.delay = .45; self.phone.fail_frame = True
                began = time.monotonic()
                changed_at = int(time.time()*1000)
                samples = []
                while not samples or samples[-1]["timestamp"] < changed_at+550:
                    self.assertLess(time.monotonic()-began, 3, "Control stream stopped")
                    packet = await receive(1)
                    samples.append(packet)
                self.assertGreaterEqual(sum(p["timestamp"] >= changed_at for p in samples), 8,
                                        "A slow phone cannot block the primary camera's packet cadence")
                self.assertEqual(packet["throttle"]["confidence"], 0)
                self.assertAlmostEqual(packet["throttle"]["value"], .8, delta=.03)
                self.assertGreater(packet["yoke"]["confidence"], .4)
                self.assertTrue(packet["weapons"]["gun"])
                async with connect(url+"/preview/throttle", proxy=None) as preview:
                    self.assertEqual(await preview.recv(), b"", "No laptop fallback when phone disappears")

                self.phone.delay = 0; self.phone.fail_frame = False
                self.phone.frame = throttle_frame(.35, yoke=True)
                self.phone.frame[60:180] = self.laptop.frame[60:180]
                packet = await receive(35)
                self.assertAlmostEqual(packet["throttle"]["value"], .35, delta=.04)
                self.laptop.fail_frame = True
                packet = await receive(6)
                self.assertEqual(packet["yoke"]["confidence"], 0, "Phone's ID 7 cannot steer")
                self.assertEqual(packet["weapons"], {"gun": False})
                self.assertGreater(packet["throttle"]["confidence"], .4)
            finally:
                if connection is not None: await connection.close()
                service.cancel()
                with self.assertRaises(asyncio.CancelledError): await service
        self.assertTrue(self.laptop.closed and self.phone.closed, "Both captures released")

    async def test_default_idle_adjustment_reaches_game_control_stream(self):
        self.args.throttle_idle = tracker.parser().parse_args(["--camera", "0"]).throttle_idle
        self.assertEqual(self.args.throttle_idle, 15)
        self.args.paper_test = True
        self.phone.frame = throttle_frame(.15)
        with patch.object(tracker, "CameraSource", side_effect=[self.laptop, self.phone]), \
                patch.object(cv2, "VideoCapture", side_effect=AssertionError("No hardware in tests")):
            service = asyncio.create_task(tracker.run(self.args))
            connection = None
            try:
                for _ in range(40):
                    try:
                        connection = await connect("ws://127.0.0.1:%d" % self.port, proxy=None)
                        break
                    except OSError:
                        await asyncio.sleep(.025)
                self.assertIsNotNone(connection)
                for rail_position, expected in ((.15, 0), (.575, .5), (1, 1)):
                    self.phone.frame = throttle_frame(rail_position)
                    for _ in range(30):
                        packet = json.loads(await asyncio.wait_for(connection.recv(), 2))
                    self.assertGreater(packet["throttle"]["confidence"], .4)
                    self.assertAlmostEqual(packet["throttle"]["value"], expected, delta=.01)
            finally:
                if connection is not None:
                    await connection.close()
                service.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await service
        self.assertTrue(self.laptop.closed and self.phone.closed)

    async def test_secondary_open_failure_releases_primary(self):
        with patch.object(tracker, "CameraSource", side_effect=[self.laptop, RuntimeError("Phone missing")]):
            with self.assertRaisesRegex(RuntimeError, "Phone missing"):
                await tracker.run(self.args)
        self.assertTrue(self.laptop.closed)

    async def test_same_camera_cannot_be_assigned_both_roles(self):
        self.args.throttle_camera = self.args.camera
        with patch.object(tracker, "CameraSource", side_effect=AssertionError("No camera should open")):
            with self.assertRaisesRegex(ValueError, "distinct"):
                await tracker.run(self.args)
