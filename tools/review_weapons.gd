extends SceneTree
var app: Node
var output: String
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if OS.get_environment("COCKPIT_DISABLE_BADGE")!="1":printerr("Offline review requires badge disabled");quit(2);return
	output=ProjectSettings.globalize_path("res://../build/weapons/action");DirAccess.make_dir_recursive_absolute(output)
	app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","sf");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.test_mode=true;app.audio.muted=true
	app.start_flight("combat");app.cockpit=false;app.text_hud=true;app.flight.spawn_airborne(Vector3(5000,1200,-14000),180);app.flight.heading=.2
	app.flight.flaps=0;app.flight.gear=false;app.apply_aircraft_pose();app.combat.spawn_clock=999;app.camera_rig.reset();app.fire_guard=0
	app.get_window().title="Offline weapon review — simulated firing, badge disabled"
	for i in range(20):app._process(1.0/60);await process_frame
	for i in range(240):
		app.combat.fire_gun()
		app.combat.fire_missile()
		app._physics_process(1.0/60);app._process(1.0/60)
		await process_frame
		if i%6==0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/frame-%03d.png" % (i/6))
	print("WEAPON VIDEO CAPTURE rounds=",app.combat.rounds_fired," missiles=",app.combat.missiles_fired)
	app.queue_free();await process_frame;quit()
