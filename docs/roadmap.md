# Delivery phases

The supplied brief requires a user checkpoint at the end of each phase. Its browser-only stack is superseded by the latest native-client request.

## Phase 0 — setup and choices

Deliver the environment report, folder, GitHub repository, architecture, aircraft-source research, and implementation plan. No playable code is expected in this phase.

## Phase 1 — native hangar and first flight

- Install a project-scoped prebuilt Godot editor and the matching export templates.
- Build the attract screen, aircraft hangar, selection flow, world, runway, cockpit/chase cameras, and basic instruments.
- Import the five requested aircraft from approved web sources; record attribution and flag any unavailable model explicitly.
- Implement keyboard and mouse input, aircraft profiles, basic flight, pause, reset, mute, and settings.
- Export a runnable Mac `.app` and provide a convenient local launch path.

Verification: open the native client; select each available aircraft; start, steer, throttle, pitch, bank, change view, pause and reset; inspect real screenshots; measure performance on this Mac. Clearly report any model substitutions or missing downloads.

Checkpoint: Does the native hangar, cockpit, and flight feel match the direction?

## Phase 2 — complete keyboard mission

- Tune acceleration, lift, drag, takeoff, stalls, assistance, ground contact, gear, and landing.
- Add five checkpoints, route guidance, approach, touchdown and crash/recovery states, audio feedback, and results.
- Add flight time, rings, smoothness, landing quality and rank; support Fly again and Next pilot.

Verification: complete the entire mission using keyboard/mouse; verify ring order and non-duplicate scoring, pause behavior, restart state, recoverable failure and valid/invalid touchdowns. Test heavy-airliner route clearance as well as fighter handling.

Checkpoint: Should final mission tuning emphasize an arcade challenge, scenic flight, or a demanding landing?

## Phase 3 — standalone vision tracker

- Create an isolated Python environment with pinned compatible dependencies.
- Implement two-marker ArUco tracking, smoothing, confidence, debug overlay, loss handling, WebSocket output, and calibration storage.
- Provide printed markers and a synthetic test mode for testing without a webcam.

Verification: unit-check range normalization and loss behavior; validate synthetic packets; then physically detect two printed markers and demonstrate stable values with an actual webcam. Synthetic tests do not count as physical validation.

Checkpoint: Will the webcam face the controls from the front or look down from above the monitor?

## Phase 4 — live cardboard control

- Connect the native client to the tracker and complete the in-game calibration flow.
- Add sensitivity, dead zones, confidence display, independent yoke/throttle health, and safe keyboard takeover.

Verification: live controls visibly move the aircraft; disconnect the tracker and cover each marker separately; ensure safe transitions and continuous keyboard play; have a new pilot calibrate without developer help.

Checkpoint: Are roll, pitch, and throttle intuitive with the actual cardboard props?

## Phase 5 — physical cockpit guide

Create a one-page build guide with dimensions, yoke and throttle cuts, carriage construction, marker placement, stabilization, camera layout, setup, and the auxiliary keyboard panel.

Verification: compare the printed marker size and mounting orientation against the calibrated tracker; check that hands do not obscure markers through the operating range.

Checkpoint: Should the physical cockpit look homemade, fighter-inspired, or retro aviation-inspired?

## Phase 6 — showcase and delivery

Finish attract mode, spectator panel/window, readable instructions, robust error recovery, packaging, README, pitch script, troubleshooting and credits.

Verification: perform a full keyboard flight and a full live-cardboard flight, repeatedly reset between pilots, check disconnected-camera startup, inspect every presentation screen, and confirm the packaged app launches outside the editor.

Checkpoint: Optimize the showcase for one judge at a time or a crowd watching a large monitor?

## Completion definition

The final product is complete only when both a full keyboard mission and real webcam/cardboard operation are demonstrated, calibration works without developer assistance, the native build is runnable, and the build/setup/recovery documentation and presentation are ready. Until then, report the completed milestone and remaining physical or software verification explicitly.
