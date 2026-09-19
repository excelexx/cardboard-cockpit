"""Three-tag slider: ID 0 = idle, ID 1 = moving grip, ID 2 = full.

All marker faces must lie in the same flat plane. Fixed endpoint centers define
the travel axis; the moving tag may run in a parallel lane to avoid covering
them. Rectifying the plane makes the fraction independent of camera position,
scale and perspective. No measured travel length or saved endpoints are used.
"""
import collections
import math

if __package__:
    from .calibration import RelativeThrottleObservation, clamp
else:
    from calibration import RelativeThrottleObservation, clamp

THROTTLE_IDLE_ID = 0
THROTTLE_ID = 1
THROTTLE_FULL_ID = 2


class RelativeThrottle:
    def __init__(self, cv2, np):
        self.cv2, self.np = cv2, np
        self.message = "Show throttle tags 0, 1 and 2."

    def observe(self, corners, ids, frame=None):
        cv, np = self.cv2, self.np
        required = (THROTTLE_IDLE_ID, THROTTLE_ID, THROTTLE_FULL_ID)
        self.message = "Show throttle tags 0, 1 and 2; last power held."
        if ids is None:
            return None
        counts = collections.Counter(int(i) for i in ids.flatten())
        if any(counts[i] != 1 for i in required):
            if any(counts[i] > 1 for i in required):
                self.message = "Duplicate throttle tag: keep only one of each ID visible."
            return None
        markers = {int(i): c.reshape(4, 2).astype(np.float32)
                   for c, i in zip(corners, ids.flatten()) if int(i) in required}
        sides = []
        for points in markers.values():
            if not np.isfinite(points).all() or not cv.isContourConvex(points):
                return None
            side = min(float(np.linalg.norm(points[(i + 1) % 4] - points[i])) for i in range(4))
            if side < 24 or abs(cv.contourArea(points)) < 24 * 24:
                self.message = "Move throttle tags closer; keep every corner visible."
                return None
            sides.append(side)
        square = np.array([[-.5, -.5], [.5, -.5], [.5, .5], [-.5, .5]], np.float32)
        try:
            # The idle marker supplies a metric plane up to an arbitrary scale.
            # Transform corners before averaging: image-space corner averages
            # are not the physical marker center under perspective.
            transform = cv.getPerspectiveTransform(markers[THROTTLE_IDLE_ID], square)
            all_points = np.concatenate([markers[i] for i in required])
            homogeneous = np.column_stack((all_points, np.ones(12))) @ transform.T
            weights = homogeneous[:, 2]
            if not np.isfinite(homogeneous).all() or not (np.all(weights > 1e-8) or np.all(weights < -1e-8)):
                return None
            rectified = (homogeneous[:, :2] / weights[:, None]).reshape(3, 4, 2)
            idle, moving, full = rectified.mean(axis=1)
            axis = full - idle
            span_squared = float(axis @ axis)
            if span_squared < 1.0:
                self.message = "Separate the fixed 0% and 100% tags."
                return None
            value = float((moving - idle) @ axis / span_squared)
            if not math.isfinite(value):
                return None
            # Recover true image centers for the preview and visibility guard.
            centers = cv.perspectiveTransform(
                np.array([[idle, moving, full]], np.float32), np.linalg.inv(transform))[0]
            if float(np.linalg.norm(centers[2] - centers[0])) < 48:
                self.message = "Throttle travel is too small in view; raise or move the camera closer."
                return None
        except (ValueError, np.linalg.LinAlgError, cv.error):
            return None
        value = clamp(value, 0, 1)
        confidence = clamp(min(sides) / 85, .25, 1)
        self.message = "THROTTLE %3.0f%% | 0 = idle, 1 = slider, 2 = full" % (value * 100)
        if frame is not None:
            pixels = [tuple(p.astype(int)) for p in centers]
            cv.line(frame, pixels[0], pixels[2], (50, 210, 255), 2)
            for marker_id, point in zip(required, pixels):
                cv.circle(frame, point, 5, (50, 210, 255), -1)
                cv.putText(frame, {0: "0%", 1: "%d%%" % round(value * 100), 2: "100%"}[marker_id],
                           (point[0] + 8, point[1] - 8), cv.FONT_HERSHEY_SIMPLEX, .5, (40, 180, 220), 2)
        return RelativeThrottleObservation(value, confidence)
