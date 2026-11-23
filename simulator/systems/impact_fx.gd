extends RefCounted
class_name ImpactFX
## Hit feedback on a goose. Every effect is a self-contained, self-freeing
## Node3D you drop at the hit point:
##
##   ImpactFX.cannon_hit(at, direction, scale)    25 mm round strikes home
##   ImpactFX.plasma_hit(at, direction, radius)   the beam is cooking the bird
##   ImpactFX.kill_accent(at, direction, scale)   the moment it dies
##
## They are deliberately compact so they layer on top of whatever the kill effect
## in combat_visuals.gd is already doing. Sparks, arcs and blooms are additive;
## the feathers and the smoke puff are alpha blended, because a feather and a
## smoke ball are OBJECTS - drawn additively they turn into glowing fog.
##
## Nothing is allocated per hit except the node tree itself: the geometry and the
## ShaderMaterials both come from a ring of VARIANTS cached sets, the billboards
## share one QuadMesh, and the flash light is handed to combat_visuals.gd's
## existing 8-light pool through `light_sink` rather than spawning an OmniLight3D
## of its own. Each effect plays from a single "t" uniform driven by one Tween;
## pass autoplay=false and call ImpactFX.set_time(node, t) to scrub it by hand.

const Art = preload("res://systems/weapon_visuals.gd")
const SPARK_SHADER := "res://assets/vfx/impact_spark.gdshader"
const FEATHER_SHADER := "res://assets/vfx/impact_feather.gdshader"
const ARC_SHADER := "res://assets/vfx/impact_arc.gdshader"
const PUFF_SHADER := "res://assets/vfx/impact_puff.gdshader"
const BLOOM_SHADER := "res://assets/vfx/impact_bloom.gdshader"

## Depth of the cache ring. Two live effects of the same kind land on the same
## slot only after this many have started, and effects last under 0.85 s, so a
## collision needs more than ~14 hits per second of one kind.
const VARIANTS := 12
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _quad: QuadMesh
static var _turn := 0

## Set this once and ImpactFX stops creating OmniLight3Ds:
##     ImpactFX.light_sink = combat_visuals.illuminate
## Signature: (at: Vector3, colour: Color, energy: float, radius: float, life: float)
static var light_sink: Callable = Callable()

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

## reach is the effect's own extent in MESH space, so the part gets an AABB that
## fits it instead of the 52 m box that used to keep every hit un-cullable.
static func _add(root: Node3D, name: String, mesh: Mesh, material: ShaderMaterial, parts: Array, t0: float, t1: float, reach: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * (reach * 2.0))
	root.add_child(node)
	parts.append({"material": material, "t0": t0, "t1": t1})
	return node

# --------------------------------------------------------------- the caches --

## One slot per effect. Every mesh and material that effect uses comes from the
## same slot, so a given hit is internally consistent.
static func _slot() -> int:
	_turn += 1
	return _turn % VARIANTS

static func _mesh(slot: int, key: String, builder: Callable) -> Mesh:
	var id: String = "%s%d" % [key, slot]
	if not _meshes.has(id): _meshes[id] = builder.call(hash(id))
	return _meshes[id]

## A cached ShaderMaterial. `values` is re-applied every call because a few
## parameters (the plasma tint, the target's size) really do vary per hit; the
## shader, the uniform defaults and the allocation do not.
static func _shader(slot: int, key: String, path: String, values: Dictionary) -> ShaderMaterial:
	var id: String = "%s%d" % [key, slot]
	var material: ShaderMaterial = _materials.get(id)
	if material == null:
		material = ShaderMaterial.new()
		material.shader = load(path)
		_materials[id] = material
	for name: String in values: material.set_shader_parameter(name, values[name])
	return material

static func _billboard() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad

static func _flash(root: Node3D, parts: Array, slot: int, key: String, mode: int, size: float, grow: float, intensity: float, core: Color, edge: Color, t0: float, t1: float, at: Vector3 = Vector3.ZERO) -> void:
	var material: ShaderMaterial = _shader(slot, key, BLOOM_SHADER, {
		"mode": mode, "size": size, "grow": grow, "intensity": intensity,
		"core_colour": core, "edge_colour": edge, "loop": 0.0,
		"spokes": 5.0 + float(slot % 5), "spin": float(slot) * 1.2566})
	var node: MeshInstance3D = _add(root, "Bloom_" + key, _billboard(), material, parts, t0, t1, size * grow * 0.75)
	node.position = at

static func _puff(root: Node3D, parts: Array, slot: int, key: String, size: float, grow: float, opacity: float, smoke: Color, lit: Color, t0: float, t1: float) -> void:
	var material: ShaderMaterial = _shader(slot, key, PUFF_SHADER, {
		"size": size, "grow": grow, "opacity": opacity,
		"smoke_colour": smoke, "lit_colour": lit, "seed": float(slot) * 1.37})
	_add(root, "Puff_" + key, _billboard(), material, parts, t0, t1, size * grow * 0.75)

## The flash. With `light_sink` set this costs nothing: combat_visuals.gd's
## pooled lights take it. Without one (the studio harness) it makes its own.
static func _flash_light(root: Node3D, parts: Array, at: Vector3, colour: Color, energy: float, radius: float, t0: float, t1: float, duration: float) -> void:
	if light_sink.is_valid():
		light_sink.call(at, colour, energy, radius, (t1 - t0) * duration)
		return
	var light := OmniLight3D.new()
	light.name = "Flash"
	light.light_color = colour
	light.omni_range = radius
	light.shadow_enabled = false
	root.add_child(light)
	parts.append({"light": light, "energy": energy, "t0": t0, "t1": t1})

# ------------------------------------------------------------- baked sprays --

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

## Jagged discharge paths ROOTED AT THE STRIKE: ribbons that climb off the
## contact point and then crawl over the bird's silhouette. Every path starts at
## the origin - an arc that begins at a random offset floats free beside the bird
## and reads as a cut-out. VERTEX = point, NORMAL = path tangent, UV.y = distance
## along the path (the shader tapers the width to nothing at both ends).
static func _arc_mesh(seed: int, arcs: int, radius: float, segments: int = 11) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var index := 0
	for a in range(arcs):
		var direction := Vector3(rng.randfn(0, 1), rng.randfn(0, 1), rng.randfn(0, 1)).normalized()
		var axis: Vector3 = direction.cross(Vector3(rng.randfn(0, 1), rng.randfn(0, 1), rng.randfn(0, 1))).normalized()
		var sweep: float = rng.randf_range(1.2, 2.6) * (1.0 if rng.randf() > 0.5 else -1.0)
		var tag := Vector2(rng.randf_range(0.7, 1.4), rng.randf() * 61.0)
		var points: PackedVector3Array = PackedVector3Array()
		for s in range(segments):
			var t: float = float(s) / (segments - 1)
			# Climbs out of the contact point over the first third, then rides
			# the silhouette.
			var reach: float = radius * smoothstep(0.0, 0.34, t) * rng.randf_range(0.92, 1.10)
			var p: Vector3 = direction.rotated(axis, sweep * t) * reach
			# Jitter off the sphere so the discharge crackles instead of orbiting.
			p += Vector3(rng.randfn(0, 1), rng.randfn(0, 1), rng.randfn(0, 1)) * 0.06 * radius * smoothstep(0.0, 0.22, t)
			points.append(p)
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

## Vane colours for knocked-loose feathers. Well off black on purpose: these are
## alpha-blended against a lit sunset, and at 0.135 sRGB (0.016 linear) every
## feather rendered as a solid black bean. impact_feather.gdshader lights them
## through as well, so the edges glow warm instead of going flat.
const VANE_DARK := Color(0.100, 0.090, 0.080)
const VANE_LIGHT := Color(0.450, 0.420, 0.380)

## A 25 mm round strikes: a hard directional spray of sparks and feather dust,
## a one-frame flash, and a few contour feathers knocked loose downrange.
static func cannon_hit(at: Vector3, direction: Vector3, scale: float = 1.0, autoplay: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "CannonHit"
	root.position = at
	var parts: Array = []
	var s: float = maxf(scale, 0.25)
	var slot: int = _slot()

	_flash(root, parts, slot, "cannon_core", 0, 0.62 * s, 2.6, 2.6, Color(1.0, 0.95, 0.82), Color(1.0, 0.44, 0.10), 0.0, 0.26)

	var spray := Node3D.new()
	spray.name = "Sparks"
	_aim(spray, direction)
	spray.scale = Vector3.ONE * s
	root.add_child(spray)
	var sparks: Mesh = _mesh(slot, "cannon_spark", func(h: int) -> Mesh: return _spray_mesh(h, 28, 0.95, Vector2(7.0, 22.0), Vector2(0.050, 0.115), 0.34))
	# GRAVITY is what made the old burst read as orange rain, not life: at -22 the
	# launch speed (down to 1/e by 0.28 s under drag 3.6) loses to gravity early
	# and every streak turns straight down, detached from the bird. At -5 the
	# radial travel wins for the whole visible life and the droop is under 20 cm.
	# Life stays long enough to still be on screen a frame or two after the hit -
	# at 0.45 the whole spray was gone by 0.17 s and a graze looked like nothing.
	var spark_material: ShaderMaterial = _shader(slot, "cannon_spark", SPARK_SHADER, {
		"drag": 3.6, "gravity": Vector3(0, -5.0, 0), "streak": 0.050, "life_scale": 0.90,
		"intensity": 1.25, "size_mul": s * 0.30, "hot_colour": Color(1.0, 0.98, 0.90),
		"mid_colour": Color(1.0, 0.56, 0.12), "cool_colour": Color(0.60, 0.06, 0.02)})
	_add(spray, "Spray", sparks, spark_material, parts, 0.0, 0.62, 8.0)

	var feathers: Mesh = _mesh(slot, "cannon_feather", func(h: int) -> Mesh: return _spray_mesh(h, 4, 0.95, Vector2(2.0, 6.5), Vector2(0.13, 0.22), 0.35))
	var feather_material: ShaderMaterial = _shader(slot, "cannon_feather", FEATHER_SHADER, {
		"drag": 3.0, "gravity": Vector3(0, -7.0, 0), "spin": 9.0, "life_scale": 0.95,
		"exposure": 1.0, "size_mul": s * 0.8, "backlight": 1.15,
		"vane_dark": VANE_DARK, "vane_light": VANE_LIGHT,
		"tip_colour": Color(0.92, 0.72, 0.46)})
	_add(spray, "Feathers", feathers, feather_material, parts, 0.03, 1.0, 6.0)

	_puff(root, parts, slot, "cannon_dust", 0.62 * s, 2.6, 0.55, Color(0.14, 0.125, 0.115), Color(0.52, 0.44, 0.34), 0.02, 0.80)
	_flash_light(root, parts, at, Color(1.0, 0.70, 0.38), 5.5 * s, 16.0 * s, 0.0, 0.20, 0.62)
	return _schedule(root, parts, 0.62, autoplay)

## The beam is cooking the bird: a sizzling contact corona, discharge crawling
## over its silhouette, embers dripping off, and a singed-down puff.
static func plasma_hit(at: Vector3, direction: Vector3, radius: float = 1.8, tint: Color = Color(0, 0, 0, 0), autoplay: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "PlasmaHit"
	root.position = at
	var parts: Array = []
	var slot: int = _slot()
	var colour: Color = tint if tint.a > 0.0 else Art.beam_tint(at.length())
	var hot: Color = colour.lerp(Color(1, 1, 1), 0.35)

	_flash(root, parts, slot, "plasma_corona", 2, 0.80 * radius, 1.5, 1.6, hot, colour, 0.0, 0.62)
	_flash(root, parts, slot, "plasma_ring", 1, 0.58 * radius, 2.6, 1.1, hot, colour, 0.0, 0.42)

	# Eight paths, not five: the discharge has to read as a crackling NET over the
	# bird. Five tapered ribbons at a sane brightness were three faint wisps.
	var arcs: Mesh = _mesh(slot, "plasma_arc", func(h: int) -> Mesh: return _arc_mesh(h, 8, 1.0, 15))
	# 0.012, not 0.026: at a 1.8 m bird the old ribbons were as thick as the
	# goose's neck. The shader tapers them to nothing at both ends now.
	var arc_material: ShaderMaterial = _shader(slot, "plasma_arc", ARC_SHADER, {
		"width": 0.014 * radius, "intensity": 1.15, "strikes": 3.0,
		"tint": colour, "hot": colour.lerp(Color(1, 1, 1), 0.40), "expand": 0.22})
	var crawl: MeshInstance3D = _add(root, "Arcs", arcs, arc_material, parts, 0.0, 0.66, 1.4)
	crawl.scale = Vector3.ONE * radius

	var spray := Node3D.new()
	spray.name = "Embers"
	_aim(spray, direction)
	spray.scale = Vector3.ONE * maxf(radius * 0.8, 0.5)
	root.add_child(spray)
	var embers: Mesh = _mesh(slot, "plasma_ember", func(h: int) -> Mesh: return _spray_mesh(h, 18, 1.15, Vector2(3.0, 11.0), Vector2(0.05, 0.11), 0.55))
	var ember_material: ShaderMaterial = _shader(slot, "plasma_ember", SPARK_SHADER, {
		"drag": 2.4, "gravity": Vector3(0, -4.0, 0), "streak": 0.044, "life_scale": 0.62,
		"intensity": 1.1, "size_mul": maxf(radius * 0.8, 0.5) * 0.38, "hot_colour": hot, "mid_colour": colour,
		"cool_colour": colour.lerp(Color(0.35, 0.08, 0.02), 0.7)})
	_add(spray, "Spray", embers, ember_material, parts, 0.02, 0.92, 6.0)

	var down: Mesh = _mesh(slot, "plasma_feather", func(h: int) -> Mesh: return _spray_mesh(h, 3, 1.25, Vector2(1.6, 5.0), Vector2(0.11, 0.18), 0.5))
	var down_material: ShaderMaterial = _shader(slot, "plasma_feather", FEATHER_SHADER, {
		"drag": 3.4, "gravity": Vector3(0, -6.0, 0), "spin": 7.0, "life_scale": 1.0,
		"size_mul": maxf(radius * 0.7, 0.4), "exposure": 1.0, "backlight": 1.3,
		"vane_dark": VANE_DARK, "vane_light": VANE_LIGHT,
		"tip_colour": Color(0.95, 0.66, 0.36)})
	_add(spray, "Singed", down, down_material, parts, 0.05, 1.0, 5.0)

	_puff(root, parts, slot, "plasma_singe", 0.9 * radius, 2.4, 0.60, Color(0.11, 0.10, 0.105), Color(0.42, 0.36, 0.34), 0.10, 0.95)
	_flash_light(root, parts, at, colour, 7.0, 22.0, 0.0, 0.45, 0.66)
	return _schedule(root, parts, 0.66, autoplay)

## Kill accent. Two stages, because a kill must not read smaller than a graze:
## a white core, then an amber fireball, then the shock ring snapping past, then
## dark smoke that outlives all of it. Still additive over combat_visuals.gd's
## feather burst rather than replacing it - this sharpens the moment.
static func kill_accent(at: Vector3, direction: Vector3, scale: float = 1.0, autoplay: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "KillAccent"
	root.position = at
	var parts: Array = []
	var s: float = maxf(scale, 0.4)
	var slot: int = _slot()
	# Windows are fractions of the 0.80 s schedule. The core and the ring keep
	# the wall-clock timings they had on the old 0.46 s one.
	_flash(root, parts, slot, "kill_core", 0, 0.58 * s, 2.2, 2.6, Color(1.0, 0.96, 0.88), Color(1.0, 0.70, 0.26), 0.0, 0.15)
	# The fireball is the stage that has to CARRY the kill: the core is over in
	# ~120 ms and the ring is deliberately gone before the eye resolves it, so
	# with a 0.35 window there was nothing left on screen by 0.2 s and a kill
	# read smaller than a graze. It runs to 0.52 (about 0.42 s) instead.
	_flash(root, parts, slot, "kill_fire", 0, 1.20 * s, 2.4, 2.1, Color(1.0, 0.82, 0.44), Color(0.95, 0.30, 0.05), 0.045, 0.52)
	_flash(root, parts, slot, "kill_ring", 1, 0.78 * s, 3.0, 1.7, Color(1.0, 0.92, 0.72), Color(1.0, 0.50, 0.12), 0.012, 0.40)

	var spray := Node3D.new()
	spray.name = "Burst"
	_aim(spray, direction)
	spray.scale = Vector3.ONE * s
	root.add_child(spray)
	var sparks: Mesh = _mesh(slot, "kill_spark", func(h: int) -> Mesh: return _spray_mesh(h, 24, 1.5, Vector2(8.0, 26.0), Vector2(0.06, 0.14), 0.62))
	var spark_material: ShaderMaterial = _shader(slot, "kill_spark", SPARK_SHADER, {
		"drag": 3.0, "gravity": Vector3(0, -5.0, 0), "streak": 0.052, "life_scale": 0.82,
		"intensity": 1.4, "size_mul": s * 0.30, "hot_colour": Color(1.0, 0.98, 0.92),
		"mid_colour": Color(1.0, 0.62, 0.16), "cool_colour": Color(0.66, 0.10, 0.02)})
	_add(spray, "Spray", sparks, spark_material, parts, 0.0, 0.52, 10.0)

	var feathers: Mesh = _mesh(slot, "kill_feather", func(h: int) -> Mesh: return _spray_mesh(h, 6, 1.35, Vector2(2.4, 7.5), Vector2(0.15, 0.26), 0.55))
	var feather_material: ShaderMaterial = _shader(slot, "kill_feather", FEATHER_SHADER, {
		"drag": 2.8, "gravity": Vector3(0, -7.0, 0), "spin": 10.0, "life_scale": 1.0,
		"exposure": 1.0, "size_mul": s * 0.95, "backlight": 1.25,
		"vane_dark": VANE_DARK, "vane_light": VANE_LIGHT,
		"tip_colour": Color(0.95, 0.74, 0.48)})
	_add(spray, "Feathers", feathers, feather_material, parts, 0.04, 1.0, 7.0)

	# Dark smoke, slow and low, outliving the fire. This is what makes the kill
	# land as an event instead of a blink.
	_puff(root, parts, slot, "kill_smoke", 1.15 * s, 2.9, 0.78, Color(0.075, 0.068, 0.064), Color(0.42, 0.30, 0.20), 0.15, 1.0)
	_flash_light(root, parts, at, Color(1.0, 0.74, 0.42), 9.0 * s, 34.0 * s, 0.0, 0.20, 0.80)
	return _schedule(root, parts, 0.80, autoplay)
