extends SceneTree

# Render the recovery overlay over the real paused flight using a synthetic
# camera frame. Route overrides never change the player's saved settings.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,800)
	var before := FileAccess.get_file_as_string("user://settings.cfg")
	var app = load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.test_mode = true
	app.audio.muted = true; app.start_flight("combat", true)
	app.vision.enabled = true; app.vision.tracking = false
	var frame := Image.load_from_file(ProjectSettings.globalize_path("res://../build/tutorial-fixture-yoke.png"))
	app.vision_preview.texture = ImageTexture.create_from_image(frame)
	var position: Vector3 = app.flight.position
	app._physics_process(.05)
	assert(app.world.visible and app.flight.position == position)
	assert(FileAccess.get_file_as_string("user://settings.cfg") == before,"Visual review cannot overwrite the saved map")
	await process_frame; await RenderingServer.frame_post_draw
	var destination := ProjectSettings.globalize_path("res://../build/yoke-recovery-review.png")
	root.get_texture().get_image().save_png(destination)
	assert(app.hud.zones.has("keyboard"))
	print("RECOVERY UI: "+destination)
	app.queue_free(); await process_frame; quit()
