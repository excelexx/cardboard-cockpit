extends RefCounted
class_name ImpactFX
## Hit feedback on a goose. Every effect is a self-contained, self-freeing
## Node3D you drop at the hit point:
##
##   ImpactFX.cannon_hit(at, direction, scale)    25 mm round strikes home
##   ImpactFX.plasma_hit(at, direction, radius)   the beam is cooking the bird
##   ImpactFX.kill_accent(at, direction, scale)   the moment it dies
##
## They are deliberately compact and purely additive so they layer on top of
## whatever the kill effect in combat_visuals.gd is already doing. Each effect
## bakes its randomness into a cached mesh (so nothing allocates geometry per
## hit) and plays from a single "t" uniform, driven by one Tween; pass
## autoplay=false and call ImpactFX.set_time(node, t) to scrub it by hand.

const Art = preload("res://systems/weapon_visuals.gd")
const SPARK_SHADER := "res://assets/vfx/impact_spark.gdshader"
const FEATHER_SHADER := "res://assets/vfx/impact_feather.gdshader"
const ARC_SHADER := "res://assets/vfx/impact_arc.gdshader"
const PUFF_SHADER := "res://assets/vfx/impact_puff.gdshader"
const BLOOM_SHADER := "res://assets/vfx/impact_bloom.gdshader"

const VARIANTS := 4
static var _meshes: Dictionary = {}
static var _turn := 0

# --------------------------------------------------------------- scheduling --

## Scrub an effect to a normalised time. Every part has its own window inside
## the effect, so the flash is over long before the embers are.
static func set_time(root: Node3D, t: float) -> void:
	if not is_instance_valid(root) or not root.has_meta("fx_parts"): return
	for part: Dictionary in root.get_meta("fx_parts"):
		var local: float = clampf((t - float(part.t0)) / maxf(float(part.t1) - float(part.t0), 0.0001), 0.0, 1.0)
		if part.has("material"): part.material.set_shader_parameter("t", local)
		if part.has("light"):
			var light: OmniLight3D = part.light
			if is_instance_valid(light):
				light.light_energy = float(part.energy) * pow(1.0 - local, 2.0)
				light.visible = local < 1.0

static func _schedule(root: Node3D, parts: Array, duration: float, autoplay: bool) -> Node3D:
	root.set_meta("fx_parts", parts)
	root.set_meta("fx_duration", duration)
	set_time(root, 0.0)
	if autoplay:
		root.tree_entered.connect(func() -> void:
			var tween: Tween = root.create_tween()
			tween.tween_method(func(v: float) -> void: set_time(root, v), 0.0, 1.0, duration)
			tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root

static func _add(root: Node3D, name: String, mesh: Mesh, material: ShaderMaterial, parts: Array, t0: float, t1: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3.ONE * -26.0, Vector3.ONE * 52.0)
	root.add_child(node)
	parts.append({"material": material, "t0": t0, "t1": t1})
	return node

static func _shader(path: String, values: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(path)
	for key: String in values: material.set_shader_parameter(key, values[key])
	return material

static func _flash(root: Node3D, parts: Array, mode: int, size: float, grow: float, intensity: float, core: Color, edge: Color, t0: float, t1: float, at: Vector3 = Vector3.ZERO) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material: ShaderMaterial = _shader(BLOOM_SHADER, {
		"mode": mode, "size": size, "grow": grow, "intensity": intensity,
		"core_colour": core, "edge_colour": edge, "spokes": 5.0 + randf() * 4.0,
		"spin": randf() * TAU})
	var node: MeshInstance3D = _add(root, "Bloom%d" % parts.size(), quad, material, parts, t0, t1)
	node.position = at

# ------------------------------------------------------------- baked sprays --

static func _cached(key: String, builder: Callable) -> Mesh:
	_turn += 1
	var slot: String = "%s%d" % [key, _turn % VARIANTS]
	if not _meshes.has(slot): _meshes[slot] = builder.call(hash(slot))
	return _meshes[slot]

## A cone of quads whose launch velocity lives in the vertex position.
static func _spray_mesh(seed: int, count: int, spread: float, speed: Vector2, size: Vector2, bias: float = 0.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var index := 0
	for i in range(count):
		# Cone around -Z; the effect node is rotated to face the shot.
		var theta: float = spread * sqrt(rng.randf())
		var phi: float = rng.randf() * TAU
		var direction := Vector3(sin(theta) * cos(phi), sin(theta) * sin(phi), -cos(theta))
		direction = direction.lerp(Vector3(rng.randfn(0.0, 0.6), rng.randfn(0.0, 0.6), rng.randfn(0.0, 0.6)).normalized(), bias).normalized()
		var velocity: Vector3 = direction * rng.randf_range(speed.x, speed.y)
		var scale: float = rng.randf_range(size.x, size.y)
		var tag := Vector2(scale, rng.randf() * 97.0)
		for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			st.set_uv(corner)
			st.set_uv2(tag)
			st.set_normal(direction)
			st.add_vertex(velocity)
		st.add_index(index); st.add_index(index + 1); st.add_index(index + 2)
		st.add_index(index); st.add_index(index + 2); st.add_index(index + 3)
		index += 4
	return st.commit()

## Jagged discharge paths over a sphere: ribbons with the tangent in NORMAL.
static func _arc_mesh(seed: int, arcs: int, radius: float, segments: int = 11) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var index := 0
	for a in range(arcs):
		var start := Vector3(rng.randfn(0, 1), rng.randfn(0, 1), rng.randfn(0, 1)).normalized()
		var axis: Vector3 = start.cross(Vector3(rng.randfn(0, 1), rng.randfn(0, 1), rng.randfn(0, 1))).normalized()
		var sweep: float = rng.randf_range(1.5, 3.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		var tag := Vector2(rng.randf_range(0.7, 1.4), rng.randf() * 61.0)
		var points: PackedVector3Array = PackedVector3Array()
		for s in range(segments):
			var t: float = float(s) / (segments - 1)
			var p: Vector3 = start.rotated(axis, sweep * t)
			# Jitter off the sphere so the discharge crackles instead of orbiting.
			p += Vector3(rng.randfn(0, 1), rng.randfn(0, 1), rng.randfn(0, 1)) * 0.065
			points.append(p.normalized() * radius * rng.randf_range(0.92, 1.12))
		for s in range(segments):
			var tangent: Vector3 = (points[mini(s + 1, segments - 1)] - points[maxi(s - 1, 0)]).normalized()
			for side in [0.0, 1.0]:
				st.set_uv(Vector2(side, float(s) / (segments - 1)))
				st.set_uv2(tag)
				st.set_normal(tangent)
				st.add_vertex(points[s])
		for s in range(segments - 1):
			var base: int = index + s * 2
			st.add_index(base); st.add_index(base + 1); st.add_index(base + 2)
			st.add_index(base + 1); st.add_index(base + 3); st.add_index(base + 2)
		index += segments * 2
	return st.commit()

static func _aim(node: Node3D, direction: Vector3) -> void:
	var forward: Vector3 = direction.normalized() if direction.length() > 0.001 else Vector3.FORWARD
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	node.basis = Basis.looking_at(forward, up)

# ----------------------------------------------------------------- the hits --

## A 25 mm round strikes: a hard directional spray of sparks and feather dust,
## a one-frame flash, and a few contour feathers knocked loose downrange.
static func cannon_hit(at: Vector3, direction: Vector3, scale: float = 1.0, autoplay: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "CannonHit"
	root.position = at
	var parts: Array = []
	var s: float = maxf(scale, 0.25)

	_flash(root, parts, 0, 0.62 * s, 2.6, 2.6, Color(1.0, 0.95, 0.82), Color(1.0, 0.44, 0.10), 0.0, 0.26)

	var spray := Node3D.new()
	spray.name = "Sparks"
	_aim(spray, direction)
	spray.scale = Vector3.ONE * s
	root.add_child(spray)
	var sparks: Mesh = _cached("cannon_spark", func(h: int) -> Mesh: return _spray_mesh(h, 28, 0.95, Vector2(7.0, 22.0), Vector2(0.050, 0.115), 0.34))
	var spark_material: ShaderMaterial = _shader(SPARK_SHADER, {
		"drag": 3.6, "gravity": Vector3(0, -22, 0), "streak": 0.050, "life_scale": 0.92,
		"intensity": 1.25, "size_mul": s * 0.30, "hot_colour": Color(1.0, 0.98, 0.90),
		"mid_colour": Color(1.0, 0.56, 0.12), "cool_colour": Color(0.60, 0.06, 0.02)})
	_add(spray, "Spray", sparks, spark_material, parts, 0.0, 0.62)

	var feathers: Mesh = _cached("cannon_feather", func(h: int) -> Mesh: return _spray_mesh(h, 7, 0.95, Vector2(2.0, 6.5), Vector2(0.13, 0.22), 0.35))
	var feather_material: ShaderMaterial = _shader(FEATHER_SHADER, {
		"drag": 3.0, "gravity": Vector3(0, -7.0, 0), "spin": 9.0, "life_scale": 0.95,
		"exposure": 1.0, "size_mul": s * 0.8,
		"vane_dark": Color(0.030, 0.026, 0.022), "vane_light": Color(0.135, 0.122, 0.110),
		"tip_colour": Color(0.34, 0.32, 0.30)})
	_add(spray, "Feathers", feathers, feather_material, parts, 0.03, 1.0)

	var puff: ShaderMaterial = _shader(PUFF_SHADER, {
		"size": 0.62 * s, "grow": 2.6, "seed": randf() * 11.0, "opacity": 0.55,
		"smoke_colour": Color(0.14, 0.125, 0.115), "lit_colour": Color(0.52, 0.44, 0.34)})
	var dust := QuadMesh.new()
	dust.size = Vector2.ONE
	_add(root, "Dust", dust, puff, parts, 0.02, 0.80)

	var light := OmniLight3D.new()
	light.name = "Flash"
	light.light_color = Color(1.0, 0.70, 0.38)
	light.omni_range = 16.0 * s
	light.shadow_enabled = false
	root.add_child(light)
	parts.append({"light": light, "energy": 5.5 * s, "t0": 0.0, "t1": 0.20})

	return _schedule(root, parts, 0.62, autoplay)

## The beam is cooking the bird: a sizzling contact corona, discharge crawling
## over its silhouette, embers dripping off, and a singed-down puff.
static func plasma_hit(at: Vector3, direction: Vector3, radius: float = 1.8, tint: Color = Color(0, 0, 0, 0), autoplay: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "PlasmaHit"
	root.position = at
	var parts: Array = []
	var colour: Color = tint if tint.a > 0.0 else Art.beam_tint(at.length())
	var hot: Color = colour.lerp(Color(1, 1, 1), 0.35)

	_flash(root, parts, 2, 0.80 * radius, 1.5, 1.6, hot, colour, 0.0, 0.62)
	_flash(root, parts, 1, 0.58 * radius, 2.6, 1.1, hot, colour, 0.0, 0.42)

	var arcs: Mesh = _cached("plasma_arc", func(h: int) -> Mesh: return _arc_mesh(h, 5, 1.0, 15))
	var arc_material: ShaderMaterial = _shader(ARC_SHADER, {
		"width": 0.026 * radius, "intensity": 0.95, "strikes": 2.0,
		"tint": colour, "hot": colour.lerp(Color(1, 1, 1), 0.40), "expand": 0.22})
	var crawl: MeshInstance3D = _add(root, "Arcs", arcs, arc_material, parts, 0.0, 0.66)
	crawl.scale = Vector3.ONE * radius

	var spray := Node3D.new()
	spray.name = "Embers"
	_aim(spray, direction)
	spray.scale = Vector3.ONE * maxf(radius * 0.8, 0.5)
	root.add_child(spray)
	var embers: Mesh = _cached("plasma_ember", func(h: int) -> Mesh: return _spray_mesh(h, 18, 1.15, Vector2(3.0, 11.0), Vector2(0.05, 0.11), 0.55))
	var ember_material: ShaderMaterial = _shader(SPARK_SHADER, {
		"drag": 2.4, "gravity": Vector3(0, -10.0, 0), "streak": 0.044, "life_scale": 0.95,
		"intensity": 1.1, "size_mul": maxf(radius * 0.8, 0.5) * 0.38, "hot_colour": hot, "mid_colour": colour,
		"cool_colour": Color(0.45, 0.10, 0.30)})
	_add(spray, "Spray", embers, ember_material, parts, 0.02, 0.92)

	var down: Mesh = _cached("plasma_feather", func(h: int) -> Mesh: return _spray_mesh(h, 5, 1.25, Vector2(1.6, 5.0), Vector2(0.11, 0.18), 0.5))
	var down_material: ShaderMaterial = _shader(FEATHER_SHADER, {
		"drag": 3.4, "gravity": Vector3(0, -6.0, 0), "spin": 7.0, "life_scale": 1.0,
		"size_mul": maxf(radius * 0.7, 0.4), "vane_dark": Color(0.026, 0.022, 0.020), "vane_light": Color(0.115, 0.100, 0.092),
		"tip_colour": Color(0.28, 0.26, 0.24), "exposure": 1.0})
	_add(spray, "Singed", down, down_material, parts, 0.05, 1.0)

	var puff: ShaderMaterial = _shader(PUFF_SHADER, {
		"size": 0.9 * radius, "grow": 2.4, "seed": randf() * 11.0, "opacity": 0.60,
		"smoke_colour": Color(0.11, 0.10, 0.105), "lit_colour": Color(0.42, 0.36, 0.34)})
	var smoke := QuadMesh.new()
	smoke.size = Vector2.ONE
	_add(root, "Singe", smoke, puff, parts, 0.10, 0.95)

	var light := OmniLight3D.new()
	light.name = "Contact"
	light.light_color = colour
	light.omni_range = 22.0
	light.shadow_enabled = false
	root.add_child(light)
	parts.append({"light": light, "energy": 7.0, "t0": 0.0, "t1": 0.45})

	return _schedule(root, parts, 0.66, autoplay)

## Kill accent: a tight shockwave ring and a hard radial spark burst. Small,
## short and additive - it sharpens the feather burst rather than replacing it.
static func kill_accent(at: Vector3, direction: Vector3, scale: float = 1.0, autoplay: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "KillAccent"
	root.position = at
	var parts: Array = []
	var s: float = maxf(scale, 0.4)

	_flash(root, parts, 0, 0.58 * s, 2.2, 2.2, Color(1.0, 0.95, 0.80), Color(1.0, 0.56, 0.14), 0.0, 0.26)
	_flash(root, parts, 1, 0.78 * s, 3.0, 1.5, Color(1.0, 0.90, 0.66), Color(1.0, 0.46, 0.10), 0.02, 0.70)

	var spray := Node3D.new()
	spray.name = "Burst"
	_aim(spray, direction)
	spray.scale = Vector3.ONE * s
	root.add_child(spray)
	var sparks: Mesh = _cached("kill_spark", func(h: int) -> Mesh: return _spray_mesh(h, 24, 1.5, Vector2(8.0, 26.0), Vector2(0.06, 0.14), 0.62))
	var spark_material: ShaderMaterial = _shader(SPARK_SHADER, {
		"drag": 3.0, "gravity": Vector3(0, -18.0, 0), "streak": 0.052, "life_scale": 0.95,
		"intensity": 1.4, "size_mul": s * 0.30, "hot_colour": Color(1.0, 0.98, 0.92),
		"mid_colour": Color(1.0, 0.62, 0.16), "cool_colour": Color(0.66, 0.10, 0.02)})
	_add(spray, "Spray", sparks, spark_material, parts, 0.0, 0.85)

	var light := OmniLight3D.new()
	light.name = "Flash"
	light.light_color = Color(1.0, 0.74, 0.42)
	light.omni_range = 34.0 * s
	light.shadow_enabled = false
	root.add_child(light)
	parts.append({"light": light, "energy": 9.0 * s, "t0": 0.0, "t1": 0.30})

	return _schedule(root, parts, 0.46, autoplay)
