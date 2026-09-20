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

from vision.calibration import simulated_calibration
from vision import tracker


class SyntheticCamera:
    def __init__(self):
        dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
        self.frame = np.full((720, 1280, 3), 255, dtype=np.uint8)
        for marker_id, x in ((7, 220), (23, 880)):
            marker = cv2.aruco.generateImageMarker(dictionary, marker_id, 160)
            self.frame[280:440, x:x + 160] = cv2.cvtColor(marker, cv2.COLOR_GRAY2BGR)
        self.hide_yoke = False
        self.hide_throttle = False
        self.closed = False
        self.reads = 0
        self.fail_frame=False

    def read(self):
        self.reads += 1
        if self.fail_frame:return None
        frame = self.frame.copy()
        if self.hide_yoke:
            frame[280:440, 220:380] = 255
        if self.hide_throttle:
            frame[280:440, 880:1040] = 255
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
            "--camera", "0", "--calibration", str(self.calibration_path),
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
