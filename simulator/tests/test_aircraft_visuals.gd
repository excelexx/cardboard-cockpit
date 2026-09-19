extends SceneTree
## Validates reversible presentation on the five real imported aircraft.
## Optional -- --capture writes rendered inspection images into workspace work/.
const Visuals = preload("res://systems/aircraft_visuals.gd")
const Catalog = preload("res://data/aircraft.gd")
const Dynamics = preload("res://systems/flight_dynamics.gd")
var failures: Array[String] = []
var checks := 0
var capture := false
var world: Node3D
var camera: Camera3D

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	world = Node3D.new()
	root.add_child(world)
	if capture:
		root.size = Vector2i(1440, 1000)
		var environment := WorldEnvironment.new()
		var settings := Environment.new()
		settings.background_mode = Environment.BG_COLOR
		settings.background_color = Color("18202b")
		settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		settings.ambient_light_color = Color("c6daee")
		settings.ambient_light_energy = 0.55
		settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.environment = settings
		world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-30, -25, 0)
		light.light_energy = 1.3
		world.add_child(light)
		camera = Camera3D.new()
		camera.fov = 42
		world.add_child(camera)
	call_deferred("run_checks")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func run_checks() -> void:
	for profile in Catalog.PLANES:
		var model: Node3D = load("res://assets/aircraft/%s/%s.tscn" % [profile.id, profile.id]).instantiate()
		world.add_child(model)
		var helper = Visuals.new()
		world.add_child(helper)
		var flight = Dynamics.new()
		flight.reset(profile)
		var original_model := model.transform
		helper.initialize(model, profile)
		var gear: Node3D = model.get_node("Airframe/LandingGear")
		var groups: Array = helper._gear_groups
		var expected_groups := 5 if profile.id in ["a380", "b747"] else 3
		expect(groups.size() == expected_groups, profile.id + ": physical wheel clusters identify each complete gear assembly")
		expect(helper.gear_progress == 1.0 and gear.visible, profile.id + ": initially extended")
		var original_parts: Dictionary = {}
		for group in groups:
			for part in group.parts:
				original_parts[part.node] = part.node.transform
		var structural := helper._find_mesh("fuselage")
		if structural == null:
			structural = helper._find_mesh("RightWing")
		var structural_transform: Transform3D = structural.transform if structural != null else Transform3D.IDENTITY
		flight.gear = false
		helper.update_visuals(1.0, flight, Vector3.ONE)
		expect(is_equal_approx(helper.gear_progress, 0.5) and helper.is_gear_moving() and gear.visible, profile.id + ": halfway position retains visible moving gear")
		for node in original_parts:
			expect(not node.transform.is_equal_approx(original_parts[node]), profile.id + ": individual gear part travels during retraction")
		expect(model.transform == original_model, profile.id + ": model origin and orientation never change")
		if structural != null:
			expect(structural.transform == structural_transform, profile.id + ": structural fuselage or wing stays unchanged")
		for surface in helper._surfaces:
			expect(not surface.node.transform.is_equal_approx(surface.original), profile.id + ": authored control surface responds to pilot input")
		if capture:
			await render_capture(helper, profile.id + "-half-gear")
		flight.gear = true
		helper.update_visuals(0.5, flight, Vector3.ZERO)
		expect(is_equal_approx(helper.gear_progress, 0.75), profile.id + ": gear reverses direction from an intermediate position")
		flight.gear = false
		helper.update_visuals(1.5, flight, Vector3.ZERO)
		expect(helper.gear_progress == 0.0 and not gear.visible, profile.id + ": gear hides only when travel is complete")
		flight.gear = true
		helper.update_visuals(0.1, flight, Vector3.ZERO)
		expect(gear.visible and helper.gear_progress > 0.0, profile.id + ": stowed gear is visible as extension starts")
		helper.update_visuals(1.9, flight, Vector3.ZERO)
		for node in original_parts:
			expect(node.transform.is_equal_approx(original_parts[node]), profile.id + ": full extension restores original mesh transform")
		expect(flight.gear and flight.elapsed == 0.0, profile.id + ": visuals do not mutate flight commands or simulation time")
		var effects: Node3D = model.get_node("FlightPresentation")
		var port: Node3D = effects.get_node("PortNavigation")
		var starboard: Node3D = effects.get_node("StarboardNavigation")
		expect(port.position.x < -helper.model_bounds.size.x * 0.45 and starboard.position.x > helper.model_bounds.size.x * 0.45, profile.id + ": navigation lamps sit on real left/right wing tips")
		helper.reset()
		helper.update_visuals(0.03, flight, Vector3.ZERO)
		expect(effects.get_node("PortStrobe").visible, profile.id + ": first strobe pulse")
		helper.update_visuals(0.06, flight, Vector3.ZERO)
		expect(not effects.get_node("PortStrobe").visible, profile.id + ": dark gap between strobe pulses")
		helper.update_visuals(0.06, flight, Vector3.ZERO)
		expect(effects.get_node("PortStrobe").visible, profile.id + ": second strobe pulse")
		flight.gear = false
		flight.engine = 1.0
		helper.update_visuals(2.0, flight, Vector3.ZERO)
		if capture:
			await render_capture(helper, profile.id + "-stowed")
		helper.reset()
		for surface in helper._surfaces:
			expect(surface.node.transform.is_equal_approx(surface.original), profile.id + ": reset restores source surface orientation")
		expect(helper.gear_progress == 1.0 and gear.visible, profile.id + ": reset extends previously hidden gear")
		for node in original_parts:
			expect(node.transform.is_equal_approx(original_parts[node]), profile.id + ": reset restores every original gear transform")
		helper.initialize(model, profile)
		expect(model.get_node_or_null("FlightPresentation") != null and helper._gear_groups.size() == expected_groups, profile.id + ": helper can reinitialize the same aircraft without duplicate effects")
		if capture:
			await render_capture(helper, profile.id + "-extended")
		print(profile.id, ": ", groups.size(), " gear assemblies, ", helper._surfaces.size(), " source-pivot control surfaces")
		model.free()
		helper.free()
	if failures.is_empty():
		print("PASS: ", checks, " aircraft presentation checks across all five imported models.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)

func render_capture(helper, label: String) -> void:
	var extent: float = maxf(helper.model_bounds.size.x, helper.model_bounds.size.z)
	camera.position = Vector3(extent * 0.74, extent * 0.22, extent * 0.94)
	camera.look_at(helper.model_bounds.get_center() * Vector3(0, 0.3, 0))
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../../../work/v02-aircraft")
	DirAccess.make_dir_recursive_absolute(path)
	root.get_texture().get_image().save_png(path.path_join(label + ".png"))
