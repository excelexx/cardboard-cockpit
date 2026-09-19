extends SceneTree
var app: Node
var child := -1
var begun := 0
var saw_live := false
var saw_loss := false
var finished := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Engine.max_fps = 60
	app = load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override", "alpine")
	root.add_child(app)
	app.set_process(false); app.set_physics_process(false)
	app.test_mode = true; app.audio.muted = true
	app.start_flight("combat")
	app.dual_cameras = true
	var probes: Array[TCPServer] = [TCPServer.new(), TCPServer.new()]
	var ports: Array[int] = []
	for probe in probes:
		if probe.listen(0, "127.0.0.1") != OK:
			finish(false, "Cannot reserve ports"); return
		ports.append(probe.get_local_port())
	for probe in probes: probe.stop()
	app.vision.endpoint = "ws://127.0.0.1:" + str(ports[0])
	app.throttle_vision.endpoint = "ws://127.0.0.1:" + str(ports[1])
	app.vision.enabled = true
	var directory: String = ProjectSettings.globalize_path("res://..").simplify_path()
	child = OS.create_process(directory.path_join(".venv/bin/python"), PackedStringArray([
		directory.path_join("vision/tests/dual_camera_fixture.py"), str(ports[0]), str(ports[1])]))
	begun = Time.get_ticks_msec()
	app.vision.retry_at = begun + 600
	app.throttle_vision.enabled = true
	app.throttle_vision.retry_at = begun + 600
	app.hud.camera_preview.retry_at = begun + 600
	app.hud.throttle_preview.retry_at = begun + 600
	if child <= 0: finish(false, "Cannot start fixture")

func _process(dt: float) -> bool:
	if app == null or child <= 0 or finished: return false
	app.poll_camera_controls(dt)
	app._physics_process(dt)
	var elapsed := Time.get_ticks_msec() - begun
	if elapsed > 20000:
		finish(false, "Timed out: live=%s loss=%s yoke=%s power=%s previews=%s/%s" % [saw_live,saw_loss,app.vision.tracking,app.vision.throttle_confidence,app.hud.camera_preview.texture!=null,app.hud.throttle_preview.texture!=null]); return false
	if app.vision.tracking:
		if app.vision.yoke.distance_to(Vector2(.25,-.4)) > .001 or app.vision.primary_switch or app.vision.salvo_switch:
			finish(false, "Phone overwrote laptop yoke or switches"); return false
	if app.vision.throttle_confidence > .4:
		if absf(app.vision.throttle-.75) > .001:
			finish(false, "Laptop overwrote phone power"); return false
		if app.hud.camera_preview.texture != null and app.hud.throttle_preview.texture != null:
			var laptop: Color = app.hud.camera_preview.texture.get_image().get_pixel(0,0)
			var phone: Color = app.hud.throttle_preview.texture.get_image().get_pixel(0,0)
			if laptop.r < .7 or phone.b < .7:
				finish(false, "Camera previews swapped"); return false
			if saw_loss:
				app.vision.enabled = false
				app.poll_camera_controls(dt)
				finish(not app.throttle_vision.enabled, "Independent controls, previews, phone outage/reconnect and shutdown")
			else: saw_live = true
	elif saw_live and elapsed > 2800 and app.hud.throttle_preview.texture == null:
		if not app.vision.tracking or absf(app.flight.throttle-.75) > .02 or app.hud.camera_preview.texture == null:
			finish(false, "Phone loss interrupted yoke, preview or held power"); return false
		saw_loss = true
	return false

func finish(success: bool, message: String) -> void:
	finished = true
	if child > 0 and OS.is_process_running(child): OS.kill(child)
	if success: print("DUAL CAMERA GAME PASS: " + message)
	else: push_error("DUAL CAMERA GAME FAIL: " + message)
	if app != null: app.queue_free()
	quit(0 if success else 1)
