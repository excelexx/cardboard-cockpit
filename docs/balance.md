# SPECTRE 0.9 balance profile

The active gameplay values live in `simulator/data/balance.gd`. The reference is **Sky Rogue**, an arcade jet combat game. These are documented reference values plus explicit adaptations for SPECTRE; they are not claimed to be an optimal or scientifically proven engagement formula. Pilot playtesting remains the judge of feel.

## Evidence and adoption

The [developer's official modding guide](https://steamcommunity.com/sharedfiles/filedetails/?id=495393634) identifies the ROGUE's base handling as pitch/yaw/roll 50/10/160 degrees per second. Its example uses throttle change speed 2, and describes a 0.5 throttle handling scalar: low throttle helps turning, full throttle reduces it. We adopt those base rates and scalar, while keeping our bounded keyboard angle demands, release-to-level and terrain protection. Its thrust values are engine-specific forces, not metres per second.

The pinned official [mod-example aircraft](https://github.com/nihilocrat/SkyRogueModTool/blob/f55e4c873a61a9fe380fa16f5c9fcafd8c538f0b/Assets/SkyRogueModTool/Example/CustomAero_base.aero.prefab) uses 100 hit points. This is an example, not a claim about every retail aircraft. We use that normalized health for the player and geese.



The Gatling fires four-round packets dealing 20 damage, giving five hit packets per 100-HP target. Ammunition is unlimited; these are game-specific balance values.

The official guide demonstrates small squadrons and flag-gated encounter stages. We keep small groups, individually stagger their arrival, and cap active contacts at four.

## Active values

| System | SPECTRE value | Basis |
| --- | --- | --- |
| Health | 100 HP | Published mod-example normalization |
| Gatling | 4 rounds/packet, 5 HP/round, 0.05 s/packet | Adapted 20-HP damage unit; 80 represented rounds/s |
| Gun hit requirement | 5 packets, 20 represented hit rounds | Derived from health/damage |
| Gun travel | 1,250 m/s muzzle speed; gravity and drag; 2.5 s life | Calibrated to existing world scale |
| Gun collision tolerance | 12 m around enlarged goose centre | Forgiving silhouette allowance |
| Aim envelope | Base acquire 6°, retain 7.5°; default 1.4× gives 8.4° / 10.5° | Saved Auto-aim slider scales both angles |
| Acquisition | Base 0.12 s; at 1.4× lock takes ~0.086 s, stick 0.168 s, switch margin 1.4° | Gun slew, aim response and reticle response also scale by the slider |
| Sight movement | 110°/s cap; exponential aim/reticle responses 30/28 s⁻¹ | Fast visible convergence, no instantaneous jump |
| Encounter pacing | 3-contact groups; 1.8 s arrivals; 3.6 s group pause; max 4 active | Small-squad structure, locally calibrated timing |
| Entry / exit | 620–825 m entry; fixed course; 28 s lifetime | Readable approaches and no chasing swarm |
| Goose speed | 90% of entry aircraft speed, clamped to 115–180 m/s | World-scale calibration |
| Flight rates | Base pitch/yaw/roll 50/10/160°/s | Published ROGUE baseline, converted to radians |
| Throttle | 2 units/s; 0.5 handling scalar | Published guide baseline |
| Speed | 430 m/s nominal maximum; 80 m/s airbrake floor; immediate W boost and S braking | Existing metric world and user responsiveness |
| Arrow response | 0.76 input scale; 55° bank and 24° pitch limits before scale; release-to-level | Preserves gentle control preference |
| Scoring | 100 base; multiplier rises every 3 clears to 5×; 5 s chain window | Existing simple score loop; no upgrades or grind |
| Route speeds | Alpine 165 m/s combat; coast 105–115 m/s sightseeing; approach 65 m/s | Authored route/runway geometry |

All other related rates, tolerances and timers—including motor coasting, terrain margins, input filtering, flare interval, scoring, landing thresholds and rollout braking—are named in the same profile. Geometry dimensions, rendering colors and mathematical constants are not balance values. Scenic waypoint positions remain in the authored route file.

## Measured checks

The existing controlled Gatling benchmark clears a stationary 100-HP target at 400 m in about 0.483 s, with five packets connecting. This is a simulation benchmark, not a guaranteed player time.

The same full-throttle two-second test at 60 Hz and 120 Hz reaches **348.67 m/s** from 185 m/s. Narrow-aim tests acquire a target at 4° within 0.2 s, retain a brief 6.8° drift, and release a 12° target. Pacing peaks at four contacts with a minimum measured arrival gap of 1.817 s.

`test_balance_profile.gd` measures damage-to-kill, actual time-to-hit, motor acceleration and timestep consistency. `test_combat_feel.gd` checks forgiving acquisition, exact crosshair convergence, no off-screen targeting, persistent trails, encounter pacing and sustained airbraking. Both run in the standard verification suite. Human preference and long-term replayability cannot be established by these tests alone.

## Player handling settings

Main-menu Settings and Esc → Settings expose independent yoke sensitivities plus **Agility** (default 1.3×, range 0.5–3×) and **Auto-aim** (default 1.4×, range 0–3×). Saved gameplay preferences live under `[gameplay]` in the local settings file. The base balance constants remain reference values. Agility scales aircraft pitch/roll/rudder rates and banked turns, ground steering/rotation, barrel-roll progress and velocity response. It does not multiply control inputs, change commanded pitch/bank limits, increase thrust or alter top speed. Auto-aim scales acquisition, retention, lock speed, target stick/switch margins and smooth aim/reticle tracking. Zero disables gun assistance. Bullet damage, hit radius and range remain fixed.

Normal combat, paper and demo flights start stationary on the departure runway at the correct terrain elevation, with gear down, takeoff flaps and zero power. Patrol time and flock encounters begin once airborne. Landing practice explicitly starts on final approach. Tests that need an in-flight fixture request an airborne start explicitly.
