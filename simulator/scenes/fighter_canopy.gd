extends Node3D
class_name FighterCanopy
## The canopy the pilot sits under: the thick forward bow with its grab handle
## and fasteners, and the acrylic shell itself.
##
## Built in cockpit space (the eye is the origin, -Z forward), from a station
## table the interior hands over, so the bow's feet land exactly on the sills and
## the glass follows the same rails. The frame goes into the interior's shared
## material groups; only the glass needs a mesh of its own.
const GLASS := preload("res://assets/look/canopy_glass.gdshader")
var glass: ShaderMaterial
var glass_mesh: MeshInstance3D
var layer_mask: int = 1
var bow_apex := Vector3(0, 0.4, -1.0)

## Height of the transparency above the rail at station `t`. Tall over the
## pilot, still generous at the bow, then raked steeply down over the nose.
static func canopy_height(t: float, bow_t: float) -> float:
	if t <= bow_t:
		return 0.960 - 0.200 * pow(t / maxf(bow_t, 0.001), 1.6)
	return lerpf(0.760, 0.140, pow((t - bow_t) / maxf(1.0 - bow_t, 0.001), 1.15))

## `stations` is an ordered Array of Dictionaries {t, z, half, base} for the
## right-hand rail, aft to nose. `frame_group` / `seal_group` / `bolt_group` name
## groups that already exist in `kit`.
func build(kit: CockpitMesh, stations: Array, bow_t: float, frame_group: String, seal_group: String,
		bolt_group: String, occluder: int) -> void:
	_build_bow(kit, stations, bow_t, frame_group, seal_group, bolt_group, occluder)
	_build_glass(stations, bow_t)

func set_sun(direction_view: Vector3, energy: float) -> void:
	if glass == null: return
	glass.set_shader_parameter("sun_view", direction_view)
	glass.set_shader_parameter("strength", clampf(energy, 0.15, 1.4))

func _station_at(stations: Array, t: float) -> Dictionary:
	var best: Dictionary = stations[0]
	var closest: float = 1e9
	for item: Dictionary in stations:
		var distance: float = absf(float(item.t) - t)
		if distance < closest:
			closest = distance
			best = item
	return best

# ------------------------------------------------------------------ the bow

func _build_bow(kit: CockpitMesh, stations: Array, bow_t: float, frame_group: String, seal_group: String,
		bolt_group: String, occluder: int) -> void:
	var seat: Dictionary = _station_at(stations, bow_t)
	var half: float = float(seat.half)
	var base: float = float(seat.base)
	var height: float = canopy_height(bow_t, bow_t)
	var z: float = float(seat.z)
	var arch: Array = []
	for i in range(31):
		var a: float = PI * float(i) / 30.0
		arch.append(_arch_point(a, half, base, height, z))
	bow_apex = arch[15]
	# The bar itself: a flat-faced, slightly squared section, deeper fore-and-aft
	# than it is wide, exactly like the demonstrator photographs.
	kit.sweep(frame_group, arch, 0.040, 0.058, Vector3.BACK, 12, Color.WHITE, occluder, 0.88, 0.55)
	# Bonding seal where the acrylic meets the bar, just outboard of it.
	var seal: Array = []
	for i in range(31):
		var a: float = PI * float(i) / 30.0
		seal.append(_arch_point(a, half, base, height, z - 0.048))
	kit.sweep(seal_group, seal, 0.012, 0.016, Vector3.BACK, 8, Color.WHITE, occluder, 0.86, 0.3)
	# Captive fasteners marching up the front face of the bar.
	for i in range(13):
		var a: float = PI * (0.06 + 0.88 * float(i) / 12.0)
		var point: Vector3 = _arch_point(a, half, base, height, z)
		var outward: Vector3 = (point - Vector3(0.0, base, z))
		outward.z = 0.0
		outward = outward.normalized()
		kit.cylinder(bolt_group, point + Vector3(0, 0, -0.046) - outward * 0.004,
			point + Vector3(0, 0, -0.054) - outward * 0.004, 0.0062, 8, Color(0.52, 0.54, 0.55), occluder)
	# Grab handle on the inside of the bow: what the pilot pulls the canopy down
	# with, and the single detail that makes the arch read as a real structure.
	# Left of the crown, where the pilot's hand falls, standing well clear of the
	# bar: flush against the arch it was invisible from the seat.
	var handle_z: float = z + 0.030
	var handle: Array = []
	for i in range(13):
		var t: float = float(i) / 12.0
		var a: float = PI * lerpf(0.585, 0.795, t)
		var seated: Vector3 = _arch_point(a, half, base, height, handle_z)
		var lift: float = sin(clampf((t - 0.08) / 0.84, 0.0, 1.0) * PI) * 0.090
		handle.append(seated + Vector3(0, 0, lift))
	kit.sweep(frame_group, handle, 0.017, 0.017, Vector3.UP, 8, Color.WHITE, occluder, 1.0, 0.2)
	for i in [0, 12]:
		var foot: Vector3 = handle[i]
		kit.cylinder(bolt_group, foot, foot + Vector3(0, 0, -0.030), 0.019, 10, Color.WHITE, occluder)
	# Mirrors either side of the bow, the way every fighter canopy carries them.
	for side: float in [-1.0, 1.0]:
		var mount: Vector3 = _arch_point(PI * (0.5 - side * 0.20), half, base, height, z + 0.046)
		kit.box(frame_group, mount + Vector3(0, -0.012, 0.030), Vector3(0.062, 0.040, 0.014), 0.004,
			Basis(Vector3.RIGHT, 0.34), Color.WHITE, occluder)
		kit.box(bolt_group, mount + Vector3(0, -0.012, 0.038), Vector3(0.052, 0.030, 0.004), 0.002,
			Basis(Vector3.RIGHT, 0.34), Color.WHITE, occluder)

func _arch_point(a: float, half: float, base: float, height: float, z: float) -> Vector3:
	# Flatter over the top than a circle, with wider shoulders: the real bow.
	var x: float = cos(a) * half * (1.0 + 0.230 * sin(a) * sin(a))
	var y: float = base + pow(sin(a), 0.80) * height
	return Vector3(x, y, z - sin(a) * 0.045)

# ---------------------------------------------------------------- the glass

func _build_glass(stations: Array, bow_t: float) -> void:
	glass = ShaderMaterial.new()
	glass.shader = GLASS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var columns := 22
	var grid: Array = []
	for item: Dictionary in stations:
		var t: float = float(item.t)
		if t > 0.88: continue
		# Outboard of the rail and tucked below it, so the acrylic's cut edge is
		# hidden behind the sill instead of drawing a hard line across the view.
		var half: float = float(item.half) + 0.056
		var base: float = float(item.base) - 0.080
		var height: float = canopy_height(t, bow_t) + 0.080
		var row: Array = []
		for c in range(columns + 1):
			var a: float = PI * float(c) / float(columns)
			var point: Vector3 = _arch_point(a, half, base, height, float(item.z))
			var normal := Vector3(-cos(a) / maxf(half, 0.01), -sin(a) / maxf(height, 0.01), 0.0).normalized()
			row.append([point, normal, Vector2(float(c) / float(columns), t)])
		grid.append(row)
	for r in range(grid.size() - 1):
		for c in range(columns):
			for corner in [[r, c], [r + 1, c], [r + 1, c + 1], [r, c], [r + 1, c + 1], [r, c + 1]]:
				var vertex: Array = grid[corner[0]][corner[1]]
				st.set_normal(vertex[1])
				st.set_uv(vertex[2])
				st.add_vertex(vertex[0])
	glass_mesh = MeshInstance3D.new()
	glass_mesh.name = "CanopyGlass"
	glass_mesh.mesh = st.commit()
	glass_mesh.material_override = glass
	glass_mesh.layers = layer_mask
	glass_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass_mesh.extra_cull_margin = 6.0
	add_child(glass_mesh)
