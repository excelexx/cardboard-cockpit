"""Fixed rendered pose through the real camera pipeline for Godot slider tests."""
import asyncio
from pathlib import Path
import sys
from unittest.mock import patch

import cv2

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from vision import tracker
from vision.tests.yoke_fixture import yoke_frame


class FixedCamera:
    def __init__(self):
        self.frame = yoke_frame(bank=4, pitch=8, yaw=8)

    def read(self):
        return self.frame.copy()

    def close(self):
        pass


if __name__ == "__main__":
    args = tracker.parser().parse_args(["--camera", "0", "--paper-test", "--no-preview", *sys.argv[1:]])
    initialize = tracker.PaperController.__init__

    def centered(detector, *args, **kwargs):
        initialize(detector, *args, **kwargs)
        detector.neutral = (0, 0)
        detector.yaw_neutral = 0

    with patch.object(tracker, "CameraSource", return_value=FixedCamera()), \
            patch.object(tracker.PaperController, "__init__", new=centered), \
            patch.object(cv2, "VideoCapture", side_effect=AssertionError("No webcam in tests")):
        asyncio.run(tracker.run(args))
