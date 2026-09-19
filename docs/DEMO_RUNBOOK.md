# SPECTRE demo runbook

1. Open the native app. On the flight deck, choose **Guided flight** for a hands-free combat demonstration, or **Launch sortie** for manual control.
2. Show the single SPECTRE airframe and permanent cannon/missile loadout. There are no upgrade screens.
3. For manual flight, make small arrow-key corrections. W/S controls power; Shift engages afterburner. Follow the lead diamond for cannon shots, and wait for the green lock before pressing T.
4. Press V for cockpit/chase. Hold X after launching a missile to show its datalink view. Watch the primary flight view throughout.
5. Red directional warnings indicate incoming missiles. Z deploys a limited countermeasure burst; maneuver and use acceleration as well.
6. Escape pauses. The pause panel contains sound and quality settings. Returning to the flight deck allows landing practice or cardboard setup.
7. For landing practice, H can demonstrate approach and rollout. Manual landing requires gentle descent, wings near level and Space to brake after touchdown.

Keyboard controls immediately take over from the guided pilot. A guided sortie can take damage and lose; it does not use an invulnerability mode. R restarts the current mode. If performance is poor, F10 selects Balanced fidelity.

For cardboard demonstration, start `tools/tracker.sh --camera 0 --calibrate` and complete the seven poses before enabling tracking in the C panel. Synthetic mode is available for connection demonstrations. Do not describe synthetic validation as a successful physical-prop test.
