"""Camera placement check for the physical cockpit; standard library only.

Collects what the tracker saw while the builder moves both controls through
their travel, then turns it into PASS / WARN / FAIL lines with one concrete fix
each. It answers "will calibration and flying work from here?" before anyone
has to fail a calibration to find out.
"""
import collections
import math
import statistics
from typing import List, Optional, Tuple

PASS, WARN, FAIL = "PASS", "WARN", "FAIL"
WINDOW = 15  # frames; about half a second of holding still


def _quietest(values: List[float]) -> float:
    """Jitter during the calmest tenth of the check: the hold-still moment, not the sweeps."""
    ordered = sorted(values)
    return ordered[len(ordered) // 10]


class PlacementCheck:
    def __init__(self, frame_width: int = 1280):
        self.scale = frame_width / 1280.0
        self.frames = 0
        self.first_time: Optional[float] = None
        self.last_time: Optional[float] = None
        self.yoke_seen = self.throttle_seen = 0
        self.yoke_sides: List[float] = []
        self.throttle_sides: List[float] = []
        self.rolls: List[float] = []
        self.pitches: List[float] = []
        self.positions: List[Tuple[float, float]] = []
        self.pitch_jumps = 0
        self.previous_pitch: Optional[float] = None
        self.recent = collections.deque(maxlen=WINDOW)
        self.still_roll: List[float] = []
        self.still_pitch: List[float] = []

    def add(self, now: float, yoke, throttle, yoke_side: Optional[float] = None,
            throttle_side: Optional[float] = None) -> None:
        self.frames += 1
        if self.first_time is None:
            self.first_time = now
        self.last_time = now
        if yoke is None:
            self.previous_pitch = None
            self.recent.clear()
        else:
            self.yoke_seen += 1
            self.rolls.append(yoke.roll)
            self.pitches.append(yoke.pitch)
            if yoke_side:
                self.yoke_sides.append(yoke_side)
            # No hand moves a yoke 20 degrees in one frame; that is a pose flip.
            if self.previous_pitch is not None and abs(yoke.pitch - self.previous_pitch) > 20:
                self.pitch_jumps += 1
            self.previous_pitch = yoke.pitch
            self.recent.append((yoke.roll, yoke.pitch))
            if len(self.recent) == WINDOW:
                rolls, pitches = zip(*self.recent)
                first = rolls[0]
                rolls = [first + (value - first + 180.0) % 360.0 - 180.0 for value in rolls]
                self.still_roll.append(statistics.pstdev(rolls))
                self.still_pitch.append(statistics.pstdev(pitches))
        if throttle is not None:
            self.throttle_seen += 1
            self.positions.append(tuple(throttle.position))
            if throttle_side:
                self.throttle_sides.append(throttle_side)

    def fps(self) -> float:
        if self.frames < 2 or self.last_time is None or self.last_time <= self.first_time:
            return 0.0
        return (self.frames - 1) / (self.last_time - self.first_time)

    def throttle_travel(self) -> float:
        if not self.positions:
            return 0.0
        xs, ys = zip(*self.positions)
        return math.hypot(max(xs) - min(xs), max(ys) - min(ys))

    def live_lines(self) -> List[str]:
        """Three short lines for the preview overlay."""
        def rate(seen):
            return 100.0 * seen / max(self.frames, 1)
        pitch = "pitch %+.0f..%+.0f" % (min(self.pitches), max(self.pitches)) if self.pitches else "pitch --"
        return ["PLACEMENT CHECK  |  %.1f FPS  |  hold still 2 s, sweep yoke + throttle, then Q" % self.fps(),
                "YOKE seen %3.0f%%  %s  flips %d" % (rate(self.yoke_seen), pitch, self.pitch_jumps),
                "THROTTLE seen %3.0f%%  travel %.0f%% of image" % (rate(self.throttle_seen), 100 * self.throttle_travel())]

    def report(self) -> List[Tuple[str, str, str]]:
        rows = []
        if self.frames < 30:
            return [(FAIL, "Frames", "Only %d frames arrived. Check the camera index and permissions." % self.frames)]
        fps = self.fps()
        rows.append((PASS if fps >= 24 else WARN if fps >= 18 else FAIL, "Frame rate",
                     "%.1f FPS%s" % (fps, "" if fps >= 24 else ". Add light (dim rooms slow webcams) or use --width 640 --height 480.")))
        for label, seen, sides, good, minimum in (
                ("Yoke (ID 7)", self.yoke_seen, self.yoke_sides, 45 * self.scale, 24 * self.scale),
                ("Throttle (ID 23)", self.throttle_seen, self.throttle_sides, 30 * self.scale, 16.0)):
            rate = 100.0 * seen / self.frames
            if seen == 0:
                rows.append((FAIL, label, "Never seen. Face it to the camera, flatten the paper, keep the white margin clear, add light."))
                continue
            rows.append((PASS if rate >= 95 else WARN if rate >= 80 else FAIL, label + " visibility",
                         "seen in %.0f%% of frames%s" % (rate, "" if rate >= 95 else ". Fingers over a corner, glare from tape, or motion blur in low light are the usual causes.")))
            if sides:
                side = statistics.median(sides)
                rows.append((PASS if side >= good else WARN if side >= minimum else FAIL, label + " size",
                             "%.0f px across%s" % (side, "" if side >= good else " (want %.0f+). Move the camera closer or print the 9 cm sticker sheet." % good)))
        if self.still_roll:
            roll_jitter, pitch_jitter = _quietest(self.still_roll), _quietest(self.still_pitch)
            worst = max(roll_jitter, pitch_jitter)
            rows.append((PASS if worst <= 1.0 else WARN if worst <= 2.5 else FAIL, "Yoke steadiness",
                         "roll %.1f deg, pitch %.1f deg at rest%s" % (roll_jitter, pitch_jitter, "" if worst <= 1.0 else
                                                                     ". Add light or move closer; try --smoothing 0.16 --deadzone 0.09.")))
        if self.pitches:
            low, high = min(self.pitches), max(self.pitches)
            rows.append((PASS if self.pitch_jumps == 0 else WARN if self.pitch_jumps <= 3 else FAIL, "Pitch flips",
                         "%d sudden jumps%s" % (self.pitch_jumps, "" if self.pitch_jumps == 0 else ". The marker is passing head-on to the lens; see the next line.")))
            if high - low < 25:
                rows.append((WARN, "Pitch travel", "only %.0f deg seen. Tilt the yoke top fully forward and back during the check." % (high - low)))
            elif low < -8 and high > 8:
                rows.append((WARN, "Pitch geometry", "travel %+.0f..%+.0f deg crosses head-on (0). Raise the camera or lean the marker plate "
                                                     "back 10-15 deg so the whole travel stays on one side." % (low, high)))
            else:
                rows.append((PASS, "Pitch geometry", "travel %+.0f..%+.0f deg stays clear of head-on" % (low, high)))
        if self.rolls and max(self.rolls) - min(self.rolls) < 30:
            rows.append((WARN, "Roll travel", "only %.0f deg seen. Bank fully left and right during the check." % (max(self.rolls) - min(self.rolls))))
        if self.positions:
            travel = self.throttle_travel()
            # The documented mount (25-40 cm up, 70-100 cm away) yields roughly 8-10%.
            rows.append((PASS if travel >= 0.08 else WARN if travel >= 0.06 else FAIL, "Throttle travel",
                         "%.1f%% of the image%s" % (100 * travel, "" if travel >= 0.08 else
                                                    " (calibration refuses under 6%, so aim for 8%+). Raise or offset the camera so the slide moves across the picture, not toward the lens.")))
            xs, ys = zip(*self.positions)
            if min(xs) < 0.06 or max(xs) > 0.94 or min(ys) < 0.06 or max(ys) > 0.94:
                rows.append((WARN, "Throttle framing", "the marker reaches the edge of the picture. Re-aim so the full slide stays inside."))
        return rows


def format_report(rows: List[Tuple[str, str, str]]) -> str:
    lines = ["", "Cardboard Cockpit placement check"]
    lines += ["  [%s] %-22s %s" % row for row in rows]
    worst = FAIL if any(row[0] == FAIL for row in rows) else WARN if any(row[0] == WARN for row in rows) else PASS
    lines.append({PASS: "Ready. Run --calibrate next.",
                  WARN: "Usable, but fix the WARN lines for a smoother demo, then run --calibrate.",
                  FAIL: "Fix the FAIL lines and run --check again before calibrating."}[worst])
    return "\n".join(lines)
