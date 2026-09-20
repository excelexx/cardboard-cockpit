# SPECTRE 0.9 balance profile

The active gameplay values live in `simulator/data/balance.gd`. The reference is **Sky Rogue**, an arcade jet combat game. These are documented reference values plus explicit adaptations for SPECTRE; they are not claimed to be an optimal or scientifically proven engagement formula. Pilot playtesting remains the judge of feel.

## Evidence and adoption

The [developer's official modding guide](https://steamcommunity.com/sharedfiles/filedetails/?id=495393634) identifies the ROGUE's base handling as pitch/yaw/roll 50/10/160 degrees per second. Its example uses throttle change speed 2, and describes a 0.5 throttle handling scalar: low throttle helps turning, full throttle reduces it. We adopt those base rates and scalar, while keeping our bounded keyboard angle demands, release-to-level and terrain protection. Its thrust values are engine-specific forces, not metres per second.

The pinned official [mod-example aircraft](https://github.com/nihilocrat/SkyRogueModTool/blob/f55e4c873a61a9fe380fa16f5c9fcafd8c538f0b/Assets/SkyRogueModTool/Example/CustomAero_base.aero.prefab) uses 100 hit points. This is an example, not a claim about every retail aircraft. We use that normalized health for the player and geese.

The official [micro-missile example](https://github.com/nihilocrat/SkyRogueModTool/blob/f55e4c873a61a9fe380fa16f5c9fcafd8c538f0b/Assets/SkyRogueModTool/Example/CustomBullet_micromissile.bullet.prefab) has damage 20 and a 0.5-second acceleration delay. We adopt the acceleration time, and combine five such damage units into our single heavier 100-damage M-26. Its force/speed field 9000 and turn field 4 are **not** copied into our metric flight model. Its targeting-cone field 20 and automatic-lock behavior are deliberately adapted to the user's much narrower, visible acquisition requirement; the example does not establish our half-angle semantics.

The [weapon example](https://github.com/nihilocrat/SkyRogueModTool/blob/f55e4c873a61a9fe380fa16f5c9fcafd8c538f0b/Assets/SkyRogueModTool/Example/CustomWeapon_micromissile.weapon.prefab) is a ten-round micro-missile launcher with a 0.1 rate field and a 1-second reload field. SPECTRE instead has one heavy missile each second, with infinite ammo and no clip/reload system. Our Gatling's four-round packets deal 20 damage, giving five hit packets per target. These weapon conversions are design adaptations, not retail Sky Rogue weapon statistics.

The official guide demonstrates small squadrons and flag-gated encounter stages. We keep small groups, individually stagger their arrival, and cap active contacts at four. The [developer's 1.2.9 notes](https://steamcommunity.com/app/381020/announcements/) describe slowing missiles near targets to improve accuracy; we implement an independently chosen 20% reduction inside 150 metres.

## Active values

| System | SPECTRE value | Basis |
| --- | --- | --- |
| Health | 100 HP | Published mod-example normalization |
| Gatling | 4 rounds/packet, 5 HP/round, 0.05 s/packet | Adapted 20-HP damage unit; 80 represented rounds/s |
| Gun hit requirement | 5 packets, 20 represented hit rounds | Derived from health/damage |
| Gun travel | 1,250 m/s muzzle speed; gravity and drag; 2.5 s life | Calibrated to existing world scale |
| Gun collision tolerance | 12 m around enlarged goose centre | Forgiving silhouette allowance |
| M-26 | 100 damage; 1 s between launches | Five reference micro-hits combined; no reload |
| Missile flight | 0.18 s separation, 0.5 s acceleration to 600 m/s, 4 s motor, 12 s life | Source acceleration time plus game-scale calibration |
| Missile terminal guidance | 110°/s maximum turn; 480 m/s inside 150 m; 14 m proximity | Adaptation of documented terminal slowdown |
| Missile targeting | Fire-and-forget on the acquired target; unguided otherwise | Preserves visible player choice; no hidden retargeting |
| Aim envelope | Acquire within 6° half-angle; retain to 7.5° | User-requested smaller area with drift tolerance |
| Acquisition | 0.12 s; 0.12 s target stick; 1° switch margin | Calibrated for low effort and stable indicators |
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

With the actual projectile simulation, a stationary 100-HP target at 400 m clears in **0.483 s** of Gatling fire, with five packets connecting. A locked target at 600 m clears in **1.533 s** from a single missile command, including bay release and ignition. These are controlled benchmarks, not guaranteed player times.

The same full-throttle two-second test at 60 Hz and 120 Hz reaches **348.67 m/s** from 185 m/s. Narrow-aim tests acquire a target at 4° within 0.2 s, retain a brief 6.8° drift, and release a 12° target. Pacing peaks at four contacts with a minimum measured arrival gap of 1.817 s.

`test_balance_profile.gd` measures damage-to-kill, actual time-to-hit, motor acceleration and timestep consistency. `test_combat_feel.gd` checks forgiving acquisition, exact crosshair convergence, no off-screen targeting, persistent trails, encounter pacing and sustained airbraking. Both run in the standard verification suite. Human preference and long-term replayability cannot be established by these tests alone.

## 0.11.0 spectral demo override

The latest user specification supersedes the earlier six-degree/single-missile/100-HP profile. Normal contacts now have 900 HP, elites 2,400, boss 16,000. Primary combines four-round Gatling packets (20 damage every 0.05 seconds) and a 220 DPS beam. A salvo launches four 130-damage missiles at 85 ms spacing and repeats every 1.25 seconds. Ammunition remains unlimited. Acquisition adapts between 8–12 degrees (+2 during the opening), with a larger retained envelope and extra roll margin. The new TargetIntent system owns these dynamic angles; legacy constants remain for historical fixtures only.

Both physical switches latch. Camera loss releases their firing state. Keyboard Space/T mirror switch behavior. This profile is our own adaptation; these values are not claimed as Sky Rogue retail values.
