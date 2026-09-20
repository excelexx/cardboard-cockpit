"""Physically sized synthetic webcam frames; no camera is ever opened.

Markers are rendered at their printed size and distance through a pinhole
camera, on grey "cardboard", with paper-like contrast, optional dimness, blur
and sensor noise. This is closer to a real desk than a pasted black square, but
it is still software evidence and not a physical-camera validation.
"""
import math

import cv2
import numpy as np

DICTIONARY = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)


def _rotation(pitch_degrees: float, roll_degrees: float):
    pitch, roll = math.radians(pitch_degrees), math.radians(roll_degrees)
    rx = np.array([[1, 0, 0], [0, math.cos(pitch), -math.sin(pitch)], [0, math.sin(pitch), math.cos(pitch)]])
    rz = np.array([[math.cos(roll), -math.sin(roll), 0], [math.sin(roll), math.cos(roll), 0], [0, 0, 1]])
    return rz @ rx @ np.diag([1., -1., -1.])


def render(width, height, items, rng, light=1.0, blur=1.0, noise=4.0, fov_degrees=70.0):
    """items: (marker_id, black_square_metres, (x, y, z) metres, pitch_degrees, roll_degrees).

    The tracker reports a yoke pitch of about -pitch_degrees.
    """
    focal = (width / 2) / math.tan(math.radians(fov_degrees) / 2)
    matrix = np.array([[focal, 0, width / 2], [0, focal, height / 2], [0, 0, 1]], dtype=np.float64)
    image = np.full((height, width), 170, np.uint8)
    for marker_id, size, position, pitch, roll in items:
        half = size * 8 / 6 / 2  # include the white quiet margin
        corners = np.array([[-half, half, 0], [half, half, 0], [half, -half, 0], [-half, -half, 0]], np.float32)
        rvec, _ = cv2.Rodrigues(_rotation(pitch, roll))
        projected, _ = cv2.projectPoints(corners, rvec, np.array(position, dtype=np.float64), matrix, np.zeros(5))
        texture = np.full((800, 800), 255, np.uint8)
        texture[100:700, 100:700] = cv2.aruco.generateImageMarker(DICTIONARY, marker_id, 600)
        transform = cv2.getPerspectiveTransform(np.array([[0, 0], [799, 0], [799, 799], [0, 799]], np.float32),
                                                projected.reshape(4, 2).astype(np.float32))
        warped = cv2.warpPerspective(texture, transform, (width, height), flags=cv2.INTER_AREA)
        mask = cv2.warpPerspective(np.full((800, 800), 255, np.uint8), transform, (width, height))
        image = np.where(mask > 127, warped, image).astype(np.uint8)
    # Printed black reflects roughly 12% and paper 85%: never pure 0 and 255.
    result = (30 + image.astype(np.float32) * (215 / 255)) * light
    if blur > 0:
        result = cv2.GaussianBlur(result, (0, 0), blur)
    result += rng.normal(0, noise, result.shape)
    return cv2.cvtColor(np.clip(result, 0, 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)


def cockpit(width, height, rng, pitch=0.0, roll=0.0, throttle=0.5, distance=1.0, camera_tilt=20.0, **conditions):
    """Both props as a webcam 25-40 cm above the desk would see them."""
    return render(width, height, [
        (7, .07, (-.18, .05, distance), pitch + camera_tilt, roll),
        (23, .05, (.22, .12 - .10 * throttle, distance + .12 * throttle), camera_tilt, 0),
    ], rng, **conditions)
