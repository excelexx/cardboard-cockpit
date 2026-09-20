extends SceneTree
var app: Node
func _initialize() -> void: call_deferred("run")
func capture(label: String) -> void:
	app.apply_aircraft_pose()
	app.aircraft_visuals.update_visuals(2.1,app.flight,app.control)
	app.cockpit_frame.update_instruments(app.flight,app.control,1.0)
	app.cockpit_frame.set_navigation("sf",app.mission.route_index,app.mission.points)
	app.camera_rig.reset()
	for i in range(30): app.camera_rig.update(1.0/60)
	app.mission.update_visuals()
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/short-demo-"+label+".png"))
func run() -> void:
	var before := FileAccess.get_file_as_string("user://settings.cfg")
	app = load("res://scenes/main.tscn").instantiate(); app.set_meta("route_override","sf"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	app.test_mode = true; app.test_finished = true
	app.on_action("guided"); app.demo_auto_fire = false
	await capture("runway")
	var captured: Dictionary = {}
	for i in range(24000):
		app._physics_process(1.0/60)
		var phase: String = app.mission.phase
		if phase=="combat" and app.mission.phase_clock>1 and not captured.has(phase):
			await capture(phase); captured[phase] = true; app.demo_auto_fire = true
		elif phase in ["return","approach"] and app.mission.phase_clock>2 and not captured.has(phase):
			await capture(phase); captured[phase] = true
		if app.mode=="results":
			await capture("complete"); break
		if i%120==0: await process_frame
	assert(app.mission_success and app.combat.kills==16)
	assert(before==FileAccess.get_file_as_string("user://settings.cfg"))
	print("SHORT DEMO VISUAL PASS: runway, sixteen targets, higher cruise, landing rings, approach and completion")
	app.queue_free(); await process_frame; quit()
