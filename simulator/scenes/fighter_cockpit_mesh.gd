extends RefCounted
class_name CockpitMesh
## Procedural mesh kit for the fighter interior.
##
## Everything is authored in COCKPIT SPACE: the pilot's eye is the origin, -Z is
## forward, +Y is up, +X is to the pilot's right. Geometry is accumulated into a
## handful of per-material SurfaceTool groups and committed as one MeshInstance3D
## each, so a cockpit with a few hundred parts still costs about a dozen draws.
##
## Ambient occlusion is baked into vertex colour at emit time. Real-time shadow
## maps do not resolve a 1 m interior when the scene's directional light is sized
## for a 1.4 km landscape, and baked AO is what actually makes bevels, recesses
## and crevices read as three-dimensional.

# 5x7 stencil face for cockpit placards, packed one glyph per 14 hex digits
# (7 rows, five bits each). One atlas, one draw call, no Label3D per legend.
const FONT_ORDER := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -./:+°"
const FONT_BITS := "0E11111F1111111E11111E11111E0E11101010110E1E11111111111E1F10101E10101F1F10101E1010100E11101711110F" + \
	"1111111F1111110E04040404040E0702020202120C111214181412111010101010101F111B151511111111191513111111" + \
	"0E11111111110E1E11111E1010100E11111115120D1E11111E1412110F10100E01011E1F0404040404041111111111110E" + \
	"11111111110A0411111115151B1111110A040A111111110A040404041F01020408101F0E11131519110E040C040404040E" + \
	"0E11010608101F1F02040201110E02060A121F02021F101E0101110E0608101E11110E1F0102040808080E11110E11110E" + \
	"0E11110F01020C000000000000000000001F00000000000000000C0C01020204080810000C0C000C0C000004041F040400" + \
	"0C12120C000000"
const FONT_COLUMNS := 8
const FONT_CELL := 24
const FONT_SCALE := 3    # glyph drawn at 15 x 21 inside the cell

# The canopy opening used for the sky-visibility term of the baked AO.
var rim_y := -0.255
var rim_half_width := 0.50
var rim_front := -1.62
var rim_back := 0.62

var groups: Dictionary = {}
var order: Array[String] = []
var occluders: Array[Dictionary] = []
var _ao_cache: Dictionary = {}
var _font_atlas: ImageTexture
var _font_index: Dictionary = {}

# ---------------------------------------------------------------- groups

func group(name: String, material: Material, cast_shadow: bool = true) -> void:
	if groups.has(name): return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	groups[name] = {"st": st, "material": material, "tris": 0, "shadow": cast_shadow}
	order.append(name)

func triangle_count() -> int:
	var total := 0
	for name: String in order: total += int(groups[name].tris)
	return total

## One MeshInstance3D per material group. `layer` is the visual layer mask the
## cockpit-only light rig is filtered to.
func commit(parent: Node3D, prefix: String, layer: int) -> Array[MeshInstance3D]:
	var built: Array[MeshInstance3D] = []
	for name: String in order:
		var bucket: Dictionary = groups[name]
		if int(bucket.tris) == 0: continue
		var st: SurfaceTool = bucket.st
		st.index()
		var instance := MeshInstance3D.new()
		instance.name = prefix + "_" + name
		instance.mesh = st.commit()
		instance.material_override = bucket.material
		instance.layers = layer
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(bucket.shadow) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A cockpit part is never culled by its own bounds: the camera sits inside it.
		instance.extra_cull_margin = 4.0
		parent.add_child(instance)
		built.append(instance)
	return built

# ---------------------------------------------------------- occluders / AO

## Register a solid the baked AO should darken around. `reach` is the AO radius
## in metres; `strength` how black the contact gets.
func occluder(box: AABB, reach: float = 0.13, strength: float = 0.72) -> int:
	occluders.append({"box": box.abs(), "reach": maxf(reach, 0.01), "strength": strength})
	return occluders.size() - 1

func ao_at(point: Vector3, normal: Vector3, skip: int = -1) -> float:
	var key := Vector4i(roundi(point.x * 150.0), roundi(point.y * 150.0), roundi(point.z * 150.0),
		(skip + 1) * 32 + _normal_bucket(normal))
	if _ao_cache.has(key): return _ao_cache[key]
	var value: float = _compute_ao(point, normal, skip)
	_ao_cache[key] = value
	return value

func _normal_bucket(n: Vector3) -> int:
	return (1 + signi(roundi(n.x * 1.4))) * 9 + (1 + signi(roundi(n.y * 1.4))) * 3 + (1 + signi(roundi(n.z * 1.4)))

func _compute_ao(point: Vector3, normal: Vector3, skip: int) -> float:
	var openness := 1.0
	var toward := Vector3.UP
	if point.y < rim_y:
		var h: float = maxf(rim_y - point.y, 0.03)
		var ax: float = atan((rim_half_width - point.x) / h) + atan((rim_half_width + point.x) / h)
		var az: float = atan((rim_back - point.z) / h) + atan((point.z - rim_front) / h)
		openness = clampf(ax * az / (PI * PI), 0.0, 1.0)
		toward = (Vector3(clampf(point.x, -rim_half_width, rim_half_width), rim_y,
			clampf(point.z, rim_front, rim_back)) - point).normalized()
	var facing: float = clampf(0.34 + 0.66 * normal.dot(toward), 0.11, 1.0)
	var value: float = 0.21 + 0.79 * pow(openness, 0.62) * facing
	for i in range(occluders.size()):
		if i == skip: continue
		var item: Dictionary = occluders[i]
		var box: AABB = item.box
		var reach: float = item.reach
		if not box.grow(reach).has_point(point): continue
		var near := Vector3(
			clampf(point.x, box.position.x, box.end.x),
			clampf(point.y, box.position.y, box.end.y),
			clampf(point.z, box.position.z, box.end.z))
		var distance: float = point.distance_to(near)
		if distance >= reach: continue
		var direction: Vector3 = (near - point)
		if distance < 0.0008: direction = box.get_center() - point
		if direction.length_squared() < 1e-8: direction = Vector3.DOWN
		var weight: float = 1.0 - distance / reach
		weight = weight * weight
		value *= 1.0 - float(item.strength) * weight * clampf(normal.dot(direction.normalized()), 0.0, 1.0)
	# A cockpit reads dark because the sky outside is blinding, not because its
	# corners are black. Never let baked occlusion crush a surface to nothing.
	return clampf(value, 0.155, 1.0)

# ------------------------------------------------------------- primitives

## Emit one triangle. Vertices are authored counter-clockwise seen from outside;
## Godot wants clockwise front faces, so the order is flipped here.
func tri(name: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, tint: Color, skip: int, flat: float) -> void:
	var bucket: Dictionary = groups[name]
	var st: SurfaceTool = bucket.st
	for entry: Array in [[a, na, ua], [c, nc, uc], [b, nb, ub]]:
		var position: Vector3 = entry[0]
		var normal: Vector3 = entry[1]
		var shade: float = flat if flat >= 0.0 else ao_at(position, normal, skip)
		st.set_color(Color(tint.r * shade, tint.g * shade, tint.b * shade, tint.a))
		st.set_normal(normal)
		st.set_uv(entry[2])
		st.add_vertex(position)
	bucket.tris = int(bucket.tris) + 1

func quad(name: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color = Color.WHITE,
		skip: int = -1, flat: float = -1.0, uv_scale: float = 6.0) -> void:
	var normal: Vector3 = (b - a).cross(c - a)
	if normal.length_squared() < 1e-12: return
	normal = normal.normalized()
	var ua := _plane_uv(a, normal, uv_scale)
	var ub := _plane_uv(b, normal, uv_scale)
	var uc := _plane_uv(c, normal, uv_scale)
	var ud := _plane_uv(d, normal, uv_scale)
	tri(name, a, b, c, normal, normal, normal, ua, ub, uc, tint, skip, flat)
	tri(name, a, c, d, normal, normal, normal, ua, uc, ud, tint, skip, flat)

func _plane_uv(p: Vector3, n: Vector3, scale: float) -> Vector2:
	var ax: Vector3 = Vector3.UP if absf(n.y) < 0.85 else Vector3.BACK
	var u: Vector3 = ax.cross(n).normalized()
	var v: Vector3 = n.cross(u)
	return Vector2(p.dot(u), p.dot(v)) * scale

## Bevelled box. Real cockpit hardware has no razor edges; the chamfer is what
## catches the light and separates one black box from the next.
func box(name: String, center: Vector3, size: Vector3, bevel: float = 0.006, basis: Basis = Basis.IDENTITY,
		tint: Color = Color.WHITE, skip: int = -1, flat: float = -1.0) -> void:
	var half: Vector3 = size * 0.5
	var chamfer: float = minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.42)
	var inner: Vector3 = half - Vector3.ONE * chamfer
	var shade: float = flat
	if shade < 0.0 and size.length() < 0.075: shade = ao_at(center, Vector3.UP, skip)
	var faces: Array = []
	for axis in range(3):
		var u: int = (axis + 1) % 3
		var v: int = (axis + 2) % 3
		for sign_value in [-1.0, 1.0]:
			var face: Array[Vector3] = []
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := Vector3.ZERO
				point[axis] = half[axis] * sign_value
				point[u] = inner[u] * corner.x
				point[v] = inner[v] * corner.y
				face.append(point)
			faces.append(face)
	for axis in range(3):
		var u: int = (axis + 1) % 3
		var v: int = (axis + 2) % 3
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var face: Array[Vector3] = []
				for corner in [Vector2(-1, 0), Vector2(1, 0), Vector2(1, 1), Vector2(-1, 1)]:
					var point := Vector3.ZERO
					point[axis] = inner[axis] * corner.x
					point[u] = (half[u] if corner.y == 0 else inner[u]) * su
					point[v] = (inner[v] if corner.y == 0 else half[v]) * sv
					face.append(point)
				faces.append(face)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				faces.append([Vector3(half.x * x, inner.y * y, inner.z * z),
					Vector3(inner.x * x, half.y * y, inner.z * z),
					Vector3(inner.x * x, inner.y * y, half.z * z)])
	for face: Array in faces:
		var world: Array[Vector3] = []
		for point: Vector3 in face: world.append(center + basis * point)
		var normal: Vector3 = (world[1] - world[0]).cross(world[2] - world[0])
		if normal.length_squared() < 1e-14: continue
		normal = normal.normalized()
		var middle := Vector3.ZERO
		for point: Vector3 in world: middle += point
		middle /= float(world.size())
		if normal.dot(middle - center) < 0.0:
			world.reverse()
			normal = -normal
		for i in range(1, world.size() - 1):
			tri(name, world[0], world[i], world[i + 1], normal, normal, normal,
				_plane_uv(world[0], normal, 6.0), _plane_uv(world[i], normal, 6.0),
				_plane_uv(world[i + 1], normal, 6.0), tint, skip, shade)

## Swept tube along `path`. `reference` pins the section's roll so a canopy bow
## keeps a flat face toward the pilot instead of twisting.
func sweep(name: String, path: Array, half_a: float, half_b: float, reference: Vector3, sides: int = 10,
		tint: Color = Color.WHITE, skip: int = -1, taper: float = 1.0, flatten: float = 0.0) -> void:
	if path.size() < 2: return
	var rings: Array = []
	for i in range(path.size()):
		var t: float = float(i) / float(maxi(path.size() - 1, 1))
		var scale: float = lerpf(1.0, taper, t)
		var tangent: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)])
		if tangent.length_squared() < 1e-12: tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var binormal: Vector3 = (reference - tangent * reference.dot(tangent))
		if binormal.length_squared() < 1e-10: binormal = tangent.cross(Vector3.RIGHT)
		binormal = binormal.normalized()
		var normal: Vector3 = tangent.cross(binormal).normalized()
		var ring: Array = []
		for s in range(sides):
			var a: float = TAU * float(s) / float(sides)
			var cs: float = cos(a)
			var sn: float = sin(a)
			# `flatten` squares off the section: a real canopy bow is a flat-faced bar.
			var fx: float = signf(cs) * pow(absf(cs), 1.0 - flatten * 0.62) if cs != 0.0 else 0.0
			var fy: float = signf(sn) * pow(absf(sn), 1.0 - flatten * 0.62) if sn != 0.0 else 0.0
			var offset: Vector3 = normal * fx * half_a * scale + binormal * fy * half_b * scale
			ring.append([path[i] + offset, (normal * fx / half_a + binormal * fy / half_b).normalized(),
				Vector2(float(s) / float(sides) * 2.0, t * 4.0)])
		rings.append(ring)
	for i in range(rings.size() - 1):
		for s in range(sides):
			var n: int = (s + 1) % sides
			var v00: Array = rings[i][s]
			var v10: Array = rings[i + 1][s]
			var v11: Array = rings[i + 1][n]
			var v01: Array = rings[i][n]
			tri(name, v00[0], v10[0], v11[0], v00[1], v10[1], v11[1], v00[2], v10[2], v11[2], tint, skip, -1.0)
			tri(name, v00[0], v11[0], v01[0], v00[1], v11[1], v01[1], v00[2], v11[2], v01[2], tint, skip, -1.0)

## Loft a closed or open cross-section along a list of station transforms.
## `sections` is an Array of Arrays of Vector3 (same length), already in cockpit space.
func loft(name: String, sections: Array, closed: bool, tint: Color = Color.WHITE, skip: int = -1,
		smooth: bool = false) -> void:
	if sections.size() < 2: return
	var count: int = (sections[0] as Array).size()
	if not smooth:
		for i in range(sections.size() - 1):
			var a: Array = sections[i]
			var b: Array = sections[i + 1]
			var last: int = count if closed else count - 1
			for s in range(last):
				var n: int = (s + 1) % count
				quad(name, a[s], b[s], b[n], a[n], tint, skip, -1.0, 3.0)
		return
	# Average the four surrounding face normals at every grid point, so a curved
	# hood or a tub wall shades as one surface instead of a run of flat panels.
	var normals: Array = []
	for i in range(sections.size()):
		var row: Array = []
		for s in range(count):
			row.append(Vector3.ZERO)
		normals.append(row)
	var last_span: int = count if closed else count - 1
	for i in range(sections.size() - 1):
		var a: Array = sections[i]
		var b: Array = sections[i + 1]
		for s in range(last_span):
			var n: int = (s + 1) % count
			var face: Vector3 = (b[s] - a[s]).cross(a[n] - a[s])
			if face.length_squared() < 1e-14: continue
			face = face.normalized()
			normals[i][s] += face
			normals[i + 1][s] += face
			normals[i + 1][n] += face
			normals[i][n] += face
	for i in range(sections.size()):
		for s in range(count):
			var value: Vector3 = normals[i][s]
			normals[i][s] = value.normalized() if value.length_squared() > 1e-12 else Vector3.UP
	for i in range(sections.size() - 1):
		var a: Array = sections[i]
		var b: Array = sections[i + 1]
		for s in range(last_span):
			var n: int = (s + 1) % count
			var uv0 := Vector2(float(s) * 0.25, float(i) * 0.25)
			var uv1 := Vector2(float(s) * 0.25, float(i + 1) * 0.25)
			var uv2 := Vector2(float(s + 1) * 0.25, float(i + 1) * 0.25)
			var uv3 := Vector2(float(s + 1) * 0.25, float(i) * 0.25)
			tri(name, a[s], b[s], b[n], normals[i][s], normals[i + 1][s], normals[i + 1][n],
				uv0, uv1, uv2, tint, skip, -1.0)
			tri(name, a[s], b[n], a[n], normals[i][s], normals[i + 1][n], normals[i][n],
				uv0, uv2, uv3, tint, skip, -1.0)

## Surface of revolution around an axis through `origin` along `axis`.
## `profile` is a list of Vector2(radius, along-axis distance). Normals are
## always smooth around the axis; `smooth` additionally blends them along the
## profile, which is what a thigh or a finger wants and a knob's rim does not.
func lathe(name: String, profile: Array, origin: Vector3, axis: Vector3, segments: int = 16,
		tint: Color = Color.WHITE, skip: int = -1, flat: float = -1.0, smooth: bool = false) -> void:
	if profile.size() < 2: return
	var up: Vector3 = axis.normalized()
	var side: Vector3 = (Vector3.UP if absf(up.y) < 0.85 else Vector3.RIGHT).cross(up).normalized()
	var other: Vector3 = up.cross(side)
	var vertex_normal: Array = []
	for i in range(profile.size()):
		var back: Vector2 = profile[maxi(i - 1, 0)]
		var ahead: Vector2 = profile[mini(i + 1, profile.size() - 1)]
		var step: Vector2 = ahead - back
		vertex_normal.append(Vector2(step.y, -step.x).normalized() if step.length_squared() > 1e-14 else Vector2(1, 0))
	var run: float = 0.0
	for i in range(profile.size() - 1):
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var step: Vector2 = p1 - p0
		if step.length_squared() < 1e-14: continue
		var face := Vector2(step.y, -step.x).normalized()
		var n0: Vector2 = vertex_normal[i] if smooth else face
		var n1: Vector2 = vertex_normal[i + 1] if smooth else face
		var run_next: float = run + step.length()
		for s in range(segments):
			var a0: float = TAU * float(s) / float(segments)
			var a1: float = TAU * float(s + 1) / float(segments)
			var r0: Vector3 = side * cos(a0) + other * sin(a0)
			var r1: Vector3 = side * cos(a1) + other * sin(a1)
			var v00: Vector3 = origin + r0 * p0.x + up * p0.y
			var v01: Vector3 = origin + r1 * p0.x + up * p0.y
			var v10: Vector3 = origin + r0 * p1.x + up * p1.y
			var v11: Vector3 = origin + r1 * p1.x + up * p1.y
			var m00: Vector3 = (r0 * n0.x + up * n0.y).normalized()
			var m01: Vector3 = (r1 * n0.x + up * n0.y).normalized()
			var m10: Vector3 = (r0 * n1.x + up * n1.y).normalized()
			var m11: Vector3 = (r1 * n1.x + up * n1.y).normalized()
			var u0 := Vector2(float(s) / float(segments) * 2.0, run * 5.0)
			var u1 := Vector2(float(s + 1) / float(segments) * 2.0, run * 5.0)
			var u2 := Vector2(float(s + 1) / float(segments) * 2.0, run_next * 5.0)
			var u3 := Vector2(float(s) / float(segments) * 2.0, run_next * 5.0)
			if p0.x < 1e-7:
				tri(name, v00, v11, v10, m00, m11, m10, u0, u2, u3, tint, skip, flat)
			elif p1.x < 1e-7:
				tri(name, v00, v01, v11, m00, m01, m11, u0, u1, u2, tint, skip, flat)
			else:
				tri(name, v00, v01, v11, m00, m01, m11, u0, u1, u2, tint, skip, flat)
				tri(name, v00, v11, v10, m00, m11, m10, u0, u2, u3, tint, skip, flat)
		run = run_next

func cylinder(name: String, from: Vector3, to: Vector3, radius: float, segments: int = 12,
		tint: Color = Color.WHITE, skip: int = -1, flat: float = -1.0, caps: bool = true) -> void:
	var axis: Vector3 = to - from
	var length: float = axis.length()
	if length < 1e-6: return
	var profile: Array = []
	if caps: profile.append(Vector2(0.0, 0.0))
	profile.append(Vector2(radius, 0.0))
	profile.append(Vector2(radius, length))
	if caps: profile.append(Vector2(0.0, length))
	lathe(name, profile, from, axis / length, segments, tint, skip,
		flat if flat >= 0.0 else ao_at((from + to) * 0.5, Vector3.UP, skip), false)

## Tapered rounded limb: the shape a thigh, a forearm or a finger actually makes.
func limb(name: String, from: Vector3, to: Vector3, radius_from: float, radius_to: float,
		segments: int = 10, rings: int = 7, tint: Color = Color.WHITE, skip: int = -1) -> void:
	var axis: Vector3 = to - from
	var length: float = axis.length()
	if length < 1e-6: return
	var direction: Vector3 = axis / length
	var profile: Array = [Vector2(0.0, 0.0)]
	for i in range(rings + 1):
		var t: float = float(i) / float(rings)
		var radius: float = lerpf(radius_from, radius_to, t)
		# Rounded ends, so a limb never shows a hard disc where it leaves frame.
		var cap: float = 1.0
		if t < 0.14: cap = sqrt(maxf(1.0 - pow(1.0 - t / 0.14, 2.0), 0.04))
		elif t > 0.86: cap = sqrt(maxf(1.0 - pow((t - 0.86) / 0.14, 2.0), 0.04))
		profile.append(Vector2(radius * cap, t * length))
	profile.append(Vector2(0.0, length))
	lathe(name, profile, from, direction, segments, tint, skip, -1.0, true)

func ball(name: String, center: Vector3, radius: Vector3, segments: int = 12, rings: int = 8,
		tint: Color = Color.WHITE, skip: int = -1) -> void:
	for r in range(rings):
		var p0: float = PI * float(r) / float(rings)
		var p1: float = PI * float(r + 1) / float(rings)
		for s in range(segments):
			var a0: float = TAU * float(s) / float(segments)
			var a1: float = TAU * float(s + 1) / float(segments)
			var points: Array = []
			var normals: Array = []
			var uvs: Array = []
			for pair in [[p0, a0], [p0, a1], [p1, a1], [p1, a0]]:
				var unit := Vector3(sin(pair[0]) * cos(pair[1]), cos(pair[0]), sin(pair[0]) * sin(pair[1]))
				points.append(center + Vector3(unit.x * radius.x, unit.y * radius.y, unit.z * radius.z))
				normals.append(Vector3(unit.x / radius.x, unit.y / radius.y, unit.z / radius.z).normalized())
				uvs.append(Vector2(pair[1] / TAU * 2.0, pair[0] / PI * 2.0))
			tri(name, points[0], points[1], points[2], normals[0], normals[1], normals[2],
				uvs[0], uvs[1], uvs[2], tint, skip, -1.0)
			tri(name, points[0], points[2], points[3], normals[0], normals[2], normals[3],
				uvs[0], uvs[2], uvs[3], tint, skip, -1.0)

# ---------------------------------------------------------------- placards

func font_atlas() -> ImageTexture:
	if _font_atlas != null: return _font_atlas
	var rows: int = int(ceil(float(FONT_ORDER.length()) / float(FONT_COLUMNS)))
	var image := Image.create(FONT_COLUMNS * FONT_CELL, rows * FONT_CELL, true, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	for index in range(FONT_ORDER.length()):
		var glyph: String = FONT_BITS.substr(index * 14, 14)
		var cell_x: int = (index % FONT_COLUMNS) * FONT_CELL
		var cell_y: int = floori(float(index) / float(FONT_COLUMNS)) * FONT_CELL
		_font_index[FONT_ORDER[index]] = index
		for row in range(7):
			var bits: int = ("0x" + glyph.substr(row * 2, 2)).hex_to_int()
			for column in range(5):
				if (bits & (1 << (4 - column))) == 0: continue
				for sy in range(FONT_SCALE):
					for sx in range(FONT_SCALE):
						image.set_pixel(cell_x + 3 + column * FONT_SCALE + sx,
							cell_y + 1 + row * FONT_SCALE + sy, Color(1, 1, 1, 1))
	image.generate_mipmaps()
	_font_atlas = ImageTexture.create_from_image(image)
	return _font_atlas

## Stencil legend on a panel. `right` and `up` are the placard's in-plane axes
## (their length is ignored); `height` is the cap height of one glyph.
func placard(name: String, text: String, at: Vector3, right: Vector3, up: Vector3, height: float,
		tint: Color = Color(0.80, 0.83, 0.82), align: float = 0.5) -> void:
	font_atlas()
	var lines: PackedStringArray = text.split("\n")
	var u: Vector3 = right.normalized()
	var v: Vector3 = up.normalized()
	var normal: Vector3 = u.cross(v).normalized()
	var advance: float = height * (6.0 / 7.0)
	var line_step: float = height * 1.42
	var shade: float = ao_at(at, normal, -1)
	var atlas_rows: int = int(ceil(float(FONT_ORDER.length()) / float(FONT_COLUMNS)))
	for line_index in range(lines.size()):
		var line: String = lines[line_index].to_upper()
		var width: float = advance * float(line.length())
		var origin: Vector3 = at + v * (-float(line_index) * line_step + float(lines.size() - 1) * line_step * 0.5) - u * width * align
		for i in range(line.length()):
			var character: String = line[i]
			if not _font_index.has(character):
				if character == " ": continue
				character = "-"
				if not _font_index.has(character): continue
			var index: int = _font_index[character]
			var cell_u: float = float(index % FONT_COLUMNS) / float(FONT_COLUMNS)
			var cell_v: float = floor(float(index) / float(FONT_COLUMNS)) / float(atlas_rows)
			var size_u: float = 1.0 / float(FONT_COLUMNS)
			var size_v: float = 1.0 / float(atlas_rows)
			var glyph_width: float = height * (5.0 / 7.0)
			var a: Vector3 = origin + u * (float(i) * advance)
			var b: Vector3 = a + u * glyph_width
			var c: Vector3 = b + v * height
			var d: Vector3 = a + v * height
			var colour := Color(tint.r * shade, tint.g * shade, tint.b * shade, tint.a)
			_glyph_quad(name, a, b, c, d, normal, colour,
				Vector2(cell_u + size_u * (3.0 / float(FONT_CELL)), cell_v + size_v * (22.0 / float(FONT_CELL))),
				Vector2(cell_u + size_u * (18.0 / float(FONT_CELL)), cell_v + size_v * (1.0 / float(FONT_CELL))))

func _glyph_quad(name: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3,
		tint: Color, uv_min: Vector2, uv_max: Vector2) -> void:
	tri(name, a, b, c, normal, normal, normal, uv_min, Vector2(uv_max.x, uv_min.y), uv_max, tint, -1, 1.0)
	tri(name, a, c, d, normal, normal, normal, uv_min, uv_max, Vector2(uv_min.x, uv_max.y), tint, -1, 1.0)
