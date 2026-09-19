# Current delivery status

The user asked to continue without phase checkpoints. The original phase-by-phase pause requirement is superseded.

## Delivered in version 0.1

- Native Mac client and runnable application bundle.
- Five-aircraft hangar with downloaded models.
- Keyboard/mouse flight, cockpit/chase views, instruments, audio, pause/reset/help/credits.
- Takeoff, five checkpoints, final approach, landing and results.
- Optional training copilot and spectator explanation panel.
- Optional two-marker vision tracker, calibration, local client connection, validation and recovery tests.
- Cardboard construction instructions, print assets, setup and troubleshooting documentation.
- Local source folder and private GitHub repository.

## Next physical verification

Print the markers, assemble the controls, position the camera, and perform a real calibration and flight. Synthetic tests and simulated packets cannot establish physical tracking stability. Record the actual camera frame rate and control latency, then tune sensitivity based on the props.

## Future realism work

Aircraft-specific cockpit interiors and animations, more sophisticated flight dynamics, weather/time-of-day controls, richer terrain and airport collision, authentic engine audio, joystick support and public distribution signing/notarization.

See [verification.md](verification.md) for the exact checks already passed and remaining limitations. The earlier [Phase 0 report](phase-0.md) is retained as historical setup context.
