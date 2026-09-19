# In-mission coaching — 0.12.0

Choose **Play** normally. The instructor teaches the actual cardboard yoke/throttle and weapon switches while you fly and clear the first three geese. There are no separate training screens, paused lessons or Continue buttons. On the third kill, the instructor says you are ready and leaves you to defeat the boss and land. The same run, score, weapon state and route assistance continue.

Coaching explains yoke rotation/tilt, throttle acceleration/braking, primary switch 1 (Space), missile switch 2 (T), aiming and badge controls. Landing guidance explains badge B / keyboard L, gear, flaps and automatic braking. Headphone/speaker output follows the Mac's selected audio device. Pause and mute also affect narration. Captions remain readable.

The initial instructor uses local OS English speech, preferring Daniel, with music ducking and a captions-only fallback. This is synthesized speech, not a studio recording. No microphone, recording or cloud voice service is used. Native start/pause/resume/stop was verified; physical headphone routing was not independently tested.

## Forgiving flight

In SF, a crash resets the plane to level flight with safe terrain clearance and route assistance. Score, cleared geese and mission progress are preserved. A landing collision or runway excursion retries a stable final approach. Automatic landing brakes remain active even if route assistance is toggled. Normal runs still finish within 150 seconds; recovery retries can extend a run.

## Accurate results

The full mission succeeds only when the boss is defeated and the aircraft lands and stops. Landing safely without defeating the boss explicitly acknowledges the safe landing and reports the missing objective. Completing three introductory geese is not itself mission completion. The screen, advice and radio share one assessment. Crash recovery does not produce a mission-failed screen.
