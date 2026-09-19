extends SceneTree
var world: Node3D
var camera: Camera3D
var craft: Node3D
var idx: int = 0
var ticks: int = 0
var ids = ["a380", "f35", "b2", "b737", "b747"]
func _initialize():
	root.size = Vector2i(1280, 840)
	world = Node3D.new()
	root.add_child(world)
	var env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("233244")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("bfd8ec")
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	light.light_energy = 1.2
	world.add_child(light)
	camera = Camera3D.new()
	camera.fov = 42
	world.add_child(camera)
	call_deferred("run_preview")
func load_aircraft():
	if craft: craft.queue_free()
	var id = ids[idx]
	craft = load("res://assets/aircraft/%s/%s.tscn" % [id,id]).instantiate()
	world.add_child(craft)
	var metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/aircraft/%s/manifest.json" % id))
	var extent = max(metadata.dimensions.length, metadata.dimensions.wingspan)
	camera.position = Vector3(extent * .95, extent * .47, -extent * 1.03)
	camera.look_at(Vector3(0, metadata.dimensions.height * .2, 0))
	ticks = 0
func capture(id: String, suffix: String):
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var path = ProjectSettings.globalize_path("res://../work/aircraft/%s%s.png" % [id, suffix])
	root.get_texture().get_image().save_png(path)
	print("Saved preview: ", path)
func run_preview():
	for id in ids:
		load_aircraft()
		await capture(id, "")
		var gear = craft.get_node_or_null("Airframe/LandingGear")
		assert(gear != null, "Missing landing gear group: " + id)
		assert(gear.get_child_count() > 0, "Empty landing gear group: " + id)
		print(id, " gear children: ", gear.get_child_count())
		var metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/aircraft/%s/manifest.json" % id))
		var extent = max(metadata.dimensions.length, metadata.dimensions.wingspan)
		camera.position = Vector3(0, extent * 1.6, 0)
		camera.look_at(Vector3.ZERO, Vector3.FORWARD)
		await capture(id, "_top")
		gear.visible = false
		camera.position = Vector3(extent * 1.6, extent * .1, 0)
		camera.look_at(Vector3(0, metadata.dimensions.height * .15, 0))
		await capture(id, "_side_retracted")
		idx += 1
	quit()
