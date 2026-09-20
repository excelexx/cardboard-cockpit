extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var before := FileAccess.get_file_as_string("user://settings.cfg")
	var app = load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","sf"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.test_mode = true; app.audio.muted = true
	app.start_flight("combat")
	assert(not app.flight.airborne and app.flight.speed==0 and app.flight.throttle==0)
	assert(app.is_on_runway(app.flight.position))
	assert(is_equal_approx(app.flight.position.y,app.world.ground_height(app.flight.position.x,app.flight.position.z)+3))
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/runway-start.png"))
	assert(before==FileAccess.get_file_as_string("user://settings.cfg"),"Review must preserve saved settings")
	print("RUNWAY START PASS: San Francisco combat flight starts at rest on the runway surface")
	app.queue_free(); await process_frame
	quit()
