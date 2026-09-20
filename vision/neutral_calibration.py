"""Three seconds of fresh, steady raw yoke angles establish a neutral pose."""
import math
import statistics

if __package__:
    from .calibration import wrap_degrees
else:
    from calibration import wrap_degrees


class NeutralCalibration:
    DURATION = 3.0
    MAX_GAP = .15
    MAX_MOVEMENT = 4.0

    def __init__(self):
        self.request_id = ""
        self.state = "idle"
        self.samples = []
        self.elapsed = 0.0
        self.reason = "show_yoke"

    def start(self, request_id):
        self.request_id = request_id
        self.state = "waiting"
        self.reset_window("show_yoke")

    def cancel(self):
        self.state = "idle"
        self.reset_window("show_yoke")

    def reset_window(self, reason):
        self.samples.clear()
        self.elapsed = 0.0
        self.reason = reason

    def observe(self, observation, now):
        if self.state not in ("waiting", "holding"):
            return None
        if observation is None or observation.confidence <= .4 or not all(
                math.isfinite(x) for x in (observation.roll, observation.pitch, observation.yaw, observation.confidence, now)):
            self.reset_window("show_yoke")
            self.state = "waiting"
            return None
        angles = (observation.roll, observation.pitch, observation.yaw)
        if self.samples:
            gap = now - self.samples[-1][0]
            if gap <= 0 or gap >= self.MAX_GAP:
                self.reset_window("hold_still")
            elif any(abs(wrap_degrees(a-b)) > self.MAX_MOVEMENT
                     for a, b in zip(angles, self.samples[0][1])):
                self.reset_window("hold_still")
        self.samples.append((now, angles))
        self.state = "holding"
        self.elapsed = min(self.DURATION, now-self.samples[0][0])
        if self.elapsed < self.DURATION:
            return None
        # Use the whole window, including wrapped roll around an upside-down tag.
        anchor = self.samples[0][1]
        neutral = tuple(wrap_degrees(anchor[i] + statistics.median(
            wrap_degrees(sample[i]-anchor[i]) for _, sample in self.samples)) for i in range(3))
        self.state = "complete"
        return neutral

    def packet(self):
        return {"request_id": self.request_id, "state": self.state,
                "elapsed": round(self.elapsed, 3), "reason": self.reason}
