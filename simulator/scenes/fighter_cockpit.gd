extends Node3D
class_name FighterCockpit
## The SPECTRE X-26 interior: an F-35-shaped single-seat tub built entirely from
## procedural meshes, in cockpit space (eye at the origin, -Z forward, +Y up).
##
## Reference: F-35 cockpit demonstrators. A thick canopy bow springing from wide
## sills, a black hooded coaming with the panoramic display recessed in it, a
## standby display flanked by hazard-striped handles, a pedestal between the
## knees, throttle left, side stick right, and the pilot's lap at the bottom of
## the frame.
##
## Two rules drive every number here. Nothing may rise above the coaming except
## the bow - the forward view stays generous. And the lap furniture (stick,
## throttle, knees, pedestal) sits roughly 12 cm higher than a real F-35 so the
## pilot's hands read at the bottom of a 76-degree frame; a game cockpit you
## cannot see your hands in looks empty.

const Kit := preload("res://scenes/fighter_cockpit_mesh.gd")
const Canopy := preload("res://scenes/fighter_canopy.gd")
const HAZARD_SHADER := preload("res://assets/look/cockpit_hazard.gdshader")
const SCREEN_SHADER := preload("res://assets/look/cockpit_screen.gdshader")
const STANDBY_SHADER := preload("res://assets/look/cockpit_standby.gdshader")

## Visual layer 20 is the cockpit's own. The interior stays on layer 1 so the
## world's key light still rakes into it; the extra bit lets the cockpit-only
## fill and shadow rig light nothing else in the scene.
const LAYER := 1 | (1 << 19)
const LIGHT_MASK := 1 << 19

# ---- canopy rail: t = 0 behind the pilot's shoulder, t = 1 at the nose -------
const RAIL_BACK_Z := 0.62
const RAIL_NOSE_Z := -1.62
const BOW_Z := -0.90

# ---- panel -------------------------------------------------------------------
const CROWN := Vector3(0.0, -0.117, -0.730)    # highest point of the glare shield
const COAMING_AFT_Z := -0.640
const COAMING_FWD_Z := -0.950
const COAMING_THICK := 0.030
## Every number below is set by one sight line. The hood's rolled aft lip is the
## nearest thing to the eye, so it subtends the largest angle; the display's top
## edge has to sit below that angle or the lip draws a bar across the symbology.
## Lip bottom: 14.0 degrees down. Display top: 14.8. Crown: 9.1, which leaves a
## visible sliver of hood top instead of a flat edge-on line.
const SCREEN_CENTRE := Vector3(0.0, -0.326, -0.722)
const SCREEN_SIZE := Vector2(0.660, 0.262)     # 2.52:1, the panoramic display's aspect
const SCREEN_TILT := -0.157                    # 9 degrees, top leaning away
const RECESS := 0.038                          # glass sits this far behind the bezel face

# ---- lap ---------------------------------------------------------------------
const CONSOLE_TOP := -0.442
const STICK_BASE := Vector3(0.325, -0.470, -0.505)
const THROTTLE_BASE := Vector3(-0.330, -0.470, -0.395)

var mesh: CockpitMesh
var canopy: FighterCanopy
var throttle_pivot: Node3D
var stick_pivot: Node3D
var display_spill: OmniLight3D
var key_spot: SpotLight3D
var sky_fill: OmniLight3D
var shade_fill: OmniLight3D
var standby_material: ShaderMaterial
var screen_glass: ShaderMaterial
var triangles: int = 0
var airframe_name: String = "X-26"
var _occ := {}
var _materials := {}

# =============================================================== construction

func build(profile: Dictionary, display_texture: Texture2D) -> void:
	airframe_name = str(profile.get("short", "X-26"))
	mesh = Kit.new()
	mesh.rim_y = -0.30
	mesh.rim_half_width = 0.46
	mesh.rim_front = -1.40
	mesh.rim_back = RAIL_BACK_Z
	_build_materials()
	_declare_occluders()
	for key: String in ["paint", "frame", "panel", "flock", "rubber", "suit"]:
		mesh.group(key, _materials[key])
	# Small hardware and legends are never worth a shadow pass of their own.
	mesh.group("metal", _materials.metal, false)
	mesh.group("legend", _materials.legend, false)
	mesh.group("hazard", _materials.hazard, false)
	mesh.group("placard", _materials.placard, false)
	_build_tub()
	_build_sills()
	_build_coaming()
	_build_panel(display_texture)
	_build_lower_panel()
	_build_pedestal()
	_build_consoles()
	_build_seat()
	_build_pilot()
	_build_canopy()
	mesh.commit(self, "Interior", LAYER)
	triangles = mesh.triangle_count()
	_build_controls()
	_build_lights()

func _material(albedo: Color, roughness: float, metallic: float = 0.0, specular: float = 0.5) -> StandardMaterial3D:
	var item := StandardMaterial3D.new()
	item.albedo_color = albedo
	item.roughness = roughness
	item.metallic = metallic
	item.metallic_specular = specular
	# Baked ambient occlusion rides in the vertex colour.
	item.vertex_color_use_as_albedo = true
	return item

func _build_materials() -> void:
	# Mid-dark greys, not black. A cockpit photographs dark because the sky
	# outside is blinding, not because the paint is black; painting it black is
	# exactly what flattened the old interior into a silhouette.
	_materials["paint"] = _material(Color(0.158, 0.174, 0.176), 0.54, 0.0, 0.42)
	# The canopy frame is the darkest painted part, but still grey enough that a
	# bevel highlight separates its front face from its sides.
	_materials["frame"] = _material(Color(0.058, 0.066, 0.072), 0.42, 0.0, 0.55)
	_materials["panel"] = _material(Color(0.086, 0.094, 0.100), 0.34, 0.0, 0.58)
	_materials["flock"] = _material(Color(0.034, 0.038, 0.040), 0.99, 0.0, 0.03)
	_materials["rubber"] = _material(Color(0.060, 0.063, 0.060), 0.90, 0.0, 0.20)
	_materials["metal"] = _material(Color(0.430, 0.445, 0.460), 0.29, 0.82, 0.5)

	_materials["suit"] = _material(Color(0.112, 0.122, 0.082), 0.86, 0.0, 0.20)
	_materials["glove"] = _material(Color(0.078, 0.082, 0.076), 0.72, 0.0, 0.32)
	var legend := _material(Color(0.055, 0.075, 0.062), 0.40)
	legend.emission_enabled = true
	legend.emission = Color(0.30, 0.82, 0.52)
	legend.emission_energy_multiplier = 0.11
	_materials["legend"] = legend
	var hazard := ShaderMaterial.new()
	hazard.shader = HAZARD_SHADER
	_materials["hazard"] = hazard
	var placard := StandardMaterial3D.new()
	placard.albedo_texture = mesh.font_atlas()
	placard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	placard.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	placard.vertex_color_use_as_albedo = true
	placard.roughness = 0.9
	placard.metallic_specular = 0.1
	placard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	placard.emission_enabled = true
	placard.emission = Color(0.62, 0.66, 0.64)
	placard.emission_energy_multiplier = 0.10
	_materials["placard"] = placard

func _declare_occluders() -> void:
	# Big solids the baked AO darkens around. The hood is separate from the panel
	# body so the bezel around the display still gets the hood's shadow.
	_occ["hood"] = mesh.occluder(AABB(Vector3(-0.44, -0.30, -0.97), Vector3(0.88, 0.20, 0.44)), 0.17, 0.80)
	_occ["panel"] = mesh.occluder(AABB(Vector3(-0.42, -0.70, -0.97), Vector3(0.84, 0.42, 0.42)), 0.15, 0.74)
	_occ["left"] = mesh.occluder(AABB(Vector3(-0.44, -0.82, -0.70), Vector3(0.24, 0.39, 0.92)), 0.13, 0.72)
	_occ["right"] = mesh.occluder(AABB(Vector3(0.20, -0.82, -0.70), Vector3(0.24, 0.39, 0.92)), 0.13, 0.72)
	_occ["pedestal"] = mesh.occluder(AABB(Vector3(-0.10, -0.98, -0.70), Vector3(0.20, 0.50, 0.40)), 0.12, 0.70)
	_occ["seat"] = mesh.occluder(AABB(Vector3(-0.29, -0.98, -0.04), Vector3(0.58, 0.86, 0.52)), 0.15, 0.74)
	_occ["wall_l"] = mesh.occluder(AABB(Vector3(-0.60, -1.00, -1.05), Vector3(0.14, 0.76, 1.75)), 0.12, 0.66)
	_occ["wall_r"] = mesh.occluder(AABB(Vector3(0.46, -1.00, -1.05), Vector3(0.14, 0.76, 1.75)), 0.12, 0.66)
	_occ["floor"] = mesh.occluder(AABB(Vector3(-0.50, -1.10, -1.05), Vector3(1.00, 0.14, 1.70)), 0.20, 0.70)
	_occ["bow"] = mesh.occluder(AABB(Vector3(-0.47, -0.36, -1.02), Vector3(0.94, 0.90, 0.13)), 0.10, 0.55)

# ------------------------------------------------------------- rail geometry

func rail_z(t: float) -> float: return lerpf(RAIL_BACK_Z, RAIL_NOSE_Z, t)
func rail_half(t: float) -> float: return 0.545 - 0.215 * pow(t, 1.6)
## Past the bow the rail plunges. In a real F-35 the nose falls away hard, and a
## rail that stayed level up here ran straight across the panoramic display.
func rail_y(t: float) -> float:
	var nose: float = maxf(t - 0.680, 0.0) / 0.320
	return -0.268 - 0.030 * sin(t * PI) - 0.105 * pow(t, 2.2) - 0.95 * nose * nose
func rail_point(t: float) -> Vector3: return Vector3(rail_half(t), rail_y(t), rail_z(t))
func rail_t(z: float) -> float: return clampf((RAIL_BACK_Z - z) / (RAIL_BACK_Z - RAIL_NOSE_Z), 0.0, 1.0)
## Inner face of the tub wall at a given station.
func wall_x(t: float) -> float: return rail_half(t) - 0.074

# --------------------------------------------------------------------- tub

func _build_tub() -> void:
	var stations: Array = []
	for i in range(15):
		stations.append(float(i) / 14.0 * 0.80)
	for side: float in [-1.0, 1.0]:
		var occluder_id: int = _occ.wall_r if side > 0.0 else _occ.wall_l
		var sections: Array = []
		for t: float in stations:
			var top := Vector3(side * wall_x(t), rail_y(t) - 0.030, rail_z(t))
			var shelf := Vector3(side * (wall_x(t) - 0.004), rail_y(t) - 0.098, rail_z(t))
			var ledge := Vector3(side * (wall_x(t) - 0.016), CONSOLE_TOP + 0.004, rail_z(t))
			var deep := Vector3(side * (wall_x(t) - 0.052), -0.98, rail_z(t))
			var points: Array = [top, shelf, ledge, deep]
			if side < 0.0: points.reverse()
			sections.append(points)
		mesh.loft("paint", sections, false, Color.WHITE, occluder_id, true)
		# Panel seams, captive fasteners and a bonded stiffener: the sidewall is a
		# bolted structure, and without that break-up it reads as a painted plane.
		for t: float in [0.13, 0.27, 0.41, 0.55]:
			var x: float = side * (wall_x(t) - 0.005)
			mesh.box("panel", Vector3(x, rail_y(t) - 0.140, rail_z(t)), Vector3(0.008, 0.170, 0.012), 0.002,
				Basis.IDENTITY, Color.WHITE, occluder_id)
		for i in range(9):
			var t: float = 0.08 + float(i) * 0.068
			mesh.cylinder("metal", Vector3(side * (wall_x(t) - 0.002), rail_y(t) - 0.058, rail_z(t)),
				Vector3(side * (wall_x(t) - 0.011), rail_y(t) - 0.058, rail_z(t)), 0.0058, 8, Color.WHITE, occluder_id)
		# Canopy actuator rail runs along the upper wall, aft of the bow.
		var strut: Array = []
		for i in range(7):
			var t: float = 0.10 + float(i) * 0.085
			strut.append(Vector3(side * (wall_x(t) - 0.020), rail_y(t) - 0.055, rail_z(t)))
		mesh.sweep("metal", strut, 0.009, 0.012, Vector3.UP, 8, Color(0.40, 0.42, 0.44), occluder_id, 1.0, 0.5)
		# Avionics box with a pull handle, and a stowage pocket further aft.
		var box_t: float = 0.33
		mesh.box("panel", Vector3(side * (wall_x(box_t) - 0.022), -0.330, rail_z(box_t)),
			Vector3(0.038, 0.098, 0.240), 0.008, Basis.IDENTITY, Color.WHITE, occluder_id)
		mesh.sweep("metal", [Vector3(side * (wall_x(box_t) - 0.044), -0.318, rail_z(box_t) - 0.060),
			Vector3(side * (wall_x(box_t) - 0.056), -0.318, rail_z(box_t)),
			Vector3(side * (wall_x(box_t) - 0.044), -0.318, rail_z(box_t) + 0.060)],
			0.006, 0.006, Vector3.UP, 8, Color(0.46, 0.48, 0.50), occluder_id)
		# Diagonal frame rib and the services block: at the game's field of view
		# the sidewall fills a whole lower corner, and it was the last bare slab.
		var rib: Array = []
		for i in range(5):
			var t: float = lerpf(0.24, 0.52, float(i) / 4.0)
			rib.append(Vector3(side * (wall_x(t) - 0.012), lerpf(rail_y(0.24) - 0.052, CONSOLE_TOP + 0.020,
				float(i) / 4.0), rail_z(t)))
		mesh.sweep("panel", rib, 0.013, 0.020, Vector3.RIGHT, 8, Color.WHITE, occluder_id, 1.0, 0.7)
		var services_t: float = 0.44
		mesh.box("panel", Vector3(side * (wall_x(services_t) - 0.026), -0.392, rail_z(services_t)),
			Vector3(0.046, 0.082, 0.150), 0.008, Basis.IDENTITY, Color.WHITE, occluder_id)
		for i in range(2):
			mesh.cylinder("rubber", Vector3(side * (wall_x(services_t) - 0.046), -0.372 + float(i) * 0.030,
				rail_z(services_t) - 0.034 + float(i) * 0.068),
				Vector3(side * (wall_x(services_t) - 0.062), -0.378 + float(i) * 0.030,
				rail_z(services_t) - 0.034 + float(i) * 0.068), 0.0105, 10, Color.WHITE, occluder_id)
		var pocket_t: float = 0.13
		mesh.box("rubber", Vector3(side * (wall_x(pocket_t) - 0.030), -0.375, rail_z(pocket_t)),
			Vector3(0.050, 0.120, 0.190), 0.012, Basis.IDENTITY, Color.WHITE, occluder_id)
		mesh.placard("placard", "STOW", Vector3(side * (wall_x(pocket_t) - 0.058), -0.302, rail_z(pocket_t)),
			Vector3(0, 0, -1) * side, Vector3.UP, 0.0085, Color(0.76, 0.78, 0.76))
		mesh.placard("placard", "SPECTRE " + airframe_name, Vector3(side * (wall_x(0.50) - 0.008), -0.316, rail_z(0.50)),
			Vector3(0, 0, -1) * side, Vector3.UP, 0.0105, Color(0.74, 0.77, 0.75))
		mesh.placard("placard", "NO STEP", Vector3(side * (wall_x(0.62) - 0.008), -0.316, rail_z(0.62)),
			Vector3(0, 0, -1) * side, Vector3.UP, 0.0080, Color(0.82, 0.74, 0.38))
	_build_nose()
	# Floor, footwell and a rudder pedal each side.
	mesh.box("rubber", Vector3(0.0, -0.995, -0.42), Vector3(0.86, 0.030, 1.30), 0.006, Basis.IDENTITY,
		Color.WHITE, _occ.floor)
	for side: float in [-1.0, 1.0]:
		mesh.box("rubber", Vector3(side * 0.175, -0.930, -0.700), Vector3(0.150, 0.026, 0.230), 0.006,
			Basis(Vector3.RIGHT, 0.30), Color.WHITE, _occ.floor)
		for i in range(4):
			mesh.box("metal", Vector3(side * 0.175, -0.9175 + float(i) * 0.0075, -0.760 + float(i) * 0.032),
				Vector3(0.130, 0.005, 0.009), 0.001, Basis(Vector3.RIGHT, 0.30), Color.WHITE, _occ.floor)
	# Rear bulkhead, so the tub never shows daylight behind the pilot.
	mesh.box("paint", Vector3(0.0, -0.700, 0.560), Vector3(0.90, 0.640, 0.040), 0.010, Basis.IDENTITY,
		Color.WHITE, _occ.seat)

## Radome deck ahead of the windscreen. It sits below the display in every
## forward view, but it closes the hull and it is what the pilot sees when the
## nose drops - without it the jet had no body at all.
func _build_nose() -> void:
	var sections: Array = []
	for i in range(9):
		var t: float = lerpf(0.698, 0.930, float(i) / 8.0)
		var half: float = rail_half(t)
		var base: float = rail_y(t)
		var crown: float = 0.052 * clampf((t - 0.698) / 0.130, 0.0, 1.0)
		var points: Array = []
		for c in range(11):
			var u: float = -1.0 + 2.0 * float(c) / 10.0
			points.append(Vector3(u * half, base + crown * (1.0 - u * u), rail_z(t)))
		sections.append(points)
	mesh.loft("paint", sections, false, Color.WHITE, _occ.panel, true)
	var last: Array = sections[sections.size() - 1]
	var tip := Vector3(0.0, rail_y(0.97), rail_z(0.97))
	for i in range(last.size() - 1):
		var a: Vector3 = last[i]
		var b: Vector3 = last[i + 1]
		var normal: Vector3 = (tip - a).cross(b - a)
		if normal.length_squared() < 1e-12: continue
		normal = normal.normalized()
		if normal.y < 0.0: normal = -normal
		mesh.tri("paint", a, tip, b, normal, normal, normal, Vector2.ZERO, Vector2.ONE, Vector2.DOWN,
			Color.WHITE, _occ.panel, 0.55)

# --------------------------------------------------------------------- sills

func _build_sills() -> void:
	for side: float in [-1.0, 1.0]:
		var rail: Array = []
		for i in range(19):
			var t: float = float(i) / 18.0 * 0.86
			var point: Vector3 = rail_point(t)
			rail.append(Vector3(point.x * side, point.y, point.z))
		# The canopy rail: wide and flat-topped, but no wider than the tub can
		# carry. At 15 cm it read as a pipe laid across the lower corners.
		mesh.sweep("paint", rail, 0.052, 0.029, Vector3.UP, 12, Color.WHITE, -1, 0.80, 0.62)
		# Inboard seal strip the canopy closes onto.
		var seal: Array = []
		for point: Vector3 in rail:
			seal.append(Vector3(point.x - signf(point.x) * 0.044, point.y + 0.024, point.z))
		mesh.sweep("rubber", seal, 0.013, 0.011, Vector3.UP, 8, Color.WHITE, -1, 0.80, 0.30)
		for i in range(10):
			var t: float = 0.05 + float(i) * 0.076
			var point: Vector3 = rail_point(t)
			mesh.cylinder("metal", Vector3(point.x * side, point.y + 0.026, point.z),
				Vector3(point.x * side, point.y + 0.034, point.z), 0.0060, 8, Color(0.62, 0.64, 0.65), -1)

# ------------------------------------------------------- coaming / glare shield

func coaming_half(z: float) -> float:
	return wall_x(rail_t(z)) + 0.010

## Height of the glare shield's crown along the centreline. It peaks just short
## of the display so the pilot sees a sliver of the hood's top surface: a flat
## edge-on lip is exactly what read as 2D before.
func coaming_top(z: float) -> float:
	var t: float = clampf((z - COAMING_AFT_Z) / (COAMING_FWD_Z - COAMING_AFT_Z), 0.0, 1.0)
	var crown: float = clampf((CROWN.z - COAMING_AFT_Z) / (COAMING_FWD_Z - COAMING_AFT_Z), 0.001, 0.999)
	if t <= crown:
		return lerpf(-0.130, CROWN.y, smoothstep(0.0, 1.0, t / crown))
	return lerpf(CROWN.y, -0.258, pow((t - crown) / (1.0 - crown), 1.35))

## How far the hood's edge falls at |u| across, at coaming station `tz`.
## The drop has to be zero at the aft edge: any droop there put the rolled lip
## straight across the top corners of the panoramic display.
func coaming_drop(u: float, tz: float) -> float:
	return 0.185 * pow(absf(u), 2.6) * smoothstep(0.0, 0.62, tz)

func _build_coaming() -> void:
	var zs: Array = []
	for i in range(11):
		zs.append(lerpf(COAMING_AFT_Z, COAMING_FWD_Z, float(i) / 10.0))
	var top_sections: Array = []
	var under_sections: Array = []
	for index in range(zs.size()):
		var z: float = zs[index]
		var tz: float = float(index) / float(zs.size() - 1)
		var half: float = coaming_half(z)
		var top: float = coaming_top(z)
		var points: Array = []
		var under: Array = []
		for i in range(13):
			var u: float = -1.0 + 2.0 * float(i) / 12.0
			var x: float = u * half
			# Ends sweep down and outboard to die into the rails, but only once
			# the hood is forward of the pilot's line of sight to the display.
			var drop: float = coaming_drop(u, tz)
			points.append(Vector3(x, top - drop, z))
			under.append(Vector3(x * 0.985, top - drop - COAMING_THICK, z))
		top_sections.append(points)
		under.reverse()
		under_sections.append(under)
	mesh.loft("flock", top_sections, false, Color.WHITE, _occ.hood, true)
	# A real underside: the hood is a box the display is recessed into, and its
	# lit inner face is the strongest depth cue in the forward view.
	mesh.loft("panel", under_sections, false, Color.WHITE, _occ.hood, true)
	# The aft lip: a rounded rolled edge, the first thing the low sun catches.
	var lip: Array = []
	for i in range(13):
		var u: float = -1.0 + 2.0 * float(i) / 12.0
		var half: float = coaming_half(COAMING_AFT_Z)
		lip.append(Vector3(u * half, coaming_top(COAMING_AFT_Z) - COAMING_THICK * 0.5, COAMING_AFT_Z))
	mesh.sweep("panel", lip, COAMING_THICK * 0.5, COAMING_THICK * 0.5, Vector3.FORWARD, 10, Color.WHITE,
		_occ.hood, 1.0, 0.0)
	# Outboard cheeks close the hood down onto the rails on both sides.
	for side: float in [-1.0, 1.0]:
		var cheek: Array = []
		for index in range(zs.size()):
			var z: float = zs[index]
			var half: float = coaming_half(z) * side
			var top: float = coaming_top(z) - coaming_drop(1.0, float(index) / float(zs.size() - 1)) - COAMING_THICK
			var foot: float = rail_y(rail_t(z)) - 0.012
			var points: Array = [Vector3(half, top, z), Vector3(half * 1.01, (top + foot) * 0.5, z),
				Vector3(half * 1.005, foot, z)]
			if side < 0.0: points.reverse()
			cheek.append(points)
		mesh.loft("paint", cheek, false, Color.WHITE, _occ.hood, true)
	# Forward face closing the hood off over the nose.
	var front: Array = []
	for i in range(13):
		var u: float = -1.0 + 2.0 * float(i) / 12.0
		var half: float = coaming_half(COAMING_FWD_Z)
		front.append([Vector3(u * half, coaming_top(COAMING_FWD_Z) - coaming_drop(u, 1.0), COAMING_FWD_Z),
			Vector3(u * half, rail_y(rail_t(COAMING_FWD_Z)) - 0.020, COAMING_FWD_Z)])
	for i in range(front.size() - 1):
		mesh.quad("paint", front[i][0], front[i][1], front[i + 1][1], front[i + 1][0], Color.WHITE, _occ.hood)
	# Helmet-tracker sensor nub, slightly off the centreline like the real one.
	mesh.box("panel", Vector3(0.062, CROWN.y + 0.010, CROWN.z + 0.012), Vector3(0.048, 0.022, 0.036), 0.005,
		Basis.IDENTITY, Color.WHITE, _occ.hood)
	mesh.cylinder("metal", Vector3(0.062, CROWN.y + 0.020, CROWN.z + 0.012),
		Vector3(0.062, CROWN.y + 0.030, CROWN.z + 0.012), 0.008, 10, Color.WHITE, _occ.hood)
	mesh.ball("metal", Vector3(0.062, CROWN.y + 0.032, CROWN.z + 0.012), Vector3(0.008, 0.005, 0.008), 10, 5,
		Color.WHITE, _occ.hood)
	# Standby compass mount on the other side of the crown.
	mesh.box("panel", Vector3(-0.150, CROWN.y + 0.002, CROWN.z + 0.020), Vector3(0.034, 0.014, 0.030), 0.004,
		Basis.IDENTITY, Color.WHITE, _occ.hood)
	# Comms and lighting sub-panels on the cheeks, angled inboard toward the
	# pilot. Without them the wedge each side of the display stayed a bare slab.
	for side: float in [-1.0, 1.0]:
		var face := Basis(Vector3.UP, -side * 1.16)
		for row in range(2):
			var z: float = -0.690 - float(row) * 0.098
			var at := Vector3(side * (coaming_half(z) - 0.016), -0.236 - float(row) * 0.020, z)
			mesh.box("panel", at, Vector3(0.086, 0.062, 0.020), 0.005, face, Color.WHITE, _occ.hood)
			for column in range(3):
				var knob: Vector3 = at + face * Vector3(-0.026 + float(column) * 0.026, 0.008, 0.013)
				if column == 1:
					mesh.cylinder("metal", knob, knob + face * Vector3(0, 0, 0.012), 0.0075, 8, Color.WHITE, _occ.hood)
				else:
					mesh.box("legend", knob, Vector3(0.018, 0.014, 0.008), 0.002, face, Color.WHITE, _occ.hood)
			mesh.placard("placard", "COMM" if row == 0 else "LIGHT", at + face * Vector3(0.0, -0.020, 0.012),
				face * Vector3.RIGHT, face * Vector3.UP, 0.0058, Color(0.74, 0.77, 0.75))
	# Demist slots along the aft lip, under the rolled edge.
	for i in range(11):
		var x: float = -0.30 + float(i) * 0.060
		mesh.box("rubber", Vector3(x, coaming_top(COAMING_AFT_Z) - 0.034, COAMING_AFT_Z - 0.010),
			Vector3(0.040, 0.008, 0.014), 0.002, Basis.IDENTITY, Color.WHITE, _occ.hood)

# ---------------------------------------------- instrument panel and display

func _build_panel(display_texture: Texture2D) -> void:
	var tilt := Basis(Vector3.RIGHT, SCREEN_TILT)
	var half := Vector2(SCREEN_SIZE.x * 0.5, SCREEN_SIZE.y * 0.5)
	var bezel_face: Vector3 = SCREEN_CENTRE + tilt * Vector3(0, 0, RECESS)
	# Bezel frame: four bevelled bars around the recess, so the display sits in a
	# hole with visible inner walls rather than being painted onto a flat plate.
	var frame: float = 0.030
	for entry: Array in [[Vector3(0, half.y + frame * 0.5, 0), Vector3(SCREEN_SIZE.x + frame * 2.0, frame, RECESS)],
			[Vector3(0, -half.y - frame * 0.5, 0), Vector3(SCREEN_SIZE.x + frame * 2.0, frame, RECESS)],
			[Vector3(-half.x - frame * 0.5, 0, 0), Vector3(frame, SCREEN_SIZE.y, RECESS)],
			[Vector3(half.x + frame * 0.5, 0, 0), Vector3(frame, SCREEN_SIZE.y, RECESS)]]:
		var centre: Vector3 = SCREEN_CENTRE + tilt * (entry[0] + Vector3(0, 0, RECESS * 0.5))
		mesh.box("panel", centre, entry[1], 0.005, tilt, Color.WHITE, _occ.panel)
	# Panel plate carrying the bezel, out to the tub walls.
	for side: float in [-1.0, 1.0]:
		var inner: float = half.x + frame
		var outer: float = coaming_half(SCREEN_CENTRE.z)
		var centre: Vector3 = SCREEN_CENTRE + tilt * Vector3(side * (inner + outer) * 0.5, 0, RECESS * 0.5)
		mesh.box("panel", centre, Vector3(maxf(outer - inner, 0.02), SCREEN_SIZE.y + frame * 2.0, RECESS), 0.006,
			tilt, Color.WHITE, _occ.panel)
		# Display bezel keys: five soft keys per side, the way the real PCD splits.
		for i in range(5):
			var y: float = half.y * (0.66 - float(i) * 0.33)
			var at: Vector3 = SCREEN_CENTRE + tilt * Vector3(side * (half.x + frame * 0.5), y, RECESS + 0.004)
			mesh.box("rubber", at, Vector3(0.016, 0.026, 0.010), 0.002, tilt, Color.WHITE, _occ.panel)
	# The live panoramic display.
	var glass := MeshInstance3D.new()
	glass.name = "PanoramicDisplay"
	var quad := QuadMesh.new()
	quad.size = SCREEN_SIZE
	glass.mesh = quad
	glass.position = SCREEN_CENTRE
	glass.basis = tilt
	glass.layers = LAYER
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.extra_cull_margin = 4.0
	var face := StandardMaterial3D.new()
	face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face.albedo_texture = display_texture
	face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	glass.material_override = face
	add_child(glass)
	# A faint reflection layer in front of the pixels. Real cover glass never
	# shows a perfectly clean image; this is what stops it reading as a decal.
	screen_glass = ShaderMaterial.new()
	screen_glass.shader = SCREEN_SHADER
	var sheen := MeshInstance3D.new()
	sheen.name = "PanoramicGlass"
	var sheen_quad := QuadMesh.new()
	sheen_quad.size = SCREEN_SIZE
	sheen.mesh = sheen_quad
	sheen.position = SCREEN_CENTRE + tilt * Vector3(0, 0, 0.0016)
	sheen.basis = tilt
	sheen.layers = LAYER
	sheen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheen.extra_cull_margin = 4.0
	sheen.material_override = screen_glass
	add_child(sheen)
	mesh.placard("placard", "SPECTRE " + airframe_name,
		bezel_face + tilt * Vector3(-half.x * 0.62, half.y + frame * 0.62, 0.004), Vector3.RIGHT, Vector3.UP, 0.0070,
		Color(0.70, 0.73, 0.71))
	mesh.placard("placard", "PCD  1", bezel_face + tilt * Vector3(half.x * 0.72, half.y + frame * 0.62, 0.004),
		Vector3.RIGHT, Vector3.UP, 0.0070, Color(0.70, 0.73, 0.71))

# ----------------------------------------- lower panel: standby, handles, switches

## The face under the display leans toward the pilot, so its switches and the
## hazard handles are lit and legible instead of hiding under the panel.
func _lower_face(x: float, drop: float) -> Vector3:
	return Vector3(x, -0.4780 - drop * 0.966, -0.7000 + drop * 0.259)

func _build_lower_panel() -> void:
	var lean := Basis(Vector3.RIGHT, 0.262)   # 15 degrees toward the pilot
	var plate_centre: Vector3 = _lower_face(0.0, 0.085)
	mesh.box("panel", plate_centre + lean * Vector3(0, 0, -0.038), Vector3(0.700, 0.190, 0.080), 0.006, lean,
		Color.WHITE, _occ.panel)
	# Standby flight display: a small emissive attitude face in its own bezel.
	var standby_at: Vector3 = _lower_face(0.0, 0.070)
	mesh.box("panel", standby_at + lean * Vector3(0, 0, 0.004), Vector3(0.110, 0.110, 0.016), 0.004, lean,
		Color.WHITE, _occ.panel)
	standby_material = ShaderMaterial.new()
	standby_material.shader = STANDBY_SHADER
	var standby := MeshInstance3D.new()
	standby.name = "StandbyDisplay"
	var face := QuadMesh.new()
	face.size = Vector2(0.084, 0.084)
	standby.mesh = face
	standby.position = standby_at + lean * Vector3(0, 0, 0.0135)
	standby.basis = lean
	standby.layers = LAYER
	standby.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	standby.extra_cull_margin = 4.0
	standby.material_override = standby_material
	add_child(standby)
	mesh.placard("placard", "SFD", _lower_face(0.0, 0.132) + lean * Vector3(0, 0, 0.010), Vector3.RIGHT,
		lean * Vector3.UP, 0.0075, Color(0.72, 0.75, 0.73))
	# Hazard-striped emergency handles flanking it: canopy jettison and manual
	# release, the yellow-and-black pair in every F-35 photograph.
	for entry: Array in [[-1.0, "CANOPY"], [1.0, "EMER"]]:
		var side: float = entry[0]
		var root: Vector3 = _lower_face(side * 0.108, 0.062)
		mesh.box("panel", root + lean * Vector3(0, 0, 0.006), Vector3(0.062, 0.120, 0.020), 0.004, lean,
			Color.WHITE, _occ.panel)
		mesh.box("hazard", root + lean * Vector3(0, 0, 0.024), Vector3(0.042, 0.092, 0.020), 0.005, lean,
			Color.WHITE, _occ.panel)
		mesh.cylinder("hazard", root + lean * Vector3(-0.018, 0.048, 0.024), root + lean * Vector3(0.018, 0.048, 0.024),
			0.0085, 8, Color.WHITE, _occ.panel)
		mesh.placard("placard", str(entry[1]), _lower_face(side * 0.108, 0.132) + lean * Vector3(0, 0, 0.010),
			Vector3.RIGHT, lean * Vector3.UP, 0.0068, Color(0.84, 0.74, 0.34))
	# Switch clusters outboard of the handles: guarded toggles and rotaries.
	var labels: Array = ["MASTER\nARM", "GUN", "MSL", "FLARE", "GEAR", "HOOK", "LIGHT", "PROBE"]
	for i in range(8):
		var side: float = -1.0 if i < 4 else 1.0
		var column: int = i % 4
		var x: float = side * (0.238 + float(column % 2) * 0.062)
		var drop: float = 0.026 + float(column / 2) * 0.068
		var at: Vector3 = _lower_face(x, drop)
		mesh.box("panel", at + lean * Vector3(0, 0, 0.006), Vector3(0.046, 0.046, 0.018), 0.004, lean,
			Color.WHITE, _occ.panel)
		if i % 3 == 0:
			# Guarded switch: a hinged wire cover over the toggle.
			mesh.box("metal", at + lean * Vector3(0, 0.004, 0.019), Vector3(0.036, 0.030, 0.006), 0.002, lean,
				Color.WHITE, _occ.panel)
			mesh.cylinder("metal", at + lean * Vector3(-0.017, 0.016, 0.014), at + lean * Vector3(0.017, 0.016, 0.014),
				0.0035, 8, Color.WHITE, _occ.panel)
		elif i % 3 == 1:
			mesh.cylinder("metal", at + lean * Vector3(0, -0.002, 0.012), at + lean * Vector3(0, 0.012, 0.024),
				0.0038, 8, Color.WHITE, _occ.panel)
			mesh.ball("metal", at + lean * Vector3(0, 0.013, 0.025), Vector3.ONE * 0.0055, 8, 5, Color.WHITE, _occ.panel)
		else:
			mesh.cylinder("rubber", at + lean * Vector3(0, 0, 0.012), at + lean * Vector3(0, 0, 0.026), 0.0165, 12,
				Color.WHITE, _occ.panel)
			mesh.box("metal", at + lean * Vector3(0, 0.010, 0.027), Vector3(0.003, 0.012, 0.004), 0.001, lean,
				Color.WHITE, _occ.panel)
		mesh.placard("placard", str(labels[i]), at + lean * Vector3(0, -0.032, 0.008), Vector3.RIGHT,
			lean * Vector3.UP, 0.0060, Color(0.74, 0.77, 0.75))
	# Backlit caution legends either side of the standby display.
	for entry: Array in [[-0.058, "FIRE"], [0.058, "CAUT"]]:
		var at: Vector3 = _lower_face(float(entry[0]), 0.150)
		mesh.box("legend", at + lean * Vector3(0, 0, 0.008), Vector3(0.050, 0.020, 0.008), 0.002, lean,
			Color.WHITE, _occ.panel)
		mesh.placard("placard", str(entry[1]), at + lean * Vector3(0, 0, 0.013), Vector3.RIGHT,
			lean * Vector3.UP, 0.0072, Color(0.10, 0.12, 0.10))

# ------------------------------------------------------------------ pedestal

func _build_pedestal() -> void:
	var top := -0.545
	var sections: Array = []
	for i in range(7):
		var t: float = float(i) / 6.0
		var z: float = lerpf(-0.660, -0.290, t)
		var half: float = 0.068 - 0.008 * t
		var height: float = top - 0.034 * t
		sections.append([Vector3(-half, -0.98, z), Vector3(-half, height, z), Vector3(half, height, z),
			Vector3(half, -0.98, z)])
	mesh.loft("paint", sections, false, Color.WHITE, _occ.pedestal, true)
	var last: Array = sections[sections.size() - 1]
	mesh.quad("paint", last[0], last[3], last[2], last[1], Color.WHITE, _occ.pedestal)
	# One switch row and two lit legends: at knee distance more than that turns
	# into a keyboard.
	for i in range(3):
		var z: float = -0.628 + float(i) * 0.052
		var height: float = top - 0.034 * clampf((z + 0.660) / 0.370, 0.0, 1.0)
		for column: int in [-1, 1]:
			var at := Vector3(float(column) * 0.030, height + 0.002, z)
			mesh.box("panel", at, Vector3(0.036, 0.010, 0.034), 0.003, Basis.IDENTITY, Color.WHITE, _occ.pedestal)
			mesh.cylinder("metal", at + Vector3(0, 0.003, 0), at + Vector3(0, 0.015, -0.007), 0.0030, 8,
				Color.WHITE, _occ.pedestal)
	for i in range(2):
		var z: float = -0.400 - float(i) * 0.050
		var height: float = top - 0.034 * clampf((z + 0.660) / 0.370, 0.0, 1.0)
		mesh.box("legend", Vector3(0.0, height + 0.003, z), Vector3(0.082, 0.008, 0.022), 0.003, Basis.IDENTITY,
			Color.WHITE, _occ.pedestal)
		mesh.placard("placard", "FUEL LOW" if i == 0 else "AUTO PILOT", Vector3(0.0, height + 0.008, z),
			Vector3.RIGHT, Vector3.FORWARD, 0.0052, Color(0.09, 0.11, 0.09))

# ------------------------------------------------------------------ consoles

func _build_consoles() -> void:
	for side: float in [-1.0, 1.0]:
		var occluder_id: int = _occ.right if side > 0.0 else _occ.left
		var sections: Array = []
		for i in range(9):
			var t: float = float(i) / 8.0
			var z: float = lerpf(-0.640, 0.180, t)
			var outer: float = wall_x(rail_t(z)) - 0.006
			var inner: float = 0.206 + 0.020 * t
			var height: float = CONSOLE_TOP - 0.016 * pow(t, 1.6)
			var points: Array = [Vector3(side * outer, height, z), Vector3(side * inner, height, z),
				Vector3(side * inner, -0.86, z)]
			if side < 0.0: points.reverse()
			sections.append(points)
		mesh.loft("paint", sections, false, Color.WHITE, occluder_id)
		var first: Array = sections[0]
		if side < 0.0: first = first.duplicate(); first.reverse()
		mesh.quad("panel", first[0], first[1], first[2], first[0] + Vector3(0, -0.418, 0), Color.WHITE, occluder_id)
		# A raised lip along the inboard edge, the ridge the pilot's wrist rests on.
		var lip: Array = []
		for i in range(9):
			var t: float = float(i) / 8.0
			var z: float = lerpf(-0.640, 0.180, t)
			lip.append(Vector3(side * (0.206 + 0.020 * t), CONSOLE_TOP - 0.016 * pow(t, 1.6) + 0.004, z))
		mesh.sweep("rubber", lip, 0.012, 0.010, Vector3.UP, 8, Color.WHITE, occluder_id, 1.0, 0.4)
	_build_left_console()
	_build_right_console()

func _build_left_console() -> void:
	# Throttle quadrant: a slot in the console top with a machined rail.
	mesh.box("panel", Vector3(-0.330, CONSOLE_TOP - 0.012, -0.330), Vector3(0.115, 0.024, 0.360), 0.005,
		Basis.IDENTITY, Color.WHITE, _occ.left)
	mesh.box("rubber", Vector3(-0.330, CONSOLE_TOP - 0.004, -0.330), Vector3(0.052, 0.014, 0.330), 0.004,
		Basis.IDENTITY, Color.WHITE, _occ.left)
	for i in range(8):
		var z: float = -0.470 + float(i) * 0.040
		mesh.box("metal", Vector3(-0.392, CONSOLE_TOP + 0.003, z), Vector3(0.026, 0.004, 0.006), 0.001,
			Basis.IDENTITY, Color.WHITE, _occ.left)
	mesh.placard("placard", "IDLE", Vector3(-0.392, CONSOLE_TOP + 0.006, -0.165), Vector3.RIGHT, Vector3.BACK,
		0.0065, Color(0.76, 0.78, 0.76))
	mesh.placard("placard", "MAX", Vector3(-0.392, CONSOLE_TOP + 0.006, -0.500), Vector3.RIGHT, Vector3.BACK,
		0.0065, Color(0.80, 0.72, 0.36))
	mesh.placard("placard", "THROTTLE", Vector3(-0.268, CONSOLE_TOP + 0.006, -0.330), Vector3.FORWARD,
		Vector3.LEFT, 0.0070, Color(0.74, 0.77, 0.75))
	# Radio and lighting panels aft of the quadrant.
	for i in range(3):
		var z: float = -0.040 + float(i) * 0.072
		mesh.box("panel", Vector3(-0.310, CONSOLE_TOP + 0.004, z), Vector3(0.150, 0.014, 0.056), 0.004,
			Basis.IDENTITY, Color.WHITE, _occ.left)
		for column: int in [-1, 0, 1]:
			mesh.cylinder("rubber", Vector3(-0.310 + float(column) * 0.046, CONSOLE_TOP + 0.010, z),
				Vector3(-0.310 + float(column) * 0.046, CONSOLE_TOP + 0.026, z), 0.0125, 10, Color.WHITE, _occ.left)
			mesh.box("metal", Vector3(-0.310 + float(column) * 0.046, CONSOLE_TOP + 0.027, z - 0.008),
				Vector3(0.003, 0.003, 0.010), 0.001, Basis.IDENTITY, Color.WHITE, _occ.left)
	mesh.placard("placard", "COMM   NAV   ILS", Vector3(-0.310, CONSOLE_TOP + 0.006, -0.082), Vector3.RIGHT,
		Vector3.BACK, 0.0062, Color(0.72, 0.75, 0.73))

func _build_right_console() -> void:
	# Stick mount boss and the pilot's wrist rest.
	mesh.box("panel", Vector3(STICK_BASE.x, CONSOLE_TOP - 0.010, STICK_BASE.z), Vector3(0.120, 0.028, 0.140), 0.006,
		Basis.IDENTITY, Color.WHITE, _occ.right)
	mesh.box("rubber", Vector3(STICK_BASE.x, CONSOLE_TOP + 0.010, STICK_BASE.z + 0.150), Vector3(0.110, 0.030, 0.150),
		0.010, Basis(Vector3.RIGHT, -0.10), Color.WHITE, _occ.right)
	mesh.placard("placard", "FLIGHT CONTROL", Vector3(0.262, CONSOLE_TOP + 0.006, -0.420), Vector3.BACK,
		Vector3.RIGHT, 0.0070, Color(0.74, 0.77, 0.75))
	for i in range(3):
		var z: float = -0.010 + float(i) * 0.076
		mesh.box("panel", Vector3(0.312, CONSOLE_TOP + 0.004, z), Vector3(0.150, 0.014, 0.058), 0.004,
			Basis.IDENTITY, Color.WHITE, _occ.right)
		for column: int in [-1, 1]:
			mesh.box("rubber", Vector3(0.312 + float(column) * 0.042, CONSOLE_TOP + 0.012, z),
				Vector3(0.038, 0.016, 0.038), 0.004, Basis.IDENTITY, Color.WHITE, _occ.right)
			mesh.cylinder("metal", Vector3(0.312 + float(column) * 0.042, CONSOLE_TOP + 0.018, z),
				Vector3(0.312 + float(column) * 0.042, CONSOLE_TOP + 0.032, z - 0.008), 0.0034, 8, Color.WHITE, _occ.right)
	mesh.placard("placard", "MASTER MODE", Vector3(0.312, CONSOLE_TOP + 0.006, -0.052), Vector3.RIGHT,
		Vector3.BACK, 0.0062, Color(0.72, 0.75, 0.73))

# ---------------------------------------------------------------------- seat

func _build_seat() -> void:
	# Only the parts of the ejection seat a seated pilot actually sees: the pan,
	# the side bolsters at the edge of vision, the harness, and the yellow and
	# black ejection handle between the knees.
	for side: float in [-1.0, 1.0]:
		var bolster: Array = []
		for i in range(8):
			var t: float = float(i) / 7.0
			var z: float = lerpf(0.42, -0.04, t)
			var y: float = -0.250 - 0.170 * pow(t, 1.4)
			bolster.append(Vector3(side * (0.268 - 0.026 * t), y, z))
		mesh.sweep("rubber", bolster, 0.046, 0.070, Vector3.UP, 12, Color.WHITE, _occ.seat, 0.84, 0.30)
		var stitch: Array = []
		for point: Vector3 in bolster: stitch.append(point + Vector3(-side * 0.030, 0.0, 0.0))
		mesh.sweep("rubber", stitch, 0.006, 0.062, Vector3.UP, 6, Color.WHITE, _occ.seat, 0.84, 0.8)
		# Harness strap running forward over the bolster, with a metal adjuster.
		mesh.box("rubber", Vector3(side * 0.206, -0.430, 0.060), Vector3(0.052, 0.014, 0.300), 0.004,
			Basis(Vector3.RIGHT, 0.40), Color.WHITE, _occ.seat)
		mesh.box("metal", Vector3(side * 0.200, -0.487, -0.072), Vector3(0.046, 0.010, 0.038), 0.004,
			Basis(Vector3.RIGHT, 0.40), Color.WHITE, _occ.seat)
	# Seat back and headrest edges, and the pan under the pilot.
	mesh.box("rubber", Vector3(0.0, -0.360, 0.480), Vector3(0.440, 0.720, 0.090), 0.020, Basis(Vector3.RIGHT, -0.10),
		Color.WHITE, _occ.seat)
	for i in range(3):
		mesh.box("rubber", Vector3(0.0, -0.200 - float(i) * 0.165, 0.432), Vector3(0.380, 0.140, 0.026), 0.012,
			Basis(Vector3.RIGHT, -0.10), Color.WHITE, _occ.seat)
	mesh.box("rubber", Vector3(0.0, -0.720, 0.070), Vector3(0.460, 0.075, 0.430), 0.018, Basis(Vector3.RIGHT, 0.12),
		Color.WHITE, _occ.seat)
	for i in range(2):
		mesh.box("rubber", Vector3(0.0, -0.692 - float(i) * 0.012, 0.200 - float(i) * 0.150), Vector3(0.400, 0.030, 0.120),
			0.012, Basis(Vector3.RIGHT, 0.12), Color.WHITE, _occ.seat)
	mesh.box("panel", Vector3(0.0, -0.790, -0.090), Vector3(0.400, 0.044, 0.120), 0.010, Basis(Vector3.RIGHT, 0.34),
		Color.WHITE, _occ.seat)
	# Ejection handle: a hazard-striped loop at the front of the pan, low enough
	# that it never reads as an object floating in the middle of the frame.
	var loop: Array = []
	for i in range(13):
		var a: float = PI * float(i) / 12.0
		loop.append(Vector3(cos(a) * 0.040, -0.660 + sin(a) * 0.044, -0.098 - sin(a) * 0.016))
	mesh.sweep("hazard", loop, 0.011, 0.011, Vector3.FORWARD, 8, Color.WHITE, _occ.seat, 1.0, 0.0)
	mesh.box("panel", Vector3(0.0, -0.672, -0.086), Vector3(0.130, 0.040, 0.060), 0.006, Basis(Vector3.RIGHT, 0.22),
		Color.WHITE, _occ.seat)

# --------------------------------------------------------------------- pilot

func _build_pilot() -> void:
	# Thighs and knees only, in olive nomex, sitting at the bottom of the frame.
	# Nothing above the lap: a floating torso or a face would be far worse than
	# no pilot at all.
	for side: float in [-1.0, 1.0]:
		var hip := Vector3(side * 0.148, -0.672, 0.140)
		var knee := Vector3(side * 0.194, -0.506, -0.548)
		mesh.limb("suit", hip, knee, 0.086, 0.068, 12, 8, Color.WHITE, _occ.seat)
		mesh.ball("suit", knee + Vector3(0, 0.003, -0.016), Vector3(0.068, 0.062, 0.056), 12, 8, Color.WHITE, _occ.panel)
		# Suit seams over the top of the thigh and a bellows pocket standing off
		# the outboard side: a bare tapered tube reads as a prop, not a leg.
		for offset: float in [-0.038, 0.038]:
			var seam: Array = []
			for i in range(7):
				var t: float = float(i) / 6.0
				var radius: float = lerpf(0.086, 0.068, t)
				seam.append(hip.lerp(knee, t) + Vector3(side * offset, sqrt(maxf(radius * radius - offset * offset, 0.0)) - 0.004, 0.0))
			mesh.sweep("suit", seam, 0.0050, 0.0050, Vector3.UP, 6, Color.WHITE, _occ.seat)
		var pocket: Vector3 = hip.lerp(knee, 0.46)
		mesh.box("suit", pocket + Vector3(side * 0.074, -0.006, 0.0), Vector3(0.026, 0.070, 0.136),
			0.010, Basis(Vector3.RIGHT, 0.24), Color.WHITE, _occ.seat)
		mesh.box("rubber", pocket + Vector3(side * 0.082, 0.028, -0.004), Vector3(0.016, 0.014, 0.120),
			0.004, Basis(Vector3.RIGHT, 0.24), Color.WHITE, _occ.seat)
		# Shin dropping away into the footwell.
		mesh.limb("suit", knee + Vector3(0, 0.0, -0.028), Vector3(side * 0.196, -0.890, -0.735), 0.062, 0.048,
			10, 6, Color.WHITE, _occ.floor)
		# Knee board on the right thigh, a pocket flap on the left.
		if side > 0.0:
			mesh.box("panel", Vector3(side * 0.196, -0.452, -0.455), Vector3(0.112, 0.010, 0.148), 0.004,
				Basis(Vector3.RIGHT, -0.20), Color.WHITE, _occ.panel)
			mesh.placard("placard", "SFO 28R\n119.10", Vector3(side * 0.196, -0.446, -0.455), Vector3.RIGHT,
				Vector3(0, 0.98, 0.20).normalized(), 0.0070, Color(0.70, 0.72, 0.68))
		else:
			mesh.box("suit", Vector3(side * 0.186, -0.524, -0.335), Vector3(0.088, 0.026, 0.118), 0.008,
				Basis(Vector3.RIGHT, 0.10), Color.WHITE, _occ.seat)

## A gloved hand wrapped around a grip that runs from `base` to `tip`.
## A gloved hand wrapped around a grip that runs from `base` to `tip`, written
## into an existing kit so a hand costs no extra draw calls.
func _hand(kit: CockpitMesh, base: Vector3, tip: Vector3, side: float) -> void:
	var axis: Vector3 = (tip - base).normalized()
	var out: Vector3 = Vector3(side, 0, 0)
	out = (out - axis * out.dot(axis)).normalized()
	var fore: Vector3 = axis.cross(out).normalized()
	var centre: Vector3 = base.lerp(tip, 0.45)
	# Palm wrapping the grip, then four fingers curling around the front.
	kit.ball("glove", centre + out * 0.028, Vector3(0.034, 0.050, 0.038), 14, 9)
	for i in range(4):
		var t: float = -0.028 + float(i) * 0.019
		var root: Vector3 = centre + axis * t + out * 0.018 + fore * 0.012
		var mid: Vector3 = root + fore * 0.028 - out * 0.022
		var end: Vector3 = mid - fore * 0.010 - out * 0.028
		kit.limb("glove", root, mid, 0.0110, 0.0100, 8, 5)
		kit.limb("glove", mid, end, 0.0100, 0.0086, 8, 5)
	# Thumb over the top of the grip.
	kit.limb("glove", centre + axis * 0.032 + out * 0.022, centre + axis * 0.048 + fore * 0.028 - out * 0.004,
		0.0130, 0.0110, 9, 5)
	# Wrist and forearm leaving frame, so the hand is never a floating prop.
	var wrist: Vector3 = centre - axis * 0.058 + out * 0.030
	kit.limb("glove", centre - axis * 0.028 + out * 0.030, wrist, 0.031, 0.027, 12, 5)
	kit.limb("suit", wrist, wrist + Vector3(side * 0.12, -0.22, 0.32), 0.029, 0.046, 12, 6)

# ------------------------------------------------------------- moving controls

func _build_controls() -> void:
	# Side stick. `stick_pivot` is what the cockpit rotates with control input.
	stick_pivot = Node3D.new()
	stick_pivot.name = "SideStick"
	stick_pivot.position = STICK_BASE
	add_child(stick_pivot)
	var kit := Kit.new()
	kit.rim_y = mesh.rim_y
	kit.rim_half_width = mesh.rim_half_width
	kit.rim_front = mesh.rim_front
	kit.rim_back = mesh.rim_back
	kit.group("rubber", _materials.rubber)
	kit.group("glove", _materials.glove)
	kit.group("suit", _materials.suit)
	kit.group("panel", _materials.panel)
	kit.group("metal", _materials.metal)
	# Rubber boot, shaft, then the moulded grip with its trigger and hat switches.
	kit.lathe("rubber", [Vector2(0.0, 0.0), Vector2(0.052, 0.002), Vector2(0.046, 0.026), Vector2(0.022, 0.048),
		Vector2(0.018, 0.058)], Vector3.ZERO, Vector3.UP, 14)
	kit.cylinder("metal", Vector3(0, 0.050, 0), Vector3(0, 0.086, 0.004), 0.016, 12)
	var grip_basis := Basis(Vector3.RIGHT, -0.22)
	kit.box("panel", Vector3(0, 0.126, 0.004), Vector3(0.058, 0.086, 0.070), 0.016, grip_basis)
	kit.box("panel", Vector3(0, 0.166, -0.008), Vector3(0.050, 0.030, 0.056), 0.012, grip_basis)
	# Trigger on the forward face; hat switch and a pickle button on top.
	kit.box("metal", Vector3(0, 0.116, -0.036), Vector3(0.018, 0.030, 0.014), 0.004, Basis(Vector3.RIGHT, -0.42))
	kit.box("rubber", Vector3(-0.014, 0.182, -0.006), Vector3(0.020, 0.010, 0.020), 0.003, grip_basis)
	kit.cylinder("metal", Vector3(0.014, 0.176, -0.006), Vector3(0.014, 0.186, -0.010), 0.008, 10)
	kit.ball("metal", Vector3(0, 0.186, 0.014), Vector3(0.010, 0.008, 0.010), 10, 5)
	_hand(kit, Vector3(0, 0.096, 0.004), Vector3(0, 0.170, -0.006), 1.0)
	kit.commit(stick_pivot, "Stick", LAYER)
	triangles += kit.triangle_count()

	# Throttle. `throttle_pivot` rotates about X: aft at idle, forward at max.
	throttle_pivot = Node3D.new()
	throttle_pivot.name = "ThrottleLever"
	throttle_pivot.position = THROTTLE_BASE
	add_child(throttle_pivot)
	var lever := Kit.new()
	lever.rim_y = mesh.rim_y
	lever.rim_half_width = mesh.rim_half_width
	lever.rim_front = mesh.rim_front
	lever.rim_back = mesh.rim_back
	lever.group("rubber", _materials.rubber)
	lever.group("glove", _materials.glove)
	lever.group("suit", _materials.suit)
	lever.group("panel", _materials.panel)
	lever.group("metal", _materials.metal)
	lever.cylinder("metal", Vector3.ZERO, Vector3(0, 0.072, 0), 0.015, 12)
	lever.box("panel", Vector3(0, 0.116, 0.004), Vector3(0.072, 0.074, 0.132), 0.018, Basis(Vector3.RIGHT, 0.16))
	for i in range(4):
		lever.box("rubber", Vector3(0, 0.150 - float(i) * 0.004, 0.046 - float(i) * 0.024),
			Vector3(0.068, 0.008, 0.012), 0.003, Basis(Vector3.RIGHT, 0.16))
	lever.box("metal", Vector3(0.028, 0.150, -0.040), Vector3(0.016, 0.012, 0.022), 0.003, Basis(Vector3.RIGHT, 0.16))
	lever.cylinder("metal", Vector3(-0.024, 0.150, -0.034), Vector3(-0.024, 0.160, -0.038), 0.008, 10)
	_hand(lever, Vector3(0, 0.086, 0.030), Vector3(0, 0.150, -0.030), -1.0)
	lever.commit(throttle_pivot, "Throttle", LAYER)
	triangles += lever.triangle_count()

# -------------------------------------------------------------------- canopy

func _build_canopy() -> void:
	var bow_t: float = rail_t(BOW_Z)
	var stations: Array = []
	for i in range(21):
		var t: float = float(i) / 20.0
		stations.append({"t": t, "z": rail_z(t), "half": rail_half(t), "base": rail_y(t)})
	# Make sure a station lands exactly on the bow so its feet sit on the rail.
	stations.append({"t": bow_t, "z": rail_z(bow_t), "half": rail_half(bow_t), "base": rail_y(bow_t)})
	stations.sort_custom(func(a, b): return float(a.t) < float(b.t))
	canopy = Canopy.new()
	canopy.name = "Canopy"
	canopy.layer_mask = LAYER
	add_child(canopy)
	canopy.build(mesh, stations, bow_t, "frame", "rubber", "metal", _occ.bow)

# -------------------------------------------------------------------- lights

func _build_lights() -> void:
	# The world's directional light is sized for a 1.4 km landscape; its shadow
	# cascade cannot resolve a 1 m cockpit. The rig below is filtered to the
	# cockpit's own visual layer, so it shades this interior and nothing else.
	sky_fill = OmniLight3D.new()
	sky_fill.name = "SkyFill"
	sky_fill.position = Vector3(0.0, 0.46, -0.44)
	sky_fill.light_color = Color(0.56, 0.72, 1.0)
	sky_fill.light_energy = 1.05
	sky_fill.omni_range = 3.4
	sky_fill.omni_attenuation = 0.9
	sky_fill.light_cull_mask = LIGHT_MASK
	sky_fill.shadow_enabled = false
	add_child(sky_fill)

	key_spot = SpotLight3D.new()
	key_spot.name = "CockpitKey"
	key_spot.light_color = Color(1.0, 0.85, 0.72)
	key_spot.light_energy = 2.4
	key_spot.spot_range = 4.6
	# A narrow cone concentrates the shadow map on the tub: at 58 degrees the map
	# spread over ten metres and every contact shadow washed out.
	key_spot.spot_angle = 36.0
	key_spot.spot_attenuation = 0.6
	key_spot.light_cull_mask = LIGHT_MASK
	key_spot.shadow_enabled = true
	key_spot.shadow_bias = 0.0022
	key_spot.shadow_normal_bias = 0.05
	key_spot.shadow_blur = 0.7
	key_spot.shadow_opacity = 0.92
	key_spot.light_specular = 0.7
	add_child(key_spot)
	set_sun(Vector3(-0.55, 0.32, -0.77), 1.0)

	# The display is the brightest thing in a fighter cockpit: it spills green
	# onto the hood's underside and the pilot's gloves.
	display_spill = OmniLight3D.new()
	display_spill.name = "DisplaySpill"
	display_spill.position = SCREEN_CENTRE + Vector3(0, 0.010, 0.085)
	display_spill.light_color = Color(0.58, 0.94, 0.74)
	display_spill.light_energy = 0.19
	display_spill.omni_range = 0.52
	display_spill.omni_attenuation = 1.8
	display_spill.light_cull_mask = LIGHT_MASK
	display_spill.shadow_enabled = false
	add_child(display_spill)

	shade_fill = OmniLight3D.new()
	var rim: OmniLight3D = shade_fill
	rim.name = "ShadeSideBounce"
	rim.position = Vector3(0.0, 0.16, 0.34)
	rim.light_color = Color(0.52, 0.62, 0.82)
	rim.light_energy = 0.55
	rim.omni_range = 2.8
	rim.light_cull_mask = LIGHT_MASK
	rim.shadow_enabled = false
	add_child(rim)

	var footwell := OmniLight3D.new()
	footwell.name = "FootwellBounce"
	footwell.position = Vector3(0.0, -0.60, -0.30)
	footwell.light_color = Color(0.58, 0.62, 0.72)
	footwell.light_energy = 0.34
	footwell.omni_range = 1.1
	footwell.light_cull_mask = LIGHT_MASK
	footwell.shadow_enabled = false
	add_child(footwell)

# ------------------------------------------------------------------- runtime

## `direction_view` points from the cockpit toward the sun, in cockpit space.
func set_sun(direction_view: Vector3, energy: float) -> void:
	var to_sun: Vector3 = direction_view.normalized()
	if to_sun.length_squared() < 0.5: to_sun = Vector3(0, 1, 0)
	if is_instance_valid(key_spot):
		# Keep the key above the rail: a spot slung under the floor would light
		# the cockpit from below and look like a fire.
		var lifted: Vector3 = (to_sun + Vector3.UP * 0.55).normalized()
		var target := Vector3(0.0, -0.46, -0.46)
		key_spot.position = lifted * 2.6 + Vector3(0, 0, -0.35)
		var aim: Vector3 = target - key_spot.position
		if aim.length_squared() > 1e-6:
			# Local, not global: the cockpit node is counter-rotated as the pilot
			# looks around, so look_at_from_position would aim this at the world.
			var up: Vector3 = Vector3.UP if absf(aim.normalized().y) < 0.97 else Vector3.BACK
			key_spot.basis = Basis.looking_at(aim.normalized(), up)
		key_spot.light_energy = clampf(energy, 0.15, 1.4) * 1.75
	if is_instance_valid(shade_fill):
		# Sky bounce off the canopy on the side away from the sun. Without it the
		# shaded console went black, which is the one thing the brief forbids.
		var away := Vector3(-to_sun.x, 0.34, -to_sun.z)
		if away.length_squared() < 0.04: away = Vector3(0, 1, 0)
		shade_fill.position = away.normalized() * 1.05 + Vector3(0, 0.10, -0.24)
		shade_fill.light_energy = 0.80 + clampf(energy, 0.0, 1.4) * 0.55
	if is_instance_valid(sky_fill):
		sky_fill.light_energy = 0.70 + clampf(energy, 0.0, 1.4) * 0.72
	if is_instance_valid(canopy): canopy.set_sun(to_sun, energy)
	if screen_glass != null: screen_glass.set_shader_parameter("sun_view", to_sun)

func set_attitude(pitch: float, roll: float) -> void:
	if standby_material == null: return
	standby_material.set_shader_parameter("pitch", pitch)
	standby_material.set_shader_parameter("roll", roll)
