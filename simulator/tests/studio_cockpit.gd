extends SceneTree
## Standalone look harness for the fighter interior. Native GPU, no world load,
## so a look-and-fix round costs seconds instead of a full mission boot.
##
## Godot --path simulator --windowed --resolution 1600x1000 --script tests/studio_cockpit.gd
##   optional: -- <view> <view> ... | flat | nosun
##
## Sky, sun and tonemap are copied from scenes/san_francisco_world.gd so what the
## studio shows is what the golden-hour mission shows.
const World := preload("res://scenes/san_francisco_world.gd")
const Catalog := preload("res://data/aircraft.gd")
const Cockpit := preload("res://scenes/cockpit.gd")
const Dynamics := preload("res://systems/flight_dynamics.gd")

var camera: Camera3D
var cockpit: DetailedCockpit
var flight: FlightDynamics
var environment: Environment
var sun: DirectionalLight3D

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("STUDIO cockpit: native GPU required")
		quit(2)
		return
	var wanted := OS.get_cmdline_user_args()
	var folder := ProjectSettings.globalize_path("res://../build/cockpit")
	DirAccess.make_dir_recursive_absolute(folder)
	var stage := Node3D.new()
	root.add_child(stage)
	_build_sky(stage)
	camera = Camera3D.new()
	camera.fov = 76.0            # the game's cockpit field of view
	camera.near = 0.02
	camera.far = 3000.0
	camera.current = true
	stage.add_child(camera)
	# A horizon to sit against: the interior has to separate from something.
	_build_ground(stage)
	var began := Time.get_ticks_msec()
	cockpit = Cockpit.new()
	stage.add_child(cockpit)
	cockpit.build(Catalog.PROFILE)
	cockpit.set_presentation_visible(true)
	var build_ms := Time.get_ticks_msec() - began
	flight = Dynamics.new()
	flight.reset(Catalog.PROFILE)
	flight.spawn_airborne(Vector3(0, 620, 0), 240.0)
	flight.throttle = 0.72
	flight.gear = false
	flight.pitch = 0.035
	flight.roll = -0.12
	cockpit.set_navigation("sf", 4)
	cockpit.set_tactical({"gun": true, "missiles": false, "tracking": true, "target": "GOOSE 04", "range": 1180.0})
	for i in 6:
		cockpit.update_instruments(flight, Vector3(0.22, -0.16, 0.0), 0.2)
		await process_frame
	if "flat" in wanted:
		# Strip every directional contribution to see the baked occlusion alone.
		sun.light_energy = 0.0
		if cockpit.fighter != null:
			cockpit.fighter.key_spot.light_energy = 0.0
			cockpit.fighter.sky_fill.light_energy = 2.4
	if "key" in wanted:
		# Cockpit key only: this is the view that proves the shadow rig works.
		sun.light_energy = 0.0
		if cockpit.fighter != null: cockpit.fighter.sky_fill.light_energy = 0.12
	if "nosun" in wanted:
		sun.light_energy = 0.35
	var views := {
		"eye": [Vector3.ZERO, Vector2(0.0, 0.0), 76.0],
		"eye_down": [Vector3.ZERO, Vector2(0.0, -20.0), 76.0],
		"left": [Vector3.ZERO, Vector2(50.0, -28.0), 76.0],
		"right": [Vector3.ZERO, Vector2(-50.0, -28.0), 76.0],
		"clay": [Vector3(1.55, 0.95, 1.35), Vector2(-999.0, 0.0), 42.0],
	}
	var fighter: FighterCockpit = cockpit.fighter
	var cost: Dictionary = {}
	for name: String in views:
		if not wanted.is_empty() and not _only_views(wanted).is_empty() and name not in wanted: continue
		var entry: Array = views[name]
		var look: Vector2 = entry[1]
		camera.fov = float(entry[2])
		if look.x < -900.0:
			# External three-quarter clay: hide the glass so the tub is readable.
			if fighter != null and is_instance_valid(fighter.canopy) and is_instance_valid(fighter.canopy.glass_mesh):
				fighter.canopy.glass_mesh.visible = false
			camera.position = entry[0]
			camera.look_at(Vector3(0.0, -0.42, -0.45), Vector3.UP)
			cockpit.basis = Basis.IDENTITY
		else:
			if fighter != null and is_instance_valid(fighter.canopy) and is_instance_valid(fighter.canopy.glass_mesh):
				fighter.canopy.glass_mesh.visible = true
			var basis := Basis.from_euler(Vector3(deg_to_rad(look.y), deg_to_rad(look.x), 0.0))
			camera.position = Vector3.ZERO
			camera.basis = basis
			# The game keeps the interior fixed to the airframe while the head turns.
			cockpit.basis = basis.inverse()
		cockpit.set_sun(sun.global_basis.z, 1.0)
		for i in 4:
			cockpit.update_instruments(flight, Vector3(0.22, -0.16, 0.0), 0.05)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "/studio_" + name + ".png")
		var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		cost[name] = draws
		print("STUDIO view ", name, " draws=", draws,
			" prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var triangles: int = fighter.triangles if fighter != null else 0
	# Godot counts the Forward+ depth prepass and the cockpit key's shadow pass as
	# draw calls, so the interior's own mesh count is roughly a third of this.
	var worst: int = 0
	for name: String in cost: worst = maxi(worst, int(cost[name]))
	print("STUDIO cockpit build_ms=", build_ms, " triangles=", triangles, " meshes=", _mesh_count(cockpit),
		" worst_draws=", worst, " fps=", Engine.get_frames_per_second(), " size=", root.size)
	var failures: Array[String] = []
	if triangles > 60000: failures.append("triangles %d over 60k" % triangles)
	if _mesh_count(cockpit) > 40: failures.append("%d mesh instances over budget" % _mesh_count(cockpit))
	if build_ms > 2500: failures.append("build took %d ms" % build_ms)
	print("STUDIO ", "PASS" if failures.is_empty() else "FAIL ", ", ".join(failures))
	quit(0 if failures.is_empty() else 1)

func _mesh_count(node: Node) -> int:
	var total := 0
	for item: Node in node.find_children("*", "GeometryInstance3D", true, false):
		if item is GeometryInstance3D and item.visible: total += 1
	return total

func _only_views(wanted: PackedStringArray) -> Array:
	var out: Array = []
	for item: String in wanted:
		if item not in ["flat", "nosun", "key"]: out.append(item)
	return out

func _build_sky(stage: Node3D) -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/look/sunset_sky.gdshader")
	material.set_shader_parameter("panorama", load("res://assets/look/kloppenheim_06_puresky_8k.hdr"))
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(World.SKY_YAW_DEGREES), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = World.EXPOSURE
	env.tonemap_white = 8.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.16
	env.fog_enabled = true
	env.fog_density = 0.000026
	env.fog_light_color = Color(0.36, 0.41, 0.50)
	env.fog_sun_scatter = 0.10
	env.fog_aerial_perspective = 0.25
	env.fog_sky_affect = 0.0
	environment = env
	var holder := WorldEnvironment.new()
	holder.environment = env
	stage.add_child(holder)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-10.0, -110.0, 0.0)
	sun.light_color = Color(1.0, 0.66, 0.38)
	sun.light_energy = World.SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1400.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.04
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.4
	stage.add_child(sun)

func _build_ground(stage: Node3D) -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(60000, 60000)
	plane.mesh = mesh
	plane.position = Vector3(0, -620, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.085, 0.105, 0.095)
	material.roughness = 0.92
	plane.material_override = material
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(plane)
