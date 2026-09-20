"""Rendered marker fixture; module entry point serves it without a webcam."""
import asyncio
import sys
from pathlib import Path
from unittest.mock import patch

import cv2
import numpy as np


def throttle_frame(value=.75, yoke=False):
    frame = np.full((720, 1280, 3), 255, np.uint8)
    dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
    positions = [(0, 600, 300, 100), (2, 1000, 300, 100),
                 (1, round(600 + 400 * value), 500, 100)]
    if yoke:
        positions.append((7, 220, 280, 160))
    for marker_id, x, y, size in positions:
        marker = cv2.aruco.generateImageMarker(dictionary, marker_id, size)
        frame[y:y + size, x:x + size] = cv2.cvtColor(marker, cv2.COLOR_GRAY2BGR)
    return frame


class FixtureCamera:
    def read(self):
        return throttle_frame()

    def close(self):
        pass


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from vision import tracker
    args = tracker.parser().parse_args(["--camera", "0", "--throttle-idle", "0", "--throttle-only", "--no-preview", *sys.argv[1:]])
    with patch.object(tracker, "CameraSource", return_value=FixtureCamera()), \
            patch.object(cv2, "VideoCapture", side_effect=AssertionError("No webcam in tests")):
        asyncio.run(tracker.run(args))
