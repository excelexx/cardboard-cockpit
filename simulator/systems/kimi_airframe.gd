extends RefCounted
class_name KimiAirframe
## Kimi's competing proposal for the hero jet: a hunched, dagger-nosed stealth
## fighter built entirely from hard-edged facets. The design brief was "angel
## of death", so the shaping choices all push the same way: a long drooped
## vulture beak of a nose, one continuous chine that knives from the tip into
## the wing root, a deep keel that buries the engine low (nozzle centre
## (0, -0.78, 7.3)), a spine that hunches over the canopy and then falls away
## to a beak over the exhaust, oversized canted twin fins, and sawtoothed
## trailing edges cut into the geometry itself.
##
## Every surface is an explicit polygon with one flat normal - the aircraft is
## faceted by construction, not by a shading trick. Nose points -Z, +Y is up,
## the origin sits near the centre of gravity. About 15.5 m long, 10.8 m span.
##
## Vertex colour is the paint's instruction set (see kimi_jet_paint.gdshader):
##   r = gold trim mask, g = heat temper mask, b = dark panel-line mask.

const LENGTH := 15.5
const SPAN := 10.8
const ENGINE_Y := -0.78
const NOZZLE_R := 0.66
const NOZZLE_Z := 7.30
const FIN_CANT := 32.0
const GOLD := Color(1, 0, 0, 1)          # mask colours: which knob, not which hue
const GOLD_DIM := Color(0.5, 0, 0, 1)
const BARE := Color(0, 0, 0, 1)
const LINE := Color(0, 0, 1, 1)

# Fuselage stations, nose to tail. Per station:
# [z, spine_y, deck_x, deck_y, chine_x, chine_y, flank_x, flank_y, belly_x, belly_y, keel_y]
# The chine stays glued to y ~= 0.1 the full length: one unbroken knife edge
# from nose tip to wing root is the whole menace of the plan view.
const STATIONS := [
	[-7.85, 0.10, 0.03, 0.08, 0.06, 0.02, 0.05, -0.03, 0.04, -0.06, -0.07],
	[-7.30, 0.26, 0.09, 0.22, 0.18, 0.05, 0.15, -0.07, 0.09, -0.16, -0.20],
	[-6.60, 0.44, 0.17, 0.36, 0.40, 0.07, 0.34, -0.11, 0.20, -0.28, -0.36],
	[-5.80, 0.60, 0.26, 0.48, 0.62, 0.09, 0.55, -0.15, 0.33, -0.40, -0.50],
	[-5.00, 0.70, 0.32, 0.56, 0.85, 0.10, 0.78, -0.18, 0.48, -0.48, -0.60],
	[-4.20, 0.76, 0.38, 0.61, 1.06, 0.11, 0.98, -0.20, 0.60, -0.53, -0.65],
	[-3.30, 0.79, 0.44, 0.64, 1.24, 0.11, 1.16, -0.21, 0.72, -0.56, -0.68],
	[-2.30, 0.79, 0.49, 0.65, 1.38, 0.11, 1.30, -0.21, 0.82, -0.58, -0.70],
	[-1.20, 0.76, 0.52, 0.62, 1.47, 0.10, 1.39, -0.21, 0.89, -0.59, -0.71],
	[ 0.00, 0.71, 0.54, 0.58, 1.50, 0.09, 1.42, -0.22, 0.91, -0.61, -0.73],
	[ 1.20, 0.65, 0.54, 0.53, 1.47, 0.07, 1.39, -0.24, 0.89, -0.64, -0.78],
	[ 2.40, 0.58, 0.52, 0.47, 1.38, 0.04, 1.30, -0.27, 0.83, -0.69, -0.86],
	[ 3.60, 0.49, 0.47, 0.39, 1.28, -0.01, 1.20, -0.32, 0.76, -0.76, -0.97],
	[ 4.60, 0.40, 0.42, 0.30, 1.08, -0.09, 1.00, -0.39, 0.64, -0.85, -1.09],
	[ 5.50, 0.30, 0.35, 0.20, 0.88, -0.20, 0.80, -0.47, 0.52, -0.95, -1.21],
	[ 6.20, 0.20, 0.27, 0.10, 0.70, -0.32, 0.64, -0.55, 0.42, -1.04, -1.33],
]

# Cranked delta, right side (x outboard, z aft). The trailing edge sawteeth are
# geometry, so they silhouette from every angle.
const WING := [
	Vector2(1.15, -3.55), Vector2(3.35, -0.65), Vector2(5.40, 1.90),
	Vector2(5.28, 2.42), Vector2(4.55, 2.30), Vector2(4.28, 2.72),
	Vector2(3.60, 2.58), Vector2(3.34, 2.98), Vector2(2.60, 2.86),
	Vector2(2.36, 3.22), Vector2(1.42, 3.32)]
const STAB := [
	Vector2(0.85, 3.60), Vector2(2.95, 5.40), Vector2(2.82, 5.95),
	Vector2(2.28, 5.78), Vector2(2.02, 6.12), Vector2(1.52, 5.98),
	Vector2(1.28, 6.28), Vector2(0.95, 6.18)]
# Fin side profile (z, y), raised off the aft deck and canted in _build_fin.
const FIN := [Vector2(3.45, 0.22), Vector2(4.90, 2.28), Vector2(5.72, 2.28), Vector2(6.18, 0.22)]

# ---------------------------------------------------------------------------
# Facet accumulator. Godot's front face is clockwise seen from the shading
# normal, so every triangle gets an explicit flat normal and a winding that
# agrees with it; no vertex is ever shared between two facets.
# ---------------------------------------------------------------------------

class Sheet:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	func tri(a: Vector3, b: Vector3, cc: Vector3, out: Vector3, col: Color) -> void:
		var normal := (b - a).cross(cc - a)
		if normal.length_squared() < 1e-12:
			return
		normal = normal.normalized()
		var pts := [a, b, cc]
		if normal.dot(out) < 0.0:
			normal = -normal
			pts = [a, cc, b]
		if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(normal) > 0.0:
			var swap: Vector3 = pts[1]
			pts[1] = pts[2]
			pts[2] = swap
		for p: Vector3 in pts:
			v.append(p)
			n.append(normal)
			c.append(col)

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, out: Vector3, col: Color) -> void:
		tri(a, b, cc, out, col)
		tri(a, cc, d, out, col)

	func fan(pts: Array, out: Vector3, col: Color) -> void:
		for i in range(1, pts.size() - 1):
			tri(pts[0], pts[i], pts[i + 1], out, col)

	func commit(label: String, material: Material) -> MeshInstance3D:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var node := MeshInstance3D.new()
		node.name = label
		node.mesh = mesh
		node.material_override = material
		node.layers = 2
		return node

static func _newell(pts: Array) -> Vector3:
	var normal := Vector3.ZERO
	for i in pts.size():
		var p: Vector3 = pts[i]
		var q: Vector3 = pts[(i + 1) % pts.size()]
		normal += Vector3((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y))
	if normal.length_squared() < 1e-12:
		return Vector3.UP
	return normal.normalized()

# --- 2D polygon helpers (planform plates) ------------------------------------

static func _signed_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5

## Outward edge normals in plan space, whichever way the polygon is wound.
static func _edge_out(poly: PackedVector2Array) -> PackedVector2Array:
	var turn := -1.0 if _signed_area(poly) > 0.0 else 1.0
	var out := PackedVector2Array()
	for i in poly.size():
		var d := (poly[(i + 1) % poly.size()] - poly[i]).normalized()
		out.append(Vector2(-d.y, d.x) * turn)
	return out

## Shrink a simple polygon along each vertex's angle bisector: the bevelled top
## and bottom faces of a plate are inset copies of its knife-edge outline.
static func _inset(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var normals := _edge_out(poly)
	var out := PackedVector2Array()
	for i in poly.size():
		var n0 := normals[(i - 1 + poly.size()) % poly.size()]
		var n1 := normals[i]
		var bisector := n0 + n1
		if bisector.length() < 0.002:
			bisector = n1
		bisector = bisector.normalized()
		out.append(poly[i] - bisector * (amount / maxf(0.36, bisector.dot(n1))))
	return out

static func _lift(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

## A bevelled horizontal plate: knife edge on the outline polygon, flat faces
## lifted by the per-vertex half thickness. Wings and stabilators share it.
static func _plate(sheet: Sheet, poly: PackedVector2Array, ys: PackedFloat32Array, half: PackedFloat32Array, bevel: float, col: Color) -> void:
	var inner := _inset(poly, bevel)
	var normals := _edge_out(poly)
	var tris := Geometry2D.triangulate_polygon(inner)
	for t in range(0, tris.size(), 3):
		var ia := tris[t]
		var ib := tris[t + 1]
		var ic := tris[t + 2]
		sheet.tri(_lift(inner[ia], ys[ia] + half[ia]), _lift(inner[ib], ys[ib] + half[ib]), _lift(inner[ic], ys[ic] + half[ic]), Vector3.UP, col)
		sheet.tri(_lift(inner[ia], ys[ia] - half[ia]), _lift(inner[ib], ys[ib] - half[ib]), _lift(inner[ic], ys[ic] - half[ic]), Vector3.DOWN, col)
	for i in poly.size():
		var j := (i + 1) % poly.size()
		var flat := Vector3(normals[i].x, 0.0, normals[i].y)
		var e0 := _lift(poly[i], ys[i])
		var e1 := _lift(poly[j], ys[j])
		var u0 := _lift(inner[i], ys[i] + half[i])
		var u1 := _lift(inner[j], ys[j] + half[j])
		var d0 := _lift(inner[i], ys[i] - half[i])
		var d1 := _lift(inner[j], ys[j] - half[j])
		sheet.quad(e0, e1, u1, u0, (flat + Vector3.UP * 0.5).normalized(), col)
		sheet.quad(e0, d0, d1, e1, (flat + Vector3.DOWN * 0.5).normalized(), col)

## A bevelled plate in an arbitrary plane (the canted fins): the outline lives
## on the plane, the two faces are inset copies pushed along the plane normal.
static func _slab(sheet: Sheet, pts: Array, thick: float, bevel: float, col: Color) -> void:
	var normal := _newell(pts)
	var u := (Vector3(pts[1]) - Vector3(pts[0])).normalized()
	var w := normal.cross(u).normalized()
	var poly := PackedVector2Array()
	for p: Vector3 in pts:
		poly.append(Vector2(p.dot(u), p.dot(w)))
	var inner := _inset(poly, bevel)
	var normals := _edge_out(poly)
	var face_a: Array = []
	var face_b: Array = []
	for p: Vector2 in inner:
		var on_plane: Vector3 = u * p.x + w * p.y
		face_a.append(on_plane + normal * thick * 0.5)
		face_b.append(on_plane - normal * thick * 0.5)
	sheet.fan(face_a, normal, col)
	sheet.fan(face_b, -normal, col)
	for i in poly.size():
		var j := (i + 1) % poly.size()
		var edge_out: Vector3 = u * normals[i].x + w * normals[i].y
		var e0: Vector3 = u * poly[i].x + w * poly[i].y
		var e1: Vector3 = u * poly[j].x + w * poly[j].y
		sheet.quad(e0, e1, face_a[j], face_a[i], (edge_out + normal * 0.5).normalized(), col)
		sheet.quad(e0, face_b[i], face_b[j], e1, (edge_out - normal * 0.5).normalized(), col)

## A flat ribbon that follows a polyline, laid just proud of a surface. All the
## gold trim and all the dark panel lines are drawn with this.
static func _ribbon(sheet: Sheet, pts: Array, out: Vector3, width: float, col: Color, lift := 0.012) -> void:
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i] + out * lift
		var b: Vector3 = pts[i + 1] + out * lift
		var along := b - a
		if along.length_squared() < 1e-9:
			continue
		var side := along.normalized().cross(out).normalized() * width * 0.5
		sheet.quad(a - side, a + side, b + side, b - side, out, col)

# --- fuselage ----------------------------------------------------------------

## Interpolated right-half cross section: [spine, crown, deck, chine, flank,
## belly, keel] as (x, y). The crown point sits slightly off the straight run
## so the deck breaks into two facets instead of reading as a smooth tube.
static func _section(z: float) -> Array:
	var lo: Array = STATIONS[0]
	var hi: Array = STATIONS[STATIONS.size() - 1]
	for i in range(STATIONS.size() - 1):
		if z >= float(STATIONS[i][0]) and z <= float(STATIONS[i + 1][0]):
			lo = STATIONS[i]
			hi = STATIONS[i + 1]
			break
	var t := clampf((z - float(lo[0])) / maxf(0.0001, float(hi[0]) - float(lo[0])), 0.0, 1.0)
	var spine := Vector2(0.0, lerpf(float(lo[1]), float(hi[1]), t))
	var deck := Vector2(lerpf(float(lo[2]), float(hi[2]), t), lerpf(float(lo[3]), float(hi[3]), t))
	var chine := Vector2(lerpf(float(lo[4]), float(hi[4]), t), lerpf(float(lo[5]), float(hi[5]), t))
	var flank := Vector2(lerpf(float(lo[6]), float(hi[6]), t), lerpf(float(lo[7]), float(hi[7]), t))
	var belly := Vector2(lerpf(float(lo[8]), float(hi[8]), t), lerpf(float(lo[9]), float(hi[9]), t))
	var keel := Vector2(0.0, lerpf(float(lo[10]), float(hi[10]), t))
	var crown := Vector2(deck.x * 0.52, lerpf(spine.y, deck.y, 0.55) + 0.035)
	return [spine, crown, deck, chine, flank, belly, keel]

## Closed 12-gon ring: down the right side from the spine, back up the left.
static func _ring(z: float) -> Array:
	var half := _section(z)
	var pts: Array = []
	for k in range(7):
		pts.append(Vector3(half[k].x, half[k].y, z))
	for k in range(5, 0, -1):
		pts.append(Vector3(-half[k].x, half[k].y, z))
	return pts

## Height of the upper hull at lateral offset x, so the canopy, fins and trim
## sit flush on real skin instead of floating.
static func _hull_top(z: float, x: float) -> float:
	var s := _section(z)
	var ax := absf(x)
	for k in range(3):
		var a: Vector2 = s[k]
		var b: Vector2 = s[k + 1]
		if ax <= b.x or k == 2:
			return lerpf(a.y, b.y, clampf((ax - a.x) / maxf(0.0001, b.x - a.x), 0.0, 1.0))
	return s[3].y

## Height of the lower hull at lateral offset x; bay doors and gear hang here.
static func _hull_bottom(z: float, x: float) -> float:
	var s := _section(z)
	var ax := absf(x)
	var run: Array = [s[6], s[5], s[4], s[3]]  # keel, belly, flank, chine
	for k in range(3):
		var a: Vector2 = run[k]
		var b: Vector2 = run[k + 1]
		if ax <= b.x or k == 2:
			return lerpf(a.y, b.y, clampf((ax - a.x) / maxf(0.0001, b.x - a.x), 0.0, 1.0))
	return s[3].y

## A point on the lower flank: t walks chine (0) -> flank (0.5) -> belly (1).
## Everything bolted to the lower side of the forebody is placed through this.
static func _flank_point(z: float, t: float, side: float) -> Vector3:
	var s := _section(z)
	var point: Vector2
	if t <= 0.5:
		point = (s[3] as Vector2).lerp(s[4], t * 2.0)
	else:
		point = (s[4] as Vector2).lerp(s[5], t * 2.0 - 1.0)
	return Vector3(point.x * side, point.y, z)

static func _flank_normal(z: float, t: float, side: float) -> Vector3:
	var a := _flank_point(z, maxf(0.0, t - 0.04), side)
	var b := _flank_point(z, minf(1.0, t + 0.04), side)
	var along := Vector2(b.x - a.x, b.y - a.y)
	if along.length() < 0.0001:
		return Vector3(side, 0, 0)
	var normal := Vector2(-along.y, along.x).normalized()
	if normal.x * side < 0.0:
		normal = -normal
	return Vector3(normal.x, normal.y, 0.0)

static func _heat_at(z: float) -> float:
	return clampf((z - 5.6) / 2.0, 0.0, 0.35)

static func _hull(sheet: Sheet) -> void:
	var cuts := PackedFloat32Array()
	for entry: Array in STATIONS:
		cuts.append(float(entry[0]))
	# Extra rings through the cockpit and wing root keep the facets short enough
	# that the chine crease stays crisp instead of smearing over long quads.
	for extra in [-7.55, -6.95, -6.20, -5.40, -4.60, -3.75, -2.80, -1.75, -0.60, 0.60, 1.80, 3.00, 4.15, 5.05, 5.85]:
		cuts.append(extra)
	cuts.sort()
	var rings: Array = []
	for z in cuts:
		rings.append(_ring(z))
	for i in range(rings.size() - 1):
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var zmid: float = (a[0].z + b[0].z) * 0.5
		var axis_y: float = (_section(a[0].z)[0].y + _section(a[0].z)[6].y) * 0.5
		var col := Color(0, _heat_at(zmid), 0, 1)
		for k in a.size():
			var j: int = (k + 1) % a.size()
			var mid: Vector3 = (a[k] + a[j] + b[k] + b[j]) * 0.25
			var outward := Vector3(mid.x, mid.y - axis_y, 0.0)
			if outward.length_squared() < 1e-8:
				outward = Vector3.UP
			sheet.quad(a[k], a[j], b[j], b[k], outward.normalized(), col)
	# Nose cap: fan the first ring into the drooped tip.
	var tip := Vector3(0, 0.05, -7.98)
	var first: Array = rings[0]
	for k in first.size():
		var j: int = (k + 1) % first.size()
		sheet.tri(first[k], first[j], tip, ((first[k] + first[j]) * 0.5 - Vector3(0, 0.02, -6.6)).normalized(), BARE)
	# Aft closure: blend the last ring into a circle around the exhaust barrel.
	var last: Array = rings[rings.size() - 1]
	var barrel: Array = []
	for k in last.size():
		var angle := deg_to_rad(90.0 - 30.0 * k)
		barrel.append(Vector3(cos(angle) * 0.80, ENGINE_Y + sin(angle) * 0.80, 6.80))
	var heat_col := Color(0, _heat_at(6.5), 0, 1)
	for k in last.size():
		var j: int = (k + 1) % last.size()
		var mid: Vector3 = (last[k] + last[j] + barrel[j] + barrel[k]) * 0.25
		sheet.quad(last[k], last[j], barrel[j], barrel[k], (mid - Vector3(0, ENGINE_Y, 5.4)).normalized(), heat_col)

# --- intakes -----------------------------------------------------------------

## Caret intake: a wedge cowl that swells out of the lower flank, with a raked
## lip, skin cheeks fore and aft of the mouth, and a duct that turns inboard
## into darkness. The mouth is a real hole edged by the bulged lip.
static func _build_intake(skin: Sheet, dark: Sheet, trim: Sheet, side: float) -> void:
	var ts := [0.0, 0.22, 0.45, 0.72, 1.0]
	var zs := [-2.75, -1.75, -0.55, 0.85, 1.95]
	var bulges := [0.28, 0.33, 0.28, 0.16, 0.0]
	var rings: Array = []
	for s in zs.size():
		var ring: Array = []
		for k in ts.size():
			var t: float = ts[k]
			# The bump is zero at the chine and the belly edge: the cowl grows
			# out of the flank and fair back into it, never leaving a seam.
			var bump := sin(PI * t)
			var base := _flank_point(zs[s], t, side)
			var pos: Vector3 = base + _flank_normal(zs[s], t, side) * (bulges[s] * bump)
			if s == 0:
				pos.z -= 0.55 * t  # raked lip: bottom edge reaches forward
			ring.append(pos)
		rings.append(ring)
	# Cowl skin between stations.
	for s in range(rings.size() - 1):
		var a: Array = rings[s]
		var b: Array = rings[s + 1]
		for k in range(ts.size() - 1):
			var mid: Vector3 = (a[k] + a[k + 1] + b[k + 1] + b[k]) * 0.25
			var reference := _flank_point(mid.z, float(ts[k] + ts[k + 1]) * 0.5, side)
			skin.quad(a[k], a[k + 1], b[k + 1], b[k], (mid - reference).normalized(), BARE)
	# Front face: skin cheeks at the two ends of the lip, open mouth between.
	var lip: Array = rings[0]
	for k in range(ts.size() - 1):
		var t0: float = ts[k]
		var t1: float = ts[k + 1]
		var h0 := _flank_point(float(lip[k].z), t0, side)
		var h1 := _flank_point(float(lip[k + 1].z), t1, side)
		if k == 1:
			# The mouth: a duct that shrinks inboard and aft into the dark.
			var centre: Vector3 = (lip[k] + lip[k + 1] + h0 + h1) * 0.25
			var inset: Array = []
			var throat: Array = []
			for p: Vector3 in [lip[k], lip[k + 1], h1, h0]:
				inset.append(p.lerp(centre, 0.10))
				var pulled: Vector3 = p.lerp(centre, 0.45)
				throat.append(Vector3(pulled.x * (1.0 - 0.25 * side * signf(pulled.x)), pulled.y + 0.05, pulled.z + 1.05))
			var out := Vector3(0, 0.05, -1).normalized()
			for m in range(4):
				var j: int = (m + 1) % 4
				skin.quad([lip[k], lip[k + 1], h1, h0][m], [lip[k], lip[k + 1], h1, h0][j], inset[j], inset[m], out, BARE)
				var wall_mid: Vector3 = (inset[m] + inset[j] + throat[j] + throat[m]) * 0.25
				dark.quad(inset[m], inset[j], throat[j], throat[m], (centre + Vector3(0, 0, 0.5) - wall_mid).normalized(), BARE)
			dark.fan(throat, Vector3(0, 0, -1), BARE)
		else:
			var mid: Vector3 = (h0 + h1 + lip[k + 1] + lip[k]) * 0.25
			skin.quad(h0, h1, lip[k + 1], lip[k], (mid - Vector3(0, -0.25, float(lip[k].z) + 0.8)).normalized(), BARE)
	# Gold along the lip's upper edge - the sharpest line on the flank.
	trim.quad(lip[0] + Vector3(0.01 * side, 0.012, -0.01), lip[1] + Vector3(0.01 * side, 0.012, -0.01),
			lip[1] + Vector3(0.01 * side, 0.012, -0.01) + Vector3(0, 0.045, 0.02),
			lip[0] + Vector3(0.01 * side, 0.012, -0.01) + Vector3(0, 0.045, 0.02),
			Vector3(side * 0.3, 0.9, -0.3).normalized(), GOLD)

# --- lifting surfaces ----------------------------------------------------------

static func _wing_half(x: float) -> float:
	return lerpf(0.150, 0.045, clampf((absf(x) - 1.30) / 4.10, 0.0, 1.0))

static func _wing_y(x: float) -> float:
	return -0.02 - 0.012 * maxf(0.0, absf(x) - 1.30)

static func _mirror(poly: Array, side: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in poly:
		out.append(Vector2(p.x * side, p.y))
	return out

static func _plate_dims(poly: PackedVector2Array, y_fn: Callable, h_fn: Callable) -> Array:
	var ys := PackedFloat32Array()
	var half := PackedFloat32Array()
	for p in poly:
		ys.append(y_fn.call(p.x))
		half.append(h_fn.call(p.x))
	return [ys, half]

static func _build_wing(sheet: Sheet, trim: Sheet, side: float) -> void:
	var poly := _mirror(WING, side)
	var dims := _plate_dims(poly, _wing_y, _wing_half)
	_plate(sheet, poly, dims[0], dims[1], 0.085, BARE)
	# Gold leading-edge strip, inset onto the upper face so it reads as a
	# painted edge band and not a wire floating over the wing.
	var lead: Array = []
	for entry: Array in [[Vector2(1.55, -3.20), WING[0], WING[1]], [Vector2(3.35, -0.65), WING[0], WING[2]], [Vector2(5.34, 1.94), WING[1], WING[2]]]:
		var point: Vector2 = entry[0]
		var dir: Vector2 = ((entry[2] as Vector2) - (entry[1] as Vector2)).normalized()
		var inward := Vector2(dir.y, -dir.x) * 0.16 * side
		var here := Vector2(point.x * side, point.y) + inward
		lead.append(Vector3(here.x, _wing_y(here.x) + _wing_half(here.x) + 0.004, here.y))
	_ribbon(trim, lead, Vector3.UP, 0.060, GOLD)

static func _build_stab(sheet: Sheet, trim: Sheet, side: float) -> void:
	var y_fn := func(x: float) -> float: return -0.30 - 0.010 * maxf(0.0, absf(x) - 0.85)
	var h_fn := func(x: float) -> float: return lerpf(0.090, 0.028, clampf((absf(x) - 0.85) / 2.10, 0.0, 1.0))
	var poly := _mirror(STAB, side)
	var dims := _plate_dims(poly, y_fn, h_fn)
	_plate(sheet, poly, dims[0], dims[1], 0.058, BARE)
	var lead: Array = []
	for entry: Array in [[Vector2(1.00, 3.78), 0.14], [Vector2(2.82, 5.32), 0.14]]:
		var point := Vector2(entry[0].x * side, entry[0].y)
		lead.append(Vector3(point.x, y_fn.call(point.x) + h_fn.call(point.x) + 0.004, point.y))
	_ribbon(trim, lead, Vector3.UP, 0.050, GOLD_DIM)

static func _build_fin(sheet: Sheet, trim: Sheet, side: float) -> void:
	var slope := tan(deg_to_rad(FIN_CANT))
	var centre: Array = []
	for p: Vector2 in FIN:
		centre.append(Vector3(side * (0.72 + (p.y - 0.22) * slope), p.y, p.x))
	var normal := _newell(centre)
	if normal.x * side < 0.0:
		normal = -normal
	_slab(sheet, centre, 0.17, 0.06, BARE)
	# Gold up the leading edge, on the outboard face.
	var lead: Array = []
	for point: Vector2 in [Vector2(3.60, 0.42), Vector2(4.20, 1.25), Vector2(4.82, 2.16)]:
		lead.append(Vector3(side * (0.72 + (point.y - 0.22) * slope), point.y, point.x) + normal * 0.058)
	_ribbon(trim, lead, normal, 0.052, GOLD)

# --- canopy --------------------------------------------------------------------

## Faceted gold canopy: six facets across, each catching a different slice of
## sky. The base ring is queried off the hull so the glass sits flush.
static func _build_canopy(sheet: Sheet, trim: Sheet) -> void:
	# z, half width, height above the hull deck.
	var profile := [
		Vector3(-5.62, 0.11, 0.05), Vector3(-5.16, 0.33, 0.30), Vector3(-4.60, 0.46, 0.46),
		Vector3(-4.00, 0.49, 0.49), Vector3(-3.40, 0.44, 0.40), Vector3(-2.96, 0.29, 0.21),
		Vector3(-2.66, 0.13, 0.08)]
	var facets := 6
	var rings: Array = []
	for entry: Vector3 in profile:
		var ring: Array = []
		for k in range(facets + 1):
			var angle := PI * float(k) / float(facets)
			var x := cos(angle) * entry.y
			ring.append(Vector3(x, _hull_top(entry.x, x) - 0.02 + sin(angle) * entry.z, entry.x))
		rings.append(ring)
	for i in range(rings.size() - 1):
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for k in range(facets):
			var mid: Vector3 = (a[k] + a[k + 1] + b[k + 1] + b[k]) * 0.25
			sheet.quad(a[k], a[k + 1], b[k + 1], b[k], Vector3(mid.x, mid.y - _hull_top(mid.z, 0.0) + 0.3, 0.0).normalized(), BARE)
	# Gold sill lines where the glass meets the deck.
	for side: float in [-1.0, 1.0]:
		var sill: Array = []
		for entry: Vector3 in [profile[0], profile[2], profile[4], profile[6]]:
			var x: float = entry.y * side * 1.05
			sill.append(Vector3(x, _hull_top(entry.x, x) + 0.006, entry.x))
		_ribbon(trim, sill, Vector3.UP, 0.042, GOLD_DIM)

# --- nozzle ---------------------------------------------------------------------

static func _ring_pt(angle: float, radius: float, z: float) -> Vector3:
	return Vector3(sin(angle) * radius, ENGINE_Y + cos(angle) * radius, z)

## One big round nozzle: a heat-tempered barrel, fourteen serrated petals with
## alternating long and short tips, and a dark interior with a centre cone.
static func _build_nozzle(skin: Sheet, dark: Sheet) -> void:
	var seg := 14
	var rings := [[6.10, 0.58, 0.15], [6.45, 0.72, 0.40], [6.90, 0.76, 0.70], [7.08, 0.70, 0.90]]
	for i in range(rings.size() - 1):
		for k in range(seg):
			var a0 := TAU * float(k) / float(seg)
			var a1 := TAU * float(k + 1) / float(seg)
			var p0 := _ring_pt(a0, rings[i][1], rings[i][0])
			var p1 := _ring_pt(a1, rings[i][1], rings[i][0])
			var q0 := _ring_pt(a0, rings[i + 1][1], rings[i + 1][0])
			var q1 := _ring_pt(a1, rings[i + 1][1], rings[i + 1][0])
			var mid: Vector3 = (p0 + p1 + q0 + q1) * 0.25
			skin.quad(p0, p1, q1, q0, Vector3(mid.x, mid.y - ENGINE_Y, 0.0).normalized(), Color(0, lerpf(float(rings[i][2]), float(rings[i + 1][2]), 0.5), 0, 1))
	# Serrated petals: each petal is a tapered tooth, even teeth long, odd short,
	# so the exit edge is a genuine sawtooth in silhouette.
	for k in range(seg):
		# Petal bases overlap their neighbours slightly: the sawtooth gaps read
		# as thin dark seams against the interior barrel, not holes into the sky.
		var a0 := TAU * float(k) / float(seg) - 0.035
		var a1 := TAU * float(k + 1) / float(seg) + 0.035
		var am := TAU * (float(k) + 0.5) / float(seg)
		var long_tooth := k % 2 == 0
		var tip_z := 7.44 if long_tooth else 7.20
		var tip_r := 0.68 if long_tooth else 0.65
		var base0 := _ring_pt(a0, 0.70, 7.08)
		var base1 := _ring_pt(a1, 0.70, 7.08)
		var tip := _ring_pt(am, tip_r, tip_z)
		var in0 := _ring_pt(a0, 0.645, 7.08)
		var in1 := _ring_pt(a1, 0.645, 7.08)
		var in_tip := _ring_pt(am, tip_r - 0.045, tip_z)
		var radial := Vector3(tip.x, tip.y - ENGINE_Y, 0.0).normalized()
		skin.tri(base0, base1, tip, (radial + Vector3(0, 0, 0.35)).normalized(), Color(0, 1, 0, 1))
		skin.tri(in0, in1, in_tip, -(radial - Vector3(0, 0, 0.35)).normalized(), Color(0, 1, 0, 1))
		skin.quad(base0, tip, in_tip, in0, Vector3(base0 - base1).normalized(), Color(0, 1, 0, 1))
		skin.quad(base1, in1, in_tip, tip, Vector3(base1 - base0).normalized(), Color(0, 1, 0, 1))
	# Interior barrel: same heat-tempered paint as the petals, running from
	# barely warm deep inside to a glowing lip at the exit.
	for i in range(3):
		var z0: float = [5.65, 6.35, 6.95][i]
		var z1: float = [6.35, 6.95, 7.56][i]
		var r0: float = [0.58, 0.60, 0.62][i]
		var r1: float = [0.60, 0.62, 0.665][i]
		var heat := [0.25, 0.55, 0.95][i]
		for k in range(seg * 2):
			var a0 := TAU * float(k) / float(seg * 2)
			var a1 := TAU * float(k + 1) / float(seg * 2)
			var radial := Vector3(sin(a0), cos(a0), 0.0)
			dark.quad(_ring_pt(a0, r0, z0), _ring_pt(a1, r0, z0), _ring_pt(a1, r1, z1), _ring_pt(a0, r1, z1), -radial, Color(0, heat, 0, 1))
	for k in range(seg):
		var a0 := TAU * float(k) / float(seg)
		var a1 := TAU * float(k + 1) / float(seg)
		dark.tri(_ring_pt(a0, 0.26, 5.80), _ring_pt(a1, 0.26, 5.80), Vector3(0, ENGINE_Y, 6.95), Vector3(0, 0, 1), Color(0, 0.5, 0, 1))

# --- panel lines, gear, lights ---------------------------------------------------

## Weapon-bay door outlines on the keel: zigzag rectangles drawn as dark
## ribbons, so the belly carries the same sawtooth language as the wing edges.
static func _build_bay_lines(trim: Sheet) -> void:
	for side: float in [-1.0, 1.0]:
		var path: Array = []
		var outline := [
			Vector2(0.14, -1.42), Vector2(0.88, -1.30), Vector2(0.74, -0.90), Vector2(0.88, -0.50),
			Vector2(0.74, -0.10), Vector2(0.88, 0.30), Vector2(0.74, 0.70), Vector2(0.88, 1.10),
			Vector2(0.70, 1.42), Vector2(0.14, 1.28), Vector2(0.30, 0.88), Vector2(0.14, 0.48),
			Vector2(0.30, 0.08), Vector2(0.14, -0.32), Vector2(0.30, -0.72), Vector2(0.14, -1.02)]
		for point: Vector2 in outline:
			var x := point.x * side
			path.append(Vector3(x, _hull_bottom(point.y, x) - 0.006, point.y))
		path.append(path[0])
		_ribbon(trim, path, Vector3.DOWN, 0.045, LINE, 0.006)

static func _box(sheet: Sheet, low: Vector3, high: Vector3, col: Color) -> void:
	var centre := (low + high) * 0.5
	var a := low
	var b := high
	var top: Array = [Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
	var bottom: Array = [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)]
	sheet.fan(top, Vector3.UP, col)
	sheet.fan(bottom, Vector3.DOWN, col)
	for i in range(4):
		var j := (i + 1) % 4
		var mid: Vector3 = (top[i] + top[j] + bottom[i] + bottom[j]) * 0.25
		sheet.quad(bottom[i], bottom[j], top[j], top[i], (mid - centre).normalized(), col)

static func _wheel(sheet: Sheet, at: Vector3, radius: float, half_width: float) -> void:
	var sides := 10
	for k in range(sides):
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var o0 := Vector3(0, cos(a0) * radius, sin(a0) * radius)
		var o1 := Vector3(0, cos(a1) * radius, sin(a1) * radius)
		var w := Vector3(half_width, 0, 0)
		sheet.quad(at + o0 - w, at + o1 - w, at + o1 + w, at + o0 + w, (o0 + o1).normalized(), BARE)
		sheet.tri(at + w, at + o0 + w, at + o1 + w, Vector3.RIGHT, BARE)
		sheet.tri(at - w, at + o0 - w, at + o1 - w, Vector3.LEFT, BARE)

## Nose leg plus two splayed mains, one mesh so hiding the gear is a single
## "gear".visible = false. Wheels bottom out at y = -2.62.
static func _build_gear(parent: Node3D, skin: Material, dark: Material) -> void:
	var struts := Sheet.new()
	var wheels := Sheet.new()
	# Nose leg.
	_box(struts, Vector3(-0.09, -2.30, -4.45), Vector3(0.09, -0.55, -4.25), BARE)
	_box(struts, Vector3(-0.06, -2.34, -4.42), Vector3(0.06, -1.60, -4.18), BARE)
	_wheel(wheels, Vector3(0, -2.28, -4.32), 0.34, 0.10)
	# Mains, raked slightly outward and aft.
	for side: float in [-1.0, 1.0]:
		_box(struts, Vector3(side * 1.00 - 0.10, -2.22, 1.22), Vector3(side * 1.00 + 0.10, -0.58, 1.52), BARE)
		_box(struts, Vector3(side * 1.36 - 0.08, -2.26, 1.30), Vector3(side * 1.36 + 0.08, -1.70, 1.60), BARE)
		struts.quad(Vector3(side * 0.95, -0.62, 1.40), Vector3(side * 1.15, -0.62, 1.40),
				Vector3(side * 1.44, -1.78, 1.45), Vector3(side * 1.28, -1.78, 1.45), Vector3(0, 0, 1), BARE)
		_wheel(wheels, Vector3(side * 1.42, -2.20, 1.45), 0.42, 0.13)
	var gear := MeshInstance3D.new()
	gear.name = "gear"
	var arrays_s := []
	arrays_s.resize(Mesh.ARRAY_MAX)
	arrays_s[Mesh.ARRAY_VERTEX] = struts.v
	arrays_s[Mesh.ARRAY_NORMAL] = struts.n
	arrays_s[Mesh.ARRAY_COLOR] = struts.c
	var arrays_w := []
	arrays_w.resize(Mesh.ARRAY_MAX)
	arrays_w[Mesh.ARRAY_VERTEX] = wheels.v
	arrays_w[Mesh.ARRAY_NORMAL] = wheels.n
	arrays_w[Mesh.ARRAY_COLOR] = wheels.c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_s)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_w)
	mesh.surface_set_material(0, skin)
	mesh.surface_set_material(1, dark)
	gear.mesh = mesh
	gear.layers = 2
	parent.add_child(gear)

## Wingtip strips in the key art's cold cyan, plus a white tail stinger.
static func _build_lights(sheet: Sheet) -> void:
	for side: float in [-1.0, 1.0]:
		var x := 5.33 * side
		var y := _wing_y(x) + 0.02
		sheet.quad(Vector3(x - 0.04, y - 0.015, 1.98), Vector3(x + 0.04, y - 0.015, 1.98),
				Vector3(x + 0.04, y + 0.02, 2.26), Vector3(x - 0.04, y + 0.02, 2.26), Vector3(0, 0.35, side * 0.94).normalized(), BARE)

# --- materials and assembly ------------------------------------------------------

static var _grain: NoiseTexture2D

static func _grain_tex() -> NoiseTexture2D:
	if _grain == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.028
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
	material.shader = preload("res://assets/look/kimi_jet_paint.gdshader")
	material.set_shader_parameter("grain", _grain_tex())
	return material

static func _glass_material() -> StandardMaterial3D:
	# Gold-tinted conductive film: dark bronze face-on, a gold mirror of the sky
	# at grazing angles.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.085, 0.025)
	material.metallic = 0.95
	material.roughness = 0.10
	return material

static func _dark_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.008, 0.009, 0.011)
	material.metallic = 0.0
	material.roughness = 0.92
	return material

static func _light_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.01, 0.02, 0.018)
	material.emission_enabled = true
	material.emission = Color(0.30, 1.0, 0.75)
	material.emission_energy_multiplier = 3.0
	return material

static func create() -> Node3D:
	var model := Node3D.new()
	model.name = "KimiSpectre"
	var skin := paint_material()
	var glass := _glass_material()
	var dark := _dark_material()
	var lights := _light_material()

	var hull := Sheet.new()
	var ducts := Sheet.new()
	var trim := Sheet.new()
	_hull(hull)
	for side: float in [-1.0, 1.0]:
		_build_intake(hull, ducts, trim, side)
	model.add_child(hull.commit("fuselage", skin))
	model.add_child(ducts.commit("intakeDucts", dark))

	var canopy := Sheet.new()
	_build_canopy(canopy, trim)
	model.add_child(canopy.commit("canopy", glass))

	for side: float in [-1.0, 1.0]:
		var suffix := "L" if side < 0.0 else "R"
		var wing := Sheet.new()
		_build_wing(wing, trim, side)
		model.add_child(wing.commit("wing" + suffix, skin))
		var stab := Sheet.new()
		_build_stab(stab, trim, side)
		model.add_child(stab.commit("stab" + suffix, skin))
		var fin := Sheet.new()
		_build_fin(fin, trim, side)
		model.add_child(fin.commit("tail" + suffix, skin))

	var nozzle := Sheet.new()
	var interior := Sheet.new()
	_build_nozzle(nozzle, interior)
	model.add_child(nozzle.commit("nozzle", skin))
	model.add_child(interior.commit("nozzleDuct", skin))

	_build_bay_lines(trim)
	model.add_child(trim.commit("trim", skin))

	_build_gear(model, skin, dark)

	var strips := Sheet.new()
	_build_lights(strips)
	model.add_child(strips.commit("navLights", lights))

	# Hooks for whoever wires this into the presentation layer.
	model.set_meta("procedural_airframe", true)
	model.set_meta("engine_glow_center", Vector3(0, ENGINE_Y, 7.10))
	model.set_meta("engine_glow_radius", NOZZLE_R - 0.10)
	model.set_meta("gear_clearance", -2.62)
	return model
