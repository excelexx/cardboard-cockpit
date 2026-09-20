extends RefCounted
class_name WeaponModels
## Hard points of the SPECTRE X-26: the CG-26 rotary cannon and the PC-26 plasma
## projector. Both are lofted procedurally so the silhouette is authored rather
## than sampled, and both are dressed in the key art's palette: near-black
## graphite, machined edges catching the sunset, thin gold trim, heat-blued
## steel. Everything a weapon owns lives under one Node3D with named parts, so
## fighter_effects.gd keeps finding "GatlingRotor" and "GunMuzzle" by name.
##
##   WeaponModels.rotary_cannon()  -> Node3D, child "GatlingRotor" spins on Z,
##                                    Marker3D "GunMuzzle" at z = -0.79
##   WeaponModels.plasma_cannon()  -> Node3D, Marker3D "BeamMuzzle"
##   WeaponModels.set_heat(gun, 0..1)               barrel glow while firing
##   WeaponModels.set_charge(cannon, 0..1, firing)  plasma spool-up

const PLATE_ALBEDO := "res://assets/weapons/gunmetal_diff_1k.jpg"
const PLATE_NORMAL := "res://assets/weapons/gunmetal_nor_gl_1k.jpg"
const PLATE_ARM := "res://assets/weapons/gunmetal_arm_1k.jpg"
const METAL_SHADER := "res://assets/weapons/gun_metal.gdshader"
const HOUSING_SHADER := "res://assets/vfx/plasma_housing.gdshader"
const BLOOM_SHADER := "res://assets/vfx/impact_bloom.gdshader"

const MUZZLE_Z := -0.79      # barrel tips; the old mount put this at -0.51
const BARREL_COUNT := 5
const BARREL_PITCH := 0.058  # radius of the barrel cluster: barrels nearly touch
const BARREL_TIP := -0.785
const BARREL_BREECH := 0.74

# ---------------------------------------------------------------- materials --

static var _plate: Array = []

static func _textures() -> Array:
	if _plate.is_empty():
		_plate = [load(PLATE_ALBEDO), load(PLATE_NORMAL), load(PLATE_ARM)]
	return _plate

static func metal(overrides: Dictionary = {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(METAL_SHADER)
	var maps: Array = _textures()
	material.set_shader_parameter("plate_albedo", maps[0])
	material.set_shader_parameter("plate_normal", maps[1])
	material.set_shader_parameter("plate_arm", maps[2])
	for key: String in overrides: material.set_shader_parameter(key, overrides[key])
	return material

static func housing(mode: int, overrides: Dictionary = {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(HOUSING_SHADER)
	material.set_shader_parameter("mode", mode)
	if mode == 0:
		var maps: Array = _textures()
		material.set_shader_parameter("plate_albedo", maps[0])
		material.set_shader_parameter("plate_normal", maps[1])
		material.set_shader_parameter("plate_arm", maps[2])
	for key: String in overrides: material.set_shader_parameter(key, overrides[key])
	return material

# ------------------------------------------------------------------ lofting --

## A circle of n points, counter-clockwise from +X.
static func circle(n: int, rx: float, ry: float = -1.0) -> PackedVector2Array:
	if ry < 0.0: ry = rx
	var out := PackedVector2Array()
	for i in range(n):
		var a: float = TAU * float(i) / n
		out.append(Vector2(cos(a) * rx, sin(a) * ry))
	return out

## The faceted gun-blister section: a crowned deck that mates with the chine, a
## hard horizontal edge down each flank, angled cheeks and a flat keel. Sixteen
## points so section(16,...) lands exactly on every corner and the facets stay
## crisp under flat shading. roundness blends it back to an ellipse for the
## nose rings.
const CHINE: Array = [
	Vector2(1.00, -0.08), Vector2(0.97, 0.30), Vector2(0.80, 0.66), Vector2(0.46, 0.86), Vector2(0.00, 0.92),
	Vector2(-0.46, 0.86), Vector2(-0.80, 0.66), Vector2(-0.97, 0.30), Vector2(-1.00, -0.08),
	Vector2(-0.94, -0.46), Vector2(-0.70, -0.80), Vector2(-0.34, -0.97), Vector2(0.00, -1.00),
	Vector2(0.34, -0.97), Vector2(0.70, -0.80), Vector2(0.94, -0.46)]

static func section(n: int, rx: float, ry: float, roundness: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var key: int = CHINE.size()
	for i in range(n):
		var f: float = float(i) / n * key
		var lo: int = int(f) % key
		var p: Vector2 = Vector2(CHINE[lo]).lerp(Vector2(CHINE[(lo + 1) % key]), f - floor(f))
		var a: float = TAU * float(i) / n
		p = p.lerp(Vector2(cos(a), sin(a)), clampf(roundness, 0.0, 1.0))
		out.append(Vector2(p.x * rx, p.y * ry))
	return out

## Outline of the union of `lobes` circles of radius `lobe` on a pitch circle,
## merged with a central hub: exactly what a gatling barrel clamp looks like.
static func scallop(n: int, hub: float, pitch: float, lobe: float, lobes: int, roll: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(n):
		var a: float = TAU * float(i) / n
		var r: float = hub
		for k in range(lobes):
			var d: float = a - (TAU * float(k) / lobes + roll)
			var along: float = pitch * cos(d)
			var across: float = pitch * sin(d)
			if absf(across) < lobe:
				r = maxf(r, along + sqrt(lobe * lobe - across * across))
		out.append(Vector2(cos(a) * r, sin(a) * r))
	return out

## Resample a closed outline to n points by walking it at a constant index rate,
## so rings with different detail can still be lofted together.
static func resample(points: PackedVector2Array, n: int) -> PackedVector2Array:
	if points.size()==n: return points
	var out := PackedVector2Array()
	var count: int = points.size()
	for i in range(n):
		var f: float = float(i)/n*count
		var lo: int = int(f)%count
		out.append(points[lo].lerp(points[(lo+1)%count],f-floor(f)))
	return out

## rings: [[z, PackedVector2Array, Vector2 offset], ...]; rings with a different
## point count are resampled to match the first. Returns the next free index so
## surfaces can be concatenated into one draw call.
static func loft(st: SurfaceTool, base: int, rings: Array, cap_front: bool = true, cap_back: bool = true, uv: Vector2 = Vector2(1.0, 1.4), smooth: int = 0) -> int:
	st.set_smooth_group(smooth)
	var count: int = rings.size()
	if count < 2: return base
	var sides: int = (rings[0][1] as PackedVector2Array).size()
	var run := 0.0
	var index: int = base
	for r in range(count):
		var ring: Array = rings[r]
		var points: PackedVector2Array = resample(ring[1],sides)
		ring[1] = points
		var offset: Vector2 = ring[2] if ring.size() > 2 else Vector2.ZERO
		if r > 0: run += absf(float(ring[0]) - float(rings[r - 1][0])) + (points[0] - PackedVector2Array(rings[r - 1][1])[0]).length() * 0.35
		var tilt: float = ring[3] if ring.size() > 3 else 0.0
		var tallest := 0.001
		for q in points: tallest = maxf(tallest, absf(q.y))
		for s in range(sides + 1):
			var p: Vector2 = points[s % sides] + offset
			st.set_uv(Vector2(float(s) / sides * uv.x, run * uv.y))
			st.add_vertex(Vector3(p.x, p.y, float(ring[0]) + tilt * (points[s % sides].y / tallest)))
	var stride: int = sides + 1
	for r in range(count - 1):
		for s in range(sides):
			var a: int = index + r * stride + s
			var b: int = a + 1
			var c: int = a + stride
			var d: int = c + 1
			# Godot treats clockwise-in-screen-space as the front face, so the
			# outward side of a loft winds a -> c -> b.
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	var next: int = index + count * stride
	if cap_front: next = _cap(st, next, rings[0], false, uv)
	if cap_back: next = _cap(st, next, rings[count - 1], true, uv)
	return next

static func _cap(st: SurfaceTool, base: int, ring: Array, facing_back: bool, uv: Vector2) -> int:
	# Caps are always flat: smoothing them into the walls domes every barrel tip.
	st.set_smooth_group(-1)
	var points: PackedVector2Array = ring[1]
	var offset: Vector2 = ring[2] if ring.size() > 2 else Vector2.ZERO
	var z: float = ring[0]
	var centre := Vector2.ZERO
	for p in points: centre += p
	centre /= points.size()
	st.set_uv(Vector2(0.5, 0.5) * uv)
	st.add_vertex(Vector3(centre.x + offset.x, centre.y + offset.y, z))
	for i in range(points.size()):
		var p: Vector2 = points[i] + offset
		st.set_uv(Vector2(0.5 + p.x, 0.5 + p.y) * uv)
		st.add_vertex(Vector3(p.x, p.y, z))
	var n: int = points.size()
	for i in range(n):
		var a: int = base + 1 + i
		var b: int = base + 1 + (i + 1) % n
		if facing_back: st.add_index(base); st.add_index(b); st.add_index(a)
		else: st.add_index(base); st.add_index(a); st.add_index(b)
	return base + n + 1

## A straight tube from z0 to z1, optionally offset off-axis.
static func tube(st: SurfaceTool, base: int, z0: float, z1: float, r0: float, r1: float, sides: int, at: Vector2 = Vector2.ZERO, cap_front: bool = true, cap_back: bool = true) -> int:
	return loft(st, base, [[z0, circle(sides, r0), at], [z1, circle(sides, r1), at]], cap_front, cap_back)

## A swept helix of small tubes: the recoil adapter springs.
static func spring(st: SurfaceTool, base: int, z0: float, z1: float, coil: float, wire: float, turns: float, at: Vector2) -> int:
	var steps: int = int(maxf(12.0, turns * 10.0))
	var rings: Array = []
	for i in range(steps + 1):
		var t: float = float(i) / steps
		var a: float = t * turns * TAU
		var z: float = lerpf(z0, z1, t)
		rings.append([z, circle(6, wire), at + Vector2(cos(a), sin(a)) * coil])
	return loft(st, base, rings, true, true, Vector2(1.0, 6.0))

static func _finish(st: SurfaceTool, material: Material, name: String, parent: Node3D) -> MeshInstance3D:
	st.generate_normals()
	st.generate_tangents()
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = st.commit()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node

# ------------------------------------------------------------ rotary cannon --

static func rotary_cannon() -> Node3D:
	var root := Node3D.new()
	root.name = "CG26"

	var barrel_material: ShaderMaterial = metal({
		"heat_bias": 1.0, "heat_front": BARREL_TIP, "heat_back": BARREL_BREECH,
		"blue_span": 0.26, "tex_scale": 2.2, "rough_lo": 0.29, "rough_hi": 0.56,
		"base_tint": Color(0.040, 0.042, 0.047), "wear_amount": 0.62})
	var body_material: ShaderMaterial = metal({
		"heat_bias": 0.13, "heat_front": 0.58, "heat_back": 1.30,
		"tex_scale": 2.6, "rough_lo": 0.22, "rough_hi": 0.58})
	var pod_material: ShaderMaterial = metal({
		"heat_bias": 0.0, "tex_scale": 4.5, "rough_lo": 0.24, "rough_hi": 0.60,
		"base_tint": Color(0.058, 0.061, 0.068), "wear_amount": 0.46, "normal_strength": 1.15})
	var trim_material: ShaderMaterial = metal({"gold_mix": 1.0, "tex_scale": 6.0, "emissive_trim": 0.0, "gold_tint": Color(0.60, 0.40, 0.12)})

	_cannon_pod(root, pod_material, trim_material)
	_cannon_body(root, body_material)

	var rotor := Node3D.new()
	rotor.name = "GatlingRotor"
	root.add_child(rotor)
	_cannon_barrels(rotor, barrel_material)

	var muzzle := Marker3D.new()
	muzzle.name = "GunMuzzle"
	muzzle.position.z = MUZZLE_Z
	root.add_child(muzzle)

	for node: Node in root.find_children("*", "GeometryInstance3D", true, false): node.layers = 2
	root.set_meta("heat_materials", [barrel_material, body_material])
	return root

static func _cannon_barrels(parent: Node3D, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for i in range(BARREL_COUNT):
		var a: float = TAU * float(i) / BARREL_COUNT
		var at := Vector2(cos(a), sin(a)) * BARREL_PITCH
		# Straight machined tube: a crown band at the muzzle, a relief where the
		# clamps grip, a thicker chamber section at the breech.
		base = loft(st, base, [
			[BARREL_TIP, circle(18, 0.0268), at],
			[BARREL_TIP + 0.005, circle(18, 0.0292), at],
			[BARREL_TIP + 0.032, circle(18, 0.0292), at],
			[BARREL_TIP + 0.037, circle(18, 0.0258), at],
			[0.020, circle(18, 0.0258), at],
			[0.048, circle(18, 0.0244), at],
			[0.340, circle(18, 0.0244), at],
			[0.372, circle(18, 0.0270), at],
			[0.520, circle(18, 0.0280), at],
			[0.560, circle(18, 0.0318), at],
			[BARREL_BREECH, circle(18, 0.0330), at]], false, true)
		# Crown: a flat annulus around a real bore, not a domed tip.
		base = loft(st, base, [
			[BARREL_TIP, circle(18, 0.0150), at],
			[BARREL_TIP, circle(18, 0.0268), at]], false, false)
		# Bore wound inside-out so the crown looks down a dark tube, plugged deep.
		base = loft(st, base, [
			[BARREL_TIP + 0.16, circle(14, 0.0140), at],
			[BARREL_TIP, circle(14, 0.0150), at]], false, false)
		base = loft(st, base, [
			[BARREL_TIP + 0.16, circle(14, 0.0004), at],
			[BARREL_TIP + 0.16, circle(14, 0.0140), at]], false, false)
	# Muzzle clamp and two mid clamps: thin scalloped discs with chamfered faces
	# that stand proud of the bundle, exactly like a gatling's barrel clamps.
	base = _clamp(st, base, BARREL_TIP + 0.082, 0.040, 0.088, 0.0400)
	base = _clamp(st, base, -0.400, 0.034, 0.084, 0.0370)
	base = _clamp(st, base, -0.058, 0.034, 0.084, 0.0370)
	# Fluted rotor drum: five scallops between the barrel roots.
	base = loft(st, base, [
		[0.580, scallop(80, 0.056, BARREL_PITCH, 0.0378, BARREL_COUNT), Vector2.ZERO],
		[0.620, scallop(80, 0.086, BARREL_PITCH, 0.0410, BARREL_COUNT), Vector2.ZERO],
		[BARREL_BREECH, scallop(80, 0.104, BARREL_PITCH, 0.0430, BARREL_COUNT), Vector2.ZERO],
		[BARREL_BREECH + 0.020, circle(40, 0.118), Vector2.ZERO],
		[BARREL_BREECH + 0.070, circle(40, 0.124), Vector2.ZERO],
		[BARREL_BREECH + 0.085, circle(40, 0.106), Vector2.ZERO]], true, true)
	_finish(st, material, "Barrels", parent)

## One barrel clamp: a chamfered scalloped disc centred on z.
static func _clamp(st: SurfaceTool, base: int, z: float, thickness: float, hub: float, lobe: float) -> int:
	var chamfer: float = minf(0.006, thickness * 0.25)
	var inner: PackedVector2Array = scallop(72, hub - 0.006, BARREL_PITCH, lobe - 0.005, BARREL_COUNT)
	var outer: PackedVector2Array = scallop(72, hub, BARREL_PITCH, lobe, BARREL_COUNT)
	return loft(st, base, [
		[z - thickness * 0.5, inner, Vector2.ZERO],
		[z - thickness * 0.5 + chamfer, outer, Vector2.ZERO],
		[z + thickness * 0.5 - chamfer, outer, Vector2.ZERO],
		[z + thickness * 0.5, inner, Vector2.ZERO]], true, true)

static func _cannon_body(parent: Node3D, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	# Rotor housing: a faceted breech casing with bolted end rings.
	base = loft(st, base, [
		[0.80, circle(20, 0.106), Vector2.ZERO],
		[0.83, circle(20, 0.132), Vector2.ZERO],
		[0.87, circle(20, 0.138), Vector2.ZERO],
		[0.90, section(20, 0.132, 0.132, 0.35), Vector2.ZERO],
		[1.38, section(20, 0.134, 0.134, 0.35), Vector2.ZERO],
		[1.41, circle(20, 0.138), Vector2.ZERO],
		[1.46, circle(20, 0.130), Vector2.ZERO],
		[1.52, circle(20, 0.110), Vector2.ZERO]], true, true)
	# Bolt heads around both end rings.
	for z: float in [0.85, 1.435]:
		for i in range(12):
			var a: float = TAU * float(i) / 12.0 + 0.13
			base = tube(st, base, z - 0.016, z + 0.016, 0.011, 0.009, 6, Vector2(cos(a), sin(a)) * 0.130)
	# Two recoil adapters with exposed springs, slung over the shoulders.
	for side: float in [-1.0, 1.0]:
		var at := Vector2(cos(deg_to_rad(54.0)) * side, sin(deg_to_rad(54.0))) * 0.156
		base = tube(st, base, 0.30, 0.66, 0.0175, 0.0175, 10, at)
		base = tube(st, base, 0.63, 0.70, 0.030, 0.030, 10, at)
		base = spring(st, base, 0.70, 1.02, 0.026, 0.0068, 7.0, at)
		base = tube(st, base, 1.00, 1.08, 0.034, 0.034, 10, at)
		base = tube(st, base, 1.06, 1.42, 0.022, 0.022, 10, at)
	# Drive motor on the right shoulder, with cooling fins.
	var motor := Vector2(0.132, -0.044)
	base = tube(st, base, 1.00, 1.07, 0.034, 0.052, 14, motor)
	base = tube(st, base, 1.07, 1.32, 0.052, 0.052, 14, motor)
	for i in range(6):
		var z: float = 1.12 + i * 0.035
		base = loft(st, base, [[z, circle(14, 0.054), motor], [z + 0.012, circle(14, 0.068), motor], [z + 0.020, circle(14, 0.068), motor], [z + 0.030, circle(14, 0.054), motor]], false, false)
	base = tube(st, base, 1.32, 1.37, 0.042, 0.026, 14, motor)
	# Feed throat into the fuselage; the pod's armoured duct covers the run.
	base = loft(st, base, [
		[1.46, circle(14, 0.062, 0.044), Vector2(-0.030, 0.052)],
		[1.60, circle(14, 0.066, 0.048), Vector2(-0.038, 0.072)],
		[1.86, circle(14, 0.060, 0.044), Vector2(-0.046, 0.086)]], true, true)
	_finish(st, material, "Housing", parent)

static func _cannon_pod(parent: Node3D, material: Material, trim: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	var sides := 16
	# A low faceted blister, not a torpedo: a crowned deck that mates with the
	# chine, a hard edge down each flank, a flat keel, and a raked shroud that
	# stops well short of the barrels so the cluster stays the silhouette.
	var shell: Array = [
		# Raked shroud collar.
		[0.010, section(sides, 0.128, 0.116, 0.52), Vector2(0.0, 0.006), -0.048],
		[0.070, section(sides, 0.162, 0.146, 0.26), Vector2(0.0, 0.006), -0.032],
		[0.150, section(sides, 0.182, 0.162, 0.10), Vector2(0.0, 0.006), -0.010],
		# Hard step where the collar meets the blister skin.
		[0.152, section(sides, 0.196, 0.174, 0.06), Vector2(0.0, 0.006), -0.008],
		[0.330, section(sides, 0.200, 0.176, 0.03), Vector2(0.0, 0.006), 0.0],
		[0.680, section(sides, 0.202, 0.178, 0.02), Vector2(0.0, 0.004), 0.0],
		# Recessed panel joint over the breech.
		[1.120, section(sides, 0.202, 0.178, 0.02), Vector2(0.0, 0.004), 0.0],
		[1.138, section(sides, 0.194, 0.170, 0.02), Vector2(0.0, 0.004), 0.0],
		[1.200, section(sides, 0.194, 0.170, 0.02), Vector2(0.0, 0.004), 0.0],
		[1.218, section(sides, 0.201, 0.177, 0.02), Vector2(0.0, 0.004), 0.0],
		[1.620, section(sides, 0.196, 0.170, 0.03), Vector2(0.0, 0.002), 0.0],
		[1.980, section(sides, 0.172, 0.144, 0.06), Vector2(0.0, -0.006), 0.0],
		[2.320, section(sides, 0.132, 0.102, 0.12), Vector2(0.0, -0.020), 0.0],
		[2.620, section(sides, 0.080, 0.054, 0.20), Vector2(0.0, -0.020), 0.0],
		[2.820, section(sides, 0.034, 0.020, 0.34), Vector2(0.0, -0.046), 0.0]]
	base = loft(st, base, shell, false, true, Vector2(1.0, 1.4), -1)
	# Shroud interior: a short back-facing wall so the gun port reads as a hole.
	base = loft(st, base, [
		[0.010, circle(sides, 0.106), Vector2(0.0, 0.006), -0.048],
		[0.110, circle(sides, 0.112), Vector2(0.0, 0.006), -0.020],
		[0.320, circle(sides, 0.146), Vector2(0.0, 0.006), 0.0]], false, true, Vector2(1.0, 1.4), -1)
	# Rolled lip joining the shroud interior to the outer skin.
	base = loft(st, base, [
		[0.010, circle(sides, 0.106), Vector2(0.0, 0.006), -0.048],
		[-0.004, circle(sides, 0.120), Vector2(0.0, 0.006), -0.050],
		[0.002, section(sides, 0.128, 0.116, 0.52), Vector2(0.0, 0.006), -0.049],
		[0.010, section(sides, 0.128, 0.116, 0.52), Vector2(0.0, 0.006), -0.048]], false, false, Vector2(1.0, 1.4), -1)
	# Gas-vent louvres let down into the deck.
	for i in range(5):
		var z: float = 0.42 + i * 0.112
		base = loft(st, base, [
			[z, circle(8, 0.052, 0.012), Vector2(-0.030, 0.152)],
			[z + 0.012, circle(8, 0.054, 0.016), Vector2(-0.030, 0.156)],
			[z + 0.058, circle(8, 0.054, 0.016), Vector2(-0.030, 0.156)],
			[z + 0.070, circle(8, 0.052, 0.012), Vector2(-0.030, 0.152)]], true, true, Vector2(1.0, 4.0), -1)
	# Blown fairing over the drive motor on the right cheek.
	base = loft(st, base, [
		[0.940, circle(12, 0.040, 0.052), Vector2(0.176, -0.030)],
		[1.020, circle(12, 0.062, 0.076), Vector2(0.182, -0.034)],
		[1.300, circle(12, 0.062, 0.076), Vector2(0.182, -0.034)],
		[1.420, circle(12, 0.030, 0.040), Vector2(0.170, -0.028)]], true, true)
	# Armoured feed duct hugging the deck into the fuselage.
	var duct: Array = []
	for i in range(7):
		var t: float = float(i) / 6.0
		var z: float = lerpf(1.42, 2.44, t)
		duct.append([z, section(12, lerpf(0.082, 0.064, t), lerpf(0.038, 0.030, t), 0.30), Vector2(-0.044 - 0.020 * t, 0.150 - 0.044 * t)])
	base = loft(st, base, duct, true, true, Vector2(1.0, 2.0), -1)
	_finish(st, material, "Pod", parent)

	# Gold strake along each chine edge - the aircraft's only warm accent.
	var gold := SurfaceTool.new()
	gold.begin(Mesh.PRIMITIVE_TRIANGLES)
	var index := 0
	for corner: int in [0, sides / 2]:
		var strake: Array = []
		for entry: Array in shell:
			var z: float = entry[0]
			if z < 0.14 or z > 2.36: continue
			var points: PackedVector2Array = entry[1]
			var offset: Vector2 = entry[2]
			var edge: Vector2 = points[corner]
			var out: Vector2 = edge.normalized()
			var ring := PackedVector2Array()
			for k in range(6):
				var a: float = TAU * float(k) / 6.0
				ring.append(edge + out * 0.0015 + Vector2(-out.y, out.x) * cos(a) * 0.0055 + out * sin(a) * 0.0030)
			strake.append([z, ring, offset])
		index = loft(gold, index, strake, true, true, Vector2(1.0, 8.0))
	_finish(gold, trim, "PodTrim", parent)

# ------------------------------------------------------------ plasma cannon --

static func plasma_cannon() -> Node3D:
	var root := Node3D.new()
	root.name = "PC26"
	var armour: ShaderMaterial = housing(0, {"tex_scale": 2.2})
	var trim: ShaderMaterial = housing(0, {"gold_mix": 1.0, "tex_scale": 5.0})
	var vane_material: ShaderMaterial = metal({"tex_scale": 4.0, "rough_lo": 0.14, "rough_hi": 0.40, "base_tint": Color(0.030, 0.032, 0.038)})
	var coil: ShaderMaterial = housing(1)
	var throat: ShaderMaterial = housing(2)

	_plasma_body(root, armour)
	_plasma_vanes(root, vane_material)
	_plasma_coils(root, coil)
	_plasma_trim(root, trim)

	var core := MeshInstance3D.new()
	core.name = "Throat"
	var bulb := SphereMesh.new()
	bulb.radius = 0.074
	bulb.height = 0.148
	bulb.radial_segments = 24
	bulb.rings = 12
	core.mesh = bulb
	core.position.z = -0.445
	core.material_override = throat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)

	var corona := MeshInstance3D.new()
	corona.name = "Corona"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	corona.mesh = quad
	corona.position.z = -0.54
	var glow := ShaderMaterial.new()
	glow.shader = load(BLOOM_SHADER)
	glow.set_shader_parameter("mode", 2)
	glow.set_shader_parameter("loop", 1.0)
	glow.set_shader_parameter("t", 0.0)
	glow.set_shader_parameter("size", 0.56)
	glow.set_shader_parameter("grow", 1.0)
	glow.set_shader_parameter("intensity", 0.0)
	glow.set_shader_parameter("core_colour", Color(0.85, 0.95, 1.0))
	glow.set_shader_parameter("edge_colour", Color(0.55, 0.20, 1.0))
	corona.material_override = glow
	corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(corona)

	var muzzle := Marker3D.new()
	muzzle.name = "BeamMuzzle"
	muzzle.position.z = -0.52
	root.add_child(muzzle)

	for node: Node in root.find_children("*", "GeometryInstance3D", true, false): node.layers = 2
	root.set_meta("charge_materials", [armour, trim, coil, throat, glow])
	return root

static func _plasma_body(parent: Node3D, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	var sides := 16
	# A segmented accelerator: a faceted muzzle collar, four armour sleeves with
	# the capacitor rings showing through the gaps, then a heavy breech block.
	base = loft(st, base, [
		[-0.520, section(sides, 0.120, 0.112, 0.20), Vector2.ZERO],
		[-0.500, section(sides, 0.152, 0.142, 0.14), Vector2.ZERO],
		[-0.448, section(sides, 0.156, 0.146, 0.12), Vector2.ZERO],
		[-0.430, section(sides, 0.140, 0.132, 0.12), Vector2.ZERO]], true, true, Vector2(1.0, 1.4), -1)
	for i in range(4):
		var z: float = -0.408 + i * 0.186
		base = loft(st, base, [
			[z, section(sides, 0.132, 0.126, 0.10), Vector2.ZERO],
			[z + 0.016, section(sides, 0.152, 0.144, 0.08), Vector2.ZERO],
			[z + 0.136, section(sides, 0.152, 0.144, 0.08), Vector2.ZERO],
			[z + 0.152, section(sides, 0.132, 0.126, 0.10), Vector2.ZERO]], true, true, Vector2(1.0, 1.4), -1)
	# Breech block.
	base = loft(st, base, [
		[0.300, section(sides, 0.150, 0.142, 0.08), Vector2.ZERO],
		[0.330, section(sides, 0.196, 0.180, 0.04), Vector2.ZERO],
		[0.620, section(sides, 0.202, 0.186, 0.03), Vector2.ZERO],
		[0.640, section(sides, 0.192, 0.178, 0.04), Vector2.ZERO],
		[0.700, section(sides, 0.192, 0.178, 0.04), Vector2.ZERO],
		[0.720, section(sides, 0.200, 0.184, 0.03), Vector2.ZERO],
		[0.960, section(sides, 0.188, 0.172, 0.06), Vector2.ZERO],
		[1.060, section(sides, 0.140, 0.122, 0.16), Vector2.ZERO],
		[1.150, section(sides, 0.062, 0.050, 0.40), Vector2.ZERO]], true, true, Vector2(1.0, 1.4), -1)
	# Dorsal heat-sink stack, sunk into the deck.
	for i in range(8):
		var z: float = 0.350 + i * 0.076
		base = loft(st, base, [
			[z, circle(8, 0.062, 0.014), Vector2(0.0, 0.150)],
			[z + 0.013, circle(8, 0.070, 0.017), Vector2(0.0, 0.168)],
			[z + 0.040, circle(8, 0.070, 0.017), Vector2(0.0, 0.168)],
			[z + 0.053, circle(8, 0.062, 0.014), Vector2(0.0, 0.150)]], true, true, Vector2(1.0, 4.0), -1)
	# Aperture cavity behind the collar.
	base = loft(st, base, [
		[-0.280, circle(sides, 0.118), Vector2.ZERO],
		[-0.520, circle(sides, 0.106), Vector2.ZERO]], false, false)
	_finish(st, material, "Housing", parent)

static func _plasma_vanes(parent: Node3D, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	# Six focusing vanes converging on the throat, like a turbine's stators.
	for i in range(6):
		var a: float = TAU * float(i) / 6.0 + 0.26
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var rings: Array = []
		for k in range(5):
			var t: float = float(k) / 4.0
			var z: float = lerpf(-0.534, -0.300, t)
			var reach: float = lerpf(0.046, 0.104, t)
			var thick: float = lerpf(0.0075, 0.014, t)
			var depth: float = lerpf(0.024, 0.042, t)
			var ring := PackedVector2Array()
			for sample in range(10):
				var b: float = TAU * float(sample) / 10.0
				ring.append(dir * (reach + sin(b) * depth) + side * cos(b) * thick)
			rings.append([z, ring, Vector2.ZERO])
		base = loft(st, base, rings, true, true, Vector2(1.0, 4.0), -1)
	_finish(st, material, "Vanes", parent)

static func _plasma_coils(parent: Node3D, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	# Capacitor rings standing proud in the gaps between armour sleeves.
	for i in range(5):
		var z: float = -0.430 + i * 0.186
		base = loft(st, base, [
			[z - 0.014, circle(28, 0.128, 0.122), Vector2.ZERO],
			[z - 0.007, circle(28, 0.158, 0.149), Vector2.ZERO],
			[z + 0.007, circle(28, 0.158, 0.149), Vector2.ZERO],
			[z + 0.014, circle(28, 0.128, 0.122), Vector2.ZERO]], true, true)
	# Three rails linking the rings back to the breech.
	for a: float in [deg_to_rad(206.0), deg_to_rad(270.0), deg_to_rad(334.0)]:
		var at := Vector2(cos(a) * 0.150, sin(a) * 0.142)
		base = tube(st, base, -0.430, 0.320, 0.0105, 0.0105, 8, at)
	_finish(st, material, "Coils", parent)

static func _plasma_trim(parent: Node3D, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	# One gold band at the emitter collar and one at the breech shoulder. The
	# key art uses gold sparingly; so does the gun.
	base = loft(st, base, [
		[-0.474, section(16, 0.1545, 0.1445, 0.12), Vector2.ZERO],
		[-0.468, section(16, 0.1585, 0.1485, 0.12), Vector2.ZERO],
		[-0.456, section(16, 0.1585, 0.1485, 0.12), Vector2.ZERO],
		[-0.450, section(16, 0.1545, 0.1445, 0.12), Vector2.ZERO]], false, false, Vector2(1.0, 6.0), -1)
	base = loft(st, base, [
		[0.648, section(16, 0.1925, 0.1785, 0.04), Vector2.ZERO],
		[0.656, section(16, 0.1965, 0.1825, 0.04), Vector2.ZERO],
		[0.692, section(16, 0.1965, 0.1825, 0.04), Vector2.ZERO],
		[0.700, section(16, 0.1925, 0.1785, 0.04), Vector2.ZERO]], false, false, Vector2(1.0, 6.0), -1)
	_finish(st, material, "Trim", parent)

# ------------------------------------------------------------------ drivers --

## Barrel heat, 0..1. Call every frame while the gun runs; decay it afterwards.
static func set_heat(weapon: Node, heat: float) -> void:
	if weapon == null or not weapon.has_meta("heat_materials"): return
	for material: ShaderMaterial in weapon.get_meta("heat_materials"):
		material.set_shader_parameter("heat", clampf(heat, 0.0, 1.0))

## Plasma spool-up (0..1) and discharge (0..1).
static func set_charge(weapon: Node, charge: float, firing: float = 0.0) -> void:
	if weapon == null or not weapon.has_meta("charge_materials"): return
	var c: float = clampf(charge, 0.0, 1.0)
	var f: float = clampf(firing, 0.0, 1.0)
	for material: ShaderMaterial in weapon.get_meta("charge_materials"):
		if material.shader == null: continue
		if material.get_shader_parameter("mode") != null and material.shader.resource_path.ends_with("impact_bloom.gdshader"):
			material.set_shader_parameter("intensity", c * 1.6 + f * 4.0)
			material.set_shader_parameter("size", 0.34 + c * 0.26 + f * 0.34)
		else:
			material.set_shader_parameter("charge", c)
			material.set_shader_parameter("firing", f)
