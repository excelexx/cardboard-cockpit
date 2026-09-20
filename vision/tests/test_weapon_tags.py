"""Exercise actual tag decoding, partial covers and trigger timing."""
import unittest
from pathlib import Path

import cv2
import numpy as np

from vision.weapon_tags import WeaponTags


def weapon_frame(ids=(4,), size=120):
    frame = np.full((480, 800, 3), 255, np.uint8)
    dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
    for marker_id, x in zip(ids, (120, 480)):
        frame[160:160+size, x:x+size] = cv2.cvtColor(
            cv2.aruco.generateImageMarker(dictionary, marker_id, size), cv2.COLOR_GRAY2BGR)
    return frame


class WeaponTagTests(unittest.TestCase):
    def setUp(self):
        self.tags = WeaponTags(cv2, np)
        self.time = 0

    def detect(self, frame):
        self.time += 1/30
        return self.tags.detect(frame, self.time)

    def arm(self, frame):
        for _ in range(5):
            result = self.detect(frame)
        return result

    def test_only_id_04_fires_after_multiple_clear_frames(self):
        frame = weapon_frame()
        self.assertEqual(self.detect(frame), {"gun": False})
        self.assertEqual(self.arm(frame), {"gun": True})
        frame[160:280, 120:240] = 255
        self.assertEqual(self.detect(frame), {"gun": False})
        self.assertEqual(self.detect(weapon_frame()), {"gun": False})
        self.assertEqual(self.arm(weapon_frame((3,))), {"gun": False})

    def test_retired_switch_ids_cannot_emit_weapon_actions(self):
        for marker_id in (31, 32, 41, 42):
            with self.subTest(marker_id=marker_id):
                self.assertEqual(self.arm(weapon_frame((marker_id,))), {"gun": False})
        self.assertEqual(self.arm(weapon_frame((4, 31))), {"gun": True})

    def test_small_partial_covers_that_still_decode_keep_firing(self):
        for marker_id in (4,):
            for x, y in ((126, 162), (126, 270), (122, 210), (230, 210), (165, 185),
                         (117, 205), (175, 157), (236, 205), (175, 276)):
                with self.subTest(marker_id=marker_id, position=(x, y)):
                    frame = weapon_frame((marker_id,))
                    name = "gun"
                    self.assertTrue(self.arm(frame)[name])
                    frame[y:y+6, x:x+6] = (100, 150, 190)
                    # Barely covering the print should not change the trigger.
                    _, ids, _ = self.tags.detector.detectMarkers(frame)
                    self.assertIsNotNone(ids)
                    self.assertIn(marker_id, ids.flatten())
                    self.assertTrue(self.detect(frame)[name])
                    self.assertTrue(self.arm(frame)[name])

    def test_margin_overlap_is_ignored_but_cropping_pattern_stops_fire(self):
        frame = weapon_frame((4,))
        self.assertTrue(self.arm(frame)["gun"])
        frame[155:159, 170:178] = 100
        self.assertTrue(self.detect(frame)["gun"])
        # A narrow visible paper margin is still fine.
        shifted = np.roll(weapon_frame((4,)), -115, axis=1)
        self.assertTrue(self.arm(shifted)["gun"])
        self.assertFalse(self.arm(np.roll(weapon_frame((4,)), -160, axis=1))["gun"])

    def test_real_printed_04_with_narrow_margins(self):
        path = Path(__file__).with_name("fixtures") / "printed-weapon-tags.png"
        frame = cv2.imread(str(path))
        self.assertIsNotNone(frame)
        # This is the supplied photo: IDs decode normally, but the old
        # full-cell margin and near-perfect pixel checks rejected both tags.
        _, ids, _ = self.tags.detector.detectMarkers(frame)
        self.assertEqual(set(ids.flatten()), {3, 4})
        variants = (frame, cv2.flip(frame, 1), cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE),
                    cv2.resize(frame, None, fx=.5, fy=.5),
                    cv2.resize(frame, None, fx=.2, fy=.2),
                    (frame.astype(np.float32)*.85+8).astype(np.uint8),
                    cv2.imdecode(cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 65])[1], cv2.IMREAD_COLOR))
        for index, view in enumerate(variants):
            with self.subTest(variant=index):
                self.tags.reset()
                self.assertEqual(self.arm(view), {"gun": True}, self.tags.messages)

    def test_real_print_small_covers_stay_on_and_large_covers_stop(self):
        path = Path(__file__).with_name("fixtures") / "printed-weapon-tags.png"
        original = cv2.imread(str(path))
        for name, x, y in (("gun", 395, 35),):
            with self.subTest(weapon=name):
                self.assertEqual(self.arm(original), {"gun": True})
                frame = original.copy()
                frame[y:y+10, x:x+10] = (100, 150, 190)
                result = self.detect(frame)
                self.assertTrue(result[name])
                # An obvious hand-sized cover across the print releases the gun.
                frame[y:y+140, x:x+80] = (100, 150, 190)
                result = self.detect(frame)
                self.assertFalse(result[name])

    def test_rejection_reasons_distinguish_small_from_hidden_tags(self):
        self.detect(weapon_frame((4,), size=18))
        self.assertEqual(self.tags.messages, {"gun": "tag too small"})
        self.detect(None)
        self.assertEqual(self.tags.messages["gun"], "no camera")

    def test_loss_duplicate_small_wrong_and_low_contrast_never_fire(self):
        for frame in (None, weapon_frame(()), weapon_frame((7, 1)), weapon_frame((3, 3)),
                      weapon_frame((4, 4)), weapon_frame(size=18),
                      (weapon_frame().astype(np.float32)*.08+100).astype(np.uint8)):
            with self.subTest(frame="missing" if frame is None else "image"):
                self.assertEqual(self.arm(frame), {"gun": False})

    def test_distant_and_dim_tags_fire_without_move_closer(self):
        for size in (24, 30, 36, 48, 60):
            for contrast in (1.0, .22):
                with self.subTest(size=size, contrast=contrast):
                    self.tags.reset()
                    frame = weapon_frame(size=size)
                    if contrast < 1:
                        frame = (frame.astype(np.float32)*contrast+80).astype(np.uint8)
                    self.assertEqual(self.arm(frame), {"gun": True}, self.tags.messages)

    def test_mirror_rotation_perspective_and_normal_lighting(self):
        frame = weapon_frame()
        source = np.float32([[0, 0], [799, 0], [799, 479], [0, 479]])
        target = np.float32([[35, 20], [765, 65], [740, 440], [75, 470]])
        tilted = cv2.warpPerspective(frame, cv2.getPerspectiveTransform(source, target), (800, 480), borderValue=(255,)*3)
        for transformed in (cv2.flip(frame, 1), cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE),
                            tilted, (frame.astype(np.float32)*.7+25).astype(np.uint8),
                            cv2.GaussianBlur(frame, (3, 3), .5)):
            self.tags.reset()
            self.assertEqual(self.arm(transformed), {"gun": True})

    def test_gap_and_missing_frame_require_fresh_rearm(self):
        frame = weapon_frame()
        self.assertTrue(self.arm(frame)["gun"])
        self.time += .2
        self.assertFalse(self.detect(frame)["gun"])
        self.assertTrue(self.arm(frame)["gun"])
        self.assertEqual(self.detect(None), {"gun": False})
        self.assertFalse(self.detect(frame)["gun"])


if __name__ == "__main__":
    unittest.main()
