#!/usr/bin/env python3
"""Bake simulator/assets/look/sf_relief.png from the SF height grid.

R,G = smooth world-space terrain normal (x,z); B = shore proximity (1 at the
waterline, fading ~400 m to sea and inland). The source meshes are coarse and
flat-shaded; the terrain and water shaders read this instead.
Run: .venv/bin/python tools/build_sf_relief.py
"""
from pathlib import Path
import cv2
import numpy as np

root = Path(__file__).resolve().parents[1] / "simulator/assets"
size, step = 2601, 50.0
height = np.fromfile(root / "san_francisco/heights.f32", np.float32).reshape(size, size)
smooth = cv2.GaussianBlur(height, (0, 0), 1.2)
dz, dx = np.gradient(smooth, step)
normal = np.dstack([-dx, np.ones_like(dx), -dz])
normal /= np.linalg.norm(normal, axis=2, keepdims=True)
land = (height > 0.6).astype(np.float32)
near = cv2.GaussianBlur(land, (0, 0), 4.0)
shore = np.clip(1.0 - np.abs(near - 0.5) * 2.0, 0, 1) ** 1.5
image = np.dstack([shore, normal[..., 2] * .5 + .5, normal[..., 0] * .5 + .5])  # BGR for OpenCV
cv2.imwrite(str(root / "look/sf_relief.png"), np.clip(image * 255 + .5, 0, 255).astype(np.uint8))
print("wrote", root / "look/sf_relief.png")
