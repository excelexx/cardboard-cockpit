extends Node3D
class_name FighterCameraRig
var app: Node
var camera: Camera3D
var pip_viewport: SubViewport
var pip_camera: Camera3D
var clock := 0.0
var trauma := 0.0
var yaw := 0.0
var pitch := 0.0
var bank := 0.0
var offset := Vector3(0,6.4,23)
var last_speed := 0.0
var acceleration := 0.0
var initialized := false
var missile_link := false
var missile_requested := false
var pip_texture: Texture2D
func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.06
	camera.far = 90000 if app.route_id=="sf" else 38000
	camera.current = true
	add_child(camera)
	pip_viewport = SubViewport.new()
	pip_viewport.size = Vector2i(480,270)
	pip_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	pip_viewport.world_3d = app.get_world_3d()
	add_child(pip_viewport)
	pip_camera = Camera3D.new()
	pip_camera.current = true
	pip_camera.fov = 78
	pip_camera.near = 0.2
	pip_camera.far = 14000
	pip_viewport.add_child(pip_camera)
	pip_texture = pip_viewport.get_texture()
func impulse(amount: float) -> void: trauma = minf(1,trauma+amount)
func reset() -> void:
	initialized = false; trauma = 0; last_speed = app.flight.speed; acceleration = 0
	missile_link = false; missile_requested = false
	if is_instance_valid(pip_viewport): pip_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
func update(dt: float) -> void:
	if app.mode=="paused": return
	clock += dt
	trauma = maxf(0,trauma-dt*2.1)
	var f: FlightDynamics = app.flight
	acceleration = lerpf(acceleration,(f.speed-last_speed)/maxf(dt,0.001),1-exp(-dt*5))
	last_speed = f.speed
	var plane_basis: Basis = Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	var speed_fraction: float = clampf((f.speed-130)/300,0,1)
	var fov: float = (76.0 if app.cockpit else 68.0)+speed_fraction*16+(3 if f.afterburner else 0)
	camera.fov = lerpf(camera.fov,fov,1-exp(-dt*3))
	var ground: float = app.world.ground_height(f.position.x,f.position.z)
	var proximity: float = (1-clampf((f.position.y-ground)/150,0,1))*speed_fraction
	var shake: float = trauma*trauma*0.006+proximity*0.0012
	shake += f.wind.length()*.00009*clampf(f.speed/220,0,1)
	var angular := Vector3(sin(clock*37)*shake,sin(clock*43+0.4)*shake*0.55,sin(clock*31)*shake*0.45)
	if app.pilot_ejected and is_instance_valid(app.fighter_fx.parachute):
		app.cockpit_frame.set_presentation_visible(false)
		var target: Vector3 = app.fighter_fx.parachute.global_position+Vector3(0,2,0)
		camera.position = target+Vector3(11,5,18)
		camera.look_at(target)
		return
	if app.cockpit:
		camera.near = 0.12
		camera.position = f.position+plane_basis*Vector3(0,2.6,-5.0)
		var look_basis := Basis.from_euler(Vector3(app.look.y,app.look.x,0))
		camera.basis = plane_basis*look_basis*Basis.from_euler(angular)
		app.cockpit_frame.basis = look_basis.inverse()
	else:
		camera.near = 1.0
		if not initialized:
			yaw = f.heading; pitch = f.pitch; bank = 0; initialized = true
		yaw = lerp_angle(yaw,f.heading,1-exp(-dt*8))
		pitch = lerp_angle(pitch,f.pitch,1-exp(-dt*10))
		bank = lerpf(bank,(-f.roll*.82 if f.barrel_remaining>0 else clampf(-f.roll*.10,-.12,.12)),1-exp(-dt*4))
		var desired := Vector3(-app.control.x*0.8,6.1+speed_fraction*1.1,22.0+speed_fraction*4+clampf(acceleration*0.035,-0.4,0.8))
		offset = offset.lerp(desired,1-exp(-dt*6))
		var orbit: Vector3 = Basis(Vector3.UP,app.look.x)*offset
		orbit.y += app.look.y*6
		# Follow the aircraft's pitch as well as heading, keeping the chase
		# offset behind its nose direction through climbs and dives.
		var chase_basis := Basis.from_euler(Vector3(pitch,-yaw,0))
		camera.position = f.position+chase_basis*orbit
		camera.position.y = maxf(camera.position.y,ground+2.5)
		var target: Vector3 = f.position+plane_basis*Vector3(0,1.0,-7)
		camera.look_at(target)
		camera.rotate_object_local(Vector3.FORWARD,bank)
		camera.basis *= Basis.from_euler(angular)
	app.cockpit_frame.set_presentation_visible(app.cockpit)
	missile_link = missile_requested and is_instance_valid(app.combat.last_missile) and app.mode=="flight"
	pip_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if missile_link else SubViewport.UPDATE_DISABLED
	if missile_link:
		var missile: Node3D = app.combat.last_missile
		pip_camera.position = missile.global_position+missile.global_basis*Vector3(1,1.0,7)
		pip_camera.look_at(missile.global_position-missile.global_basis.z*35)

func _exit_tree() -> void:
	if is_instance_valid(pip_viewport): pip_viewport.world_3d = null
