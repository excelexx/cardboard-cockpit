"""Read the secondary camera independently so a stalled phone cannot stall yoke input."""
import asyncio
import threading
import time


class BackgroundCamera:
    FRESH_SECONDS = .15

    def __init__(self, source, fps):
        self.source, self.fps = source, fps
        self.frame = None
        self.received = 0.0
        self.lock = threading.Lock()
        self.stopping = threading.Event()
        # Timestamp and publish on the capture thread. OpenCV detection can
        # occupy the asyncio thread long enough to delay a to_thread callback;
        # that must not make an already-arrived phone frame look stale.
        self.thread = threading.Thread(target=self._capture, name="throttle-camera", daemon=True)
        self.thread.start()

    def _capture(self):
        while not self.stopping.is_set():
            begun = time.monotonic()
            try:
                frame = self.source.read()
            except Exception:
                # Read failures are missing observations, never permission to
                # switch to a different camera or reuse a stale throttle pose.
                frame = None
            with self.lock:
                self.frame = frame
                self.received = time.monotonic()
            self.stopping.wait(max(0, 1/self.fps-(time.monotonic()-begun)))

    def snapshot(self):
        with self.lock:
            if self.frame is None or time.monotonic()-self.received >= self.FRESH_SECONDS:
                return None
            return self.frame.copy()

    async def close(self):
        self.stopping.set()
        # Do not release VideoCapture while its worker thread is still reading.
        try:
            await asyncio.to_thread(self.thread.join)
        finally:
            self.source.close()
