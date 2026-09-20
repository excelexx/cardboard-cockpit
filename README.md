# Goose Protocol — SPECTRE X-26

Version **0.18.0** combines the current San Francisco visuals and gameplay with the team’s two-camera controls, settings and pause screens, plus a separate badge-guided **Tutorial**. Normal Play retains the current flock encounter and assisted SFO landing. Tutorial takes off, clears sixteen targets and follows a longer route to land. Both have unlimited ammunition and forgiving flight assistance.

Open **Launch Cardboard Cockpit.command** or the packaged **Cardboard Cockpit.app**. Both flight modes use excelex's cardboard controls and settings, with the current graphics and aircraft presentation. **Watch demo** flies and shoots automatically.

## Controls

**Play** and **Tutorial** both begin with excelex's cardboard calibration and control checks. Choose **Use keyboard** in setup to fly without cameras. Play keeps the current SF flock route; Tutorial keeps the sixteen-target takeoff/combat/landing route.

| Input | Action |
|---|---|
| Printed gun tag ID 4 visible / covered | Fire adaptive dual plasma / stop both beams |
| Hold Space or left mouse / release | Fire adaptive dual plasma / stop both beams |
| Large-flock support | Missiles launch automatically, four every second |
| Yoke rotation, tilt, swivel | Bank, pitch, yaw |
| Relative throttle tags 0 / 1 / 2 | Idle endpoint / moving handle / full endpoint |
| Arrows / A D | Pitch and bank / rudder |
| W / S / Shift | Keyboard power / brake / afterburner |
| Q / V | Barrel roll / cockpit or chase view |
| G / F / L | Gear / flaps / landing assistance |
| H / hold E / Z | Route assist / eject / cosmetic flares |
| C / Escape / R / M | Cardboard setup / pause / replay / mute |

Two plasma beams are the manual weapon. They split across two targets or focus together on one, with **SPLIT**, **FOCUS** or **FIRING** shown on the HUD. Automatic missile support fires four missiles together at up to one burst per second during large flocks, when four eligible targets are available. [Adaptive plasma controls and feedback](docs/ADAPTIVE_PLASMA.md).

Normal SF Play has a **twelve-goose wave**, a brief clear beat, then **twenty more**. The objective counts all 32 actual kills and the two waves separately. Tutorial still has sixteen route targets. Yoke loss pauses the flight; a steady return resumes it. Sound starts enabled each launch; **M** mutes the current session. The steady camera keeps recoil and chase movement subdued for comfort.

## Cardboard and badge

Open **Launch Two-Camera Cockpit.command** (or **Launch Cardboard Tracker.command**) with the phone connected. The laptop tracks yoke ID 7 and gun ID 4; the phone tracks the relative throttle's IDs 0/1/2. Setup checks calibration, throttle idle/full/idle, yoke instructions, and gun show/cover/show before starting. [Vision setup and print masters](docs/vision-setup.md).

Settings retains separate pitch, bank and yaw sensitivity and agility, plus aim assistance. excelex defaults are restored: agility **1.30×** per axis and aim assistance **1.40×**; saved pilot preferences remain intact until Reset defaults is selected. Sensitivity changes apply live to the tracker, with no double gain.

The electronic badge remains a secondary instrument: START start/replay, HOME pause/back, A gear, B landing assistance, LEFT cockpit/chase, RIGHT tactical view, UP route assist, short DOWN text visibility / held DOWN tactical view. It never fires or steers the aircraft. The packaged app includes its Bluetooth helper. [Badge instrument and wireless handoff](hardware/badge-controller/INSTRUMENT.md).

## World, audio and performance

The sourced SF region includes SFO, downtown, residential streets, hills, Golden Gate Bridge, Bay Bridge and Alcatraz. The playable menu exposes one map. Historical coastal/alpine fixtures remain in source for regression testing. [SF coverage and source licenses](docs/san-francisco.md).

Forward+ rendering retains streamed native meshes, LODs and filtered foliage. Local fog, selective glow, twin plasma beams and bounded pools of sprites, projectile meshes, lights and spatial sounds support combat. High and Balanced modes retain independent HUD resolution. The physical terrain guard and soft protection around compact tall landmarks keep low flight forgiving; SF buildings do not use solid mesh collision.

Radio uses licensed human voices processed with military-style band-pass filtering, compression, saturation, RF hiss and push-to-talk squelch. Ground-base and pilot cues have priority, expiry, subtitles and music ducking. The music track adjusts with encounter intensity without restarting. These are processed Kenney recordings, not generated voice clones.

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
