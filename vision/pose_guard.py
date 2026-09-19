"""Reject isolated orientation spikes without learning a drifting neutral."""
import math


class PoseGuard:
    def __init__(self):
        self.reset()

    def reset(self):
        self.previous = None
        self.previous_time = None
        self.pending = None
        self.pending_count = 0

    @staticmethod
    def distance(a, b):
        return max(abs((x - y + 180) % 360 - 180) for x, y in zip(a, b))

    def accept(self, angles, now):
        if not all(math.isfinite(x) for x in (*angles, now)):
            return False
        if self.previous_time is None or now - self.previous_time > .4 or now < self.previous_time:
            self.reset()
        # Ordinary continuous motion passes immediately. A large discontinuity
        # needs three agreeing samples, so an isolated bad pose cannot steer.
        delta = 1 / 30 if self.previous_time is None else max(0, now - self.previous_time)
        threshold = 8 + 180 * min(delta, .10)
        if self.previous is not None and self.distance(angles, self.previous) > threshold:
            self.pending_count = self.pending_count + 1 if self.pending is not None and self.distance(angles, self.pending) < 6 else 1
            self.pending = angles
            if self.pending_count < 3:
                return False
        self.previous, self.previous_time = angles, now
        self.pending = None
        self.pending_count = 0
        return True
