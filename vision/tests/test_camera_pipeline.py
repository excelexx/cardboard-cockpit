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
from vision.tests.throttle_fixture import throttle_frame


class SyntheticCamera:
    def __init__(self):
        self.frame = throttle_frame(.75, yoke=True)
        self.hide_yoke = False
        self.hide_throttle = False
        self.closed = False
        self.reads = 0

    def read(self):
        self.reads += 1
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
                # The separate preview stream must deliver a mirrored, bounded
                # JPEG while the original connection keeps receiving controls.
                async with connect("ws://127.0.0.1:%d/preview" % self.port, proxy=None) as preview:
                    jpeg = await asyncio.wait_for(preview.recv(), 1)
                    self.assertIsInstance(jpeg, bytes)
                    self.assertLessEqual(len(jpeg), 65536)
                    decoded = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_COLOR)
                    self.assertEqual(decoded.shape, (180, 320, 3))
                    expected = cv2.flip(cv2.resize(self.camera.frame, (320, 180), interpolation=cv2.INTER_AREA), 1)
                    self.assertLess(np.abs(decoded.astype(float)-expected).mean(), 3)
                    control = json.loads(await asyncio.wait_for(connection.recv(), 1))
                    self.assertGreater(control["sequence"], packet["sequence"])
                    self.assertTrue(control["tracking"])
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

    async def test_python_readout_and_game_packet_share_sensitive_pitch(self):
        self.args.no_preview = False
        shown = {}
        original_step = tracker.ControlFilter.step

        def raw_input(controller, *args):
            packet = original_step(controller, *args)
            # Exercise both directions and saturation through the actual send
            # and preview paths, independently of synthetic pose estimation.
            pitch = (.2, -.35, .8)[packet["sequence"] % 3]
            packet["yoke"].update(roll=-.15, pitch=pitch, confidence=1)
            packet["throttle"]["value"] = .4
            return packet

        def readout(frame, packet, wizard, fps, *status):
            shown[packet["sequence"]] = json.loads(json.dumps(packet))

        with patch.object(tracker, "CameraSource", return_value=self.camera), \
                patch.object(tracker.ControlFilter, "step", raw_input), \
                patch.object(tracker, "draw_preview", side_effect=readout), \
                patch.object(cv2, "waitKey", return_value=-1), \
                patch.object(cv2, "getWindowProperty", return_value=1):
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
                for _ in range(6):
                    packet = json.loads(await asyncio.wait_for(connection.recv(), 1))
                    self.assertEqual(packet, shown[packet["sequence"]])
                    self.assertAlmostEqual(packet["yoke"]["roll"], -.21)
                    self.assertAlmostEqual(packet["yoke"]["pitch"], (.4, -.7, 1)[packet["sequence"] % 3])
                    self.assertEqual(packet["throttle"]["value"], .4)
            finally:
                if connection is not None:
                    await connection.close()
                service.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await service
            self.assertTrue(self.camera.closed)
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
