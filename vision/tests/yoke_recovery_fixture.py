"""Synthetic visible/lost/returned yoke for the actual game recovery test."""
import asyncio
from pathlib import Path
import sys
import tempfile
import time
from unittest.mock import patch

import cv2

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from vision import tracker
from vision.calibration import simulated_calibration
from vision.tests.throttle_fixture import throttle_frame


class RecoveryCamera:
    def __init__(self):
        self.started = time.monotonic()

    def read(self):
        elapsed = time.monotonic() - self.started
        frame = throttle_frame(.4, yoke=not 1.5 < elapsed < 4)
        cv2.putText(frame, "SYNTHETIC CAMERA / YOKE RECOVERY TEST", (80, 90),
                    cv2.FONT_HERSHEY_SIMPLEX, .9, (70, 70, 70), 2, cv2.LINE_AA)
        return frame

    def close(self):
        pass


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as directory:
        calibration = Path(directory) / "calibration.json"
        simulated_calibration().save(calibration)
        args = tracker.parser().parse_args([
            "--camera", "0", "--throttle-idle", "0", "--calibration", str(calibration), "--no-preview", *sys.argv[1:]])
        with patch.object(tracker, "CameraSource", return_value=RecoveryCamera()), \
                patch.object(cv2, "VideoCapture", side_effect=AssertionError("No webcam in tests")):
            asyncio.run(tracker.run(args))
