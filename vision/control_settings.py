"""Live yoke gains shared by the tracker preview and game; never calibration."""
import math


class ControlSettings:
    def __init__(self):
        self.sensitivity = {"pitch": 1.2, "bank": 1.0, "yaw": 1.0}

    def accept(self, command):
        if not isinstance(command, dict) or set(command) != {"action", "request_id", "sensitivity"}:
            raise ValueError("Invalid settings command")
        request_id = command["request_id"]
        if command["action"] != "set_sensitivity" or not isinstance(request_id, str) or not 1 <= len(request_id) <= 80:
            raise ValueError("Invalid settings request")
        gains = command["sensitivity"]
        if not isinstance(gains, dict) or set(gains) != {"pitch", "bank", "yaw"}:
            raise ValueError("Invalid sensitivity axes")
        if any(isinstance(value, bool) or not isinstance(value, (int, float))
               or not math.isfinite(value) or not .25 <= value <= 6 for value in gains.values()):
            raise ValueError("Invalid sensitivity gain")
        self.sensitivity = dict(gains)
        return {"request_id": request_id, "sensitivity": dict(self.sensitivity)}

    def apply(self, packet):
        # Keep physical movement for tutorial checks and instantaneous game-side
        # updates while a new settings command is travelling to the tracker.
        raw = {axis: packet["yoke"][axis] for axis in ("roll", "pitch", "yaw")}
        packet["raw_yoke"] = raw
        packet["sensitivity"] = dict(self.sensitivity)
        for axis, setting in (("roll", "bank"), ("pitch", "pitch"), ("yaw", "yaw")):
            packet["yoke"][axis] = max(-1.0, min(1.0, raw[axis] * self.sensitivity[setting]))
