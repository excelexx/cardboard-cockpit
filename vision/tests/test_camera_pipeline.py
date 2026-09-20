"""Exercise the camera-mode pipeline using rendered markers, never a webcam."""
import asyncio
import json
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import patch

import cv2
import numpy as np
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed, InvalidStatus

from vision.calibration import simulated_calibration
from vision import tracker
from vision.tests.throttle_fixture import throttle_frame
from vision.tests.test_weapon_tags import weapon_frame
from vision.tests.yoke_fixture import yoke_frame


class SyntheticCamera:
    def __init__(self):
        self.frame = throttle_frame(.75, yoke=True)
        self.hide_yoke = False
        self.hide_throttle = False
        self.closed = False
        self.reads = 0
        self.fail_frame = False

    def read(self):
        self.reads += 1
        if self.fail_frame:
            return None
        frame = self.frame.copy()
        if self.hide_yoke:
            frame[280:440, 220:380] = 255
        if self.hide_throttle:
            frame[450:650, 500:1200] = 255
        return frame

    def close(self):
        self.closed = True


class CameraPipelineTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.calibration_path = Path(self.directory.name) / "calibration.json"
        simulated_calibration().save(self.calibration_path)
        with socket.socket() as temporary:
            temporary.bind(("127.0.0.1", 0))
            self.port = temporary.getsockname()[1]
        self.args = tracker.parser().parse_args([
            "--camera", "0", "--throttle-idle", "0", "--calibration", str(self.calibration_path),
            "--no-preview", "--duration", "3", "--port", str(self.port),
        ])
        self.camera = SyntheticCamera()

    async def test_images_to_socket_and_independent_loss(self):
        with patch.object(tracker, "CameraSource", return_value=self.camera), \
                patch.object(cv2, "VideoCapture", side_effect=AssertionError("No real camera allowed")):
            service = asyncio.create_task(tracker.run(self.args))
            connection = None
            try:
                for _ in range(40):
                    try:
                        connection = await connect("ws://127.0.0.1:%d" % self.port, proxy=None)
                        break
                    except OSError:
                        await asyncio.sleep(.025)
                self.assertIsNotNone(connection, "Camera-mode service must bind")
                for _ in range(8):
                    packet = json.loads(await asyncio.wait_for(connection.recv(), 1))
                self.assertTrue(packet["tracking"])
                self.assertTrue(packet["yoke_enabled"])
                self.assertGreater(packet["throttle"]["value"], .1)
                self.camera.hide_yoke = True
                for _ in range(5):
                    packet = json.loads(await asyncio.wait_for(connection.recv(), 1))
                self.assertEqual(packet["yoke"]["confidence"], 0)
                self.assertGreater(packet["throttle"]["confidence"], .4)
                self.camera.hide_throttle = True
                for _ in range(5):
                    packet = json.loads(await asyncio.wait_for(connection.recv(), 1))
                held_power = packet["throttle"]["value"]
                self.assertEqual(packet["throttle"]["confidence"], 0)
                packet = json.loads(await asyncio.wait_for(connection.recv(), 1))
                self.assertEqual(packet["throttle"]["value"], held_power)
            finally:
                if connection is not None:
                    await connection.close()
                service.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await service
            self.assertTrue(self.camera.closed, "Cancellation releases capture")

    async def test_throttle_only_starts_without_saved_yoke_calibration(self):
        self.args.throttle_only = True
        self.calibration_path.unlink()
        self.args.duration = .15
        self.camera.hide_yoke = True
        with patch.object(tracker, "CameraSource", return_value=self.camera), \
                patch.object(tracker, "CalibrationWizard", side_effect=AssertionError("No yoke calibration")):
            await tracker.run(self.args)
        self.assertGreater(self.camera.reads, 0)
        self.assertTrue(self.camera.closed)

    async def test_tutorial_captures_three_seconds_of_raw_yoke_and_applies_neutral(self):
        self.args.paper_test = True
        self.args.duration = 15
        detectors = []
        original_init = tracker.PaperController.__init__
        def initialize(detector, *args, **kwargs):
            original_init(detector, *args, **kwargs)
            detector.neutral = (25, 18)  # Previously centred in a different pose.
            detectors.append(detector)
        received = []
        reader = None
        with patch.object(tracker, "CameraSource", return_value=self.camera), \
                patch.object(tracker.PaperController, "__init__", new=initialize), \
                patch.object(cv2, "VideoCapture", side_effect=AssertionError("No real camera allowed")):
            service = asyncio.create_task(tracker.run(self.args))
            url = "ws://127.0.0.1:%d" % self.port
            connection = None
            try:
                for _ in range(40):
                    try:
                        connection = await connect(url+"/calibration", proxy=None)
                        break
                    except OSError:
                        await asyncio.sleep(.025)
                self.assertIsNotNone(connection)
                async with connection, connect(url, proxy=None) as controls:
                    async def read_controls():
                        async for message in controls:
                            received.append(json.loads(message))
                    reader = asyncio.create_task(read_controls())
                    await connection.send(json.dumps({"action": "start", "request_id": "tutorial-test"}))
                    async def until(predicate):
                        for _ in range(220):
                            status = json.loads(await asyncio.wait_for(connection.recv(), 1))
                            self.assertEqual(status["request_id"], "tutorial-test")
                            if predicate(status):
                                return status
                        self.fail("Calibration state timed out")
                    await until(lambda s: s["elapsed"] >= .5)
                    packet = received[-1]
                    self.assertEqual(packet["yoke"]["confidence"], 0)
                    self.assertFalse(packet["weapons"]["gun"])
                    self.camera.hide_yoke = True
                    status = await until(lambda s: s["state"] == "waiting")
                    self.assertEqual(status["elapsed"], 0)
                    started = asyncio.get_running_loop().time()
                    self.camera.hide_yoke = False
                    await until(lambda s: s["state"] == "complete")
                    self.assertGreaterEqual(asyncio.get_running_loop().time()-started, 3)
                    for _ in range(20):
                        await asyncio.sleep(.05)
                        if received[-1]["yoke"]["confidence"] > .4:
                            break
                    packet = received[-1]
                    self.assertNotEqual(detectors[0].neutral, (25,18))
                    self.assertGreater(packet["yoke"]["confidence"], .4)
                    self.assertAlmostEqual(packet["yoke"]["roll"], 0, places=3)
                    self.assertAlmostEqual(packet["yoke"]["pitch"], 0, places=3)
                    self.assertAlmostEqual(packet["yoke"]["yaw"], 0, places=3)
                    self.camera.frame = yoke_frame(yaw=20)
                    for _ in range(30):
                        await asyncio.sleep(.05)
                        if received[-1]["yoke"]["yaw"] > .5:
                            break
                    self.assertGreater(received[-1]["yoke"]["yaw"],.5,"Camera swivel must reach the actual yaw socket field")
                    self.assertAlmostEqual(received[-1]["yoke"]["pitch"],0,places=3)
                    self.assertAlmostEqual(received[-1]["yoke"]["roll"],0,places=3)
                    # A fresh attempt never inherits the completed request.
                async with connect(url+"/calibration", proxy=None) as retry:
                    await retry.send(json.dumps({"action": "start", "request_id": "retry"}))
                    status = json.loads(await asyncio.wait_for(retry.recv(), 1))
                    self.assertEqual(status["request_id"], "retry")
                    self.assertLess(status["elapsed"], .15)
                    self.assertNotEqual(status["state"], "complete")
                with self.assertRaises(InvalidStatus):
                    async with connect(url+"/calibration", origin="https://example.com", proxy=None):
                        pass
            finally:
                if reader is not None:
                    reader.cancel()
                    await asyncio.gather(reader, return_exceptions=True)
                if connection is not None:
                    await connection.close()
                service.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await service

    async def test_weapon_frames_reach_socket_and_stop_without_hold(self):
        self.args.throttle_only = True
        self.camera.frame = weapon_frame()
        with patch.object(tracker, "CameraSource", return_value=self.camera), \
                patch.object(cv2, "VideoCapture", side_effect=AssertionError("No real camera allowed")):
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
                for _ in range(8):
                    packet = json.loads(await asyncio.wait_for(connection.recv(), 1))
                self.assertEqual(packet["weapons"], {"gun": True})
                self.assertFalse(packet["yoke_enabled"])
                self.camera.frame[160:250, 120:180] = (100, 150, 190)
                # Allow only already-queued/in-flight frames before the cover.
                for _ in range(3):
                    packet = json.loads(await asyncio.wait_for(connection.recv(), 1))
                self.assertEqual(packet["weapons"], {"gun": False})
                self.camera.fail_frame = True
                for _ in range(3):
                    packet = json.loads(await asyncio.wait_for(connection.recv(), 1))
                self.assertEqual(packet["weapons"], {"gun": False})
            finally:
                if connection is not None:
                    await connection.close()
                service.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await service
            self.assertTrue(self.camera.closed)

    async def test_local_preview_is_separate_live_jpeg_and_clears_on_camera_loss(self):
        with patch.object(tracker, "CameraSource", return_value=self.camera), \
                patch.object(cv2, "VideoCapture", side_effect=AssertionError("No real camera allowed")):
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
                async with connection, connect(url+"/preview", proxy=None) as preview:
                    # The control stream still carries only JSON.
                    self.assertIsInstance(await connection.recv(), str)
                    jpeg = await asyncio.wait_for(preview.recv(), 1)
                    self.assertIsInstance(jpeg, bytes)
                    decoded = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_COLOR)
                    self.assertEqual(decoded.shape[:2], (540, 960))
                    self.camera.fail_frame = True
                    for _ in range(3):
                        jpeg = await asyncio.wait_for(preview.recv(), 1)
                        if not jpeg:
                            break
                    self.assertEqual(jpeg, b"", "No stale camera image after capture failure")
                    await preview.send("not a control channel")
                    with self.assertRaises(ConnectionClosed):
                        while True:
                            await asyncio.wait_for(preview.recv(), 1)
                with self.assertRaises(InvalidStatus):
                    async with connect(url+"/preview", origin="https://example.com", proxy=None):
                        pass
            finally:
                service.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await service

    async def test_tutorial_streams_focus_live_controls_and_remain_read_only(self):
        with patch.object(tracker, "CameraSource", return_value=self.camera), \
                patch.object(cv2, "VideoCapture", side_effect=AssertionError("No real camera allowed")):
            service = asyncio.create_task(tracker.run(self.args))
            url = "ws://127.0.0.1:%d" % self.port
            try:
                for _ in range(40):
                    try:
                        connection = await connect(url+"/preview/yoke", proxy=None)
                        break
                    except OSError:
                        await asyncio.sleep(.025)
                async with connection:
                    jpeg = await asyncio.wait_for(connection.recv(), 1)
                    image = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_COLOR)
                    detector = cv2.aruco.ArucoDetector(cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50))
                    _, ids, _ = detector.detectMarkers(cv2.flip(image, 1))
                    self.assertTrue({0, 1, 2, 7}.issubset(set(ids.flatten())), "Tutorial preserves the full camera view")
                    async with connect(url+"/preview/throttle", proxy=None) as throttle:
                        jpeg = await asyncio.wait_for(throttle.recv(), 1)
                        image = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_COLOR)
                        _, ids, _ = detector.detectMarkers(cv2.flip(image, 1))
                        self.assertTrue({0, 1, 2}.issubset(set(ids.flatten())))
                    self.camera.frame = weapon_frame()
                    async with connect(url+"/preview/weapons", proxy=None) as weapons:
                        jpeg = await asyncio.wait_for(weapons.recv(), 1)
                        image = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_COLOR)
                        _, ids, _ = detector.detectMarkers(cv2.flip(image, 1))
                        self.assertEqual(set(ids.flatten()), {4})
                        self.camera.fail_frame = True
                        for _ in range(3):
                            jpeg = await asyncio.wait_for(weapons.recv(), 1)
                            if not jpeg:
                                break
                        self.assertEqual(jpeg, b"")
                    await connection.send("not allowed")
                    with self.assertRaises(ConnectionClosed):
                        while True:
                            await asyncio.wait_for(connection.recv(), 1)
                with self.assertRaises(InvalidStatus):
                    async with connect(url+"/preview/yoke", origin="https://example.com", proxy=None):
                        pass
            finally:
                service.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await service

    async def test_resolution_change_requires_recalibration_and_releases_camera(self):
        self.camera.frame = self.camera.frame[:480, :640]
        with patch.object(tracker, "CameraSource", return_value=self.camera):
            with self.assertRaisesRegex(RuntimeError, "resolution changed"):
                await tracker.run(self.args)
        self.assertTrue(self.camera.closed)

    async def test_closing_preview_stops_capture(self):
        self.args.no_preview = False
        self.args.duration = .2
        with patch.object(tracker, "CameraSource", return_value=self.camera), \
                patch.object(tracker, "draw_preview"), \
                patch.object(cv2, "waitKey", return_value=-1), \
                patch.object(cv2, "getWindowProperty", return_value=0):
            await tracker.run(self.args)
        self.assertEqual(self.camera.reads, 1, "Closing preview must stop instead of reopening it")
        self.assertTrue(self.camera.closed)


if __name__ == "__main__":
    unittest.main()
