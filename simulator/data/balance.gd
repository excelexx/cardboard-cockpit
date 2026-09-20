extends RefCounted
class_name GameBalance
## Gameplay profile. See docs/balance.md for source values, units and adaptations.
## Sky Rogue reference: official mod tools f55e4c873a61a9fe380fa16f5c9fcafd8c538f0b.
## Published retail handling is distinct from the custom prefab's example stats.
##
## PLAYABILITY GUARD (binding on every value in this file): "realism" here means how
## things MOVE and LOOK. Nothing in this file may make the game harder to play.
## No finite ammunition, no energy bleed that slows the player, no slower or
## stricter lock-on, no smaller hit volumes, no longer takeoff, no lower speeds.
## Where a realism figure and the guard disagree, the guard wins and the realism
## goes into the POSE (angle of attack, banking, vapour, tracers), not the rules.
const ID := "spectre-skein-10"
# Combat: a goose is a goose. One cannon packet (2 rounds x 12) kills outright.
const PLAYER_HEALTH := 100.0
const CONTACT_HEALTH := 20.0
const GUN_ROUNDS_PER_PACKET := 2
const GUN_DAMAGE_PER_ROUND := 12.0
# Cadence is QUANTISED to the 60 Hz physics tick (project.godot): combat.gd:180
# only fires when the cooldown reaches zero, so every value in (1/60,2/60] costs
# exactly two ticks and .0364 cost three - the same 0.05 s cadence it replaced.
# .0333 -> 30 packets/s x 2 rounds = 60 rounds/s and 30 tracers/s, against the
# 20 packets/s / 80 rounds/s / 400 dps the shipped .05 actually delivered.
# Damage per second RISES to 720/s. Never lower these.
# P2: combat.gd:309 spawns ONE tracer per packet whatever round_count says, so
# the gatling LOOK needs GUN_ROUNDS_PER_PACKET tracers spawned per packet.
const GUN_INTERVAL := .0333
const GUN_MUZZLE_SPEED := 1040.0
const GUN_DRAG := .00030
const GUN_LIFETIME := 2.5
const GUN_HIT_RADIUS := 12.0
const GUN_RELEASE_TAIL := .05
# -1 means UNLIMITED and is the convention CombatDirector.ammo already uses.
# Ordnance is deliberately infinite: a booth player must never run dry.
const GUN_MAGAZINE := -1
const MISSILE_STORES := -1
# Cosmetic tracer scatter only. At 5 mrad and 0.6 sigma the cone is under 3 m at
# 900 m against a 20 m hit sphere, so it cannot turn a good burst into a miss.
const GUN_DISPERSION_MRAD := 5.0
const MISSILE_DAMAGE := 130.0
const MISSILE_INTERVAL := .85
const MISSILE_SPEED := 600.0
const MISSILE_ACCELERATION_TIME := .5
const MISSILE_IGNITION_DELAY := .18
const MISSILE_MOTOR_TIME := 4.0
const MISSILE_LIFETIME := 10.0
const MISSILE_TURN_DEGREES := 110.0
const MISSILE_TERMINAL_DISTANCE := 150.0
const MISSILE_TERMINAL_SPEED_RATIO := .80
const MISSILE_LEAD_TIME := .12
const MISSILE_COAST_SPEED := 400.0
const MISSILE_COAST_DRAG := 18.0
# Proximity fuse radius in metres, ABSOLUTE (not a bonus added to the target).
# The live test it replaces is combat.gd:437, float(enemy.hit_radius)+5.0, which
# is 27.0 m against today's 22.0 m goose - so anything under 28.0 would make a
# missile hit LESS often than it does now, which the guard forbids. P2: wire the
# fuse as maxf(MISSILE_HIT_RADIUS,float(enemy.hit_radius)+5.0) so that a larger
# target can never end up with a smaller fuse than it has today.
const MISSILE_HIT_RADIUS := 28.0
const MISSILE_ARM_TIME := 1.2
const MISSILE_SPLASH_MAX := 3
# Proportional navigation. The G limit is the turn limit and is deliberately
# generous, so a just-ignited missile still makes the corner.
const MISSILE_PN_GAIN := 4.0
const MISSILE_G_LIMIT := 60.0
const MISSILE_BAY_DELAY := .23
const MISSILE_RAIL_DELAY := .05
const MISSILE_DROP_SPEED := 4.0
const MISSILE_SMOKE_TIME := 3.0
const FLARE_INTERVAL := 1.5
# Narrow, forgiving envelope: user constraint, not the reference's wider cone.
const ACQUIRE_DEGREES := 6.0
const RETAIN_DEGREES := 7.5
const LOCK_TIME := .12
const TARGET_STICK_TIME := .12
const TARGET_SWITCH_MARGIN := 1.0
const TARGET_RANGE := 2300.0
const AIM_RESPONSE := 30.0
const RETICLE_RESPONSE := 28.0
const AIM_SLEW_DEGREES := 110.0
# COSMETIC ONLY: the fill duration of the cockpit LOCKING bar. There is no lock
# gate on firing today - combat.gd fire_missile() checks missile_cooldown and
# nothing else - so ANY value used as a gate would be stricter than the status
# quo, which the guard forbids. P2/P5: never let these delay fire_missile() or
# the guidance target it already picks at lock_progress>=.65.
const LOCK_SECONDS_FAST := .30
const LOCK_SECONDS_SLOW := .45
# Aim assist capture/deflection cone in degrees, and a FLOOR, never a ceiling.
# The live cone is target_intent.gd retain_degrees() = 16.1-18.7 deg (30.7 deg
# through a barrel roll), read at combat.gd:265 and :270. 19.0 covers the whole
# live band, so wiring it can never narrow the assist. P2: apply it as
# maxf(AIM_DEFLECTION_DEGREES,intent.retain_degrees(self)).
const AIM_DEFLECTION_DEGREES := 19.0
# Small staged groups; timings calibrated against our engagement/flight scale.
const MAX_CONTACTS := 4
const GROUP_SIZE := 3
const FIRST_ARRIVAL := .7
const ARRIVAL_INTERVAL := 1.8
const GROUP_BREATHER := 3.6
const SPAWN_DISTANCE := 620.0
const SPAWN_DISTANCE_STEP := 70.0
const SPAWN_DISTANCE_JITTER := 65.0
const SPAWN_LANES := [0.0,-.15,.20,-.23,.12]
const CONTACT_SPEED_RATIO := .90
# Real Canada goose cruise. Slower targets than the old 115-180 m/s: easier.
const CONTACT_MIN_SPEED := 16.0
const CONTACT_MAX_SPEED := 24.0
const CONTACT_LIFETIME := 28.0
const CONTACT_RETIRE_DISTANCE := 2300.0
const CONTACT_RETIRE_BEHIND := 280.0
const CONTACT_WEAVE_SPEED := 16.0
const CONTACT_VERTICAL_SPEED := 5.0
const CONTACT_FADE_IN := .8
const CONTACT_FADE_OUT := .65
const CONTACT_CLEARANCE := 110.0
const CONTACT_FLIGHT_CLEARANCE := 90.0
# Still far larger than life. NEVER go below 3.0: the bird has to read at 600 m.
const CONTACT_MODEL_SCALE := 3.0
# Hit sphere, decoupled from the model. The live value is combat.gd:168,
# 22.0*size_factor, and the cannon test adds 2.0+intent.help_amount*3 on top of
# it (24.0-26.8 m effective today), so 24.0 is the smallest value that cannot
# shrink a hit volume. P2: use it AS enemy.hit_radius, never below 22.0.
const CONTACT_HIT_RADIUS := 24.0
# The skein. One V of twelve, spawned a couple of birds per frame.
const SKEIN_SIZE := 12
const SKEIN_DEADLINE := 107.0
const SKEIN_SPAWN_DISTANCE := 1500.0
const SKEIN_SPAWN_HEIGHT := 140.0
const SKEIN_SPAWN_PER_FRAME := 2
const SKEIN_V_DEGREES := 58.0
const SKEIN_SLOT_BACK := 34.0
const SKEIN_SLOT_SIDE := 19.0
const SKEIN_SLOT_RISE := 3.0
const SKEIN_SLOT_JITTER := 1.5
const SKEIN_LEAD_ROTATE := 9.0
const SKEIN_DESPAWN_AGE := 90.0
const SKEIN_DESPAWN_DISTANCE := 4000.0
const BASE_SCORE := 40
const STREAK_TIME := 5.0
const STREAK_STEP := 3
const MAX_MULTIPLIER := 5
# Published ROGUE pitch/yaw/roll rates; radian conversion only.
const PITCH_RATE := 50.0*PI/180.0
const YAW_RATE := 10.0*PI/180.0
# 200 deg/s paired with a dynamic-pressure floor of 0.80 in flight_dynamics, so
# the commanded rate never drops below the 160 deg/s the jet had before.
const ROLL_RATE := 200.0*PI/180.0
const THROTTLE_RATE := 2.0
# 0.0: throttle no longer inverts roll authority (240 deg/s idle, 80 in burner).
const THROTTLE_HANDLING_SCALAR := 0.0
# World metres/second. Source force values are intentionally not treated as speeds.
const ROTATION_SPEED := 56.0
const MAX_SPEED := 430.0
const BASE_ACCELERATION := 29.0
const INPUT_ACCELERATION := 65.0
const AIRBRAKE_DECELERATION := 95.0
const AIRBRAKE_MIN_SPEED := 80.0
const AIRBRAKE_RESPONSE := 6.0
const AIRBRAKE_TAPER := 35.0
const ENGINE_INPUT_UP := 3.8
const ENGINE_INPUT_DOWN := 5.0
const ENGINE_CRUISE_UP := .52
const ENGINE_CRUISE_DOWN := .7
const AFTERBURNER_THRUST := 1.58
const AFTERBURNER_SPEED := 1.19
const ROLL_RESPONSE := 13.0
const PITCH_RESPONSE := 12.0
const YAW_RESPONSE := 5.0
const VELOCITY_RESPONSE := 4.0
# Raised from 3.0: the flight path follows the nose FASTER than before.
const VERTICAL_RESPONSE := 4.5
const BANK_TURN_FORCE := 64.0
const KEYBOARD_SCALE := .76
const INPUT_RESPONSE := 18.0
const INPUT_DEADZONE := .04
const BANK_LIMIT_DEGREES := 55.0
const PITCH_LIMIT_DEGREES := 24.0
const LANDING_PITCH_LIMIT_DEGREES := 12.0
const ANGLE_RESPONSE := 3.0
const ROLL_DAMPING := .40
const PITCH_DAMPING := .35
const RUDDER_SCALE := .8
const MOUSE_RANGE := Vector2(430,300)
const TERRAIN_MARGIN := 80.0
const TERRAIN_SPEED_MARGIN := .12
# Route speed/timing remains calibrated to the authored runway and waypoint geometry.
const PATROL_DURATION := 180.0
const ALPINE_COMBAT_SPEED := 165.0
const ALPINE_RETURN_SPEED := 130.0
const ALPINE_COMBAT_LIMIT := 85.0
const COAST_EARLY_SPEED := 105.0
const COAST_CRUISE_SPEED := 115.0
const COAST_RETURN_SPEED := 100.0
const WAYPOINT_RADIUS := 290.0
const WAYPOINT_HEIGHT_TOLERANCE := 190.0
# Landing gates stay exactly as forgiving as they were. A nose-high flare is a
# LOOK change (P4), not a tighter gate.
const APPROACH_SPEED := 65.0
const TOUCHDOWN_MAX_SPEED := 105.0
const TOUCHDOWN_MAX_SINK := 10.0
const TOUCHDOWN_MAX_BANK := .4
const ROLLOUT_DRAG := 1.4
const ROLLOUT_BRAKING := 5.2
const ROLLOUT_HOLD_PITCH_DEGREES := 10.0
const ROLLOUT_HOLD_SPEED := 42.0
const BARREL_DURATION := .78
# Takeoff rotation: the nose comes up through ROTATION_PITCH before the mains
# leave, then on to GROUND_PITCH_LIMIT. Rate is set so this costs under 1 s.
const GROUND_PITCH_LIMIT := .20
const GROUND_PITCH_RATE := .15
const ROTATION_PITCH := .105
# Gusts. Pose-first: a few metres of path at most, never a fight with the player.
const GUST_SCALE := 7.0
const GUST_MAX := 11.0
const GUST_TERRAIN_RANGE := 450.0
const GUST_AMBIENT := .12
const GUST_CLOUD_GAIN := .55
const GUST_POSE_PITCH_DEGREES := .55
const GUST_POSE_ROLL_DEGREES := .85
const GUST_POSE_YAW_DEGREES := .35
const GUST_VERTICAL_COUPLING := 1.6

# Demo spectacle tuning layered on the retained arcade physics/weapon profile.
const DEMO_LIMIT := 148.0
# The designator beam no longer does damage; the gun does. P7 restyles the mesh.
const BEAM_DPS := 0.0
const BEAM_RANGE := 1900.0
# DEPRECATED, there is no boss and no elite. Held at CONTACT_HEALTH so that any
# surviving spawn branch dies like an ordinary goose. Delete once combat.gd:163
# and :166 stop naming them.
const ELITE_HEALTH := CONTACT_HEALTH
const BOSS_HEALTH := CONTACT_HEALTH
const SALVO_STAGGER := .085
const MAX_SHOTS := 220
const MAX_MISSILES := 48

# Cross-package look constants. Owned here so no other package has to reopen
# this file; each is consumed by the package named in the comment.
# P4 - camera weight, shake and G vignette.
const CAMERA_SHAKE_ANGLE_DEGREES := 3.2
const CAMERA_SHAKE_ROLL_DEGREES := 1.6
const CAMERA_SHAKE_SHIFT_CHASE := .42
const CAMERA_SHAKE_SHIFT_COCKPIT := .05
const CAMERA_SHAKE_ENERGY_CAP := 1.4
const CAMERA_SHAKE_RATE := 22.0
const CAMERA_BUFFET_RATE := 30.0
const GLOAD_VIGNETTE_ONSET := 6.2
const GLOAD_VIGNETTE_SPAN := 1.5
# P7 - vapour. Thresholds are rebased on the signed normal g_load this package
# now publishes; see the handoff for the measured values they came from.
const VAPOR_MACH_LOW := .88
const VAPOR_MACH_HIGH := 1.14
const VAPOR_ALPHA_CAP := .55
const WINGTIP_STATION := 6.25
const WINGTIP_VAPOR_G_ONSET := 4.2
const WINGTIP_VAPOR_G_SPAN := 2.4
const WINGTIP_TRAIL_LIFE := 1.1
# P7 - feathers instead of airframe debris.
const FEATHER_COUNT := 64
const FEATHER_LIFETIME := 2.2
const FEATHER_DOWN_COUNT := 96
const FEATHER_DOWN_LIFETIME := 3.5
