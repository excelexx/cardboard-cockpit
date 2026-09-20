import asyncio
import threading
import time
import unittest

import numpy as np

from vision.background_camera import BackgroundCamera


class Camera:
    def __init__(self):
        self.reads = 0
        self.fail = False
        self.closed = False
        self.delay = 0
        self.entered = threading.Event()

    def read(self):
        self.entered.set()
        time.sleep(self.delay)
        self.reads += 1
        return None if self.fail else np.full((2, 2, 3), self.reads % 256, np.uint8)

    def close(self):
        self.closed = True


class BackgroundCameraTests(unittest.IsolatedAsyncioTestCase):
    async def test_busy_processing_loop_cannot_delay_frame_publication(self):
        camera = Camera()
        feed = BackgroundCamera(camera, 60)
        try:
            await asyncio.sleep(.04)
            before = camera.reads
            # Deliberately keep asyncio busy, as marker detection does. Real
            # camera frames must still be published with their capture times.
            time.sleep(.22)
            frame = feed.snapshot()
            self.assertIsNotNone(frame)
            self.assertGreater(camera.reads, before+3)
            self.assertLess(time.monotonic()-feed.received, .1)
            frame[:] = 0
            self.assertTrue(feed.snapshot().any(), "Caller annotations cannot mutate captured pixels")
        finally:
            await feed.close()
        self.assertTrue(camera.closed)

    async def test_missing_and_stale_frames_still_invalidate_controls(self):
        camera = Camera()
        feed = BackgroundCamera(camera, 60)
        try:
            await asyncio.sleep(.04)
            self.assertIsNotNone(feed.snapshot())
            camera.delay = .3
            await asyncio.sleep(.21)
            self.assertIsNone(feed.snapshot(), "A stalled capture must not keep old throttle observations live")
            camera.fail = True
            await asyncio.sleep(.15)
            self.assertIsNone(feed.snapshot())
            camera.fail = False; camera.delay = 0
            await asyncio.sleep(.35)
            self.assertIsNotNone(feed.snapshot())
        finally:
            await feed.close()

    async def test_close_waits_for_the_active_read(self):
        camera = Camera(); camera.delay = .12
        feed = BackgroundCamera(camera, 30)
        await asyncio.to_thread(camera.entered.wait)
        closing = asyncio.create_task(feed.close())
        await asyncio.sleep(.025)
        self.assertFalse(camera.closed)
        await closing
        self.assertTrue(camera.closed)
        self.assertFalse(feed.thread.is_alive())
