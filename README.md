# Goose Protocol — SPECTRE X-26

Version 0.10.1 is a relaxed native Mac arcade flight game: **one SPECTRE fighter, unlimited Gatling fire, and large Waterloo geese to intercept over San Francisco Bay**. The geese do not attack. There are no upgrades, reloads, heat limits or steady-lock requirements.

**Five-minute flight demo:** start stationary on the runway, take off through gold rings, climb to cruising altitude and shoot sixteen spaced goose targets, then follow a gentle bend to a landing airfield roughly 27 km ahead. Prompts walk through reducing throttle, lowering gear and selecting landing flaps. The aircraft brakes automatically after touchdown. [Demo runbook](docs/DEMO_RUNBOOK.md).

Open **Launch Cardboard Cockpit.command** or run `tools/run.sh`. The game opens its main menu. **Play** (or Enter) begins a three-second neutral calibration and sequential camera checks: throttle 0% → 100% → 0%, a four-second yoke overview with no required movements, then the gun grip and cover/uncover test. A fixed mirrored camera view fills the screen, with central instructions and movement arrows. After the checks, centre the yoke, set idle and cover the gun tag; flight starts automatically after one steady second. Run the Python tracker first. **Keyboard / mouse** skips camera checks; hold **Space** or **left mouse** to fire. **Watch demo** runs the sortie automatically.

![SPECTRE in the valley](docs/screenshots/combat-09-overview.png)

## Fly

| Input | Action |
| --- | --- |
| Arrow keys | Smooth bank / pitch; release to level |
| A / D | Rudder; steer during rollout |
| W / S | Fast acceleration / airbrake |
| Hold Shift | Afterburner |
| Hold Space / left mouse | Unlimited Gatling fire; Space brakes on the ground |
| Z | Optional flare effects |
| Q | Quick barrel roll, when altitude permits |
| V | Cockpit / chase camera |
| Alt + mouse / middle drag | Look around |
| G / F | Gear / flap detent |
| B / J | Mouse yoke / close-range aim assistance |
| H | Route flight assistance on/off |
| Hold E | Eject |
| C / F1 | Cardboard setup / controls |
| Escape / R / M | Pause / restart / mute |
| F9 / F10 | Telemetry / graphics quality |

Bring a goose inside the small six-degree acquisition ring. The crosshair smoothly tracks it, a brief amber acquisition turns green, and the HUD shows track ID, range and gun aim assistance. A 7.5-degree retention margin tolerates small drift. A separate small lead diamond shows the gun solution. In the short demo, sixteen geese appear at successive positions along the higher cruising section, 500 metres apart across 7.5 km, with varied heights and left/right offsets. They stay available until cleared; landing preparation begins after all sixteen are cleared and the cruise gates are completed. Slower shooters get more cruising room ahead. Markers, projectiles, trails and impact effects keep the action readable. Clears within five seconds build a streak and increase points. Personal best scores are saved for player-controlled shooting runs; Watch demo does not set your record.

Hold W for immediate acceleration and S for a strong airbrake, with a forgiving 80 m/s minimum while airborne with gear up. The HUD shows ACCEL, AIRBRAKE and CRUISE. Keyboard steering or power input takes over from route assistance. The manual controller maps inputs to a controlled bank or pitch angle; releasing settles the aircraft toward level flight. A gentle terrain guard pulls up through the physics model when needed. H rejoins the guided route. Switching applications pauses flight, and help/setup overlays freeze the simulation.

Landing practice starts on final with gear and flaps selected. With neutral pitch input, landing assistance follows the descent and flare; neutral power input uses approach-speed assistance. After touchdown, Space brakes and A/D steers. The complete assisted sortie lands and brakes automatically. Touchdown preserves position and attitude and settles through a physical rollout.

## Scenery and presentation

Festyve’s `graphics/coastal-overhaul` is integrated: offline Helsinki photogrammetry, 128 base tiles with 256 detailed refinements, 60 Kominka countryside homes, a maritime air station, grounded airports, shoreline scenery and an eleven-landmark coastal tour. The cockpit improvements and instrument batching are retained. The short demo uses gold and cyan rings for a short departure-to-landing route; our SPECTRE, permanent weapons, infinite ammunition and harmless geese are shared by both routes. The existing alpine environment remains selectable. [Coastal credits](simulator/assets/photogrammetry/CREDITS.md) · [Scenic route](docs/SCENIC_ROUTE.md).

The active balance uses developer-published Sky Rogue references with documented metric-scale and difficulty adaptations. [Balance values and provenance](docs/balance.md) distinguish source values from our calibration.

## Presentation and handling

SPECTRE refines a licensed FlightGear airframe with a graphite livery, reflective canopy, animated control surfaces and folding gear. The rotary cannon has an animated rotor, muzzle effects and unlimited ammunition.

Cannon rounds inherit aircraft velocity and include gravity, drag and swept collision checks. Visible tracers make the gunfire easy to follow.

The valley uses generated sunset-cloud, conifer, granite and explosion textures alongside the licensed environment sources. Tall varied forests, lake islands, wet shoreline boulders, reflective rippled water, cloud/mist volumes, shadows and ambient occlusion build depth. Wing vapor, wind streaks, trails, heat distortion and correctly positioned afterburner exhaust respond to flight. The sky and lighting follow the title artwork's warm/cool palette; this remains a real-time game environment rather than a reproduction of every detail in that generated still.

High quality is the default. F10 selects Balanced. Internal 3D resolution is budgeted to 1600 pixels wide in High and 1280 in Balanced, with spatial upscaling; the HUD stays at window resolution. This keeps large Retina windows responsive. High uses temporal antialiasing to reduce foliage shimmer.

Audio combines licensed engine, wind, weapon, impact, gear and tire sounds with cockpit ambience and music. Radio cues use filtering, priority/expiry, subtitles and ducking; these are Kenney recordings, not ElevenLabs generations. Escalating confirmation tones and streak feedback reinforce successful clears.

## Cardboard controls

Use [vision setup](docs/vision-setup.md) and the [construction guide](docs/cardboard-build-guide.md). Print the updated [marker sheet](vision/printable-cockpit.html) at **100% / actual size**. The yoke uses ID 7; the relative throttle uses **0 = fixed idle, 1 = moving slider, 2 = fixed full** (`DICT_4X4_50`). Legacy ID 23 PDFs do not match the new throttle.

```sh
./tools/setup_vision.sh
./tools/tracker.sh --list-cameras
./tools/tracker.sh --camera "MacBook Air Camera" --throttle-camera "iPhone (2) Camera" --paper-test
# In another terminal:
./tools/run.sh -- --stickers
```

This setup uses the phone for throttle tracking and its tutorial camera view, and the laptop webcam for the yoke and shooting tags. Select the camera names returned by `--list-cameras`; the final ready screen shows both. The fixed markers define the travel range each frame, including a roughly 10 cm slider. Keep all three marker faces coplanar and visible. Arrow keys steer with throttle-only tracking; W/S takes over power. Use `--paper-test` on the Python tracker to add auto-centered yoke control. The separate game's paper-test flight accepts the physical throttle once visible. Manual yoke calibration has five poses; throttle needs no endpoint capture.

For shooting, mount **04 = gun** above the yoke: uncover to fire, cover to stop. Print the [gun tag](vision/printable-weapons.html) at actual size. Keep the middle finger on the green band, ring finger on the blue band, and lift/replace the right pointer finger over 04. Your left hand stays free for the throttle. No extra calibration is required. See [shooting setup](docs/vision-setup.md#shooting-tags).

Covered throttle tags hold the current power; showing them again blends smoothly to the new slider position. Losing yoke 7 pauses the game and shows a light warning and a small mirrored camera inset over the paused flight until it stays visible for half a second. Explicit `--throttle-only` mode keeps keyboard steering without requiring a yoke.

The service stays on `127.0.0.1`; the tutorial and recovery screens receive local previews, and images are not uploaded or recorded. The native game works without Python or a camera. Synthetic tracking and the local game connection are tested; real cardboard/webcam operation remains unverified.

## Develop and verify

The project pins Godot 4.7.2. Mac exports include Apple Silicon and Intel binaries; runtime verification is on Apple Silicon with Metal.

```sh
./tools/setup.sh
./tools/run.sh
./tools/verify.sh
./tools/package_mac.sh
```

Packaging creates `build/Cardboard Cockpit.app` and `build/Cardboard Cockpit Mac.zip`, including source and asset notices. The build is locally signed and is not Apple-notarized. See [verification](docs/verification.md), [demo runbook](docs/DEMO_RUNBOOK.md), and [asset credits](docs/demo-assets.md).

This remains a compact, game-tuned flight project. It does not provide certified aerodynamics, global scenery, a clickable avionics simulation or commercial AAA production assets. Terrain and major buildings collide; trees and small scenery are forgiving. Historical licensed aircraft files remain as source provenance and are excluded from the playable export. Large geese, generous aim assistance and unlimited weapons are intentional arcade choices.

## San Francisco world

The default map is now a complete sourced San Francisco regional tile with the city, SFO, Golden Gate Bridge, Bay Bridge, Alcatraz, terrain, roads and residential neighborhoods. The current short demo stays near SFO and reaches a landing airfield almost directly ahead in about 85 seconds with the guided pilot. The route selector also retains the two legacy maps. See [coverage, licenses and conversion details](docs/san-francisco.md).

The existing badge bridge and firmware remain in `hardware/`. Badge gear and flap buttons update the same flight state used by the landing prompts; its pause, view, assistance and flight-phase LEDs remain connected. The two-camera launcher now starts the combined tracker, with independent capture and preview for each camera.
