extends RefCounted
class_name SpectreAirframe
## The SPECTRE X-26, modelled procedurally with SurfaceTool.
##
## Low-observable shaping is made of flat facets and straight creases, which is
## exactly what a polygon builder is good at: every surface below is an explicit
## polygon with one hard face normal, so the airframe is faceted by construction
## rather than by a smoothing trick. Nose points -Z, up is +Y, and the origin
## sits 3.0 m above the wheels so the shared profile "clearance" still parks the
## aircraft on its gear.
##
## Layout: 15.5 m long, 10.8 m span. Chined forebody, caret intakes, cranked
## diamond wing with a sawtoothed trailing edge, all-moving stabilators, large
## canted fins, one big serrated nozzle.

const WHEEL_BOTTOM := -3.0
const ENGINE_Y := -0.30
const NOZZLE_Z := 7.30
const NOZZLE_R := 0.62
const GOLD := Color(1.00, 0.63, 0.13, 1.0)
const GOLD_DIM := Color(1.00, 0.63, 0.13, 0.42)
const BLOOD := Color(0.46, 0.038, 0.030, 0.08)

# z, spine_x, spine_y, deck_x, deck_y, chine_x, chine_y, belly_x, belly_y, keel_x, keel_y
# The chine is the widest point of every station: it stays near y=0 the whole
# length of the aircraft, which gives the hard horizontal knife edge the key art
# reads as "stealth" before any paint is applied.
const STATIONS := [
	[-8.20, 0.012, 0.010, 0.016, 0.000, 0.020, -0.014, 0.016, -0.028, 0.012, -0.038],
	[-7.85, 0.055, 0.085, 0.105, 0.070, 0.170, -0.060, 0.110, -0.150, 0.055, -0.200],
	[-7.20, 0.125, 0.180, 0.300, 0.150, 0.500, -0.080, 0.320, -0.240, 0.135, -0.330],
	[-6.40, 0.200, 0.235, 0.520, 0.190, 0.850, -0.090, 0.550, -0.340, 0.215, -0.470],
	[-5.50, 0.290, 0.310, 0.700, 0.250, 1.120, -0.090, 0.730, -0.440, 0.285, -0.610],
	[-4.60, 0.350, 0.420, 0.820, 0.350, 1.300, -0.080, 0.850, -0.550, 0.325, -0.750],
	[-3.50, 0.420, 0.550, 0.920, 0.470, 1.450, -0.050, 0.930, -0.660, 0.375, -0.870],
	[-2.30, 0.510, 0.720, 1.000, 0.610, 1.560, -0.010, 1.180, -0.720, 0.425, -0.980],
	[-1.00, 0.610, 0.755, 1.080, 0.640, 1.660, 0.030, 1.310, -0.710, 0.465, -1.020],
	[ 0.40, 0.670, 0.740, 1.140, 0.630, 1.700, 0.050, 1.350, -0.710, 0.495, -1.020],
	[ 1.90, 0.690, 0.700, 1.160, 0.595, 1.660, 0.030, 1.270, -0.730, 0.495, -0.995],
	[ 3.20, 0.690, 0.620, 1.170, 0.535, 1.540, 0.000, 1.070, -0.725, 0.455, -0.945],
	[ 4.50, 0.710, 0.530, 1.170, 0.465, 1.400, -0.050, 0.950, -0.695, 0.395, -0.955],
	[ 5.50, 0.650, 0.460, 1.070, 0.400, 1.240, -0.120, 0.850, -0.685, 0.335, -0.985],
	[ 6.20, 0.420, 0.400, 0.730, 0.330, 0.940, -0.190, 0.680, -0.700, 0.280, -1.020],
]

# --- low level mesh helpers -------------------------------------------------
# Godot front faces are clockwise seen from the shading normal (verified against
# BoxMesh), so _face orders its vertices that way and always sets an explicit
# flat normal: no vertex is ever shared between two facets.

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func _face(st: SurfaceTool, pts: Array, outward: Vector3, color: Color = Color.WHITE) -> void:
	if pts.size() < 3: return
	var count := pts.size()
	var normal := Vector3.ZERO
	for i in count:
		var p: Vector3 = pts[i]
		var q: Vector3 = pts[(i + 1) % count]
		normal += Vector3((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y))
	if normal.length_squared() < 1e-13: return
	normal = normal.normalized()
	var order: Array = pts.duplicate()
	if normal.dot(outward) < 0.0:
		normal = -normal
		order.reverse()
	var winding: Vector3 = (Vector3(order[1]) - Vector3(order[0])).cross(Vector3(order[2]) - Vector3(order[0]))
	if winding.dot(normal) > 0.0: order.reverse()
	for i in range(1, order.size() - 1):
		for vertex: Vector3 in [order[0], order[i], order[i + 1]]:
			st.set_color(color)
			st.set_normal(normal)
			st.add_vertex(vertex)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color = Color.WHITE) -> void:
	_face(st, [a, b, c, d], outward, color)

static func _signed_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5

## Per-edge outward normal in planform space, independent of winding direction.
static func _edge_normals(poly: PackedVector2Array) -> PackedVector2Array:
	var turn := -1.0 if _signed_area(poly) > 0.0 else 1.0
	var out := PackedVector2Array()
	for i in poly.size():
		var d := (poly[(i + 1) % poly.size()] - poly[i]).normalized()
		out.append(Vector2(-d.y, d.x) * turn)
	return out

## Shrink a simple polygon by `amount` along each vertex's angle bisector. Used
## to lift a bevelled top/bottom face off a knife edge.
static func _inset(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var count := poly.size()
	var normals := _edge_normals(poly)
	var out := PackedVector2Array()
	for i in count:
		var n0 := normals[(i - 1 + count) % count]
		var n1 := normals[i]
		var bisector := n0 + n1
		if bisector.length() < 0.002: bisector = n1
		bisector = bisector.normalized()
		out.append(poly[i] - bisector * (amount / maxf(0.36, bisector.dot(n1))))
	return out

## A thin, bevelled plate: sharp edge all the way round at `y`, flat faces
## lifted by the per-vertex half thickness. This is how every lifting surface on
## the aircraft is built, so wings and tails share one silhouette language.
static func _plate(st: SurfaceTool, poly: PackedVector2Array, y: float, half: PackedFloat32Array, bevel: float, color: Color = Color.WHITE) -> void:
	var count := poly.size()
	var inner := _inset(poly, bevel)
	var normals := _edge_normals(poly)
	var indices := Geometry2D.triangulate_polygon(inner)
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		_face(st, [Vector3(inner[a].x, y + half[a], inner[a].y), Vector3(inner[b].x, y + half[b], inner[b].y), Vector3(inner[c].x, y + half[c], inner[c].y)], Vector3.UP, color)
		_face(st, [Vector3(inner[a].x, y - half[a], inner[a].y), Vector3(inner[b].x, y - half[b], inner[b].y), Vector3(inner[c].x, y - half[c], inner[c].y)], Vector3.DOWN, color)
	for i in count:
		var j := (i + 1) % count
		var flat := Vector3(normals[i].x, 0, normals[i].y)
		var p0 := Vector3(poly[i].x, y, poly[i].y)
		var p1 := Vector3(poly[j].x, y, poly[j].y)
		var u0 := Vector3(inner[i].x, y + half[i], inner[i].y)
		var u1 := Vector3(inner[j].x, y + half[j], inner[j].y)
		var d0 := Vector3(inner[i].x, y - half[i], inner[i].y)
		var d1 := Vector3(inner[j].x, y - half[j], inner[j].y)
		_quad(st, p0, p1, u1, u0, (flat + Vector3.UP * 0.55).normalized(), color)
		_quad(st, p0, d0, d1, p1, (flat + Vector3.DOWN * 0.55).normalized(), color)

## A flat ribbon following a polyline across a surface: the gold trim strips and
## the red tail flashes are all built from this.
static func _ribbon(st: SurfaceTool, points: Array, up: Vector3, width: float, color: Color) -> void:
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var along := (b - a)
		if along.length_squared() < 1e-9: continue
		var side := along.normalized().cross(up).normalized() * width * 0.5
		_quad(st, a - side, a + side, b + side, b - side, up, color)

# --- fuselage ---------------------------------------------------------------

## Interpolated station: [spine, deck, chine, belly, keel] as (half width, y).
static func _station_at(z: float) -> PackedVector2Array:
	var lo: Array = STATIONS[0]
	var hi: Array = STATIONS[STATIONS.size() - 1]
	for i in range(STATIONS.size() - 1):
		if z >= float(STATIONS[i][0]) and z <= float(STATIONS[i + 1][0]):
			lo = STATIONS[i]
			hi = STATIONS[i + 1]
			break
	var span: float = maxf(0.0001, float(hi[0]) - float(lo[0]))
	var t: float = clampf((z - float(lo[0])) / span, 0.0, 1.0)
	var out := PackedVector2Array()
	for k in range(5):
		out.append(Vector2(lerpf(float(lo[1 + k * 2]), float(hi[1 + k * 2]), t), lerpf(float(lo[2 + k * 2]), float(hi[2 + k * 2]), t)))
	return out

## Right half of a cross section: spine, shoulder, deck, chine, flank, belly,
## keel. The shoulder and flank sit slightly proud of the straight run between
## their neighbours, which adds two more hard creases per side -- that is what
## breaks the flanks into separate facets instead of one smooth panel.
static func _half_section(z: float) -> PackedVector2Array:
	var s := _station_at(z)
	var centre := Vector2(0.0, s[2].y)
	var out := PackedVector2Array()
	for pair: Array in [[0, 1, 0.50, 1.014], [1, 2, 0.55, 1.009], [2, 3, 0.45, 1.010], [3, 4, 0.50, 1.012]]:
		out.append(s[int(pair[0])])
		out.append(centre + (s[int(pair[0])].lerp(s[int(pair[1])], float(pair[2])) - centre) * float(pair[3]))
	out.append(s[4])
	return out

## Closed 14-gon cross section, from the spine down the right side and back up
## the left.
static func _loop(z: float) -> Array:
	var half := _half_section(z)
	var pts: Array = []
	pts.append(Vector3(-half[0].x, half[0].y, z))
	for point: Vector2 in half: pts.append(Vector3(point.x, point.y, z))
	for i in range(half.size() - 1, -1, -1): pts.append(Vector3(-half[i].x, half[i].y, z))
	pts.remove_at(pts.size() - 1)
	return pts

## Height of the upper hull surface at lateral offset x, so anything mounted on
## the spine (canopy, fins, dorsal trim) sits flush instead of floating.
static func _hull_top_y(z: float, x: float) -> float:
	var s := _station_at(z)
	var ax := absf(x)
	if ax <= s[0].x: return s[0].y
	for k in range(2):
		if ax <= s[k + 1].x:
			var t: float = (ax - s[k].x) / maxf(0.0001, s[k + 1].x - s[k].x)
			return lerpf(s[k].y, s[k + 1].y, t)
	return s[2].y

static func _hull(st: SurfaceTool) -> void:
	var rings: Array = []
	var cuts := PackedFloat32Array()
	for entry: Array in STATIONS: cuts.append(float(entry[0]))
	# Extra cuts through the cockpit and the wing root keep the facets short
	# enough that the chine crease stays crisp in the chase view.
	for extra in [-6.90, -6.00, -5.05, -4.05, -2.90, -1.65, -0.30, 1.15, 2.55, 3.85, 5.00, 5.85]:
		cuts.append(extra)
	var sorted: Array = []
	for value in cuts: sorted.append(value)
	sorted.sort()
	for z: float in sorted: rings.append(_loop(z))
	for i in range(rings.size() - 1):
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var mid_y: float = (_station_at(float(a[0].z))[2].y + _station_at(float(b[0].z))[2].y) * 0.5
		for k in a.size():
			var j: int = (k + 1) % a.size()
			var centre: Vector3 = (a[k] + a[j] + b[k] + b[j]) * 0.25
			var outward := Vector3(centre.x, centre.y - mid_y, 0.0)
			if outward.length_squared() < 1e-8: outward = Vector3.UP
			_quad(st, a[k], a[j], b[j], b[k], outward.normalized())
	# Aft face: a thin faceted ring closing the boat tail around the exhaust barrel.
	var last: Array = rings[rings.size() - 1]
	var barrel: Array = []
	for point: Vector3 in last:
		var radial := Vector2(point.x, point.y - ENGINE_Y)
		if radial.length() < 0.001: radial = Vector2(0, 1)
		radial = radial.normalized() * (NOZZLE_R + 0.035)
		barrel.append(Vector3(radial.x, ENGINE_Y + radial.y, 6.20))
	for k in last.size():
		var j: int = (k + 1) % last.size()
		_quad(st, last[k], last[j], barrel[j], barrel[k], Vector3.BACK)

## A point on the hull's outboard flank: t=0 at the chine crease, t=1 at the
## belly crease, walking the real skin including the flank facet. Everything
## bolted to the side of the aircraft is placed through this so it sits on the
## surface rather than sunk under it.
static func _hull_side(z: float, t: float, side: float = 1.0) -> Vector3:
	var half := _half_section(z)
	var run: Array = [half[3], half[4], half[5]]
	var a: float = (run[0] as Vector2).distance_to(run[1])
	var b: float = (run[1] as Vector2).distance_to(run[2])
	var at: float = clampf(t, 0.0, 1.0) * (a + b)
	var point: Vector2 = (run[0] as Vector2).lerp(run[1], at / maxf(0.0001, a)) if at <= a else (run[1] as Vector2).lerp(run[2], (at - a) / maxf(0.0001, b))
	return Vector3(point.x * side, point.y, z)

## Outward normal of that flank, in the cross-section plane.
static func _hull_side_normal(z: float, t: float, side: float = 1.0) -> Vector3:
	var a := _hull_side(z, maxf(0.0, t - 0.04), side)
	var b := _hull_side(z, minf(1.0, t + 0.04), side)
	var along := Vector2(b.x - a.x, b.y - a.y)
	if along.length() < 0.0001: return Vector3(side, 0, 0)
	var normal := Vector2(-along.y, along.x).normalized() * side
	return Vector3(normal.x, normal.y, 0.0)

# --- lifting surfaces -------------------------------------------------------

const WING := [
	Vector2(1.34, -3.00), Vector2(3.60, 0.30), Vector2(5.40, 2.48),
	Vector2(5.32, 3.00), Vector2(1.34, 2.74)]
## Sawtoothed flaperon: the notches are real geometry, not a texture, so they
## break the trailing-edge silhouette from every angle.
const FLAPERON := [
	Vector2(5.32, 3.00), Vector2(5.24, 3.36), Vector2(4.32, 3.22), Vector2(4.08, 3.58),
	Vector2(2.98, 3.38), Vector2(2.74, 3.74), Vector2(1.34, 3.52), Vector2(1.34, 2.74)]
const STAB := [Vector2(0.98, 3.55), Vector2(3.35, 5.35), Vector2(3.18, 6.20), Vector2(0.98, 5.60)]
const FIN := [Vector2(-0.32, -1.60), Vector2(2.60, 0.42), Vector2(2.60, 1.06), Vector2(-0.32, 1.30)]
const RUDDER := [Vector2(2.60, 1.06), Vector2(2.60, 1.44), Vector2(-0.32, 1.95), Vector2(-0.32, 1.30)]
const FIN_CANT := 27.0
const FIN_TILT := 6.7
const FIN_X := 0.95
const FIN_Z := 4.25
const FIN_Y := 0.4155

static func _poly(source: Array, side: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in source: out.append(Vector2(point.x * side, point.y))
	return out

static func _taper(poly: PackedVector2Array, root: float, tip: float, inner: float, outer: float, absolute: bool = true) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for point in poly:
		var reach: float = absf(point.x) if absolute else point.x
		out.append(lerpf(root, tip, clampf((reach - inner) / maxf(0.001, outer - inner), 0.0, 1.0)))
	return out

static func _mesh_node(label: String, st: SurfaceTool, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = st.commit()
	node.material_override = material
	node.layers = 2
	return node

static func _fin_basis(side: float) -> Basis:
	return Basis(Vector3(0, 0, 1), deg_to_rad(-FIN_CANT * side)) * Basis(Vector3(1, 0, 0), deg_to_rad(FIN_TILT)) * Basis(Vector3(0, 0, 1), PI * 0.5)

# --- assemblies -------------------------------------------------------------

static func _build_wing(parent: Node3D, side: float, skin: Material, trim: SurfaceTool) -> void:
	var suffix: String = "R" if side > 0 else "L"
	var wing := Node3D.new()
	wing.name = "Wing" + suffix
	wing.position = Vector3(0, -0.05, 0)
	wing.basis = Basis(Vector3(0, 0, 1), deg_to_rad(-2.2 * side))
	parent.add_child(wing)
	var plan := _poly(WING, side)
	var thickness := _taper(plan, 0.140, 0.032, 1.48, 5.40)
	var st := _begin()
	_plate(st, plan, 0.0, thickness, 0.085)
	wing.add_child(_mesh_node("WingSkin" + suffix, st, skin))
	var flap_plan := _poly(FLAPERON, side)
	var flap := _begin()
	_plate(flap, flap_plan, 0.0, _taper(flap_plan, 0.088, 0.028, 1.48, 5.32), 0.055)
	var flaperon := _mesh_node("flaperon" + suffix, flap, skin)
	wing.add_child(flaperon)
	# Hinge recorded in model space; mirrored sides get the mirrored hinge
	# direction, so one shared response deflects the pair differentially in roll.
	var hinge_in: Vector3 = wing.transform * Vector3(1.34 * side, 0.0, 2.74)
	var hinge_out: Vector3 = wing.transform * Vector3(5.32 * side, 0.0, 3.00)
	flaperon.set_meta("surface_pivot", hinge_in)
	flaperon.set_meta("surface_axis", (hinge_out - hinge_in).normalized())
	flaperon.set_meta("surface_response", Vector3(-20.0, 0, 0))
	# The game hangs four visible stores at a fixed height under the wing, so the
	# airframe reaches down and meets them on real pylons.
	for station: float in [2.80, 4.05]:
		var pylon := _begin()
		var top: Vector3 = wing.transform * Vector3(station * side, -_wing_half(station), 2.85)
		_faceted_pylon(pylon, station * side, top.y + 0.02, -1.06, 2.85)
		parent.add_child(_mesh_node("Pylon%d%s" % [int(station * 100), suffix], pylon, skin))
	# Gold leading-edge strip, inset onto the upper surface.
	var lead: Array = []
	for entry: Array in [[Vector2(1.85, -2.42), 0.0], [Vector2(3.60, 0.30), 0.0], [Vector2(5.30, 2.38), 0.0]]:
		var point: Vector2 = entry[0]
		var dir: Vector2 = (WING[2] - WING[1]).normalized() if point.x > 3.4 else (WING[1] - WING[0]).normalized()
		var inward := Vector2(dir.y, -dir.x) * 0.15 * side
		var here := Vector2(point.x * side, point.y) + inward
		lead.append(wing.transform * Vector3(here.x, _wing_half(here.x) + 0.012, here.y))
	_ribbon(trim, lead, wing.basis * Vector3.UP, 0.062, GOLD)
	# Outline the tip and the outboard trailing edge as well: a continuous gold
	# line round the planform is what keeps the wing off a sunlit hillside.
	var tip_line: Array = []
	for point: Vector2 in [Vector2(5.26, 2.52), Vector2(5.20, 2.94)]:
		tip_line.append(wing.transform * Vector3(point.x * side, _wing_half(point.x) + 0.012, point.y))
	_ribbon(trim, tip_line, wing.basis * Vector3.UP, 0.055, GOLD)
	var trail: Array = []
	for point: Vector2 in [Vector2(5.16, 3.28), Vector2(4.36, 3.15), Vector2(4.12, 3.50)]:
		trail.append(wing.transform * Vector3(point.x * side, _wing_half(point.x) * 0.72 + 0.012, point.y))
	_ribbon(trim, trail, wing.basis * Vector3.UP, 0.045, GOLD_DIM)

## Half thickness of the wing plate at a lateral station, so trim strips and
## pylons land exactly on its surface instead of floating over it.
static func _wing_half(reach: float) -> float:
	return lerpf(0.140, 0.032, clampf((absf(reach) - 1.48) / 3.92, 0.0, 1.0))

## A thin hexagonal blade rather than a flat-sided box: two narrow facets per
## side never present the sun with one big mirror the way a slab does.
static func _faceted_pylon(st: SurfaceTool, x: float, top: float, bottom: float, z: float) -> void:
	var half := 0.046
	var front := z - 0.66
	var back := z + 0.74
	var waist: float = lerpf(top, bottom, 0.34)
	var rings: Array = []
	for entry: Array in [[top, 1.0, 0.0], [waist, 1.0, 0.16], [bottom, 0.42, 0.26]]:
		var y: float = entry[0]
		var width: float = half * float(entry[1])
		var trim: float = float(entry[2])
		rings.append([
			Vector3(x - width, y, lerpf(front, back, trim * 0.5)),
			Vector3(x - width * 0.30, y, front + (back - front) * trim * 0.18),
			Vector3(x + width * 0.30, y, front + (back - front) * trim * 0.18),
			Vector3(x + width, y, lerpf(front, back, trim * 0.5)),
			Vector3(x + width * 0.30, y, back - (back - front) * trim * 0.22),
			Vector3(x - width * 0.30, y, back - (back - front) * trim * 0.22)])
	var axis := Vector3(x, (top + bottom) * 0.5, z)
	for i in range(rings.size() - 1):
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for k in range(6):
			var j: int = (k + 1) % 6
			var mid: Vector3 = (a[k] + a[j] + b[j] + b[k]) * 0.25
			_quad(st, a[k], a[j], b[j], b[k], (mid - Vector3(axis.x, mid.y, axis.z)).normalized())
	_face(st, rings[rings.size() - 1], Vector3.DOWN)

static func _build_stabilator(parent: Node3D, side: float, skin: Material) -> void:
	var plan := _poly(STAB, side)
	var st := _begin()
	_plate(st, plan, 0.0, _taper(plan, 0.100, 0.031, 0.98, 3.35), 0.058)
	var node := _mesh_node("elevator" + ("R" if side > 0 else "L"), st, skin)
	node.position = Vector3(0, -0.22, 0)
	node.basis = Basis(Vector3(0, 0, 1), deg_to_rad(-4.0 * side))
	parent.add_child(node)
	var axis := (Vector3(3.35, 0, 5.62) - Vector3(0.98, 0, 4.20)).normalized()
	if side < 0: axis = Vector3(axis.x, -axis.y, -axis.z)   # pseudo-vector mirror keeps pitch symmetric
	node.set_meta("surface_pivot", node.transform * Vector3(0.98 * side, 0.0, 4.20))
	node.set_meta("surface_axis", axis)
	node.set_meta("surface_response", Vector3(0, -22.0, 0))

static func _build_fin(parent: Node3D, side: float, skin: Material, trim: SurfaceTool) -> void:
	var mount := Node3D.new()
	mount.name = "FinMount" + ("R" if side > 0 else "L")
	mount.position = Vector3(FIN_X * side, FIN_Y, FIN_Z)
	mount.basis = _fin_basis(side)
	parent.add_child(mount)
	var plan := _poly(FIN, 1.0)
	var st := _begin()
	_plate(st, plan, 0.0, _taper(plan, 0.062, 0.021, -0.32, 2.60, false), 0.050)
	mount.add_child(_mesh_node("Fin" + ("R" if side > 0 else "L"), st, skin))
	var rudder_plan := _poly(RUDDER, 1.0)
	var rst := _begin()
	_plate(rst, rudder_plan, 0.0, _taper(rudder_plan, 0.048, 0.019, -0.32, 2.60, false), 0.038)
	var rudder := _mesh_node("rudder" + ("R" if side > 0 else "L"), rst, skin)
	mount.add_child(rudder)
	var local_a := Vector3(-0.30, 0, 1.20)
	var local_b := Vector3(2.45, 0, 0.98)
	var world_a: Vector3 = mount.transform * local_a
	var world_b: Vector3 = mount.transform * local_b
	rudder.set_meta("surface_pivot", world_a)
	rudder.set_meta("surface_axis", (world_b - world_a).normalized())
	rudder.set_meta("surface_response", Vector3(0, 0, 16.0))
	# Gold strip up the fin leading edge and a subdued blood-red flash outboard.
	var out_normal: Vector3 = mount.basis * Vector3(0, 1, 0)
	var lead: Array = []
	for point: Vector2 in [Vector2(0.10, -1.30), Vector2(1.20, -0.52), Vector2(2.35, 0.30)]:
		lead.append(mount.transform * Vector3(point.x, 0.052, point.y))
	_ribbon(trim, lead, out_normal, 0.050, GOLD)
	var flash: Array = []
	for point: Vector2 in [Vector2(0.55, 0.60), Vector2(1.55, 0.76)]:
		flash.append(mount.transform * Vector3(point.x, 0.050, point.y))
	_ribbon(trim, flash, out_normal, 0.40, BLOOD)

# --- inlets, canopy, exhaust ------------------------------------------------

## Caret inlet: a swept cowl that stands proud of the flank and fades back into
## it, with a sharp lip and a duct that turns out of sight. A black hole in the
## skin is most of what sells a stealth intake at gameplay range.
static func _build_inlet(skin: SurfaceTool, dark: SurfaceTool, trim: SurfaceTool, side: float) -> void:
	const CUTS := [0.02, 0.24, 0.50, 0.76, 0.96]
	var stations: Array = []
	for entry: Array in [[-2.72, 0.175], [-2.05, 0.215], [-0.70, 0.185], [0.90, 0.075], [2.10, 0.0]]:
		var z: float = entry[0]
		var bulge: float = entry[1]
		var ring: Array = []
		for t: float in CUTS:
			ring.append(_hull_side(z, t, side) + _hull_side_normal(z, t, side) * bulge)
		stations.append(ring)
	for i in range(stations.size() - 1):
		var a: Array = stations[i]
		var b: Array = stations[i + 1]
		for k in range(CUTS.size() - 1):
			var mid: Vector3 = (a[k] + a[k + 1] + b[k + 1] + b[k]) * 0.25
			var reference: Vector3 = _hull_side(mid.z, float(CUTS[k] + CUTS[k + 1]) * 0.5, side)
			_quad(skin, a[k], a[k + 1], b[k + 1], b[k], (mid - reference).normalized() if mid.distance_to(reference) > 0.02 else Vector3(side, 0, 0))
		# Close the cowl back onto the skin along its top and bottom edges,
		# otherwise the bulge leaves an open seam down the flank.
		for k: int in [0, CUTS.size() - 1]:
			var edge_a: Vector3 = _hull_side(float(a[k].z), float(CUTS[k]), side)
			var edge_b: Vector3 = _hull_side(float(b[k].z), float(CUTS[k]), side)
			var face_up: float = 1.0 if k == 0 else -1.0
			_quad(skin, edge_a, edge_b, b[k], a[k], (_hull_side_normal(float(a[k].z), float(CUTS[k]), side) * 0.35 + Vector3(0, face_up, 0)).normalized())
	# Mouth: lip ring, then a duct that narrows aft and inboard into darkness.
	var lip: Array = stations[0]
	var mouth: Array = []
	var centre := Vector3(0, 0, 0)
	for point: Vector3 in lip: centre += point / float(lip.size())
	for point: Vector3 in lip: mouth.append(point.lerp(centre, 0.13))
	for k in range(CUTS.size() - 1):
		var mid: Vector3 = (lip[k] + lip[k + 1] + mouth[k + 1] + mouth[k]) * 0.25
		_quad(skin, lip[k], lip[k + 1], mouth[k + 1], mouth[k], (mid - centre + Vector3(0, 0, -0.55)).normalized())
	var throat: Array = []
	var cap: Array = []
	var deep := Vector3(centre.x * 0.45, centre.y + 0.12, centre.z + 1.35)
	for point: Vector3 in mouth:
		throat.append(Vector3(point.x * 0.62, point.y + 0.06, point.z + 0.80))
		cap.append(deep + (point - centre) * 0.42)
	for k in range(CUTS.size() - 1):
		_quad(dark, mouth[k], mouth[k + 1], throat[k + 1], throat[k], (centre - (mouth[k] + throat[k + 1]) * 0.5).normalized())
		_quad(dark, throat[k], throat[k + 1], cap[k + 1], cap[k], (deep - (throat[k] + cap[k + 1]) * 0.5).normalized())
	_face(dark, cap, Vector3.FORWARD)
	# Gold line along the upper lip, the sharpest edge on the whole flank.
	_ribbon(trim, [lip[0] + Vector3(0.015 * side, 0.02, -0.01), lip[0].lerp(lip[1], 0.9) + Vector3(0.015 * side, 0.02, -0.01)], Vector3(side, 0.6, 0).normalized(), 0.040, GOLD)

## Faceted canopy: eight facets across, gold-tinted, sitting flush on the spine
## because every base point is queried from the hull surface itself.
static func _build_canopy(parent: Node3D, glass: Material, skin: Material, trim: SurfaceTool) -> void:
	# z, half width, height above the spine. Six facets per side: enough to read
	# as a canopy, few enough that every one of them catches a different slice of
	# sky instead of blurring into a bubble.
	var profile := [
		Vector3(-5.38, 0.100, 0.05), Vector3(-4.98, 0.34, 0.29), Vector3(-4.44, 0.48, 0.45),
		Vector3(-3.80, 0.50, 0.47), Vector3(-3.18, 0.46, 0.39), Vector3(-2.68, 0.34, 0.24),
		Vector3(-2.28, 0.17, 0.08)]
	var facets := 6
	var rings: Array = []
	for entry: Vector3 in profile:
		var ring: Array = []
		for k in range(facets + 1):
			var angle: float = PI * float(k) / float(facets)
			var x: float = cos(angle) * entry.y
			ring.append(Vector3(x, _hull_top_y(entry.x, x) - 0.03 + sin(angle) * entry.z, entry.x))
		rings.append(ring)
	var st := _begin()
	for i in range(rings.size() - 1):
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for k in range(facets):
			var centre: Vector3 = (a[k] + a[k + 1] + b[k + 1] + b[k]) * 0.25
			_quad(st, a[k], a[k + 1], b[k + 1], b[k], Vector3(centre.x, centre.y - _hull_top_y(centre.z, 0.0) + 0.25, 0.0).normalized())
	parent.add_child(_mesh_node("Canopy", st, glass))
	# Frame: a heavy windscreen bow, a sill down each side, and the spine fairing
	# that carries the canopy back into the dorsal deck.
	var frame := _begin()
	for side: float in [-1.0, 1.0]:
		var sill: Array = []
		for entry: Vector3 in profile:
			var x: float = entry.y * side
			sill.append(Vector3(x * 1.06, _hull_top_y(entry.x, x) + 0.012, entry.x))
		_ribbon(frame, sill, Vector3.UP, 0.085, Color.WHITE)
	for index: int in [1, 2]:
		var bow: Array = []
		var entry: Vector3 = profile[index]
		for k in range(facets + 1):
			var angle: float = PI * float(k) / float(facets)
			var x: float = cos(angle) * entry.y * 1.02
			bow.append(Vector3(x, _hull_top_y(entry.x, x) - 0.03 + sin(angle) * entry.z * 1.03, entry.x))
		_ribbon(frame, bow, Vector3.FORWARD if index == 1 else Vector3.BACK, 0.075 if index == 1 else 0.05, Color.WHITE)
	parent.add_child(_mesh_node("CanopyFrame", frame, skin))
	for side: float in [-1.0, 1.0]:
		var line: Array = []
		for entry: Vector3 in [profile[1], profile[3], profile[5]]:
			var x: float = entry.y * side * 1.08
			line.append(Vector3(x, _hull_top_y(entry.x, x) + 0.022, entry.x))
		_ribbon(trim, line, Vector3.UP, 0.038, GOLD_DIM)

## One big round nozzle: a titanium barrel, twelve serrated petals and a dark
## interior with a centre cone. The sawtooth exit is geometry, so it silhouettes
## against the plume.
static func _build_nozzle(parent: Node3D, heat: Material, dark: Material, trim: SurfaceTool) -> void:
	var nozzle := Node3D.new()
	nozzle.name = "Nozzle"
	parent.add_child(nozzle)
	var petals := 12
	var barrel := _begin()
	var rings := [[5.70, NOZZLE_R + 0.045], [6.30, NOZZLE_R + 0.105], [6.90, NOZZLE_R + 0.135]]
	for i in range(rings.size() - 1):
		var lo: Array = rings[i]
		var hi: Array = rings[i + 1]
		for k in range(petals):
			var a0: float = TAU * float(k) / float(petals)
			var a1: float = TAU * float(k + 1) / float(petals)
			var p0 := _ring_point(a0, float(lo[1]), float(lo[0]))
			var p1 := _ring_point(a1, float(lo[1]), float(lo[0]))
			var q0 := _ring_point(a0, float(hi[1]), float(hi[0]))
			var q1 := _ring_point(a1, float(hi[1]), float(hi[0]))
			var mid: Vector3 = (p0 + p1 + q0 + q1) * 0.25
			_quad(barrel, p0, p1, q1, q0, Vector3(mid.x, mid.y - ENGINE_Y, 0).normalized())
	nozzle.add_child(_mesh_node("NozzleBarrel", barrel, heat))
	# Serrated petals: alternating long and short tips around the exit.
	var petal_tool := _begin()
	for k in range(petals):
		var a0: float = TAU * float(k) / float(petals)
		var a1: float = TAU * float(k + 1) / float(petals)
		var am: float = (a0 + a1) * 0.5
		var base0 := _ring_point(a0, NOZZLE_R + 0.135, 6.90)
		var base1 := _ring_point(a1, NOZZLE_R + 0.135, 6.90)
		var tip := _ring_point(am, NOZZLE_R + 0.085, NOZZLE_Z)
		var inner0 := _ring_point(a0, NOZZLE_R + 0.010, 6.90)
		var inner1 := _ring_point(a1, NOZZLE_R + 0.010, 6.90)
		var inner_tip := _ring_point(am, NOZZLE_R + 0.030, NOZZLE_Z)
		_face(petal_tool, [base0, base1, tip], Vector3(tip.x, tip.y - ENGINE_Y, 0.25).normalized())
		_face(petal_tool, [inner0, inner1, inner_tip], -Vector3(tip.x, tip.y - ENGINE_Y, -0.25).normalized())
		_quad(petal_tool, base0, tip, inner_tip, inner0, Vector3(base0 - base1).normalized())
		_quad(petal_tool, base1, tip, inner_tip, inner1, Vector3(base1 - base0).normalized())
	nozzle.add_child(_mesh_node("NozzlePetals", petal_tool, heat))
	# Dark interior barrel plus the centre body; the plume sprites sit in front.
	var throat := _begin()
	for i in range(3):
		var z0: float = [5.10, 5.90, 6.60][i]
		var z1: float = [5.90, 6.60, NOZZLE_Z][i]
		var r0: float = [NOZZLE_R - 0.05, NOZZLE_R - 0.04, NOZZLE_R + 0.01][i]
		var r1: float = [NOZZLE_R - 0.04, NOZZLE_R + 0.01, NOZZLE_R + 0.03][i]
		for k in range(petals * 2):
			var a0: float = TAU * float(k) / float(petals * 2)
			var a1: float = TAU * float(k + 1) / float(petals * 2)
			_quad(throat, _ring_point(a0, r0, z0), _ring_point(a1, r0, z0), _ring_point(a1, r1, z1), _ring_point(a0, r1, z1), -Vector3(cos(a0), sin(a0), 0))
	for k in range(petals):
		var a0: float = TAU * float(k) / float(petals)
		var a1: float = TAU * float(k + 1) / float(petals)
		_face(throat, [_ring_point(a0, 0.30, 5.55), _ring_point(a1, 0.30, 5.55), Vector3(0, ENGINE_Y, 6.50)], Vector3(0, 0, 1))
	nozzle.add_child(_mesh_node("NozzleInterior", throat, dark))
	var ring: Array = []
	for k in range(petals * 2 + 1):
		ring.append(_ring_point(TAU * float(k) / float(petals * 2), NOZZLE_R + 0.128, 6.32))
	_ribbon(trim, ring, Vector3.BACK, 0.05, GOLD_DIM)
	nozzle.set_meta("engine_glow_center", Vector3(0, ENGINE_Y, 6.92))
	nozzle.set_meta("engine_glow_radius", NOZZLE_R - 0.12)

static func _ring_point(angle: float, radius: float, z: float) -> Vector3:
	return Vector3(sin(angle) * radius, ENGINE_Y + cos(angle) * radius, z)

# --- undercarriage, bays, detail --------------------------------------------

static func _box(st: SurfaceTool, low: Vector3, high: Vector3, shrink_top: float = 1.0) -> void:
	var centre := (low + high) * 0.5
	var corners: Array = []
	for point: Vector3 in [low, high]:
		var scale: float = shrink_top if point.y > centre.y else 1.0
		corners.append(Vector3(centre.x + (point.x - centre.x) * scale, point.y, centre.z + (point.z - centre.z) * scale))
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var top: Array = [Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
	var bottom: Array = [Vector3(low.x, a.y, low.z), Vector3(high.x, a.y, low.z), Vector3(high.x, a.y, high.z), Vector3(low.x, a.y, high.z)]
	_face(st, top, Vector3.UP)
	_face(st, bottom, Vector3.DOWN)
	for i in range(4):
		var j: int = (i + 1) % 4
		var mid: Vector3 = (top[i] + top[j] + bottom[i] + bottom[j]) * 0.25
		_quad(st, bottom[i], bottom[j], top[j], top[i], (mid - centre).normalized())

static func _wheel(st: SurfaceTool, at: Vector3, radius: float, half_width: float) -> void:
	var sides := 12
	for k in range(sides):
		var a0: float = TAU * float(k) / float(sides)
		var a1: float = TAU * float(k + 1) / float(sides)
		var o0 := Vector3(0, cos(a0) * radius, sin(a0) * radius)
		var o1 := Vector3(0, cos(a1) * radius, sin(a1) * radius)
		var w := Vector3(half_width, 0, 0)
		_quad(st, at + o0 - w, at + o1 - w, at + o1 + w, at + o0 + w, (o0 + o1).normalized())
		_face(st, [at + w, at + o0 + w, at + o1 + w], Vector3.RIGHT)
		_face(st, [at - w, at + o0 - w, at + o1 - w], Vector3.LEFT)

## Ventral strakes under the boat tail: more hard edges below the waterline, and
## they stop the belly reading as one smooth tray from the chase camera.
static func _build_strakes(parent: Node3D, skin: Material) -> void:
	for side: float in [-1.0, 1.0]:
		var plan := PackedVector2Array([Vector2(0.0, 3.30), Vector2(0.72, 5.05), Vector2(0.64, 5.78), Vector2(0.0, 4.95)])
		var st := _begin()
		_plate(st, plan, 0.0, _taper(plan, 0.050, 0.020, 0.0, 0.72), 0.034)
		var node := _mesh_node("Strake" + ("R" if side > 0 else "L"), st, skin)
		node.position = Vector3(0.94 * side, _hull_lower_y(4.30, 0.94) + 0.06, 0.0)
		node.basis = Basis(Vector3(0, 0, 1), deg_to_rad(-50.0 if side > 0 else -130.0))
		parent.add_child(node)

static func _build_gear(parent: Node3D, skin: Material, dark: Material) -> void:
	var gear := Node3D.new()
	gear.name = "LandingGear"
	parent.add_child(gear)
	for spec: Array in [
		["Nose", 0.0, -4.30, 0.00, Vector3(1, 0, 0), 80.0, 0.30],
		["Left", -1.00, 1.20, -0.55, Vector3(0, 0, 1), 100.0, 0.30],
		["Right", 1.00, 1.20, 0.55, Vector3(0, 0, 1), -100.0, 0.30]]:
		var label: String = spec[0]
		var root_x: float = spec[1]
		var root_z: float = spec[2]
		var splay: float = spec[3]
		var top_y: float = _station_at(root_z)[4].y if absf(root_x) < 0.4 else _hull_lower_y(root_z, root_x)
		var leg := Node3D.new()
		leg.name = "Gear" + label
		leg.position = Vector3(root_x, top_y, root_z)
		gear.add_child(leg)
		var axle := Vector3(splay, WHEEL_BOTTOM + 0.38 - top_y, 0.0)
		var st := _begin()
		_box(st, Vector3(-0.09, axle.y + 0.30, -0.10), Vector3(0.09, 0.06, 0.10), 1.6)
		_box(st, Vector3(splay - 0.07, axle.y, -0.08), Vector3(splay + 0.07, axle.y + 0.34, 0.08))
		_quad(st, Vector3(-0.07, axle.y + 0.42, 0.05), Vector3(0.07, axle.y + 0.42, 0.05), Vector3(splay + 0.06, axle.y + 0.30, 0.05), Vector3(splay - 0.06, axle.y + 0.30, 0.05), Vector3.BACK)
		_quad(st, Vector3(-0.07, axle.y + 0.42, -0.05), Vector3(0.07, axle.y + 0.42, -0.05), Vector3(splay + 0.06, axle.y + 0.30, -0.05), Vector3(splay - 0.06, axle.y + 0.30, -0.05), Vector3.FORWARD)
		leg.add_child(_mesh_node("strut" + label, st, skin))
		var wheels := _begin()
		var radius := 0.38 if label == "Nose" else 0.42
		var width := 0.11 if label == "Nose" else 0.14
		for offset: float in ([-0.14, 0.14] if label == "Nose" else [0.0]):
			_wheel(wheels, Vector3(splay + offset, WHEEL_BOTTOM + radius - top_y, 0.0), radius, width)
		leg.add_child(_mesh_node("wheel." + label.substr(0, 1), wheels, dark))
		var door := _begin()
		var sign: float = signf(splay) if absf(splay) > 0.01 else 1.0
		_box(door, Vector3(sign * 0.10, axle.y + 0.30, -0.62), Vector3(sign * 0.13, 0.02, 0.62))
		leg.add_child(_mesh_node("strutdoor" + label, door, skin))
		leg.set_meta("gear_pivot", Vector3(root_x, top_y, root_z))
		leg.set_meta("gear_axis", Vector3(spec[4]))
		leg.set_meta("gear_angle", deg_to_rad(float(spec[5])))
		leg.set_meta("gear_rise", float(spec[6]))

## Height of the lower hull surface at lateral offset x: the mirror of
## _hull_top_y, used to hang gear legs and bay doors off the real skin.
static func _hull_lower_y(z: float, x: float) -> float:
	var s := _station_at(z)
	var ax := absf(x)
	if ax >= s[2].x: return s[2].y
	if ax >= s[3].x:
		var t: float = (ax - s[3].x) / maxf(0.0001, s[2].x - s[3].x)
		return lerpf(s[3].y, s[2].y, t)
	if ax >= s[4].x:
		var t2: float = (ax - s[4].x) / maxf(0.0001, s[3].x - s[4].x)
		return lerpf(s[4].y, s[3].y, t2)
	return s[4].y

## A panel laid on the underside: its y follows the real skin, so a door can
## zigzag across the belly curve without floating off it.
static func _belly_panel(st: SurfaceTool, poly: PackedVector2Array, drop: float, rise: float) -> void:
	var low: Array = []
	var high: Array = []
	for point: Vector2 in poly:
		var y: float = _hull_lower_y(point.y, point.x) - drop
		low.append(Vector3(point.x, y, point.y))
		high.append(Vector3(point.x, y + rise, point.y))
	var indices := Geometry2D.triangulate_polygon(poly)
	for i in range(0, indices.size(), 3):
		_face(st, [low[indices[i]], low[indices[i + 1]], low[indices[i + 2]]], Vector3.DOWN)
		_face(st, [high[indices[i]], high[indices[i + 1]], high[indices[i + 2]]], Vector3.UP)
	var normals := _edge_normals(poly)
	for i in poly.size():
		var j: int = (i + 1) % poly.size()
		_quad(st, low[i], low[j], high[j], high[i], Vector3(normals[i].x, 0, normals[i].y))

## Four weapon-bay doors on the keel, with sawtoothed outboard edges. The combat
## code opens one side at a time; the inner pair lags the outer pair.
static func _build_bays(parent: Node3D, skin: Material, dark: Material) -> void:
	var bay := _begin()
	_box(bay, Vector3(-1.06, -1.22, -1.58), Vector3(1.06, -0.94, 1.42))
	parent.add_child(_mesh_node("WeaponBay", bay, dark))
	for spec: Array in [
		["door bayLI", -1.0, true, -0.07, -0.58, 82.0],
		["door bayRI", 1.0, true, 0.07, 0.58, -82.0],
		["door bayLO", -1.0, false, -1.06, -0.60, -96.0],
		["door bayRO", 1.0, false, 1.06, 0.60, 96.0]]:
		var side: float = spec[1]
		var inner: bool = spec[2]
		var hinge_x: float = spec[3]
		var free_x: float = spec[4]
		var z0: float = -1.44 if inner else -1.24
		var z1: float = 1.32 if inner else 1.14
		var teeth: float = 0.085 * signf(free_x - hinge_x)
		var poly := PackedVector2Array([Vector2(hinge_x, z0), Vector2(free_x, z0)])
		for k in range(1, 5):
			var t: float = float(k) / 5.0
			poly.append(Vector2(free_x + (teeth if k % 2 == 1 else 0.0), lerpf(z0, z1, t)))
		poly.append(Vector2(free_x, z1))
		poly.append(Vector2(hinge_x, z1))
		if side * (free_x - hinge_x) < 0.0: poly.reverse()
		var st := _begin()
		_belly_panel(st, poly, 0.006, 0.055)
		var node := _mesh_node(str(spec[0]), st, skin)
		parent.add_child(node)
		node.set_meta("bay_pivot", Vector3(hinge_x, _hull_lower_y(0.0, hinge_x) - 0.006, 0.0))
		node.set_meta("bay_axis", Vector3(0, 0, 1))
		node.set_meta("bay_angle", deg_to_rad(float(spec[5])))
		node.set_meta("bay_side", side)
		node.set_meta("bay_inner", inner)

## Sensor facets, spine fairings and the chine trim line: the small hard shapes
## that tell the eye this is a machine and not a smooth toy.
static func _build_details(skin: SurfaceTool, glass: SurfaceTool, trim: SurfaceTool) -> void:
	# Faceted electro-optical sensor under the nose.
	var top: Array = []
	var low: Array = []
	for entry: Vector2 in [Vector2(0.30, -5.70), Vector2(0.38, -5.10), Vector2(0.26, -4.55)]:
		top.append(Vector3(-entry.x, _hull_lower_y(entry.y, entry.x) + 0.02, entry.y))
		top.append(Vector3(entry.x, _hull_lower_y(entry.y, entry.x) + 0.02, entry.y))
		low.append(Vector3(-entry.x * 0.62, _hull_lower_y(entry.y, entry.x) - 0.21, entry.y + 0.05))
		low.append(Vector3(entry.x * 0.62, _hull_lower_y(entry.y, entry.x) - 0.21, entry.y + 0.05))
	for i in range(2):
		_quad(glass, top[i * 2], top[i * 2 + 1], top[i * 2 + 3], top[i * 2 + 2], Vector3.UP)
		_quad(glass, low[i * 2], low[i * 2 + 1], low[i * 2 + 3], low[i * 2 + 2], Vector3.DOWN)
		_quad(glass, top[i * 2], low[i * 2], low[i * 2 + 2], top[i * 2 + 2], Vector3.LEFT)
		_quad(glass, top[i * 2 + 1], low[i * 2 + 1], low[i * 2 + 3], top[i * 2 + 3], Vector3.RIGHT)
	_face(glass, [top[0], top[1], low[1], low[0]], Vector3.FORWARD)
	_face(glass, [top[4], top[5], low[5], low[4]], Vector3.BACK)
	# Dorsal fairing that carries the fins and closes the spine aft of the canopy.
	var spine_rings: Array = []
	for entry: Vector2 in [Vector2(-1.70, 0.22), Vector2(0.40, 0.46), Vector2(2.60, 0.44), Vector2(4.60, 0.30), Vector2(5.90, 0.12)]:
		var ring: Array = []
		for x: float in [-entry.y, -entry.y * 0.45, entry.y * 0.45, entry.y]:
			ring.append(Vector3(x, _hull_top_y(entry.x, x) + (0.16 if absf(x) < entry.y * 0.6 else 0.05), entry.x))
		spine_rings.append(ring)
	for i in range(spine_rings.size() - 1):
		var a: Array = spine_rings[i]
		var b: Array = spine_rings[i + 1]
		for k in range(3):
			_quad(skin, a[k], a[k + 1], b[k + 1], b[k], Vector3.UP)
	# Chine trim: the longest gold line on the aircraft, following the real crease.
	for side: float in [-1.0, 1.0]:
		var chine: Array = []
		for z: float in [-7.30, -6.40, -5.40, -4.40, -3.40, -2.40]:
			var reach: float = _station_at(z)[2].x * 0.90
			chine.append(Vector3(reach * side, _hull_top_y(z, reach) + 0.014, z))
		_ribbon(trim, chine, Vector3.UP, 0.046, GOLD)
	# Formation strips on the upper chine, aft of the cockpit.
	for side: float in [-1.0, 1.0]:
		var strip: Array = []
		for z: float in [-1.60, 0.90]:
			strip.append(Vector3(_station_at(z)[1].x * side * 1.01, _hull_top_y(z, _station_at(z)[1].x) + 0.012, z))
		_ribbon(trim, strip, Vector3.UP, 0.040, GOLD_DIM)

# --- materials and assembly -------------------------------------------------

static var _grain: NoiseTexture2D

static func grain() -> NoiseTexture2D:
	if _grain == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.03
		noise.fractal_octaves = 5
		_grain = NoiseTexture2D.new()
		_grain.width = 512
		_grain.height = 512
		_grain.seamless = true
		_grain.generate_mipmaps = true
		_grain.noise = noise
	return _grain

static func paint_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/look/jet_paint.gdshader")
	material.set_shader_parameter("grain", grain())
	material.set_shader_parameter("use_livery", false)
	return material

static func _trim_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/look/jet_trim.gdshader")
	return material

static func _heat_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/look/jet_nozzle.gdshader")
	material.set_shader_parameter("grain", grain())
	return material

static func _dark_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.012, 0.013, 0.015)
	material.metallic = 0.0
	material.roughness = 0.85
	return material

static func _canopy_material() -> StandardMaterial3D:
	# Gold-tinted conductive film over the transparency: dark from outside, warm
	# where the sky grazes it.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.215, 0.150, 0.048)
	material.metallic = 0.92
	material.roughness = 0.075
	material.clearcoat_enabled = true
	material.clearcoat = 1.0
	material.clearcoat_roughness = 0.03
	return material

static func _sensor_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.03, 0.035, 0.045)
	material.metallic = 0.85
	material.roughness = 0.12
	return material

static func create() -> Node3D:
	var model := Node3D.new()
	model.name = "SpectreX26"
	var frame := Node3D.new()
	frame.name = "Airframe"
	model.add_child(frame)
	var skin := paint_material()
	var trim_material := _trim_material()
	var heat := _heat_material()
	var dark := _dark_material()
	var glass := _canopy_material()
	var sensor_glass := _sensor_material()
	var hull := _begin()
	var duct := _begin()
	var sensor := _begin()
	var trim := _begin()
	_hull(hull)
	for side: float in [-1.0, 1.0]:
		_build_inlet(hull, duct, trim, side)
	_build_details(hull, sensor, trim)
	frame.add_child(_mesh_node("Hull", hull, skin))
	frame.add_child(_mesh_node("InletDucts", duct, dark))
	frame.add_child(_mesh_node("Sensors", sensor, sensor_glass))
	for side: float in [-1.0, 1.0]:
		_build_wing(frame, side, skin, trim)
		_build_stabilator(frame, side, skin)
		_build_fin(frame, side, skin, trim)
	_build_canopy(frame, glass, skin, trim)
	_build_nozzle(frame, heat, dark, trim)
	_build_bays(frame, skin, dark)
	_build_strakes(frame, skin)
	_build_gear(frame, skin, dark)
	frame.add_child(_mesh_node("Trim", trim, trim_material))
	# Hooks the presentation layer reads instead of guessing from mesh names.
	model.set_meta("procedural_spectre", true)
	model.set_meta("engine_glow_center", Vector3(0, ENGINE_Y, 6.86))
	model.set_meta("engine_glow_radius", NOZZLE_R - 0.19)
	model.set_meta("nav_port", Vector3(-5.24, -0.05 + 5.24 * sin(deg_to_rad(-2.2)) + 0.05, 2.62))
	model.set_meta("nav_starboard", Vector3(5.24, -0.05 - 5.24 * sin(deg_to_rad(2.2)) + 0.05, 2.62))
	model.set_meta("beacon_top", Vector3(0, _hull_top_y(1.30, 0.0) + 0.20, 1.30))
	model.set_meta("beacon_bottom", Vector3(0, _hull_lower_y(-1.90, 0.0) - 0.05, -1.90))
	return model
