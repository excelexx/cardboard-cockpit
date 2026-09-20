extends RefCounted
class_name FlightDynamics
const Tune = preload("res://data/balance.gd")
## Fictional fly-by-wire dynamics: filtered angular rates, momentum and energy.
var profile: Dictionary
var pitch_agility: float = 1.0:
	set(value): pitch_agility = clampf(value,.5,6.0) if is_finite(value) else 1.0
var bank_agility: float = 1.0:
	set(value): bank_agility = clampf(value,.5,6.0) if is_finite(value) else 1.0
var yaw_agility: float = 1.0:
	set(value): yaw_agility = clampf(value,.5,6.0) if is_finite(value) else 1.0
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
var g_load := 1.0
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
var rollout_elapsed := 0.0
var stall_time := 0.0
var barrel_remaining := 0.0
var barrel_direction := 1.0
var barrel_start := 0.0
var last_ground := 0.0
const BARREL_DURATION := Tune.BARREL_DURATION


# Current visual presentation is independent of the XLX flight trajectory.
var vertical_trend := 0.0
var aoa := 0.0
var beta := 0.0
var mach := 0.0
var pose_offset := Vector3.ZERO
var barrel_angle := 0.0
var touchdown_pitch := 0.0
const G_LIMIT := 9.0
const G_LIMIT_NEG := .2
const GEAR_PITCH_ARM := 3.4
const ALPHA_MAX := 0.2793
const ALPHA_MIN := -0.1117
const ALPHA_REF := 0.0103
const ALPHA_V_REF := 200.0
const ALPHA_BIAS := 0.0131
const ALPHA_FLAP := 0.012
const ALPHA_GEAR := 0.045
const ALPHA_RESPONSE := 5.0
const BETA_RESPONSE := 6.0

func reset(aircraft: Dictionary) -> void:
	vertical_trend=0;aoa=0;beta=0;mach=0;pose_offset=Vector3.ZERO;barrel_angle=0;touchdown_pitch=0
	profile = aircraft.duplicate(true)
	position = Vector3(0,float(profile.clearance),1100)
	velocity = Vector3.ZERO; wind = Vector3.ZERO
	speed = 0; throttle = 0; engine = 0; power_input = 0; airbrake = 0
	pitch = 0; roll = 0; heading = 0
	pitch_velocity = 0; roll_velocity = 0; yaw_velocity = 0
	vertical_speed = 0; g_load = 1
	airborne = false; ever_airborne = false; gear = true; afterburner = false
	flaps = 0; elapsed = 0; airborne_time = 0; distance = 0; roughness = 0
	contact = ""; stall_time = 0; barrel_remaining = 0; rollout_elapsed = 0
	touchdown_speed = 0; touchdown_sink = 0; touchdown_bank = 0; touchdown_center = 0

func spawn_airborne(at: Vector3, airspeed: float) -> void:
	vertical_trend=0;aoa=0;beta=0;pose_offset=Vector3.ZERO;barrel_angle=0
	position = at
	speed = airspeed
	throttle = 0.55; engine = 0.55
	airborne = true; ever_airborne = true; airborne_time = 30
	gear = false; contact = ""
	velocity = forward()*speed

func forward() -> Vector3:
	return Vector3(sin(heading)*cos(pitch),sin(pitch),-cos(heading)*cos(pitch))

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
	var previous_velocity: Vector3 = velocity
	if airborne:
		var handling: float = 1+Tune.THROTTLE_HANDLING_SCALAR*(1-2*throttle)
		var authority: float = clampf(speed/effective_rotation_speed(),0.15,1.25)
		# Aircraft angular rates, independent of yoke input sensitivity and angle limits.
		roll_velocity = lerpf(roll_velocity,controls.x*float(profile.roll_rate)*handling*bank_agility,1-exp(-dt*Tune.ROLL_RESPONSE))
		pitch_velocity = lerpf(pitch_velocity,controls.y*float(profile.pitch_rate)*authority*handling*pitch_agility,1-exp(-dt*Tune.PITCH_RESPONSE))
		var rolling: bool = barrel_remaining>0
		if rolling:
			barrel_remaining = maxf(0,barrel_remaining-dt*bank_agility)
			roll = wrapf(barrel_start+barrel_direction*TAU*smoothstep(0,1,1-barrel_remaining/BARREL_DURATION),-PI,PI)
			if barrel_remaining==0: roll = barrel_start
		else:
			roll = wrapf(roll+roll_velocity*dt,-PI,PI)
		pitch = clampf(pitch+pitch_velocity*dt,-1.10,1.20)
		var coordinated: float = sin(roll)*Tune.BANK_TURN_FORCE/maxf(speed,55.0)
		var rudder: float = controls.z*Tune.YAW_RATE*handling
		var desired_yaw: float = coordinated*bank_agility+rudder*yaw_agility
		var turn_weight: float = absf(coordinated)+absf(rudder)
		var turn_agility: float = (absf(coordinated)*bank_agility+absf(rudder)*yaw_agility)/turn_weight if turn_weight>0.0001 else 1.0
		yaw_velocity = lerpf(yaw_velocity,0.0 if rolling else desired_yaw,1-exp(-dt*Tune.YAW_RESPONSE))
		heading = wrapf(heading+yaw_velocity*dt,-PI,PI)
		var lift: float = clampf(speed/(effective_rotation_speed()*0.82),0,1)
		var sink: float = (1-lift)*28.0+(1-maxf(cos(roll),0.0))*6.0
		var desired_vertical: float = sin(pitch)*speed-sink
		if airborne_time<5 and position.y-ground<25: desired_vertical = maxf(desired_vertical,2)
		vertical_speed = lerpf(vertical_speed,desired_vertical,1-exp(-dt*Tune.VERTICAL_RESPONSE*pitch_agility))
		var horizontal := Vector3(sin(heading),0,-cos(heading))*speed*cos(pitch)+wind
		if velocity.length()<0.01 and speed>1: velocity = Vector3(horizontal.x,vertical_speed,horizontal.z)
		velocity.x = lerpf(velocity.x,horizontal.x,1-exp(-dt*Tune.VELOCITY_RESPONSE*turn_agility))
		velocity.z = lerpf(velocity.z,horizontal.z,1-exp(-dt*Tune.VELOCITY_RESPONSE*turn_agility))
		velocity.y = vertical_speed
		position += velocity*dt
		airborne_time += dt
		stall_time = stall_time+dt if lift<0.85 else 0
		roughness += (absf(controls.x)*0.15+absf(controls.y)*0.10)*dt
		var acceleration: float = (velocity-previous_velocity).length()/maxf(dt,0.001)
		g_load = lerpf(g_load,clampf(1+acceleration/9.81,0.2,9.0),1-exp(-dt*3))
	else:
		heading = wrapf(heading+controls.z*0.38*clampf(speed/20,0,1)*dt*yaw_agility,-PI,PI)
		pitch = move_toward(pitch,maxf(controls.y,0)*0.14,dt*0.13*pitch_agility)
		roll = 0; vertical_speed = 0; g_load = 1
		position.y = ground+float(profile.clearance)
		velocity = Vector3(sin(heading),0,-cos(heading))*speed
		position += velocity*dt
		if speed>=effective_rotation_speed() and controls.y>0.12:
			airborne = true; ever_airborne = true
			vertical_speed = 4; position.y += 0.12
	distance += speed*dt
	vertical_trend=lerpf(vertical_trend,vertical_speed,1-exp(-dt*3))
	mach=speed/maxf(340.3-0.0039*position.y,250.0)
	barrel_angle=barrel_start+barrel_direction*TAU*smoothstep(0,1,1-barrel_remaining/BARREL_DURATION) if barrel_remaining>0 else roll
	update_pose(dt,controls,ground)

func resolve_contact(ground: float, runway: bool) -> void:
	if contact!="": return
	if airborne and position.y<=ground+float(profile.clearance):
		touchdown_pitch=pose_pitch()
		touchdown_speed = speed; touchdown_sink = vertical_speed; touchdown_bank = roll; touchdown_center = absf(position.x)
		if runway and gear and speed<Tune.TOUCHDOWN_MAX_SPEED and vertical_speed>-Tune.TOUCHDOWN_MAX_SINK and absf(roll)<Tune.TOUCHDOWN_MAX_BANK:
			airborne = false; position.y = ground+float(profile.clearance)
			vertical_speed = 0; velocity.y = 0; contact = "landed"
		else: contact = "crash"
	if not airborne and not runway and speed>50: contact = "excursion"

func rollout_step(dt: float, brakes: bool, steering: float, on_runway: bool) -> void:
	if contact!="landed": return
	elapsed += dt; rollout_elapsed += dt
	pitch = move_toward(pitch,0,dt*0.10)
	roll = move_toward(roll,0,dt*0.18)
	pitch_velocity = move_toward(pitch_velocity,0,dt)
	roll_velocity = move_toward(roll_velocity,0,dt)
	throttle = 0; afterburner = false; engine = move_toward(engine,0,dt*0.5)
	speed = maxf(0,speed-(Tune.ROLLOUT_DRAG+(Tune.ROLLOUT_BRAKING if brakes else 0))*dt)
	heading += clampf(steering,-1,1)*0.11*clampf(speed/20,0,1)*dt*yaw_agility
	velocity = Vector3(sin(heading),0,-cos(heading))*speed
	position += velocity*dt; distance += speed*dt
	if not on_runway: contact = "overrun"

func effective_rotation_speed() -> float:
	return float(profile.rotation_speed)*(1-clampi(flaps,0,2)*0.06)
func get_heading_degrees() -> float: return fposmod(rad_to_deg(heading),360)
func start_barrel_roll(direction: float = 1) -> bool:
	if not airborne or position.y-last_ground<35 or barrel_remaining>0 or contact!="": return false
	barrel_start = roll; barrel_direction = -1 if direction<0 else 1; barrel_remaining = BARREL_DURATION
	return true
func landing_score() -> int:
	return clampi(int(100-absf(touchdown_sink)*7-absf(rad_to_deg(touchdown_bank))*0.8-touchdown_center*0.45-maxf(0,touchdown_speed-float(profile.rotation_speed)*1.15)*0.7),0,100)
func get_smoothness() -> int:
	return clampi(int(100-roughness/maxf(elapsed,1)*180-stall_time),0,100)

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
