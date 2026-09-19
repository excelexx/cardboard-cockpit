# Control schema — version 1

Implemented by `vision/tracker.py`. Vision is an optional local process; the native client must remain playable without Python, a camera, or this connection.

Transport: one UTF-8 JSON object per WebSocket text message at approximately 24–30 Hz. The service defaults to `ws://127.0.0.1:8765`.

```json
{
  "version": 1,
  "sequence": 42,
  "timestamp": 1789737600123,
  "tracking": true,
  "yoke": {
    "roll": -0.35,
    "pitch": 0.2,
    "confidence": 0.95
  },
  "throttle": {
    "value": 0.72,
    "confidence": 0.98
  }
}
```

| Field | Meaning |
| --- | --- |
| `version` | Protocol version; reject unsupported versions |
| `sequence` | Monotonically increasing integer per tracker process; not necessarily zero when a client connects |
| `timestamp` | Unix milliseconds; useful for logging, not the sole timeout source |
| `tracking` | True only when both yoke and three-tag throttle are usable; individual confidence still governs each control |
| `yoke.roll` | -1 left to +1 right |
| `yoke.pitch` | -1 nose-down to +1 nose-up |
| `yoke.confidence` | 0 lost to 1 confident; geometric quality heuristic, not a probability |
| `throttle.value` | 0 idle to 1 full |
| `throttle.confidence` | 0 lost to 1 confident; independent of yoke visibility |

Receiver requirements:

- Validate shape, version, types, finite numbers, size, sequence and bounds before merging input.
- Use a local monotonic receive clock to detect stale packets.
- Keep keyboard and mouse providers independent of the connection.
- Support explicit keyboard takeover and never let a stale packet overwrite it.
- Smooth yoke changes and blend toward neutral after a short hold on loss.
- Handle throttle confidence independently; preserve safe power during brief loss and offer keyboard takeover.
- Reset sequence validation after a new connection and display connection state without blocking gameplay.

## Transport and timing

The service binds only to `127.0.0.1`, never a public interface. It accepts native WebSocket clients without an `Origin` header and rejects browser origins. Messages are output only; sending client data closes that connection. No images or calibration data travel over the control socket. Each client has a one-frame queue so a slow receiver cannot accumulate stale controls. The target rate is 30 Hz (`--fps 24` or `25` is also supported); actual webcam speed depends on hardware and light.

The separate `/preview` WebSocket path carries binary JPEG frames for the game's bottom-right self-view. Frames are mirrored for display only, preserve aspect ratio within 320 x 240 pixels, are capped at 64 KiB, and are sent at most 10 times per second only while a preview client is connected. Its independent one-frame queue cannot accumulate stale video or delay control sends. Images remain in memory on this computer and are never recorded or uploaded. The game clears the image after one second without a valid frame or when tracking is disabled. Marker detection always uses the original, unmirrored image.

Use a local monotonic timeout of roughly 350 ms to detect a stopped service. `timestamp` uses wall clock for logging; system clock changes must not override timeout logic. Discard duplicate or older sequence numbers within a connection. Reset the sequence guard on reconnection, since the service may have restarted. Packets are normally under 300 bytes; receivers can cap messages at 2 KB.

## Loss and ownership

The tracker smooths valid input with a 0.10 s exponential time constant, uses a 6% yoke dead zone, and limits yoke changes to 3.5 units/second and throttle changes to 1.5 units/second. Values are bounded before serialization. Low confidence (<0.25), invalid numbers, duplicated marker IDs, and detection failure count as loss.

After filtering, the tracker applies `--yoke-sensitivity` (default 2.0) to bank and pitch, with an additional `--bank-scale` (default 0.7) for bank only, then clamps them to [-1, 1]. Effective gains are 1.4 for bank and 2.0 for pitch. These final values drive both its on-screen readout and the control packet. The game uses the packet directly without another gain; its YOKE readout displays the received command separately from aircraft attitude and flight-control corrections. Throttle and weapon controls are unaffected.

Yoke loss sets confidence to zero immediately, holds its last target for 250 ms, then eases toward roll/pitch zero. Throttle loss sets its confidence to zero immediately and holds the last smoothed power setting. It does **not** cut power during a camera interruption. At first startup all outputs are zero. During calibration, confidence is zero for both controls and the same loss policies apply.

The receiver owns keyboard takeover and decides whether vision is selected. A user pressing keyboard controls must retain control; receiving another valid camera frame must not silently steal ownership. Summary `tracking: false` must not disable the independently visible control. A disconnected socket must never block the game loop or its menus.

## Calibration

Calibration is a local five-step yoke screen in the tracker, launched with `--camera 0 --calibrate`. Its preview accepts **Space** to capture each endpoint, **C** to restart calibration, and **Q/Escape** to stop the tracker. No socket command is needed. Values are stored atomically in the ignored `vision/calibration.local.json` by default:

```json
{
  "version": 1,
  "camera_index": 0,
  "width": 1280,
  "height": 720,
  "roll": {"negative": 35.0, "neutral": 0.0, "positive": -35.0},
  "pitch": {"negative": -25.0, "neutral": 0.0, "positive": 25.0},
  "throttle": {"idle": [0.75, 0.8], "full": [0.75, 0.4]}
}
```

Roll and pitch endpoints are raw orientation angles in degrees. Each axis requires at least 8° of movement on **both** sides of neutral; the signs may reverse with mounting orientation. A calibrated endpoint always maps to the intended direction. The saved throttle endpoints remain in the version-1 file for compatibility with simulations. Live throttle uses tags 0/1/2 and ignores these saved pixels: rectify the common marker plane, then project moving tag 1 along the current 0-to-2 axis. All three tags must be uniquely visible in the same frame; no stale endpoint caching is used. These are relative controls, not metrically calibrated camera pose.

`--simulate --loss-demo` supplies a deterministic 20-second loop for integration testing: yoke is absent at 8–11 s; throttle is absent at 13–16 s. It never accesses a camera. See `docs/vision-setup.md` for setup and known limits.

Keyboard steering while the yoke is absent preserves throttle tracking. W/S explicitly releases camera input. In paper-test flight, automatic speed stops after the first valid relative throttle observation and stays off through marker loss until a flight restart.
