extends Node3D
class_name FighterCameraRig
## Camera weight, framing and choreography for the SPECTRE showcase.
##
## Everything in this file is FEEL. The gun fires along combat.assisted_direction()
## and the lock is computed from the airframe, so nothing here can make the jet
## harder to aim. The aircraft is allowed to drift inside a 4 deg window and no
## further, the shake is capped so a crash plus a boom plus reheat cannot stack,
## and the cockpit eye travel is clamped under the 0.12 m near plane.
var app: Node
var camera: Camera3D
var clock := 0.0
var trauma := 0.0
var yaw := 0.0
var bank := 0.0
var offset := Vector3(0,6.4,23)
var last_speed := 0.0
var acceleration := 0.0
var initialized := false

## --- feel state -------------------------------------------------------------
var noise: FastNoiseLite
## Lagged chase aim point: where the camera is looking, which is NOT the jet.
var aim := Vector3.ZERO
## Pilot head offset in eye-local metres, and its two small rotations.
var head := Vector3.ZERO
var head_pitch := 0.0
var head_yaw := 0.0
## Smoothed lift that keeps the boom off the Daly City cliffs.
var ground_lift := 0.0
## Gear oleo bounce after the mains touch.
var settle := 0.0
var settle_clock := 0.0
var results_clock := 0.0
var rollout_clock := 0.0
var burner_latch := false
var inhale := 0.0
var attributes: CameraAttributesPractical

const SHAKE_STRENGTH := 0.90 # Brief, visible feedback on confirmed kills only.
const HEAD_MOTION_STRENGTH := 0.0
const FOV_PUNCH_STRENGTH := 0.0
const SHAKE_ANGLE := 0.05585      # 3.2 deg of pitch/yaw rattle at full energy
const SHAKE_ROLL := 0.02793       # 1.6 deg of roll rattle
const SHAKE_SHIFT_CHASE := 0.42   # metres of boom translation
const SHAKE_SHIFT_COCKPIT := 0.05 # metres, well under the near plane
const SHAKE_ENERGY_CAP := 1.4
const SHAKE_RATE := 22.0          # impact/ground channel
const VIBRATION_RATE := 31.0      # burner and transonic buffet channel
const AIM_DEADZONE := 0.06981     # 4 deg: a novice never loses the jet
const AIM_LEAD := 0.10
const AIM_LEAD_MAX := 40.0
const AIM_GAIN := 5.0
const BANK_LIMIT := 0.26180       # 15 deg of camera roll into a bank
const HEAD_LIMIT := 0.11          # total eye travel, metres
const HEAD_TAU := 0.13            # a neck, not a servo
const GROUND_CLEARANCE := 3.5
const ROLLOUT_OFFSET := Vector3(-7.5,2.4,15.0)
const ROLLOUT_SETTLE := 2.5

func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.06
	camera.far = 90000 if app.route_id=="sf" else 38000
	camera.current = true
	add_child(camera)
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 20260919
	noise.frequency = 1.0

func impulse(_amount: float) -> void:pass # Recoil, terrain, boost and generic impacts do not shake the view.
func kill_impulse(amount: float = .85) -> void:trauma=minf(1,trauma+maxf(amount,0))
## The one impact in the mission the player is meant to enjoy: mains on concrete.
## Clamped at both ends so a greaser still registers and a firm arrival never hurts.
func touchdown(strength: float) -> void:
	impulse(clampf(strength,0.12,0.60))
	settle = 0.0
	settle_clock = 0.0
func reset() -> void:
	initialized = false; trauma = 0; last_speed = app.flight.speed; acceleration = 0
	aim = Vector3.ZERO; head = Vector3.ZERO; head_pitch = 0; head_yaw = 0
	ground_lift = 0; settle = 0; settle_clock = 0
	results_clock = 0; rollout_clock = 0; inhale = 0; burner_latch = false
	if is_instance_valid(camera): camera.attributes = null
func update(dt: float) -> void:
	if app.mode=="paused": return
	clock += dt
	# Two-rate decay: a thump lets go quickly, a rumble lingers.
	trauma = maxf(0,trauma-dt*(1.4+trauma*2.2))
	settle *= exp(-dt*4.0)
	settle_clock += dt
	var f: FlightDynamics = app.flight
	acceleration = lerpf(acceleration,(f.speed-last_speed)/maxf(dt,0.001),1-exp(-dt*5))
	last_speed = f.speed
	var plane_basis: Basis = Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	var ground: float = app.world.ground_height(f.position.x,f.position.z)
	var speed_norm: float = clampf((f.speed-120.0)/260.0,0,1)
	var proximity: float = (1.0-clampf((f.position.y-ground)/150.0,0,1))*speed_norm
	_update_fov(dt,f,speed_norm,proximity)
	# --- shake energy ---------------------------------------------------------
	# Transonic buffet builds from Mach 0.86, peaks near 0.98 and clears by 1.02.
	var buffet: float = clampf((f.mach-0.86)/0.12,0,1)*clampf((1.02-f.mach)/0.06,0,1)*0.55
	var vibration: float = 0.0
	var thump: float = trauma*trauma
	var raw: float = thump+vibration
	if raw>SHAKE_ENERGY_CAP:
		var cap: float = SHAKE_ENERGY_CAP/raw
		thump *= cap; vibration *= cap
	var t: float = clock*SHAKE_RATE
	var v: float = clock*VIBRATION_RATE
	var wobble := Vector3(
		noise.get_noise_2d(t,0.0)*thump+noise.get_noise_2d(v,90.0)*vibration,
		noise.get_noise_2d(t,37.0)*thump+noise.get_noise_2d(v,131.0)*vibration,
		noise.get_noise_2d(t,74.0)*thump+noise.get_noise_2d(v,172.0)*vibration)
	wobble *= SHAKE_STRENGTH
	var angular := Vector3(wobble.x*SHAKE_ANGLE,wobble.y*SHAKE_ANGLE*0.6,wobble.z*SHAKE_ROLL)
	if app.pilot_ejected and is_instance_valid(app.fighter_fx.parachute):
		app.cockpit_frame.set_presentation_visible(false)
		camera.attributes = null
		var chute: Vector3 = app.fighter_fx.parachute.global_position+Vector3(0,2,0)
		camera.position = chute+Vector3(11,5,18)
		camera.look_at(chute)
		return
	var showcase: bool = app.mode=="results" and not app.pilot_ejected
	if app.cockpit and not showcase:
		_cockpit_view(dt,f,angular,wobble*SHAKE_SHIFT_COCKPIT)
	else:
		_chase_view(dt,f,plane_basis,ground,speed_norm,angular,wobble*SHAKE_SHIFT_CHASE,showcase)
	app.cockpit_frame.set_presentation_visible(app.cockpit and not showcase)


## FOV as a transient. Base plus a signed punch off the low-passed acceleration,
## a reheat step, and a ground-rush term, opening fast and closing slowly. A short
## inhale at ignition makes the reheat kick read as a surge rather than a step.
func _update_fov(dt: float, f: FlightDynamics, speed_norm: float, proximity: float) -> void:
	var base: float = 76.0 if app.cockpit else 68.0
	if f.afterburner and not burner_latch: inhale = 1.0
	burner_latch = f.afterburner
	inhale = maxf(0.0,inhale-dt*4.0)
	var punch: float = clampf(acceleration*0.055,-3.0,9.0)
	var target: float = base+speed_norm*11.0+((7.0 if f.afterburner else 0.0)+proximity*6.0+punch-inhale*3.0)*FOV_PUNCH_STRENGTH
	target = clampf(target,base-4.0,base+14.0)
	camera.fov = lerpf(camera.fov,target,1-exp(-dt*(3.0 if target>camera.fov else 2.2)))

## Head mass. The eye is sprung against the airframe at a neck's time constant and
## the cockpit is counter-translated, so the canopy bow and the coaming no longer
## move in perfect lockstep with the view. Total travel stays under the near plane.
func _cockpit_view(dt: float, f: FlightDynamics, angular: Vector3, shift: Vector3) -> void:
	camera.near = 0.12
	camera.attributes = null
	var alpha: float = clampf(f.aoa,-0.12,0.16)
	var eye_basis: Basis = Basis.from_euler(Vector3(f.pitch+alpha,-f.heading+clampf(f.beta,-0.10,0.10),-f.roll))
	var g_excess: float = clampf(f.g_load-1.0,-2.5,5.0)
	var want_head := Vector3(
		clampf(-f.yaw_velocity*0.045,-0.045,0.045),
		clampf(-g_excess*0.011,-0.055,0.055),
		clampf(-acceleration*0.0013,-0.060,0.060))
	var blend: float = 1-exp(-dt/HEAD_TAU)
	head = head.lerp(want_head*HEAD_MOTION_STRENGTH,blend)
	head_pitch = lerpf(head_pitch,clampf(g_excess*0.008,-0.026,0.026)*HEAD_MOTION_STRENGTH,blend)
	head_yaw = lerpf(head_yaw,clampf(f.yaw_velocity*0.30,-0.038,0.038)*HEAD_MOTION_STRENGTH,blend)
	var look_basis: Basis = Basis.from_euler(Vector3(app.look.y+head_pitch,app.look.x+head_yaw,0))
	var travel: Vector3 = head+shift
	travel.x = clampf(travel.x,-HEAD_LIMIT,HEAD_LIMIT)
	travel.y = clampf(travel.y-sin(settle_clock*19.0)*settle*0.09,-HEAD_LIMIT,HEAD_LIMIT)
	travel.z = clampf(travel.z,-HEAD_LIMIT,HEAD_LIMIT)
	camera.position = f.position+eye_basis*Vector3(0,2.6,-5.0)
	camera.basis = eye_basis*look_basis*Basis.from_euler(angular)
	camera.position += camera.basis*travel
	# The frame keeps most of the airframe's own attitude: the view rattles against it.
	app.cockpit_frame.basis = (look_basis*Basis.from_euler(angular*0.7)).inverse()
	app.cockpit_frame.position = -travel

## Chase. The jet is allowed to live inside a 4 deg window instead of being pinned
## to the exact centre of the screen, the boom leads into the turn, and the ground
## floor is a spring rather than a snap.
func _chase_view(dt: float, f: FlightDynamics, plane_basis: Basis, ground: float, speed_norm: float, angular: Vector3, shift: Vector3, showcase: bool) -> void:
	camera.near = 1.0
	var truth: Vector3 = f.position+plane_basis*Vector3(0,1.9,-7)
	if not initialized:
		yaw = f.heading; bank = 0; initialized = true
		aim = truth
	var rolling: bool = f.barrel_remaining>0
	if showcase:
		# Results orbit: a slow hero pass with depth of field, for this beat only.
		results_clock += dt
		var orbit_offset := Vector3(0,5.5+sin(results_clock*0.3)*1.2,17.0)
		camera.position = f.position+Basis(Vector3.UP,results_clock*0.18)*orbit_offset
		bank = lerpf(bank,0.0,1-exp(-dt*3))
		aim = aim.lerp(f.position+Vector3(0,1.2,0),1-exp(-dt*6))
	else:
		results_clock = 0
		camera.attributes = null
		# Yaw LEAD, not lag: the boom swings to the inside of the turn.
		yaw = lerp_angle(yaw,f.heading+clampf(f.yaw_velocity*0.55,-0.5,0.5),1-exp(-dt*7))
		# barrel_angle is unwrapped, so the roll never reverses at the +-PI seam.
		var want_bank: float = -f.barrel_angle*0.82 if rolling else clampf(-f.roll*0.30-f.roll_velocity*0.10,-BANK_LIMIT,BANK_LIMIT)
		var desired := Vector3(-app.control.x*0.8,5.2+speed_norm*1.0,22.0+speed_norm*4+clampf(acceleration*0.035,-0.4,0.8))
		if app.mode=="rollout":
			rollout_clock += dt
			var settled: float = clampf(rollout_clock/ROLLOUT_SETTLE,0,1)
			desired = desired.lerp(ROLLOUT_OFFSET,settled)
			want_bank = lerpf(want_bank,0.0,settled)
		else:
			rollout_clock = 0
		bank = lerpf(bank,want_bank,1-exp(-dt*(9.0 if rolling else 4.0)))
		if not rolling: bank = wrapf(bank,-PI,PI)
		offset = offset.lerp(desired,1-exp(-dt*6))
		var orbit: Vector3 = Basis(Vector3.UP,app.look.x)*offset
		orbit.y += app.look.y*6
		camera.position = f.position+Basis(Vector3.UP,-yaw)*orbit
		var want_aim: Vector3 = truth+f.velocity.limit_length(AIM_LEAD_MAX/maxf(AIM_LEAD,0.001))*AIM_LEAD
		aim = aim.lerp(want_aim,1-exp(-dt*AIM_GAIN))
	# A spring, not a snap: the boom stops popping over the cliffs and the headlands.
	var lift: float = maxf(0.0,(ground+GROUND_CLEARANCE)-camera.position.y)
	ground_lift = lerpf(ground_lift,lift,1-exp(-dt*(9.0 if lift>ground_lift else 3.0)))
	camera.position.y = maxf(camera.position.y+ground_lift,ground+1.2)
	camera.position.y -= sin(settle_clock*19.0)*settle*0.55
	_look(truth)
	camera.rotate_object_local(Vector3.FORWARD,bank)
	camera.basis *= Basis.from_euler(angular)
	camera.position += camera.basis*shift
	if showcase: _apply_results_dof(f)

## Point at the lagged aim, but never let the jet leave a 4 deg cone around the
## truth: the aircraft moves in frame, it never leaves it.
func _look(truth: Vector3) -> void:
	var to_truth: Vector3 = truth-camera.position
	var to_aim: Vector3 = aim-camera.position
	var span: float = to_truth.length()
	if span<0.05 or to_aim.length()<0.05 or not to_aim.is_finite():
		camera.look_at(truth if span>0.05 else camera.position+camera.basis*Vector3(0,0,-10))
		return
	var dir_truth: Vector3 = to_truth/span
	var dir_aim: Vector3 = to_aim.normalized()
	var err: float = dir_truth.angle_to(dir_aim)
	if err>AIM_DEADZONE and err>0.0001:
		dir_aim = dir_truth.slerp(dir_aim,AIM_DEADZONE/err)
	var point: Vector3 = camera.position+dir_aim*span
	if absf(dir_aim.dot(Vector3.UP))>0.995: camera.look_at(point,Vector3.FORWARD)
	else: camera.look_at(point)

## Depth of field for the results orbit only, recomputed from the live distance so
## the jet itself always stays sharp. Cleared on every other mode by camera.attributes = null.
func _apply_results_dof(f: FlightDynamics) -> void:
	if attributes==null:
		attributes = CameraAttributesPractical.new()
		attributes.dof_blur_far_enabled = true
		attributes.dof_blur_amount = 0.07
	var span: float = camera.position.distance_to(f.position)
	attributes.dof_blur_far_distance = span+26.0
	attributes.dof_blur_far_transition = maxf(span*0.6,12.0)
	if camera.attributes!=attributes: camera.attributes = attributes
