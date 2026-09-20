extends Node3D
## Bounded, world-space detonation; combat owns damage and calls this only once.
## No process callback: the owner advances all blasts with its gameplay clock.
const Impact = preload("res://systems/impact_fx.gd")
const DURATION := 3.2
const MAX_RADIUS := 180.0
static var _spark_mesh: Mesh
static var _orbit_mesh: Mesh
static var _ring_mesh: SphereMesh
static var _puff_mesh: QuadMesh
static var _debris_mesh: PrismMesh
var elapsed := 0.0
var radius := 120.0
var parts: Array[Dictionary] = []
var shockwaves: Array[Dictionary] = []
var clouds: Array[Dictionary] = []
var fragments: Array[Dictionary] = []
var light: OmniLight3D
var alive := true

func configure(blast_radius: float) -> void:
	radius = clampf(blast_radius, 8.0, MAX_RADIUS)
	name = "MissileAreaBlast"
	var size: float = radius / 120.0
	var random := RandomNumberGenerator.new()
	random.seed = 260920
	# A very short bright nucleus, not a screen-filling white overlay.
	var core := _shader("res://assets/vfx/impact_bloom.gdshader", {
		"mode": 0, "size": 18.0 * size, "grow": 1.65, "intensity": 2.8,
		"core_colour": Color(1,.98,.87), "edge_colour": Color(1,.22,.035), "spokes": 8.0})
	_part("IgnitionCore", _quad(), core, 0.0, 0.18)
	# Dense fire remains briefly under the smoke after the nucleus extinguishes.
	var heart := _shader("res://assets/vfx/impact_bloom.gdshader", {
		"mode": 2, "size": 27.0 * size, "grow": 1.8, "intensity": 0.75,
		"core_colour": Color(1,.75,.30), "edge_colour": Color(1,.07,.015)})
	_part("FireHeart", _quad(), heart, 0.035, 0.70)
	if _ring_mesh == null:
		_ring_mesh = SphereMesh.new()
		_ring_mesh.radius = 1.0; _ring_mesh.height = 2.0
		_ring_mesh.radial_segments = 64; _ring_mesh.rings = 32
	for index in range(2):
		var material := _shader("res://systems/missile_blast_shock.gdshader", {
			"tint": Color(1,.25,.03) if index == 0 else Color(.04,.48,1),
			"intensity": 1.45 if index == 0 else 0.85})
		var ring := _mesh("PressureRing%d" % index, _ring_mesh, material)
		ring.custom_aabb = AABB(Vector3.ONE * -1.2, Vector3.ONE * 2.4)
		ring.rotation = Vector3(1.05 if index == 0 else -0.52, 0.25, 0.18 if index == 0 else 0.63)
		shockwaves.append({"node": ring, "material": material, "index": index})
	# Reuse cached authored geometry builders: one draw call for every ember,
	# and one for the electric shock crawling around the expanding fireball.
	if _spark_mesh == null:
		_spark_mesh = Impact._spray_mesh(92026, 64, PI, Vector2(70,230), Vector2(.35,1.0), 1.0)
	if _orbit_mesh == null: _orbit_mesh = Impact._arc_mesh(2619, 7, 23.0, 18)
	var sparks := _shader("res://assets/vfx/impact_spark.gdshader", {
		"drag": 1.65, "gravity": Vector3(0,-35,0), "streak": .065,
		"intensity": 1.5, "min_width": .00065, "min_length": .003,
		"hot_colour": Color(1,.95,.7), "mid_colour": Color(1,.31,.025), "cool_colour": Color(.45,.018,.004)})
	_part("BallisticEmbers", _spark_mesh, sparks, .025, 2.25).scale = Vector3.ONE * size
	var orbit := _shader("res://assets/vfx/impact_arc.gdshader", {
		"width": .50 * size, "min_width": .0005, "intensity": .6,
		"tint": Color(.10,.65,1), "hot": Color(.65,.90,1), "expand": 1.15, "strikes": 2.0})
	_part("IonizedShock", _orbit_mesh, orbit, .025, .85).scale = Vector3.ONE * size
	# Independent puffs occupy a volume rather than one huge photographic card.
	# Their shader edges dissolve to zero, preventing a square smoke outline.
	for index in range(10):
		var direction := Vector3(random.randfn(), random.randfn() * .7, random.randfn()).normalized()
		var velocity: Vector3 = direction * random.randf_range(17,38) * size
		var material := _shader("res://systems/missile_blast.gdshader", {
			"size": random.randf_range(17,25) * size, "seed": float(index) * 4.71,
			"opacity": .64, "warmth": random.randf_range(.7,1.0)})
		var puff := _part("FireSmoke%d" % index, _quad(), material, .035 + index * .008, DURATION - index * .035)
		clouds.append({"node": puff, "origin": direction * random.randf_range(4,11) * size, "velocity": velocity})
	if _debris_mesh == null:
		_debris_mesh = PrismMesh.new(); _debris_mesh.size = Vector3(.7,.9,2.0)
	for index in range(8):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(.07,.055,.042); material.metallic = .5; material.roughness = .75
		var node := _mesh("WarheadFragment%d" % index, _debris_mesh, material)
		node.scale = Vector3.ONE * size * random.randf_range(.7,1.5)
		fragments.append({"node": node, "velocity": Vector3(random.randf_range(-50,50),random.randf_range(-10,55),random.randf_range(-50,50))*size,
			"spin": Vector3(random.randf_range(-8,8),random.randf_range(-8,8),random.randf_range(-8,8))})
	light = OmniLight3D.new()
	light.name = "BlastLight"; light.shadow_enabled = false
	light.light_color = Color(1,.42,.12); light.omni_range = radius * 1.2
	light.omni_attenuation = 1.8
	add_child(light)
	advance(0.0)

func _shader(path: String, values: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new(); material.shader = load(path)
	for key: String in values: material.set_shader_parameter(key, values[key])
	return material

func _quad() -> QuadMesh:
	if _puff_mesh == null:
		_puff_mesh = QuadMesh.new(); _puff_mesh.size = Vector2(2,2)
	return _puff_mesh

func _mesh(label: String, geometry: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label; node.mesh = geometry; node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3.ONE * -MAX_RADIUS * 1.5, Vector3.ONE * MAX_RADIUS * 3.0)
	add_child(node)
	return node

func _part(label: String, geometry: Mesh, material: ShaderMaterial, start: float, end: float) -> MeshInstance3D:
	var node := _mesh(label, geometry, material)
	parts.append({"node": node, "material": material, "start": start, "end": end})
	return node

## Returns false after cleanup is due. Negative/nonfinite steps never rewind VFX.
func advance(dt: float) -> bool:
	if not alive: return false
	if is_finite(dt) and dt > 0: elapsed += dt
	if elapsed >= DURATION:
		alive = false; visible = false
		light.visible = false
		return false
	for part in parts:
		part.node.visible = elapsed >= part.start and elapsed < part.end
		part.material.set_shader_parameter("t", clampf((elapsed-part.start)/(part.end-part.start),0,1))
	for wave in shockwaves:
		var age: float = elapsed - float(wave.index) * .055
		var progress: float = clampf(age / .90,0,1)
		wave.node.visible = age > 0 and progress < 1
		wave.node.scale = Vector3.ONE * radius * lerpf(.08,1.0,pow(progress,.62))
		wave.material.set_shader_parameter("t", progress)
	for cloud in clouds:
		cloud.node.position = cloud.origin + cloud.velocity * (1.0-exp(-elapsed*1.4))/1.4 + Vector3.UP * elapsed * elapsed * 4.0
	for fragment in fragments:
		fragment.node.position = fragment.velocity * (1.0-exp(-elapsed*1.1))/1.1 + Vector3.DOWN * 8.0 * elapsed * elapsed
		fragment.node.rotation = fragment.spin * elapsed
		fragment.node.transparency = smoothstep(1.8,2.5,elapsed)
		fragment.node.visible = elapsed < 2.5
	light.visible = elapsed < .55
	light.light_energy = 5.0 * pow(clampf(1.0-elapsed/.55,0,1),2)
	return true
