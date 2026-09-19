# Guided tutorial — 0.12.0

Choose **Tutorial** on the flight deck. It is a separate, self-paced training run: the aircraft waits during briefings, and flight assistance supports the weapon exercises. Continue with the on-screen button, Enter or START on the badge. Weapon exercises cannot be skipped by pressing Continue.

The instructor covers:

1. Mission objective: defeat the geese and boss, then land safely at SFO.
2. Cardboard yoke: rotate to bank; tilt toward you to climb and forward to descend. C opens camera setup; arrow keys remain available when props are not calibrated.
3. Cardboard throttle: FULL accelerates, the top end boosts, IDLE slows and brakes. W/S/Shift are alternatives.
4. Primary switch: one latched switch runs minigun and beam together; Space is the keyboard alternative. The player must fire it.
5. Missile switch: one latched switch repeats four-missile salvos; T is the keyboard alternative. The player must launch a salvo.
6. Targeting: bring a goose into the aim ring and destroy at least one. The full mission additionally requires its boss.
7. Wireless badge: START start/resume/continue training; HOME pause; A gear; B assisted landing; LEFT view; RIGHT missile inset; UP route assistance; DOWN HUD text.
8. Landing: badge B, keyboard L or Land deploys gear/full flaps, safes weapons and starts assisted SFO final.
9. Touchdown and braking: training succeeds only after the exercises and a landed, fully stopped aircraft.

**Repeat voice** repeats the current instruction. **Exit tutorial** returns to the flight deck. R restarts training. Pause, focus loss and setup/help overlays pause narration; M mutes it along with the game. Captions remain available, including when HUD text is hidden. The instructor takes priority over routine radio and lowers the game mix while speaking.

## Voice and headphones

The initial implementation uses Godot's operating-system text-to-speech, preferring the installed English Daniel voice and falling back to another installed English voice. It uses calm instructor wording and a measured delivery rate. This is local synthesized speech, not a commissioned or studio-recorded voice. The lesson script is separated in `simulator/systems/tutorial.gd` so a later production voice can replace it without changing the exercise flow.

Audio follows the Mac's selected output, including wired or Bluetooth headphones. The app does not pair headphones, change macOS output settings, use a microphone, record sound or send lesson text to a cloud voice service. If no English voice is available, the tutorial clearly reports captions-only operation. Headphone hardware routing has not been independently tested.

## Honest outcomes

`sortie_result.gd` supplies one result for the headline, explanation, retry advice, score eligibility and radio. A safe landing without defeating the boss is **OBJECTIVE INCOMPLETE**, with the safe landing acknowledged. Defeating the boss without completing recovery is **LANDING INCOMPLETE**. Both objectives together produce **MISSION COMPLETE**. Crash, runway excursion, ejection and sector exit have their own explanations. Tutorial success is **TRAINING COMPLETE**, and does not require the full mission's boss or update the player's combat record.

Tests cover the complete tutorial through real weapon damage and landing, gated progress, restart/exit, and the result cases above. Physical cardboard calibration remains a separate on-prop step.
