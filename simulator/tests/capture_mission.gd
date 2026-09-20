extends SceneTree
# Plays the real auto-flown showcase in real time and saves frames to build/mission/. Native GPU only.
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("Native GPU required");quit(2);return
	var folder:=ProjectSettings.globalize_path("res://../build/mission")
	DirAccess.make_dir_recursive_absolute(folder)
	var app: Node3D=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	for i in 30:await process_frame
	app.audio.muted=true;app.set_quality(true)
	app.capture_file="review"   # a capture window is never focused; this keeps the game from auto-pausing
	app.on_action("guided")
	var marks: Array=[10.0,20.0,30.0,42.0,55.0,68.0,82.0]
	for value in OS.get_cmdline_user_args():
		if value.begins_with("hud=off"):app.hud.visible=false
	var began:=Time.get_ticks_msec()
	for mark: float in marks:
		while (Time.get_ticks_msec()-began)/1000.0<mark:
			if app.mode=="paused":app.mode=app.resume_mode   # unfocused capture windows auto-pause
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/t%03d.png" % int(mark))
		print("MISSION t=",mark," phase=",app.mission.phase," pos=",app.flight.position," fps=",Engine.get_frames_per_second())
	quit(0)
