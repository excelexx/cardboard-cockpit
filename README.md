# Goose Protocol — SPECTRE X-26

Version **0.22.12** is one continuous San Francisco judge demo: take off, fly, shoot adaptive dual plasma and keep clearing new flocks for as long as you like. The HUD keeps the aiming area clear. Press **B** or **badge B** when you want to land, then fly the approach yourself.

Open **Launch Cardboard Cockpit.command** or the packaged **Cardboard Cockpit.app**. The demo uses excelex's cardboard controls and settings with the current graphics and aircraft presentation. **Watch demo** flies and shoots automatically. [Judge demo flow](docs/JUDGE_DEMO.md).

## Controls

Choose **Play / Enter / badge Start** for calibration only, or **Set Up Cardboard** for the full control tutorial. **Use keyboard** bypasses camera setup. Older Tutorial entry points open the same demo. Both live setup previews are equally large and preserve the complete camera image without cropping.

| Input | Action |
|---|---|
| Printed gun tag ID 4 visible / covered | Fire adaptive dual plasma / stop both beams |
| Hold Space or left mouse / release | Fire adaptive dual plasma / stop both beams |
| Large-flock support | Missiles launch automatically, two every five seconds |
| Yoke rotation, tilt, swivel | Bank, pitch, yaw |
| Relative throttle tags 0 / 1 / 2 | Idle endpoint / moving handle / full endpoint |
| Arrows / comma and period | Pitch and bank / rudder |
| W / S / Shift | Keyboard power / brake / afterburner |
| Q / V | Barrel roll / cockpit or chase view |
| Badge A / keyboard A or G | Gear and flaps together: retract after takeoff, deploy for landing |
| F | Flaps only |
| B / badge B | Enter landing mode / restart approach; retain manual control |
| H / hold E / Z | Route assist / eject / cosmetic flares |
| C / Escape / R / M | Cardboard setup / pause / replay / mute |

Two plasma beams are the manual weapon. They split across two targets or focus together on one, with **SPLIT**, **FOCUS** or **FIRING** shown on the HUD. Automatic missile support fires two missiles together every five seconds during large flocks, when two eligible targets are available. [Adaptive plasma controls and feedback](docs/ADAPTIVE_PLASMA.md).

Groups of **1–4 geese arrive every 600–1,500 metres of flight path**, with loose offsets and stable plasma target locks. Flocks continue with a compact **WAVE N · kills/total** readout, without a progress bar. The flight timer appears only during landing. There is no countdown or fixed kill quota before landing. Only actual kills count. Yoke loss pauses the flight; a steady return resumes it. Sound starts enabled each launch; **M** mutes the current session. **Settings → Audio** has independent Free Bird, engine/wind, effects and voice sliders. Defaults are music **200%**, other channels **50%**, and changes save automatically. The steady camera keeps recoil and chase movement subdued for comfort.

After takeoff, **A / G** retracts gear and flaps. **B** starts or retries the manual landing approach. Touchdowns on dry airport ground are accepted; water or off-airport contact starts an automatic flight back to the runway.

## Cardboard and badge

Open **Launch Two-Camera Cockpit.command** (or **Launch Cardboard Tracker.command**) with the phone connected. The laptop tracks yoke ID 7 and gun ID 4; the phone tracks the relative throttle's IDs 0/1/2. The full setup checks calibration, throttle idle/full/idle, yoke instructions, gun uncover/cover, and badge A/B practice. Quick Start only calibrates the yoke before the live-camera/idle check. [Vision setup and print masters](docs/vision-setup.md).

Settings retains separate pitch, bank and yaw sensitivity and agility, plus aim assistance. excelex defaults are restored: agility **1.30×** per axis and aim assistance **1.40×**; saved pilot preferences remain intact until Reset defaults is selected. Sensitivity changes apply live to the tracker, with no double gain.

The electronic badge remains a secondary instrument: START start/replay, HOME pause/back, A gear + flaps, B manual landing mode, LEFT cockpit/chase, RIGHT tactical view, UP route assist, short DOWN text visibility / held DOWN tactical view. It never fires or steers the aircraft. The packaged app includes its Bluetooth helper. [Badge instrument and wireless handoff](hardware/badge-controller/INSTRUMENT.md).

## World, audio and performance

The sourced SF region includes SFO, downtown, residential streets, hills, Golden Gate Bridge, Bay Bridge and Alcatraz. The playable menu exposes one map. Historical coastal/alpine fixtures remain in source for regression testing. [SF coverage and source licenses](docs/san-francisco.md).

Forward+ rendering retains streamed native meshes, LODs and filtered foliage. Local fog, selective glow, twin plasma beams and bounded pools of sprites, projectile meshes, lights and spatial sounds support combat. High and Balanced modes retain independent HUD resolution. The physical terrain guard and soft protection around compact tall landmarks keep low flight forgiving; SF buildings do not use solid mesh collision.

Radio uses licensed human voices processed with military-style band-pass filtering, compression, saturation, RF hiss and push-to-talk squelch. Ground-base and pilot cues have priority, expiry, subtitles and music ducking. The supplied Free Bird solo cues at each runway start, beginning at source 0:12 with a five-second fade. The bundled cut is 15 minutes and continues through landing until the main menu. These are processed Kenney recordings, not generated voice clones.

## Develop and verify

Godot **4.7.2**, Forward+ / Metal. Game exports are universal; the bundled badge helper is built for the build host (this release: Apple Silicon). Rebuild it on Intel if required.

```sh
./tools/setup.sh
./tools/run.sh
./tools/verify.sh
./tools/build_badge_helper.sh
./tools/package_mac.sh
```

Packaging produces **build/Cardboard Cockpit.app** and **build/Cardboard Cockpit Mac.zip**, including complete source and notices. The app is locally signed and not Apple-notarized. [Demo runbook](docs/DEMO_RUNBOOK.md) · [verification](docs/verification.md) · [implementation ledger](docs/SPRINT_SCOPE.md) · [asset credits](THIRD_PARTY_ASSETS.md).

The licensed FlightGear airframe source, sourced Google goose and original editable M-26 missile remain included. This is an arcade demo, with game-tuned flight and exaggerated combat readability.
