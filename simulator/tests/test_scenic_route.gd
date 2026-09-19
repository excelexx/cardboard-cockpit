extends SceneTree
const ScenicRoute = preload("res://systems/scenic_route.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.set_physics_process(false)
	app.audio.muted = true
	app.on_action("demo")
	var visual: bool = "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	# Offscreen captures must not auto-pause when Finder or the editor has focus.
	if visual: app.capture_file = "scenic-review"
	var previous_index := -1
	var peak := 0.0
	var floor_corrections := 0
	for frame in range(36000):
		app._physics_process(1.0/60.0)
		peak = maxf(peak,app.flight.position.y)
		if app.combat.phase=="combat" and absf(app.flight.position.y-app.world.ground_height(app.flight.position.x,app.flight.position.z)-100)<0.01:
			floor_corrections += 1
		if app.combat.route_index!=previous_index:
			previous_index = app.combat.route_index
			print("ROUTE ",previous_index," t=",app.flight.elapsed," pos=",app.flight.position)
			if visual:
				app._process(1.0/60.0)
				await process_frame
				await RenderingServer.frame_post_draw
				var destination: String = ProjectSettings.globalize_path("res://../docs/screenshots/scenic")
				DirAccess.make_dir_recursive_absolute(destination)
				root.get_texture().get_image().save_png(destination+"/route-%02d.png" % previous_index)
		if app.mode=="results": break
		if frame%600==0: await process_frame
	if not app.mission_success: failures.append("Did not finish with a safe runway stop: "+str(app.flight.position)+" phase="+app.combat.phase)
	if app.combat.visited_route.size()!=ScenicRoute.POINTS.size(): failures.append("Not every scenic landmark was visited")
	if peak<1000: failures.append("Did not reach the Pacific panorama altitude")
	if floor_corrections>0: failures.append("Route relied on terrain safety correction: "+str(floor_corrections))
	if app.camera_view!="cockpit": failures.append("View left cockpit")
	print("SCENIC RESULT: ","PASS" if failures.is_empty() else "FAIL"," seconds=",app.flight.elapsed," peak=",peak," landmarks=",app.combat.visited_route.size()," corrections=",floor_corrections)
	for failure in failures: printerr(failure)
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
