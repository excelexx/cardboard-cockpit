extends Node3D
class_name FighterEffects
const WeaponArt = preload("res://systems/weapon_visuals.gd")
const Fighter = preload("res://systems/fighter_model.gd")
const Utils = preload("res://systems/model_utils.gd")
var app: Node
var exhaust: MeshInstance3D
var exhaust_material: ShaderMaterial
var haze: MeshInstance3D
var haze_material: ShaderMaterial
var exhaust_light: OmniLight3D
var airframe_fill: OmniLight3D
var condensation: Array[Sprite3D] = []
var trails: Array[MeshInstance3D] = []
var trail_points: Array[Array] = [[],[]]
var particles: Array[Dictionary] = []
var stores: Array[Node3D] = []
var parachute: Node3D
var chute_clock := 0.0
var sonic_armed := true
var clock := 0.0
var gun_gimbal: Node3D
var gun_rotor: Node3D
var gun_muzzle: Node3D
var gun_flash: Node3D
var gun_light: OmniLight3D
var rotor_speed := 0.0
var last_store := 0
var store_timers: Array[float] = [0,0,0,0]
var wind_field: MeshInstance3D
var wind_points: Array[Vector3] = []
var wind_rng := RandomNumberGenerator.new()
func build() -> void:
	for store: Node3D in stores:
		if is_instance_valid(store): store.queue_free()
	for child: Node in get_children(): child.queue_free()
	gun_gimbal = app.aircraft.find_child("GunGimbal",true,false)
	gun_rotor = app.aircraft.find_child("GatlingRotor",true,false)
	gun_muzzle = app.aircraft.find_child("GunMuzzle",true,false)
	gun_flash = Node3D.new(); add_child(gun_flash)
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash_material.albedo_texture = load("res://assets/vfx/gatling-flash.png")
	for angle in [0.0,PI/2]:
		var plane := MeshInstance3D.new(); var quad := QuadMesh.new(); quad.size = Vector2(2.1,.64)
		plane.mesh = quad; plane.material_override = flash_material
		plane.basis = Basis(Vector3.BACK,angle)*Basis(Vector3.UP,PI/2)
		plane.position.z = -1.02; plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gun_flash.add_child(plane)
	gun_light = OmniLight3D.new(); gun_light.light_color = Color(1,.62,.20)
	gun_light.omni_range = 5; gun_light.shadow_enabled = false; add_child(gun_light)
	condensation.clear(); trails.clear(); stores.clear(); particles.clear(); trail_points = [[],[]]
	var shape := CylinderMesh.new()
	shape.top_radius = 0.035
	shape.bottom_radius = 0.48
	shape.height = 4
	shape.radial_segments = 32
	exhaust = MeshInstance3D.new()
	exhaust.mesh = shape
	exhaust_material = ShaderMaterial.new()
	exhaust_material.shader = load("res://assets/vfx/exhaust.gdshader")
	exhaust.material_override = exhaust_material
	exhaust.rotation.x = PI/2
	add_child(exhaust)
	exhaust_light = OmniLight3D.new()
	exhaust_light.light_color = Color(1,.50,.22)
	exhaust_light.omni_range = 8
	exhaust_light.shadow_enabled = false
	add_child(exhaust_light)
	airframe_fill = OmniLight3D.new()
	airframe_fill.light_cull_mask = 2
	airframe_fill.light_color = Color(.73,.84,1.0)
	airframe_fill.light_energy = 1.2
	airframe_fill.omni_range = 24
	airframe_fill.omni_attenuation = .6
	airframe_fill.shadow_enabled = false
	add_child(airframe_fill)
	haze = MeshInstance3D.new()
	var quad := QuadMesh.new(); quad.size = Vector2(3.5,8)
	haze.mesh = quad
	haze_material = ShaderMaterial.new()
	haze_material.shader = load("res://assets/vfx/heat_haze.gdshader")
	haze.material_override = haze_material
	add_child(haze)
	for side in [-1,1]:
		var vapor := Sprite3D.new()
		vapor.texture = load("res://assets/vfx/smoke.png")
		vapor.pixel_size = 0.010
		vapor.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		vapor.modulate = Color(0.87,0.94,1,0)
		add_child(vapor); condensation.append(vapor)
		var trail := MeshInstance3D.new(); trail.mesh = ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = load("res://assets/vfx/smoke.png")
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail.material_override = material
		trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(trail); trails.append(trail)
	wind_rng.seed = 202609
	wind_field = MeshInstance3D.new(); wind_field.mesh = ImmediateMesh.new()
	var wind_material := StandardMaterial3D.new()
	wind_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wind_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wind_material.albedo_texture = load("res://assets/vfx/smoke.png")
	wind_material.vertex_color_use_as_albedo = true
	wind_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	wind_field.material_override = wind_material
	wind_field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wind_field)
	for i in range(28):
		wind_points.append(Vector3(wind_rng.randf_range(-24,24),wind_rng.randf_range(-18,18),wind_rng.randf_range(-45,24)))
	for i in range(4):
		var store: Node3D = WeaponArt.missile()
		for geometry: Node in store.find_children("*","GeometryInstance3D",true,false): geometry.layers = 2
		var mount := Node3D.new()
		mount.add_child(store)
		app.aircraft.add_child(mount)
		mount.position = Vector3((-1 if i<2 else 1)*(2.8+(i%2)*1.25),-1.14,2.85)
		stores.append(mount)
func missile_launch(_side: float, index: int = -1) -> void:
	last_store += 1
	if index>=0 and index<stores.size():
		store_timers[index] = .85; stores[index].visible = false
func update(dt: float) -> void:
	clock += dt
	update_gun(dt)
	for i in range(stores.size()):
		store_timers[i] = maxf(0,store_timers[i]-dt)
		stores[i].visible = store_timers[i]<.22
		for geometry: Node in stores[i].find_children("*","GeometryInstance3D",true,false): geometry.transparency = clampf(store_timers[i]/.22,0,1)
	var f: FlightDynamics = app.flight
	var basis := Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	airframe_fill.position = f.position+basis*Vector3(0,6,-2)
	airframe_fill.visible = not app.cockpit
	update_wind(dt,basis)
	var power: float = clampf(f.engine if f.afterburner else 0.0,0,1)
	exhaust.visible = f.afterburner and f.engine>0.3
	exhaust.position = f.position+basis*(Fighter.NOZZLE+Vector3(0,0,2*(0.15+power*.72)))
	exhaust.basis = basis*Basis(Vector3.RIGHT,PI/2)
	exhaust.scale = Vector3(1+power*0.35,0.15+power*.72,1+power*0.35)
	exhaust_material.set_shader_parameter("power",power)
	exhaust_light.position = f.position+basis*Fighter.NOZZLE
	exhaust_light.light_energy = power*3.0
	haze.position = f.position+basis*(Fighter.NOZZLE+Vector3(0,0,3))
	haze.look_at(app.camera.global_position)
	haze_material.set_shader_parameter("power",maxf(power,f.engine*0.35))
	haze.visible = not app.cockpit and f.engine>0.35
	var vapor_strength: float = clampf((f.g_load-2.0)/5,0,0.30)*clampf((f.speed-120)/120,0,1)
	for i in range(2):
		var side: float = -1 if i==0 else 1
		condensation[i].position = f.position+basis*Vector3(side*3.4,-0.18,1.5)
		condensation[i].modulate.a = vapor_strength
		update_trail(i,f.position+basis*Vector3(side*5.73,-0.47,3.55),dt,clampf((f.g_load-1.5)/4,0,0.4) if f.airborne else 0.0)
	if f.speed>335 and sonic_armed:
		sonic_armed = false
		app.audio.play_effect("sonic",-12)
		app.camera_rig.impulse(0.23)
	if f.speed<305: sonic_armed = true
	for i in range(particles.size()-1,-1,-1):
		var item: Dictionary = particles[i]
		item.life -= dt
		if item.life<=0:
			item.node.queue_free(); particles.remove_at(i)
		else:
			item.velocity.y -= dt*8
			item.node.position += item.velocity*dt
			item.node.rotation += item.spin*dt
			item.node.transparency = clampf(1-item.life,0,1)
func update_trail(index: int, at: Vector3, dt: float, strength: float) -> void:
	var points: Array = trail_points[index]
	for point: Dictionary in points: point.life -= dt
	while not points.is_empty() and points[0].life<=0: points.pop_front()
	if strength>0.03 and (points.is_empty() or Vector3(points.back().position).distance_to(at)>5): points.append({"position":at,"life":3.0,"alpha":strength})
	if points.size()>100: points.pop_front()
	var mesh: ImmediateMesh = trails[index].mesh
	mesh.clear_surfaces()
	if points.size()<2: return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()-1):
		var a: Vector3 = points[i].position; var b: Vector3 = points[i+1].position
		var side: Vector3 = (b-a).normalized().cross((app.camera.position-a).normalized()).normalized()*lerpf(0.65,0.07,float(i)/points.size())
		var alpha: float = float(points[i].alpha)*clampf(float(points[i].life)/3,0,1)
		for vertex: Array in [[a-side,Vector2(0,0)],[a+side,Vector2(1,0)],[b-side,Vector2(0,1)],[b-side,Vector2(0,1)],[a+side,Vector2(1,0)],[b+side,Vector2(1,1)]]:
			mesh.surface_set_color(Color(0.8,0.87,0.95,alpha*0.55))
			mesh.surface_set_uv(vertex[1])
			mesh.surface_add_vertex(vertex[0])
	mesh.surface_end()
func debris(at: Vector3) -> void:
	for i in range(12):
		var node := MeshInstance3D.new()
		var shape := BoxMesh.new(); shape.size = Vector3(0.18,0.06,1.1)
		node.mesh = shape
		node.material_override = Utils.material(Color(0.23,0.23,0.18) if i%2 else Color(0.72,0.74,0.68),0.05,0.8)
		node.position = at
		add_child(node)
		particles.append({"node":node,"velocity":Vector3(randf_range(-24,24),randf_range(-4,20),randf_range(-24,24)),"spin":Vector3(randf_range(-5,5),randf_range(-5,5),randf_range(-5,5)),"life":randf_range(1.3,2.5)})
func begin_ejection() -> void:
	parachute = Node3D.new(); add_child(parachute); chute_clock = 0
	parachute.position = app.flight.position+Vector3(0,5,0)
	var canopy := MeshInstance3D.new()
	var shape := SphereMesh.new(); shape.radius = 3.8; shape.height = 2
	canopy.mesh = shape; canopy.material_override = Utils.material(Color(0.82,0.85,0.78),0,0.85)
	canopy.position.y = 5
	parachute.add_child(canopy)
	var pilot := CapsuleMesh.new(); pilot.radius = 0.25; pilot.height = 1.8
	var body := MeshInstance3D.new(); body.mesh = pilot; body.material_override = Utils.material(Color(0.18,0.24,0.18),0,0.8)
	parachute.add_child(body)
	for side in [-1,1]: Utils.box(parachute,Vector3(0.02,4.5,0.02),Vector3(side*0.8,2.7,0),Utils.material(Color(0.8,0.82,0.75),0,0.7))
func tick_ejection(dt: float) -> void:
	chute_clock += dt
	parachute.position += Vector3(0,8 if chute_clock<0.7 else -4,-2)*dt
	parachute.scale = Vector3.ONE*clampf(chute_clock/0.7,0.1,1)

func reset() -> void:
	rotor_speed = 0
	if is_instance_valid(gun_flash): gun_flash.visible = false
	if is_instance_valid(gun_light): gun_light.visible = false
	clock = 0; sonic_armed = true; last_store = 0; store_timers = [0,0,0,0]
	for store: Node3D in stores:
		if is_instance_valid(store): store.visible = true
	for item: Dictionary in particles:
		if is_instance_valid(item.node): item.node.queue_free()
	particles.clear(); trail_points = [[],[]]
	if is_instance_valid(parachute): parachute.queue_free()
	parachute = null
	for trail: MeshInstance3D in trails: trail.mesh.clear_surfaces()

func update_wind(dt: float, basis: Basis) -> void:
	if not is_instance_valid(wind_field): return
	var mesh: ImmediateMesh = wind_field.mesh
	mesh.clear_surfaces()
	var strength: float = clampf((app.flight.speed-125)/250,0,.85)
	if strength<.01 or not app.flight.airborne: return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(wind_points.size()):
		var local: Vector3 = wind_points[i]
		local.z += app.flight.speed*dt*.55
		if local.z>25:
			local = Vector3(wind_rng.randf_range(-24,24),wind_rng.randf_range(-18,18),-45)
		wind_points[i] = local
		if absf(local.x)<6 and absf(local.y)<7: continue
		var a: Vector3 = app.flight.position+basis*local
		var b: Vector3 = a+basis.z*clampf(app.flight.speed*.016,2,7)
		var view: Vector3 = app.camera.global_position-a
		if view.length()<4: continue
		var side: Vector3 = (b-a).normalized().cross(view.normalized()).normalized()*.11
		var alpha: float = strength*.14*clampf((25-local.z)/15,0,1)*clampf((local.z+45)/12,0,1)
		for vertex: Array in [[a-side,Vector2(0,0)],[a+side,Vector2(1,0)],[b-side,Vector2(0,1)],[b-side,Vector2(0,1)],[a+side,Vector2(1,0)],[b+side,Vector2(1,1)]]:
			mesh.surface_set_color(Color(.86,.93,1,alpha)); mesh.surface_set_uv(vertex[1]); mesh.surface_add_vertex(vertex[0])
	mesh.surface_end()

func gun_muzzle_position(fallback: Vector3) -> Vector3:
	return gun_muzzle.global_position if is_instance_valid(gun_muzzle) else fallback

func update_gun(dt: float) -> void:
	var firing: bool = app.combat.active and app.combat.gun_firing_time>0 and app.mode=="flight"
	rotor_speed = move_toward(rotor_speed,62.0 if firing else 0.0,dt*(480 if firing else 110))
	if is_instance_valid(gun_gimbal):
		var wanted: Vector3 = app.combat.assisted_direction() if app.combat.active else app.flight.forward()
		gun_gimbal.look_at(gun_gimbal.global_position+wanted*100,Vector3.UP)
	if is_instance_valid(gun_rotor): gun_rotor.rotate_z(rotor_speed*dt)
	gun_flash.visible = firing and not app.cockpit
	gun_light.visible = firing
	if is_instance_valid(gun_muzzle):
		gun_flash.global_transform = gun_muzzle.global_transform.orthonormalized()
		gun_flash.scale = Vector3.ONE*(.78+.22*sin(clock*137))
		gun_light.global_position = gun_muzzle.global_position
	gun_light.light_energy = (1.5+sin(clock*137)*.5) if firing else 0.0
