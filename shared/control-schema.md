# Control schema — version 1

Implemented by `vision/tracker.py`. Vision is an optional local process; the native client must remain playable without Python, a camera, or this connection.

Transport: one UTF-8 JSON object per WebSocket text message at approximately 24–30 Hz. The service defaults to `ws://127.0.0.1:8765`.

```json
{
  "version": 1,
  "sequence": 42,
  "timestamp": 1789737600123,
  "tracking": true,
  "yoke_enabled": true,
  "yoke": {
    "roll": -0.35,
    "pitch": 0.2,
    "yaw": 0.15,
    "confidence": 0.95
  },
  "throttle": {
    "value": 0.72,
    "confidence": 0.98
  },
  "weapons": {
    "gun": true
  }
}
```

| Field | Meaning |
| --- | --- |
| `version` | Protocol version; reject unsupported versions |
| `sequence` | Monotonically increasing integer per tracker process; not necessarily zero when a client connects |
| `timestamp` | Unix milliseconds; useful for logging, not the sole timeout source |
| `tracking` | True only when both yoke and three-tag throttle are usable; individual confidence still governs each control |
| `yoke_enabled` | Optional boolean, defaults true for older senders; false only for explicit throttle-only mode |
| `yoke.roll` | -1 left to +1 right |
| `yoke.pitch` | -1 nose-down to +1 nose-up |
| `yoke.yaw` | Optional -1 nose-left to +1 nose-right rudder, defaults to zero for older senders |
| `yoke.confidence` | 0 lost to 1 confident; geometric quality heuristic, not a probability |
| `throttle.value` | 0 idle to 1 full |
| `throttle.confidence` | 0 lost to 1 confident; independent of yoke visibility |
| `weapons.gun` | Boolean held trigger: ID 4 is clearly visible |

Receiver requirements:

- Validate shape, version, types, finite numbers, size, sequence and bounds before merging input.
- Use a local monotonic receive clock to detect stale packets.
- Keep keyboard and mouse providers independent of the connection.
- Support explicit keyboard takeover and never let a stale packet overwrite it.
- Smooth yoke changes and blend toward neutral after a short hold on loss.
- Handle throttle confidence independently; preserve safe power during brief loss and offer keyboard takeover.
- Reset sequence validation after a new connection and display connection state without blocking gameplay.

The game keeps the packet values as raw physical movement for tutorial checks. `VisionClient.steering()` applies the saved pitch/bank/yaw sensitivities once and clamps each result to [-1, 1] before flight input. Sliders in main-menu Settings and Esc-menu Settings run from 0.25× to 3×; defaults are pitch 1.2×, bank 1× and yaw 1×. The Python tracker sends unit-gain input so gains are not compounded. Yaw is a separate swivel of the yoke face, measured from its normal, with an independent neutral anchor, jitter dead zone, median filter and time smoothing. It does not reuse the bank value. In paper mode full yaw input is reached at 25° from neutral; small movement stays inside a 4° entry / 2.5° exit neutral zone. Missing yaw fields default to zero, and malformed/nonfinite/out-of-range yaw rejects the whole packet.

## Tutorial neutral calibration

The separate local `/calibration` WebSocket accepts one JSON command per connection: `{"action":"start","request_id":"unique-session-token"}`. It shares the loopback-only binding, native-client origin restriction and 1 KB incoming limit. The tracker replies at camera rate with `request_id`, `state` (`waiting`, `holding`, `complete`, or `unavailable`), `elapsed` (0–3 seconds) and `reason` (`show_yoke` or `hold_still`). Closing the connection cancels an unfinished measurement; each new connection starts a fresh window. The game checks matching request tokens and results less than 150 ms old. A result from a prior Play/Retry cannot complete calibration.

The tracker measures **three consecutive seconds of raw yoke angles**, before dead zones, gain, clipping or smoothing. Loss, confidence ≤0.4, capture gaps ≥150 ms or movement over 4° from the initial pose reset the window. The median of the whole window establishes roll/pitch/yaw neutral (with angle wrapping). Paper mode replaces its neutral anchor; manually calibrated mode shifts its stored axis ranges in memory while preserving spans/signs. No calibration file is overwritten. Steering and gun fire are suppressed during capture; throttle remains independent. Completion clears old steering filter values. Tutorial progress requires both recent control data and a live camera picture; it then advances to the throttle checks. Back/Escape cancels capture, and Retry starts a fresh three-second window.

## Transport and timing

The service binds only to `127.0.0.1`, never a public interface. It accepts native WebSocket clients without an `Origin` header and rejects browser origins. Control and preview messages are output only; sending client data to those streams closes that connection. The `/` control stream contains JSON only. Each client has a one-frame queue so a slow receiver cannot accumulate stale controls. The target rate is 30 Hz (`--fps 24` or `25` is also supported); actual webcam speed depends on hardware and light.

The separate `/preview` WebSocket carries binary JPEGs, at most 10 FPS and 960×540, when a local viewer is connected. `/preview/throttle`, `/preview/yoke` and `/preview/weapons` select the appropriate full camera view for the tutorial; they use their assigned live camera and the same origin/read-only restrictions. With `--throttle-camera`, `/preview/throttle` comes exclusively from that second camera, while `/preview/yoke`, `/preview/weapons` and `/preview` use the primary camera. `/preview/all` shows both complete frames side by side for the ready screen (one full frame in single-camera mode). Preview labels identify the configured device. A secondary frame older than 150 ms is unavailable; its capture runs independently so a stalled phone cannot block yoke/weapon packets. Missing phone frames set throttle confidence to zero without falling back to primary-camera throttle tags. The receiver retains its last preview image across brief empty-frame gaps, clearing it 700 ms after the last valid JPEG; empty packets do not refresh that timestamp. Phone capture publishes frames and capture timestamps on its own thread so busy marker processing cannot delay freshness updates. No control packets are changed. Empty binary frames mean no camera image. The game subscribes only during the tutorial or yoke recovery, discards queued old frames, clears images after 700 ms without a fresh frame, and disconnects/clears its texture on exit. All previews use fixed full-frame pixels, mirrored horizontally for display, with readable labels added afterwards. Marker motion or visibility never crops, zooms or recentres the image. The two-camera ready view mirrors each camera independently, preserving camera ownership and column order. Control detection and signs are unchanged. Camera frames stay in memory on this computer; nothing is saved or uploaded. Tutorial checks also require fresh control packets (under 150 ms old); render frames do not count as new observations.

Use a local monotonic timeout of roughly 350 ms to detect a stopped service. `timestamp` uses wall clock for logging; system clock changes must not override timeout logic. Discard duplicate or older sequence numbers within a connection. Reset the sequence guard on reconnection, since the service may have restarted. Packets are normally under 300 bytes; receivers can cap messages at 2 KB.

Weapons use a shorter **150 ms** receive timeout and clear immediately on disconnect or disabling camera controls. The optional `weapons` object preserves version-1 compatibility: absent means the gun trigger is false; if present it must contain a boolean `gun` field. Invalid packets cannot refresh the timeout or change any controls. Firing uses the game's normal cooldowns and requires active, unpaused, airborne combat. Keyboard/mouse firing remains available.

## Loss and ownership

The tracker smooths valid input with a 0.10 s exponential time constant, uses a 6% yoke dead zone, and limits yoke changes to 3.5 units/second and throttle changes to 1.5 units/second. Values are bounded before serialization. Low confidence (<0.25), invalid numbers, duplicated marker IDs, and detection failure count as loss.

Yoke loss sets confidence to zero immediately, holds its last target for 250 ms, then eases toward roll/pitch/yaw zero. Throttle loss sets its confidence to zero immediately and holds the last smoothed power setting. It does **not** cut power during a camera interruption. At first startup all outputs are zero. During calibration, confidence is zero for both controls and the same loss policies apply.

The game pauses flight/rollout physics, combat, shooting and mission clocks whenever camera yoke control is selected and yoke confidence is unavailable (including socket timeout). It keeps the paused flight visible behind a translucent recovery prompt and a small mirrored camera inset and resumes the same flight after 0.5 seconds of continuous usable tracking. Manual pause/menus remain independent. `yoke_enabled: false` preserves throttle-only play; missing throttle never causes the yoke pause. The recovery screen's keyboard button explicitly releases camera control.

Game throttle follows a valid target with a 0.25 s exponential response, capped at 0.8 units/second with at most a 50 ms integration step. Invalid/missing throttle freezes the current game power. Reacquisition starts from that held power, not an unseen target; neither loss nor a pause snaps power to the returned slider position.

Weapon tags are checked separately on the unannotated camera frame. Dictionary correction is enabled (`errorCorrectionRate=1.0`, border error rate `0.35`); the shortest side must span about 24 pixels, counting pixel centres. The rectified black square is scored as a whole, excluding colour-transition pixels and ignoring the outer paper margin. Up to 18% mismatched checked pixels are tolerated, with at least 35 grayscale levels of contrast. This deliberately ignores small overlaps, scuffs and camera noise; the mismatch percentage measures image agreement, not a calibrated fraction of physical hand coverage. An unreadable ID or substantial pattern mismatch releases the trigger. Each trigger requires at least three consecutive valid frames spanning 80 ms. Any failed observation immediately sends false, with no smoothing or hold. A frame gap over 150 ms restarts the clear-frame requirement. Camera read failures, five-step calibration and simulation send the gun trigger false. Tag detection remains independent, but the game blocks all firing during yoke recovery and for 0.3 seconds after resuming.

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
