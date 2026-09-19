"""Validated calibration and time-based filtering; standard library only.

Coordinates are unmirrored camera image coordinates. Endpoints establish signs,
so either physical tilt direction and either throttle travel direction work.
"""
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, Optional, Tuple


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def finite_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def wrap_degrees(angle: float) -> float:
    return (angle + 180.0) % 360.0 - 180.0


@dataclass(frozen=True)
class AxisCalibration:
    negative: float
    neutral: float
    positive: float

    def validate(self, label: str, minimum_span: float = 8.0) -> None:
        if not all(finite_number(v) for v in (self.negative, self.neutral, self.positive)):
            raise ValueError("%s calibration must contain finite numbers." % label)
        negative = wrap_degrees(self.negative - self.neutral)
        positive = wrap_degrees(self.positive - self.neutral)
        if abs(negative) < minimum_span or abs(positive) < minimum_span:
            raise ValueError("%s: move at least %.0f degrees each way from neutral." % (label, minimum_span))
        if negative * positive >= 0:
            raise ValueError("%s endpoints must be on opposite sides of neutral." % label)
        if abs(negative) > 100 or abs(positive) > 100:
            raise ValueError("%s: use a comfortable range under 100 degrees." % label)

    def normalize(self, value: float) -> float:
        offset = wrap_degrees(value - self.neutral)
        positive_span = wrap_degrees(self.positive - self.neutral)
        if offset * positive_span >= 0:
            return clamp(offset / positive_span, 0.0, 1.0)
        negative_span = wrap_degrees(self.negative - self.neutral)
        return -clamp(offset / negative_span, 0.0, 1.0)


@dataclass(frozen=True)
class ThrottleCalibration:
    idle: Tuple[float, float]
    full: Tuple[float, float]

    def validate(self) -> None:
        if len(self.idle) != 2 or len(self.full) != 2:
            raise ValueError("Throttle endpoints must each contain x and y.")
        if not all(finite_number(v) and 0 <= v <= 1 for v in (*self.idle, *self.full)):
            raise ValueError("Throttle endpoints must be finite image coordinates in [0, 1].")
        if math.hypot(self.full[0] - self.idle[0], self.full[1] - self.idle[1]) < 0.06:
            raise ValueError("Throttle: move through at least 6% of the camera image. Raise the camera slightly.")

    def normalize(self, position: Tuple[float, float]) -> float:
        dx, dy = self.full[0] - self.idle[0], self.full[1] - self.idle[1]
        return clamp(((position[0] - self.idle[0]) * dx + (position[1] - self.idle[1]) * dy) / (dx * dx + dy * dy), 0, 1)


@dataclass(frozen=True)
class Calibration:
    roll: AxisCalibration
    pitch: AxisCalibration
    throttle: ThrottleCalibration
    camera_index: int = 0
    width: int = 1280
    height: int = 720
    version: int = 1

    def validate(self) -> None:
        if type(self.version) is not int or self.version != 1:
            raise ValueError("Unsupported calibration version.")
        self.roll.validate("Roll")
        self.pitch.validate("Pitch")
        self.throttle.validate()
        if any(type(v) is not int for v in (self.camera_index, self.width, self.height)):
            raise ValueError("Camera index and frame dimensions must be integers.")
        if self.width <= 0 or self.height <= 0 or self.camera_index < 0:
            raise ValueError("Camera index and frame dimensions are invalid.")

    def save(self, path: Path) -> None:
        self.validate()
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(json.dumps(asdict(self), indent=2, allow_nan=False) + "\n", encoding="utf-8")
        temporary.replace(path)

    @classmethod
    def load(cls, path: Path) -> "Calibration":
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            result = cls(
                roll=AxisCalibration(**payload["roll"]),
                pitch=AxisCalibration(**payload["pitch"]),
                throttle=ThrottleCalibration(tuple(payload["throttle"]["idle"]), tuple(payload["throttle"]["full"])),
                camera_index=payload["camera_index"], width=payload["width"],
                height=payload["height"], version=payload["version"],
            )
            result.validate()
            return result
        except (OSError, ValueError, TypeError, KeyError) as error:
            raise ValueError("Cannot use calibration %s: %s" % (path, error)) from error


def simulated_calibration() -> Calibration:
    """For synthetic input only. Real cameras must use guided calibration."""
    return Calibration(AxisCalibration(-35, 0, 35), AxisCalibration(-25, 0, 25),
                       ThrottleCalibration((0.75, 0.80), (0.75, 0.40)))


@dataclass(frozen=True)
class YokeObservation:
    roll: float
    pitch: float
    confidence: float


@dataclass(frozen=True)
class ThrottleObservation:
    position: Tuple[float, float]
    confidence: float


def dead_zone(value: float, radius: float) -> float:
    if abs(value) <= radius:
        return 0.0
    return math.copysign((abs(value) - radius) / (1.0 - radius), value)


class ControlFilter:
    """Independent marker loss policies and bounded motion prevent sharp jumps.

    Event tuning: smoothing_seconds = 0.10, deadzone = 0.06, hold_seconds = 0.25.
    Throttle holds its last level after loss; never unexpectedly cuts an engine.
    Confidence is zero immediately on loss so the client can show keyboard help.
    """
    def __init__(self, calibration: Calibration, smoothing_seconds: float = 0.10,
                 deadzone: float = 0.06, hold_seconds: float = 0.25):
        calibration.validate()
        if not 0.01 <= smoothing_seconds <= 2 or not 0 <= deadzone < 0.5 or not 0 <= hold_seconds <= 2:
            raise ValueError("Invalid smoothing, deadzone, or hold duration.")
        self.calibration = calibration
        self.smoothing_seconds = smoothing_seconds
        self.deadzone = deadzone
        self.hold_seconds = hold_seconds
        self.roll = self.pitch = self.throttle = 0.0
        self.roll_target = self.pitch_target = 0.0
        self.last_yoke = float("-inf")
        self.last_time: Optional[float] = None
        self.sequence = 0

    def _smooth(self, current: float, target: float, delta: float, rate: float) -> float:
        step = (target - current) * (1.0 - math.exp(-delta / self.smoothing_seconds))
        return current + clamp(step, -rate * delta, rate * delta)

    def step(self, now: float, timestamp_ms: int, yoke: Optional[YokeObservation],
             throttle: Optional[ThrottleObservation]) -> Dict[str, object]:
        if not finite_number(now) or type(timestamp_ms) is not int:
            raise ValueError("Invalid clocks.")
        delta = 1 / 30 if self.last_time is None else clamp(now - self.last_time, 0, 0.10)
        self.last_time = now
        yoke_confidence = throttle_confidence = 0.0
        if yoke is not None and all(finite_number(v) for v in (yoke.roll, yoke.pitch, yoke.confidence)) and yoke.confidence >= 0.25:
            self.roll_target = dead_zone(self.calibration.roll.normalize(yoke.roll), self.deadzone)
            self.pitch_target = dead_zone(self.calibration.pitch.normalize(yoke.pitch), self.deadzone)
            self.last_yoke = now
            yoke_confidence = clamp(yoke.confidence, 0, 1)
        elif now - self.last_yoke > self.hold_seconds:
            self.roll_target = self.pitch_target = 0.0
        self.roll = self._smooth(self.roll, self.roll_target, delta, 3.5)
        self.pitch = self._smooth(self.pitch, self.pitch_target, delta, 3.5)
        if throttle is not None and len(throttle.position) == 2 and all(finite_number(v) for v in (*throttle.position, throttle.confidence)) and throttle.confidence >= 0.25:
            target = self.calibration.throttle.normalize(throttle.position)
            self.throttle = self._smooth(self.throttle, target, delta, 1.5)
            throttle_confidence = clamp(throttle.confidence, 0, 1)
        packet = {
            "version": 1, "sequence": self.sequence, "timestamp": timestamp_ms,
            "tracking": yoke_confidence > 0 and throttle_confidence > 0,
            "yoke": {"roll": round(self.roll, 5), "pitch": round(self.pitch, 5), "confidence": round(yoke_confidence, 3)},
            "throttle": {"value": round(self.throttle, 5), "confidence": round(throttle_confidence, 3)},
        }
        self.sequence += 1
        return packet


def simulated_observations(frame: int, fps: float, loss_demo: bool = False):
    """Repeatable bounded trajectories; no camera or random generator involved."""
    seconds = frame / fps
    yoke = YokeObservation(18 * math.sin(seconds * 0.45), 8 * math.sin(seconds * 0.3), 0.98)
    throttle = ThrottleObservation((0.75, 0.80 - 0.40 * (0.65 + 0.20 * math.sin(seconds * 0.2))), 0.98)
    if loss_demo:
        cycle = seconds % 20
        if 8 <= cycle < 11:
            yoke = None
        if 13 <= cycle < 16:
            throttle = None
    return yoke, throttle
