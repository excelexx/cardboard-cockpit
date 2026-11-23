extends SceneTree
## Standalone look harness for the SPECTRE airframe. It builds the sky, sun and
## grading of the San Francisco world without loading a single terrain chunk, so
## a full sweep of hero angles takes seconds instead of minutes.
##
##   Godot --path simulator --windowed --resolution 1600x1000 --script tests/studio_jet.gd
##   ... -- top chase overwater        # only those views
##   ... -- gear                       # gear-down variant as well
##   ... -- gearsweep                  # mid-travel retraction poses only
##   ... -- bays                       # port weapon bay open, belly + low 3/4
##   ... -- symlight                   # flat symmetric light: proves the paint
##                                     # shader treats a mirrored pair alike
##   Godot --headless --path simulator --script tests/studio_jet.gd -- probe
##
## PNGs land in build/jet/.
const Catalog = preload("res://data/aircraft.gd")
const Dynamics = preload("res://systems/flight_dynamics.gd")
const Model = preload("res://systems/fighter_model.gd")
const Visuals = preload("res://systems/aircraft_visuals.gd")
const Spectre = preload("res://systems/spectre_airframe.gd")

const SKY_YAW_DEGREES := -79.8
const SUN_ENERGY := 3.0

# name: [camera offset, look target, fov, backdrop]
const VIEWS := {
	"chase": [Vector3(0, 3.4, 13.0), Vector3(0, 0, 0), 52.0, "water"],
	"game": [Vector3(0, 6.4, 23.0), Vector3(0, 1.0, -7.0), 70.0, "water"],
	# The three backdrops the owner called out, shot through the real chase
	# camera geometry from systems/camera_rig.gd.
	"game_water": [Vector3(0, 8.6, 23.0), Vector3(0, -0.6, -7.0), 70.0, "water"],
	"game_hills": [Vector3(0, 8.6, 23.0), Vector3(0, -0.6, -7.0), 70.0, "hills"],
	"game_sky": [Vector3(0, 2.0, 23.0), Vector3(0, 3.4, -7.0), 70.0, "sky"],
	"overwater": [Vector3(0, 12.5, 21.0), Vector3(0, -0.5, -2.0), 46.0, "water"],
	"overhills": [Vector3(0, 12.5, 21.0), Vector3(0, -0.5, -2.0), 46.0, "hills"],
	"keyart": [Vector3(10.0, 5.2, 12.5), Vector3(0, 0, 1.5), 42.0, "water"],
	"front34low": [Vector3(-9.0, -3.2, -12.5), Vector3(0, 0.2, -1.0), 40.0, "sky"],
	# Tight on the port chine ahead of the intake: this is the shot that proves
	# the CG-26 is bolted to the outside of the aircraft and not buried in it.
	"gunbay": [Vector3(-5.6, -2.6, -9.4), Vector3(-1.34, -0.46, -3.72), 32.0, "sky"],
	"side": [Vector3(21.0, 0.8, 0.0), Vector3(0, -0.2, 0.2), 32.0, "water"],
	"top": [Vector3(0, 25.0, 0.2), Vector3(0, 0, 0), 34.0, "water"],
	"headon": [Vector3(0, 0.6, -19.0), Vector3(0, -0.2, 0), 28.0, "hills"],
	"againstsky": [Vector3(0, -8.0, 15.0), Vector3(0, 0.5, 0), 46.0, "sky"],
	# Straight up at the keel. Everything the airframe hangs under the belly --
	# bay, doors, strakes, pylons, stowed gear -- has to read as one flush
	# surface here, not as boxes bolted on.
	"belly": [Vector3(0, -13.5, 1.2), Vector3(0, 0, 0.4), 40.0, "sky"],
	# The pose the gear travel is judged from: below and ahead of the wing root,
	# where both main legs are in frame at once.
	"gearview": [Vector3(-6.4, -6.6, 8.2), Vector3(0, -1.1, 0.9), 46.0, "sky"],
}
const ORDER := ["top", "chase", "game", "game_water", "game_hills", "game_sky", "overwater", "overhills", "keyart", "front34low", "gunbay", "side", "headon", "againstsky", "belly"]
## Mid-travel retraction fractions. No render of a partly retracted pose existed
## before, which is exactly how both main legs came to scissor through each
## other and swap sides unnoticed for the whole 2 s cycle.
const GEAR_STEPS := [0.25, 0.5, 0.75]

var model: Node3D
var visuals
var flight
var ground: MeshInstance3D
var water_material: StandardMaterial3D
var hill_material: StandardMaterial3D
var camera: Camera3D

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var wanted := OS.get_cmdline_user_args()
	if "probe" in wanted:
		probe()
		return
	if DisplayServer.get_name() == "headless":
		printerr("Native GPU required (or pass -- probe)")
		quit(2)
		return
	var folder := ProjectSettings.globalize_path("res://../build/jet")
	DirAccess.make_dir_recursive_absolute(folder)
	_stage()
	var gear_down: bool = "gear" in wanted
	var sweep: bool = "gearsweep" in wanted
	_pose(gear_down)
	for i in 20: await process_frame
	if "symlight" in wanted:
		# The paint shader used to gate "facing up" / "facing down" on the vertex
		# normal in each MeshInstance3D's OWN space. FinMount is
		# Basis(Z,-cant*side) * Basis(X,tilt) * Basis(Z,PI/2), so both fins carry
		# the SAME local normal while their world normals are opposite: one blade
		# got the sun-baked matting and the other the warm under-bounce, measured
		# 1.6x apart in luminance and opposite in hue.
		#
		# Under a flat, top-down, side-free light any residual left/right split
		# on a mirror-symmetric airframe has to come from the shader. Deflect
		# nothing (the flaperons roll differentially) and diff the frame against
		# its own mirror.
		_symmetric_light()
		visuals.reset()
		visuals.update_visuals(3.0, flight, Vector3.ZERO)
		visuals.update_visuals(0.016, flight, Vector3.ZERO)
		for i in 10: await process_frame
		await _shoot("againstsky", folder, "sym_againstsky")
		await _shoot("top", folder, "sym_top")
		quit(0)
		return
	if "bays" in wanted:
		# The bay volume is recessed inside the loft now, so the cavity the doors
		# expose is a set of skin-following mouth panels. Both states have to be
		# looked at: shut, the keel is one unbroken line; open, there is a real
		# dark opening and still nothing hanging below the skin.
		visuals.open_weapon_bay(-1.0)
		for i in 8: visuals.update_visuals(0.05, flight, Vector3(0.45, 0.30, 0.0))
		await _shoot("belly", folder, "bays_belly")
		await _shoot("front34low", folder, "bays_front34low")
		quit(0)
		return
	if sweep:
		for step: float in GEAR_STEPS:
			visuals.gear_progress = step
			visuals._apply_gear()
			await _shoot("gearview", folder, "gear%d" % int(step * 100.0))
		visuals.gear_progress = 1.0
		visuals._apply_gear()
		await _shoot("gearview", folder, "gear100")
		quit(0)
		return
	for view: String in ORDER:
		if not wanted.is_empty() and view not in wanted and not (wanted.size() == 1 and gear_down): continue
		await _shoot(view, folder, view + ("_gear" if gear_down else ""))
	quit(0)

## One framed capture. `view` picks the camera, `label` names the PNG.
func _shoot(view: String, folder: String, label: String) -> void:
	var spec: Array = VIEWS[view]
	_backdrop(str(spec[3]))
	camera.fov = float(spec[2])
	camera.global_position = Vector3(spec[0])
	camera.look_at(Vector3(spec[1]), Vector3(0, 0, -1) if view == "top" else Vector3.UP)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + "/" + label + ".png")
	print("JET SHOT ", label, " prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))

## Headless sanity pass: the airframe builds, is the right size, and still
## publishes every node name the rest of the game looks up.
func probe() -> void:
	var built: Node3D = Model.create()
	root.add_child(built)
	var bounds := _bounds(built, Transform3D.IDENTITY)
	var triangles := 0
	var meshes := 0
	for node in built.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
		for surface in node.mesh.get_surface_count():
			triangles += node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size() / 3
	print("PROBE bounds=", bounds.position.snapped(Vector3.ONE * 0.01), " size=", bounds.size.snapped(Vector3.ONE * 0.01))
	print("PROBE meshes=", meshes, " triangles=", triangles)
	var failures: Array[String] = []
	# Names every airframe must keep, then the ones only the procedural SPECTRE
	# publishes: flipping FighterModel.USE_SPECTRE_AIRFRAME must not fail this.
	var required: Array[String] = ["GunGimbal", "GatlingRotor", "GunMuzzle", "flaperonL", "flaperonR",
		"rudderL", "rudderR", "door bayLI", "door bayLO", "door bayRI", "door bayRO"]
	if Model.USE_SPECTRE_AIRFRAME:
		required.append_array(["elevatorL", "elevatorR", "Canopy", "NozzlePetals", "Strake", "FinL", "FinR"] as Array[String])
	for name: String in required:
		if built.find_child(name + "*" if name == "Strake" else name, true, false) == null: failures.append(name)
	if built.get_node_or_null("Airframe/LandingGear") == null: failures.append("Airframe/LandingGear")
	# The cannon has to live OUTSIDE the skin. Buried at the old mount it drew
	# nothing, and the muzzle flash was half depth-clipped by the fuselage.
	var gun: Node3D = built.get_node_or_null("CG26")
	if gun == null:
		failures.append("CG26")
	else:
		var box := _bounds(gun, Transform3D.IDENTITY)
		print("PROBE gun aabb=", box.position.snapped(Vector3.ONE * 0.01), " size=", box.size.snapped(Vector3.ONE * 0.01))
		var muzzle: Node3D = gun.find_child("GunMuzzle", true, false)
		var samples: Array[Vector3] = [Model.GUN_MOUNT, Model.MUZZLE, box.get_center(),
			Vector3(box.get_center().x, box.get_center().y, box.position.z + box.size.z * 0.06),
			Vector3(box.get_center().x, box.get_center().y, box.position.z + box.size.z * 0.94)]
		if muzzle != null: samples.append(muzzle.global_position if muzzle.is_inside_tree() else Model.MUZZLE)
		for point: Vector3 in samples:
			if _inside_hull(point): failures.append("gun point %s is inside the skin" % str(point.snapped(Vector3.ONE * 0.01)))
		# The 2.1 m muzzle-flash quad is centred 1.02 m ahead of the marker.
		for step in 9:
			var at: Vector3 = Model.MUZZLE + Vector3(0, 0, -2.07 + 2.1 * float(step) / 8.0)
			if _inside_hull(at): failures.append("muzzle flash clipped at z=%.2f" % at.z)
	var presentation = Visuals.new()
	root.add_child(presentation)
	presentation.initialize(built, Catalog.PROFILE)
	print("PROBE surfaces=", presentation._surfaces.size(), " gear_groups=", presentation._gear_groups.size(), " bay_doors=", presentation.bay_doors.size(), " glow=", presentation._engine_glow != null)
	if presentation._gear_groups.size() != 3: failures.append("expected 3 gear legs")
	if presentation.bay_doors.size() != 4: failures.append("expected 4 bay doors")
	if presentation._engine_glow == null: failures.append("no engine glow")
	if absf(bounds.position.y + 3.0) > 0.08: failures.append("wheels at %.3f, not -3.0" % bounds.position.y)
	if Model.USE_SPECTRE_AIRFRAME:
		if presentation._surfaces.size() != 6: failures.append("expected 6 control surfaces")
		if absf(bounds.size.z - 15.5) > 0.6: failures.append("length %.2f is not ~15.5 m" % bounds.size.z)
		if absf(bounds.size.x - 10.8) > 0.6: failures.append("span %.2f is not ~10.8 m" % bounds.size.x)
	print("STUDIO JET PROBE: ", failures.size(), " failures")
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

## Is a point in aircraft space inside the fuselage skin? The hull is a lofted
## cross-section, so the honest test is point-in-polygon against the section at
## that z -- an axis-aligned _hull_top_y / _hull_lower_y pair lies about the
## flank, which is exactly where the gun has to sit.
func _inside_hull(point: Vector3) -> bool:
	if point.z < -8.2 or point.z > 6.2: return false
	var half: PackedVector2Array = Spectre._half_section(point.z)
	var poly := PackedVector2Array()
	for p: Vector2 in half: poly.append(p)
	for i in range(half.size() - 2, 0, -1): poly.append(Vector2(-half[i].x, half[i].y))
	return Geometry2D.is_point_in_polygon(Vector2(point.x, point.y), poly)

func _bounds(node: Node3D, accumulated: Transform3D) -> AABB:
	var here: Transform3D = accumulated * node.transform
	var result := AABB()
	var found := false
	if node is MeshInstance3D and node.mesh != null:
		result = here * node.get_aabb()
		found = true
	for child in node.get_children():
		if child is Node3D:
			var inner := _bounds(child, here)
			if inner.size.length() > 0:
				result = inner if not found else result.merge(inner)
				found = true
	return result

func _stage() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://assets/look/sunset_sky.gdshader")
	sky_material.set_shader_parameter("panorama", load("res://assets/look/kloppenheim_06_puresky_8k.hdr"))
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(SKY_YAW_DEGREES), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.16
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.25
	var holder := WorldEnvironment.new()
	holder.environment = env
	root.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-10.0, -110, 0)
	sun.light_color = Color(1.0, 0.66, 0.38)
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120
	root.add_child(sun)
	# The effects layer lights the airframe with a culled fill light; mirror it
	# here so studio shots match what the chase camera actually sees.
	var fill := OmniLight3D.new()
	fill.light_cull_mask = 2
	fill.light_color = Color(1.0, 0.93, 0.84)
	fill.light_energy = 2.6
	fill.omni_range = 24
	fill.omni_attenuation = 0.6
	fill.shadow_enabled = false
	fill.position = Vector3(0, 7, 5)
	root.add_child(fill)
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 6000)
	ground = MeshInstance3D.new()
	ground.mesh = plane
	ground.position = Vector3(0, -70, 0)
	root.add_child(ground)
	water_material = StandardMaterial3D.new()
	water_material.albedo_color = Color(0.019, 0.030, 0.044)
	water_material.metallic = 0.85
	water_material.roughness = 0.10
	hill_material = StandardMaterial3D.new()
	hill_material.albedo_color = Color(0.095, 0.230, 0.072)
	hill_material.roughness = 0.92
	hill_material.metallic = 0.0
	camera = Camera3D.new()
	camera.near = 0.2
	camera.far = 12000
	camera.current = true
	root.add_child(camera)

## Flat grey surround and a straight-down sun: no left/right bias anywhere in
## the lighting, so a mirrored pair of parts must render identically.
func _symmetric_light() -> void:
	for node in root.get_children():
		if node is WorldEnvironment:
			var env: Environment = node.environment
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.22, 0.24, 0.27)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.30, 0.32, 0.36)
			env.ambient_light_sky_contribution = 0.0
			env.ambient_light_energy = 1.0
			env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		elif node is DirectionalLight3D:
			node.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		elif node is OmniLight3D:
			node.position = Vector3(0, 9, 0)

func _backdrop(kind: String) -> void:
	ground.visible = kind != "sky"
	ground.material_override = hill_material if kind == "hills" else water_material

func _pose(gear_down: bool) -> void:
	model = Model.create()
	root.add_child(model)
	visuals = Visuals.new()
	root.add_child(visuals)
	visuals.initialize(model, Catalog.PROFILE)
	flight = Dynamics.new()
	flight.reset(Catalog.PROFILE)
	flight.spawn_airborne(Vector3.ZERO, 260)
	flight.gear = gear_down
	flight.engine = 1.0
	flight.afterburner = true
	visuals.reset()
	# One long step settles the gear and control surfaces into their held pose.
	visuals.update_visuals(3.0, flight, Vector3(0.45, 0.30, 0.0))
	visuals.update_visuals(0.016, flight, Vector3(0.45, 0.30, 0.0))
