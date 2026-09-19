# Proposed control schema — version 1

Status: design only, to implement during the vision phases.

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
| `sequence` | Monotonically increasing integer per connection |
| `timestamp` | Unix milliseconds; useful for logging, not the sole timeout source |
| `tracking` | Summary flag; individual confidence still governs each control |
| `yoke.roll` | -1 left to +1 right |
| `yoke.pitch` | -1 nose-down to +1 nose-up |
| `yoke.confidence` | 0 lost to 1 confident |
| `throttle.value` | 0 idle to 1 full |
| `throttle.confidence` | 0 lost to 1 confident |

Receiver requirements:

- Validate shape, version, types, finite numbers, size, sequence and bounds before merging input.
- Use a local monotonic receive clock to detect stale packets.
- Keep keyboard and mouse providers independent of the connection.
- Support explicit keyboard takeover and never let a stale packet overwrite it.
- Smooth yoke changes and blend toward neutral after a short hold on loss.
- Handle throttle confidence independently; preserve safe power during brief loss and offer keyboard takeover.
- Reset sequence validation after a new connection and display connection state without blocking gameplay.

Calibration requests, responses and persistence formats will be defined when the tracker is implemented. Keyboard-only clients must not require this service.
