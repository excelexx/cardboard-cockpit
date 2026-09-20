extends RefCounted
class_name FlightDynamics
const Tune = preload("res://data/balance.gd")
## Fictional fly-by-wire dynamics: filtered angular rates, momentum and energy.
##
## POSE vs PATH (read before touching this file):
## `pitch` is the FLIGHT PATH angle, as it always has been. `aoa` and `beta` are
## PRESENTATION state: the airframe is drawn at `pitch + aoa` / `heading + beta`
## so the nose rides above the path the way a real jet's does, but neither value
## is ever fed back into the trajectory, the drag or the stall logic. Autopilots
## therefore keep commanding `pitch` exactly as before and MUST NOT add `aoa` to
## their demands - doing so would make the aircraft climb.
var pitch_agility: float=1.0:
	set(value):pitch_agility=clampf(value,.5,3.0) if is_finite(value) else 1.0
var bank_agility: float=1.0:
	set(value):bank_agility=clampf(value,.5,3.0) if is_finite(value) else 1.0
var yaw_agility: float=1.0:
	set(value):yaw_agility=clampf(value,.5,3.0) if is_finite(value) else 1.0
var profile: Dictionary
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var speed := 0.0
var throttle := 0.0
var engine := 0.0
var afterburner := false
var power_input := 0.0
var airbrake := 0.0
var wind := Vector3.ZERO
var pitch := 0.0
var roll := 0.0
var heading := 0.0
var pitch_velocity := 0.0
var roll_velocity := 0.0
var yaw_velocity := 0.0
var vertical_speed := 0.0
## Low-passed vertical speed. Assists read this so a gust cannot make them chatter.
var vertical_trend := 0.0
## Signed, smoothed NORMAL load factor: the component of acceleration along the
## lift axis plus the gravity term. Negative in a bunt. Throttle does not move it.
var g_load := 1.0
## Displayed angle of attack and sideslip, radians. Pose only. See the note above.
var aoa := 0.0
var beta := 0.0
## Displayed Mach number. Pose only: nothing in this file reads it back.
var mach := 0.0
## Extra POSE offsets (pitch, yaw, roll) in radians, written from outside by
## whoever samples the GustField. Zero by default; pose_*() fold it in.
var pose_offset := Vector3.ZERO
var airborne := false
var ever_airborne := false
var gear := true
var flaps := 0
var elapsed := 0.0
var airborne_time := 0.0
var distance := 0.0
var roughness := 0.0
var contact := ""
var touchdown_speed := 0.0
var touchdown_sink := 0.0
var touchdown_bank := 0.0
var touchdown_center := 0.0
var touchdown_pitch := 0.0
var rollout_elapsed := 0.0
var stall_time := 0.0
var barrel_remaining := 0.0
var barrel_direction := 1.0
var barrel_start := 0.0
## Unwrapped roll through a barrel roll, so a chase camera never sees the wrap.
## Equal to `roll` whenever a roll is not running.
var barrel_angle := 0.0
var barrel_pitch_offset := 0.0
var barrel_heading_offset := 0.0
var last_ground := 0.0
const BARREL_DURATION := Tune.BARREL_DURATION
## Nose displacement flown through the barrel roll. Both terms are exactly zero
## at phase TAU, so the manoeuvre returns the aircraft to its original path.
const BARREL_PITCH := 0.1047
const BARREL_YAW := 0.0698
## Angle of attack model. CL ~ n/V^2, so alpha rises with load and falls with the
## square of speed, and it is SIGNED: a bunt is negative lift, so the airframe is
## drawn nose-LOW relative to its path, the way the published g_load already goes
## negative. Calibrated against a headless run: see tests/test_flight_envelope.gd.
const ALPHA_MAX := 0.2793
## Floor for the signed angle of attack: a push may draw the nose 6.4 deg below
## the path and no further.
const ALPHA_MIN := -0.1117
const ALPHA_REF := 0.0103
const ALPHA_V_REF := 200.0
const ALPHA_BIAS := 0.0131
const ALPHA_FLAP := 0.012
const ALPHA_GEAR := 0.045
const ALPHA_RESPONSE := 5.0
const BETA_RESPONSE := 6.0
## Structural band for the flight-path rate limiter and for the published g_load.
const G_LIMIT := 7.0
const G_LIMIT_NEG := -2.5
const G_RESPONSE := 9.0
## The response this model had before the limiter existed. The limiter may never
## make the aircraft slower to answer the stick than this.
const LEGACY_VERTICAL_RESPONSE := 3.0
## Roll authority scales with dynamic pressure, with a floor chosen so the
## commanded rate never falls below the 160 deg/s the aircraft had before.
const ROLL_AUTHORITY_SPEED := 245.0
const ROLL_AUTHORITY_MIN := 0.80
const ROLL_AUTHORITY_MAX := 1.30
const GEAR_PITCH_ARM := 3.4

func reset(aircraft: Dictionary) -> void:
	profile = aircraft.duplicate(true)
	position = Vector3(0,float(profile.clearance),1100)
	velocity = Vector3.ZERO; wind = Vector3.ZERO
	speed = 0; throttle = 0; engine = 0; power_input = 0; airbrake = 0
	pitch = 0; roll = 0; heading = 0
	pitch_velocity = 0; roll_velocity = 0; yaw_velocity = 0
	vertical_speed = 0; vertical_trend = 0; g_load = 1
	aoa = 0; beta = 0; mach = 0; pose_offset = Vector3.ZERO
	airborne = false; ever_airborne = false; gear = true; afterburner = false
	flaps = 0; elapsed = 0; airborne_time = 0; distance = 0; roughness = 0
	contact = ""; stall_time = 0; barrel_remaining = 0; rollout_elapsed = 0
	barrel_angle = 0; barrel_pitch_offset = 0; barrel_heading_offset = 0
	touchdown_speed = 0; touchdown_sink = 0; touchdown_bank = 0; touchdown_center = 0
	touchdown_pitch = 0

func spawn_airborne(at: Vector3, airspeed: float) -> void:
	position = at
	speed = airspeed
	throttle = 0.55; engine = 0.55
	airborne = true; ever_airborne = true; airborne_time = 30
	gear = false; contact = ""
	velocity = forward()*speed
	# A respawn is a clean aircraft. vertical_trend in particular MUST be cleared:
	# arcade_controls reads it, and a stale climb rate carried over from the crash
	# would suppress the terrain assist for most of a second at the exact moment a
	# novice is closest to the ground.
	vertical_speed = 0; vertical_trend = 0; g_load = 1
	aoa = 0; beta = 0; pose_offset = Vector3.ZERO
	stall_time = 0; roll_velocity = 0; pitch_velocity = 0; yaw_velocity = 0
	barrel_remaining = 0; barrel_angle = roll
	barrel_pitch_offset = 0; barrel_heading_offset = 0

func forward() -> Vector3:
	return Vector3(sin(heading)*cos(pitch),sin(pitch),-cos(heading)*cos(pitch))

## Attitude the airframe is DRAWN at: the flight path plus the angle of attack.
func pose_pitch() -> float: return pitch+aoa+pose_offset.x
## Heading the airframe is DRAWN at: the ground track plus the sideslip.
func pose_heading() -> float: return heading+beta+pose_offset.y
## Bank the airframe is DRAWN at: the flown roll plus the gust wobble.
func pose_roll() -> float: return roll+pose_offset.z
## The airframe basis. The moment scenes/main.gd apply_aircraft_pose() draws the
## aircraft from pose_pitch()/pose_heading()/pose_roll(), everything BOLTED TO the
## airframe has to come from here in the SAME commit, or it hangs off the drawn
## hull by aoa+beta - 1.6 deg at cruise, 10.3 deg on approach:
##   fighter_effects.gd  nozzle/afterburner anchor (two Basis.from_euler sites)
##   combat.gd           gun muzzle, missile stores, designator beam origin
##   combat_visuals.gd   beam start
##   camera_rig.gd       the COCKPIT branch only - the pilot sits in the airframe
## The chase branch of camera_rig.gd deliberately stays on the PATH basis: that is
## what lets the player see the jet ride at an angle to its own flight path.
func pose_basis() -> Basis:
	return Basis.from_euler(Vector3(pose_pitch(),-pose_heading(),-pose_roll()))

func step(dt: float, controls: Vector3, brakes: bool, ground: float, runway: bool, resolve_surface: bool = true) -> void:
	if contact!="" or dt<=0: return
	last_ground = ground
	var bounded: float = minf(dt,0.5)
	var steps: int = maxi(1,int(ceil(bounded*120)))
	for i in range(steps):
		integrate(bounded/steps,controls.clamp(-Vector3.ONE,Vector3.ONE),brakes,ground)
		if resolve_surface:
			resolve_contact(ground,runway)
			if contact!="": break

func integrate(dt: float, controls: Vector3, brakes: bool, ground: float) -> void:
	elapsed += dt
	engine = move_toward(engine,throttle,dt*((Tune.ENGINE_INPUT_UP if throttle>engine else Tune.ENGINE_INPUT_DOWN) if absf(power_input)>.01 else (Tune.ENGINE_CRUISE_UP if throttle>engine else Tune.ENGINE_CRUISE_DOWN)))
	var thrust: float = float(profile.acceleration)*engine*(Tune.AFTERBURNER_THRUST if afterburner and not gear else 1.0)
	airbrake = move_toward(airbrake,1.0 if power_input<-.1 and airborne else 0.0,dt*Tune.AIRBRAKE_RESPONSE)
	if airborne and power_input>0: thrust += power_input*Tune.INPUT_ACCELERATION
	var drag: float = float(profile.acceleration)*pow(speed/float(profile.max_speed),2)
	drag += (0.70 if gear else 0.15)+flaps*(0.35+speed*0.007)
	if airborne: drag += airbrake*Tune.AIRBRAKE_DECELERATION*clampf((speed-Tune.AIRBRAKE_MIN_SPEED)/Tune.AIRBRAKE_TAPER,0,1)
	if not airborne: drag += 0.45+(19 if brakes else 0)
	speed = clampf(speed+(thrust-drag-sin(pitch)*5.0)*dt,0,float(profile.max_speed)*(Tune.AFTERBURNER_SPEED if afterburner else 1.03))
	if airborne and not gear and power_input<-.1: speed = maxf(speed,Tune.AIRBRAKE_MIN_SPEED)
	# Display only. Nothing below reads this back into the trajectory or the drag.
	mach = speed/maxf(340.3-0.0039*position.y,250.0)
	var previous_velocity: Vector3 = velocity
	if airborne:
		var handling: float = 1+Tune.THROTTLE_HANDLING_SCALAR*(1-2*throttle)
		var authority: float = clampf(speed/effective_rotation_speed(),0.15,1.25)
		var roll_authority: float = clampf(speed/ROLL_AUTHORITY_SPEED,ROLL_AUTHORITY_MIN,ROLL_AUTHORITY_MAX)
		roll_velocity = lerpf(roll_velocity,controls.x*float(profile.roll_rate)*handling*bank_agility*roll_authority,1-exp(-dt*Tune.ROLL_RESPONSE))
		pitch_velocity = lerpf(pitch_velocity,controls.y*float(profile.pitch_rate)*authority*handling*pitch_agility,1-exp(-dt*Tune.PITCH_RESPONSE))
		var rolling: bool = barrel_remaining>0
		var barrel_phase := 0.0
		if rolling:
			barrel_remaining = maxf(0,barrel_remaining-dt)
			barrel_phase = TAU*smoothstep(0,1,1-barrel_remaining/BARREL_DURATION)
			if barrel_remaining==0: barrel_phase = TAU
			barrel_angle = barrel_start+barrel_direction*barrel_phase
			roll = barrel_start if barrel_remaining==0 else wrapf(barrel_angle,-PI,PI)
		else:
			roll = wrapf(roll+roll_velocity*dt,-PI,PI)
			barrel_angle = roll
		pitch = clampf(pitch+pitch_velocity*dt,-1.10,1.20)
		# The nose traces a small circle through the roll. Both offsets are held
		# as state and removed exactly, so the path is unchanged when it ends.
		if rolling or barrel_pitch_offset!=0.0 or barrel_heading_offset!=0.0:
			var pitch_offset: float = sin(barrel_phase)*BARREL_PITCH if rolling else 0.0
			var heading_offset: float = (1.0-cos(barrel_phase))*BARREL_YAW*barrel_direction if rolling else 0.0
			pitch += pitch_offset-barrel_pitch_offset
			heading = wrapf(heading+heading_offset-barrel_heading_offset,-PI,PI)
			barrel_pitch_offset = pitch_offset
			barrel_heading_offset = heading_offset
		var coordinated: float = sin(roll)*Tune.BANK_TURN_FORCE/maxf(speed,55.0)
		var desired_yaw: float = coordinated*bank_agility+controls.z*Tune.YAW_RATE*handling*yaw_agility
		yaw_velocity = lerpf(yaw_velocity,0.0 if rolling else desired_yaw,1-exp(-dt*Tune.YAW_RESPONSE))
		heading = wrapf(heading+yaw_velocity*dt,-PI,PI)
		var lift: float = clampf(speed/(effective_rotation_speed()*0.82),0,1)
		var sink: float = (1-lift)*28.0+(1-maxf(cos(roll),0.0))*6.0
		var desired_vertical: float = sin(pitch)*speed-sink
		if airborne_time<5 and position.y-ground<25: desired_vertical = maxf(desired_vertical,2)
		# Flight-path smoothing, rate-limited by load factor so a hard pull at
		# high speed no longer asks the path for tens of g. The limiter may only
		# ever SMOOTH the answer, never delay it past the old first-order lag.
		var legacy: float = lerpf(vertical_speed,desired_vertical,1-exp(-dt*LEGACY_VERTICAL_RESPONSE))
		var eager: float = lerpf(vertical_speed,desired_vertical,1-exp(-dt*Tune.VERTICAL_RESPONSE*pitch_agility))
		var load: float = cos(pitch)*maxf(cos(roll),0.0)
		var up_rate: float = 9.81*maxf(G_LIMIT-load,0.5)*dt
		var down_rate: float = 9.81*maxf(load-G_LIMIT_NEG,0.5)*dt
		var limited: float = clampf(eager,vertical_speed-down_rate,vertical_speed+up_rate)
		vertical_speed = limited if absf(limited-desired_vertical)<=absf(legacy-desired_vertical) else legacy
		# The jet rides the bumps. Bounded by GUST_MAX and washed out by the lag
		# above, so a gust is worth a couple of metres, never a fight.
		if wind.y!=0.0: vertical_speed += wind.y*dt*Tune.GUST_VERTICAL_COUPLING
		vertical_trend = lerpf(vertical_trend,vertical_speed,1-exp(-dt*LEGACY_VERTICAL_RESPONSE))
		var horizontal := Vector3(sin(heading),0,-cos(heading))*speed*cos(pitch)+wind
		if velocity.length()<0.01 and speed>1: velocity = Vector3(horizontal.x,vertical_speed,horizontal.z)
		velocity.x = lerpf(velocity.x,horizontal.x,1-exp(-dt*Tune.VELOCITY_RESPONSE))
		velocity.z = lerpf(velocity.z,horizontal.z,1-exp(-dt*Tune.VELOCITY_RESPONSE))
		velocity.y = vertical_speed
		position += velocity*dt
		airborne_time += dt
		stall_time = stall_time+dt if lift<0.85 else 0
		roughness += (absf(controls.x)*0.15+absf(controls.y)*0.10)*dt
		# Signed normal load factor: acceleration along the lift axis only, so
		# throttle and airbrake never show up as g.
		var body_up: Vector3 = Basis.from_euler(Vector3(pitch,-heading,-roll))*Vector3.UP
		var normal_acceleration: float = ((velocity-previous_velocity)/maxf(dt,0.001)).dot(body_up)
		g_load = lerpf(g_load,clampf(normal_acceleration/9.81+cos(pitch)*cos(roll),G_LIMIT_NEG,G_LIMIT),1-exp(-dt*G_RESPONSE))
		update_pose(dt,controls,ground)
	else:
		heading = wrapf(heading+controls.z*0.38*clampf(speed/20,0,1)*dt,-PI,PI)
		# Rotation: the nose comes up through ROTATION_PITCH before the mains
		# leave the ground, which costs at most 0.7 s of the takeoff roll.
		var demand: float = maxf(controls.y,0.0)
		var rotation_target: float = Tune.GROUND_PITCH_LIMIT*clampf(demand/0.6,0.0,1.0)
		pitch = move_toward(pitch,rotation_target,dt*Tune.GROUND_PITCH_RATE)
		roll = 0; vertical_speed = 0; vertical_trend = 0; g_load = 1
		barrel_angle = 0
		# The origin rises with the nose: the aircraft is sitting on its mains.
		position.y = ground+gear_drop()
		velocity = Vector3(sin(heading),0,-cos(heading))*speed
		position += velocity*dt
		update_pose(dt,controls,ground)
		if speed>=effective_rotation_speed() and demand>0.12 and pitch>=minf(Tune.ROTATION_PITCH,rotation_target-0.005):
			airborne = true; ever_airborne = true
			vertical_speed = 4; position.y += 0.12
	distance += speed*dt

## Presentation state only. Never call anything here from the integration above.
func update_pose(dt: float, controls: Vector3, ground: float) -> void:
	var target_alpha := 0.0
	if airborne:
		# SIGNED in g_load: in a bunt the wing is carrying negative lift, so the
		# nose sits BELOW the flight path. The trim term follows the sign of the
		# load (saturating at +-1 g) so the cruise and approach figures are the
		# ones this package measured, while a push cannot come out nose-up.
		target_alpha = ALPHA_REF*g_load*pow(ALPHA_V_REF/maxf(speed,60.0),2.0)
		target_alpha += ALPHA_BIAS*clampf(g_load,-1.0,1.0)
		target_alpha += float(clampi(flaps,0,2))*ALPHA_FLAP+(ALPHA_GEAR if gear else 0.0)
		target_alpha *= 1.0-0.15*clampf(1.0-(position.y-ground)/8.0,0.0,1.0)
	aoa = lerpf(aoa,clampf(target_alpha,ALPHA_MIN,ALPHA_MAX),1-exp(-dt*ALPHA_RESPONSE))
	var target_beta: float = clampf(controls.z*0.09-sin(roll)*0.02,-0.12,0.12) if airborne else 0.0
	beta = lerpf(beta,target_beta,1-exp(-dt*BETA_RESPONSE))

## Height of the lowest gear below the reference point. A nose-high jet puts its
## mains down first, which is what makes P4's landing flare read correctly.
func gear_drop() -> float:
	return float(profile.clearance)+sin(maxf(pitch,0.0))*GEAR_PITCH_ARM

func resolve_contact(ground: float, runway: bool) -> void:
	if contact!="": return
	if airborne and position.y<=ground+gear_drop():
		touchdown_speed = speed; touchdown_sink = vertical_speed; touchdown_bank = roll; touchdown_center = absf(position.x)
		touchdown_pitch = pitch
		if runway and gear and speed<Tune.TOUCHDOWN_MAX_SPEED and vertical_speed>-Tune.TOUCHDOWN_MAX_SINK and absf(roll)<Tune.TOUCHDOWN_MAX_BANK:
			airborne = false; position.y = ground+gear_drop()
			vertical_speed = 0; vertical_trend = 0; velocity.y = 0; contact = "landed"
		else: contact = "crash"
	if not airborne and not runway and speed>50: contact = "excursion"

func rollout_step(dt: float, brakes: bool, steering: float, on_runway: bool) -> void:
	if contact!="landed": return
	elapsed += dt; rollout_elapsed += dt
	# Aerodynamic braking: hold whatever nose-up attitude was flown onto the
	# runway, then derotate. A flat touchdown behaves exactly as it did before.
	var hold: float = clampf(touchdown_pitch,0.0,deg_to_rad(Tune.ROLLOUT_HOLD_PITCH_DEGREES)) if speed>Tune.ROLLOUT_HOLD_SPEED else 0.0
	pitch = move_toward(pitch,hold,dt*0.16)
	roll = move_toward(roll,0,dt*0.18)
	pitch_velocity = move_toward(pitch_velocity,0,dt)
	roll_velocity = move_toward(roll_velocity,0,dt)
	aoa = move_toward(aoa,0,dt*0.30); beta = move_toward(beta,0,dt*0.30)
	throttle = 0; afterburner = false; engine = move_toward(engine,0,dt*0.5)
	speed = maxf(0,speed-(Tune.ROLLOUT_DRAG+(Tune.ROLLOUT_BRAKING if brakes else 0))*dt)
	mach = speed/340.3
	heading += clampf(steering,-1,1)*0.11*clampf(speed/20,0,1)*dt
	velocity = Vector3(sin(heading),0,-cos(heading))*speed
	position += velocity*dt; distance += speed*dt
	position.y = move_toward(position.y,last_ground+gear_drop(),dt*1.2)
	if not on_runway: contact = "overrun"

func effective_rotation_speed() -> float:
	return float(profile.rotation_speed)*(1-clampi(flaps,0,2)*0.06)
func get_heading_degrees() -> float: return fposmod(rad_to_deg(heading),360)
func start_barrel_roll(direction: float = 1) -> bool:
	if not airborne or position.y-last_ground<35 or barrel_remaining>0 or contact!="": return false
	barrel_start = roll; barrel_direction = -1 if direction<0 else 1; barrel_remaining = BARREL_DURATION
	barrel_angle = barrel_start; barrel_pitch_offset = 0.0; barrel_heading_offset = 0.0
	return true
func landing_score() -> int:
	return clampi(int(100-absf(touchdown_sink)*7-absf(rad_to_deg(touchdown_bank))*0.8-touchdown_center*0.45-maxf(0,touchdown_speed-float(profile.rotation_speed)*1.15)*0.7),0,100)
func get_smoothness() -> int:
	return clampi(int(100-roughness/maxf(elapsed,1)*180-stall_time),0,100)
