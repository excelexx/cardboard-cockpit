> Historical planning / release notes. Current gameplay and controls are documented in [README](../README.md) and [SPECTRE runbook](DEMO_RUNBOOK.md).

# Demo and recovery

## Thirty-second introduction

“Remember pretending a cardboard box was a plane? This project turns that idea into a flight simulator. Choose one of five aircraft, take off, follow the rings through the valley, and land at the next airport. The desktop client already works with keyboard and mouse. The optional camera tracker watches two printed markers on a cardboard yoke and throttle, then sends their movement into the same flight controls.”

For the current prototype, show keyboard controls first. Only say “the cardboard controls are driving this flight” after real marker tracking is connected and visibly controlling the aircraft.

## Fast pilot handoff

1. Press R to reset, or choose Next pilot after landing.
2. Explain W for throttle and the arrows for pitch and bank. The HUD shows rotation speed.
3. Offer H for a training copilot if the visitor wants a scenic demonstration.
4. Use V for chase view when showing the aircraft to a crowd. Tab shows the cardboard explanation.
5. Keep the tracker preview small and secondary when physical tracking is connected.

## Recovery

| Problem | Recovery |
| --- | --- |
| Aircraft gets lost or crashes | R restarts from the runway with idle power and gear down. |
| Need to stop immediately | Escape pauses. Choose Resume or return to hangar. |
| Unexpected camera movement | Release right mouse; press B if mouse yoke was enabled. |
| Camera tracker fails | Any arrow, A/D or W/S takes over on keyboard; restart tracker separately. |
| Low frame rate | Q selects Balanced quality; close other graphics-heavy apps. |
| No sound | M toggles mute. Check Mac output volume. |
| App does not start | Run `./tools/run.sh` to see diagnostics, or rebuild with `./tools/package_mac.sh`. |
| New downloaded copy is blocked by macOS | This local build is not notarized; use normal macOS app verification/opening controls or build from source. No security settings need to be disabled. |

The simulator preserves aircraft selection, graphics quality and mute setting locally. Calibration belongs to the optional tracker and persists in its local calibration JSON.
