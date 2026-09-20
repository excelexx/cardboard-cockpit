# XLX behavior with current graphics — 0.16.0

Reference: excelex commit `64011f3`. User decisions: keep both normal SF Play and the sixteen-target Tutorial; gun ID 4 visible fires, covering it stops; gun only, with no missiles, plasma/laser or old two-switch weapon behavior. Keep the current visual presentation.

Both title actions enter the guided cardboard checks, with an explicit keyboard fallback. Both modes share the restored XLX receiver, PoseGuard detector, relative throttle, live sensitivity and per-axis agility, aim-strength defaults, held keyboard/mouse fire, yoke-loss freeze and steady-return recovery, and throttle reacquisition blending. Camera throttle alone does not force afterburner. The original modern gun/throttle print masters are restored.

Flight trajectories and common gameplay constants follow the reference. Current presentation-only attitude, Mach/readouts, gust pose, aircraft/world art, gun models, traces, lighting, audio and impact treatment remain. The separate SF encounter and route remain by the user's explicit two-mode choice. Tutorial targets use the XLX spaced route positions and slow forward motion. No active missile launcher, missile stores, missile camera, beam firing or beam audio remains. Badge RIGHT selects the tactical view, and game telemetry does not advertise missile readiness or projectile contacts.

Offline validation includes modern camera/marker tests, all settings sliders, visible/covered firing, held/released input, missing-yoke pause/resume, throttle smoothing, keyboard fallback, and complete sorties in both modes. Live cameras and physical badge demonstrations require separate coordination; this integration does not flash firmware.
