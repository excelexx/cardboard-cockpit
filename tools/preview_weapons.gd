extends SceneTree
const Art = preload("res://systems/weapon_visuals.gd")
var world: Node3D
func _initialize() -> void: call_deferred("render")
func render() -> void:
	root.size = Vector2i(1440,900)
	world = Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035,0.055,0.075)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.72,0.83,1)
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	light.light_energy = 1.5
	world.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(10,11,16)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17
	var names: Array[String] = ["GATLING / TRACER","GUIDED SEEKER","HEAVY AUTOCANNON","BATTERY MISSILE","PULSE PLASMA"]
	for i in range(5):
		var kind: String = "missile" if i in [1,3] else "plasma" if i==4 else "cannon"
		var variant: String = "battery" if i==3 else "heavy" if i==2 else "gatling"
		var projectile: Node3D = Art.projectile(kind,variant)
		world.add_child(projectile)
		projectile.position = Vector3((i-2)*3.3,0,0)
		if kind=="cannon": projectile.scale = Vector3(2.5,2.5,1)
		var label := Label3D.new()
		label.text = names[i]
		label.font_size = 40
		label.pixel_size = 0.009
		label.position = Vector3((i-2)*3.3,-1.0,4.6)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(label)
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../build/weapon-designs.png")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	root.get_texture().get_image().save_png(output)
	world.queue_free()
	await process_frame
	quit()
