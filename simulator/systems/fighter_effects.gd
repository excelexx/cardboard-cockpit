extends Node3D
class_name FighterEffects
const Utils = preload("res://systems/model_utils.gd")
var app: Node
var exhaust: MeshInstance3D
var exhaust_material: ShaderMaterial
var haze: MeshInstance3D
var haze_material: ShaderMaterial
var exhaust_light: OmniLight3D
var condensation: Array[Sprite3D] = []
var trails: Array[MeshInstance3D] = []
var trail_points: Array[Array] = [[],[]]
var particles: Array[Dictionary] = []
var stores: Array[Node3D] = []
var parachute: Node3D
var chute_clock := 0.0
var sonic_armed := true
var clock := 0.0
var last_store := 0
func build() -> void:
	for store: Node3D in stores:
		if is_instance_valid(store): store.queue_free()
	for child: Node in get_children(): child.queue_free()
	condensation.clear(); trails.clear(); stores.clear(); particles.clear(); trail_points = [[],[]]
	var shape := CylinderMesh.new()
	shape.top_radius = 0.42
	shape.bottom_radius = 0.08
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
	exhaust_light.light_color = Color(0.25,0.45,1)
	exhaust_light.omni_range = 8
	exhaust_light.shadow_enabled = false
	add_child(exhaust_light)
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
	for i in range(4):
		var store: Node3D = load("res://assets/weapons/seeker.glb").instantiate()
		store.rotation.x = -PI/2
		var bounds: AABB = Utils.bounds(store)
		var factor: float = 3.0/maxf(bounds.size.z,0.01)
		store.scale = Vector3.ONE*factor
		store.position = -bounds.get_center()*factor
		var mount := Node3D.new()
		mount.add_child(store)
		app.aircraft.add_child(mount)
		mount.position = Vector3((-1 if i<2 else 1)*(2.7+(i%2)*1.05),-0.5,0.5)
		stores.append(mount)
func missile_launch(side: float) -> void:
	last_store += 1
	if last_store>4:
		var index: int = mini(last_store-5,stores.size()-1)
		if index>=0 and is_instance_valid(stores[index]): stores[index].visible = false
func update(dt: float) -> void:
	clock += dt
	var f: FlightDynamics = app.flight
	var basis := Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	var power: float = clampf(f.engine if f.afterburner else 0.0,0,1)
	exhaust.visible = f.afterburner and f.engine>0.3
	exhaust.position = f.position+basis*Vector3(0,0.05,9.1+power*1.8)
	exhaust.basis = basis*Basis(Vector3.RIGHT,PI/2)
	exhaust.scale = Vector3(1+power*0.35,0.3+power*1.3,1+power*0.35)
	exhaust_material.set_shader_parameter("power",power)
	exhaust_light.position = f.position+basis*Vector3(0,0,7.2)
	exhaust_light.light_energy = power*3.0
	haze.position = f.position+basis*Vector3(0,0,10)
	haze.look_at(app.camera.global_position)
	haze_material.set_shader_parameter("power",maxf(power,f.engine*0.35))
	haze.visible = not app.cockpit and f.engine>0.35
	var vapor_strength: float = clampf((f.g_load-2.0)/5,0,0.30)*clampf((f.speed-120)/120,0,1)
	for i in range(2):
		var side: float = -1 if i==0 else 1
		condensation[i].position = f.position+basis*Vector3(side*3.4,0.15,0.4)
		condensation[i].modulate.a = vapor_strength
		update_trail(i,f.position+basis*Vector3(side*5.7,0.2,1.3),dt,clampf((f.g_load-1.5)/4,0,0.4) if f.airborne else 0.0)
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
	clock = 0; sonic_armed = true; last_store = 0
	for store: Node3D in stores:
		if is_instance_valid(store): store.visible = true
	for item: Dictionary in particles:
		if is_instance_valid(item.node): item.node.queue_free()
	particles.clear(); trail_points = [[],[]]
	if is_instance_valid(parachute): parachute.queue_free()
	parachute = null
	for trail: MeshInstance3D in trails: trail.mesh.clear_surfaces()
