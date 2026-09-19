extends RefCounted
class_name FlightDynamics
const Tune = preload("res://data/balance.gd")
## Fictional fly-by-wire dynamics: filtered angular rates, momentum and energy.
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

func reset(aircraft: Dictionary) -> void:
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
		roll_velocity = lerpf(roll_velocity,controls.x*float(profile.roll_rate)*handling,1-exp(-dt*Tune.ROLL_RESPONSE))
		pitch_velocity = lerpf(pitch_velocity,controls.y*float(profile.pitch_rate)*authority*handling,1-exp(-dt*Tune.PITCH_RESPONSE))
		var rolling: bool = barrel_remaining>0
		if rolling:
			barrel_remaining = maxf(0,barrel_remaining-dt)
			roll = wrapf(barrel_start+barrel_direction*TAU*smoothstep(0,1,1-barrel_remaining/BARREL_DURATION),-PI,PI)
			if barrel_remaining==0: roll = barrel_start
		else:
			roll = wrapf(roll+roll_velocity*dt,-PI,PI)
		pitch = clampf(pitch+pitch_velocity*dt,-1.10,1.20)
		var coordinated: float = sin(roll)*Tune.BANK_TURN_FORCE/maxf(speed,55.0)
		var desired_yaw: float = coordinated+controls.z*Tune.YAW_RATE*handling
		yaw_velocity = lerpf(yaw_velocity,0.0 if rolling else desired_yaw,1-exp(-dt*Tune.YAW_RESPONSE))
		heading = wrapf(heading+yaw_velocity*dt,-PI,PI)
		var lift: float = clampf(speed/(effective_rotation_speed()*0.82),0,1)
		var sink: float = (1-lift)*28.0+(1-maxf(cos(roll),0.0))*6.0
		var desired_vertical: float = sin(pitch)*speed-sink
		if airborne_time<5 and position.y-ground<25: desired_vertical = maxf(desired_vertical,2)
		vertical_speed = lerpf(vertical_speed,desired_vertical,1-exp(-dt*Tune.VERTICAL_RESPONSE))
		var horizontal := Vector3(sin(heading),0,-cos(heading))*speed*cos(pitch)+wind
		if velocity.length()<0.01 and speed>1: velocity = Vector3(horizontal.x,vertical_speed,horizontal.z)
		velocity.x = lerpf(velocity.x,horizontal.x,1-exp(-dt*Tune.VELOCITY_RESPONSE))
		velocity.z = lerpf(velocity.z,horizontal.z,1-exp(-dt*Tune.VELOCITY_RESPONSE))
		velocity.y = vertical_speed
		position += velocity*dt
		airborne_time += dt
		stall_time = stall_time+dt if lift<0.85 else 0
		roughness += (absf(controls.x)*0.15+absf(controls.y)*0.10)*dt
		var acceleration: float = (velocity-previous_velocity).length()/maxf(dt,0.001)
		g_load = lerpf(g_load,clampf(1+acceleration/9.81,0.2,9.0),1-exp(-dt*3))
	else:
		heading = wrapf(heading+controls.z*0.38*clampf(speed/20,0,1)*dt,-PI,PI)
		pitch = move_toward(pitch,maxf(controls.y,0)*0.14,dt*0.13)
		roll = 0; vertical_speed = 0; g_load = 1
		position.y = ground+float(profile.clearance)
		velocity = Vector3(sin(heading),0,-cos(heading))*speed
		position += velocity*dt
		if speed>=effective_rotation_speed() and controls.y>0.12:
			airborne = true; ever_airborne = true
			vertical_speed = 4; position.y += 0.12
	distance += speed*dt

func resolve_contact(ground: float, runway: bool) -> void:
	if contact!="": return
	if airborne and position.y<=ground+float(profile.clearance):
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
	heading += clampf(steering,-1,1)*0.11*clampf(speed/20,0,1)*dt
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
