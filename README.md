# Goose Protocol — SPECTRE X-26

Version **0.12.0**: one San Francisco map, one fighter, two latched weapon switches, and a giant goose boss. A complete demo lasts **at most 150 seconds**. The game has unlimited ammunition and forgiving flight assistance.

Open **Launch Cardboard Cockpit.command** or **build/Cardboard Cockpit.app**. **Play / Enter** guides takeoff and the SF route while you shoot. Tap **Space** to switch the minigun on; tap **T** to switch repeated four-missile salvos on. Tap either again to stop. **Watch demo** flies and shoots automatically. Keyboard steering takes over from route assistance; **H** rejoins it. **R** immediately replays.

**Play teaches you during the mission:** spoken tips guide the first three geese, then the instructor hands the rest to you. Flight never pauses for lessons. Crashes recover to stable flight; landing mishaps retry final approach. [Coaching and voice details](docs/TUTORIAL.md).

## Controls

| Input | Action |
|---|---|
| Arrows / A D | Pitch and bank / rudder; release toward level |
| W / S / hold Shift | Accelerate / airbrake / afterburner |
| Space or left mouse | Toggle continuous minigun |
| T or right mouse | Toggle repeated four-missile salvos |
| Q | Fast recoverable barrel roll |
| V / X | Cockpit or chase / missile camera inset |
| Alt + mouse / middle drag | Look around |
| G / F | Gear / flap detent |
| B / J / H | Mouse yoke / aim assistance / route assistance |
| Hold E / Z | Eject / optional flares |
| C / F1 | Cardboard setup / controls |
| Escape / R / M | Pause / replay / mute |
| F8 / F9 / F10 | Hide text / telemetry / graphics quality |

The opening leads from SFO into the city; encounters escalate before an anomalous signature reveals the boss. Destroy it for several seconds of free-flight aftermath, then land at SFO. Badge B, keyboard L or the LAND AT SFO button deploys gear/flaps and starts assisted final approach, touchdown and braking. The ending also starts this automatically after its prompt. A brief transition skips the long return trip, preserving the 150-second limit. Escaping bosses remain an incomplete intercept even after a safe landing. Replays vary encounter motifs. Normal geese have 900 HP, elites 2,400, and the boss 16,000 with staged weak regions. The geese do not fire back.

Aim near a visible contact. Intent scoring, prediction, hysteresis and smoothly varying assistance make tracking forgiving without turning the aircraft automatically in manual flight. Missiles guide only toward their original selected target; free shots remain free shots. Four hardpoints launch with staggered separation and divergent paths. Hit reactions, physical smoke, spectral world cues, audio and local light reinforce real impacts.

## Cardboard and badge

The **cardboard yoke** owns steering and both latched weapon switches. The **cardboard throttle** owns power, boost and braking. The **wireless badge** supplies occasional secondary controls: START start/replay, HOME pause, A gear, B assisted landing, LEFT view, RIGHT missile inset, UP route assist, DOWN short press text visibility / hold tactical view. See [switch construction, mapping and evidence](docs/WEAPON_SWITCHES.md) and [printable switch faces](vision/markers/weapon-switches.html).

Use [vision setup](docs/vision-setup.md) and [construction guide](docs/cardboard-build-guide.md) for yoke ID 7 and throttle IDs 0 (idle), 1 (slider), and 2 (full). Flip-tab faces use 31/32 and 41/42 in the same `DICT_4X4_50` dictionary.

For the **laptop yoke + phone throttle**, connect the phone through Apple Continuity Camera (or a webcam app) and open **Launch Two-Camera Cockpit.command**. This launches the current source game with two labeled camera previews. Hold yoke 7 steady to center; SPACE in the Python window recenters it. All three throttle tags must stay visible to the phone. The slider takes over automatic power as soon as it is tracked.

```sh
./tools/dual_camera_tracker.sh --list-cameras
# Automatic laptop / iPhone selection; source game and both trackers:
./"Launch Two-Camera Cockpit.command"
# Other webcam apps or an explicit choice (use indices from the list):
./"Launch Two-Camera Cockpit.command" --yoke-camera 1 --throttle-camera 0
```

Each camera has its own tracker and preview connection. Phone loss holds power while laptop steering continues. W/S takes over power and disables tracking; C opens setup to enable it again. To play the ordinary mission with two cameras, run `./tools/dual_camera_tracker.sh` and, separately, `./tools/run.sh -- --dual-cameras --stickers`. The packaged app must be rebuilt to include these source changes.

Controls and preview images stay on localhost; no camera images are saved or uploaded. Automated marker, role-isolation, preview, dropout/reconnect and game integration tests cover the input path. Physical tag placement still determines tracking quality. The release app includes an offline BLE helper and reconnects to the existing badge firmware automatically. All eight physical badge buttons and simultaneous A+B were measured live. Phase feedback was written and read back. The badge now runs the verified live-instrument firmware; see [display, protocol and wireless handoff](hardware/badge-controller/INSTRUMENT.md).

## World, audio and performance

The sourced SF region includes SFO, downtown, residential streets, hills, Golden Gate Bridge, Bay Bridge and Alcatraz. The playable menu exposes one map. Historical coastal/alpine fixtures remain in source for regression testing. [SF coverage and source licenses](docs/san-francisco.md).

Forward+ rendering retains streamed native meshes, LODs and filtered foliage. Local fog, selective glow, reflective missiles and bounded pools of sprites, projectile meshes, lights and spatial sounds support combat. High and Balanced modes retain independent HUD resolution. The physical terrain guard and soft protection around compact tall landmarks keep low flight forgiving; SF buildings do not use solid mesh collision.

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
