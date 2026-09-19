extends SceneTree

# Real rendered ArUco images -> Python camera loop -> WebSocket -> game physics.
# The fixture forbids opening a physical camera.
var app: Node
var child: int = -1
var begun: int
var verified := false

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
	app.flight.throttle = .2; app.flight.engine = .2; app.copilot = true
	var probe := TCPServer.new()
	if probe.listen(0, "127.0.0.1") != OK:
		finish(false, "Cannot reserve fixture port")
		return
	var port: int = probe.get_local_port()
	probe.stop()
	app.vision.endpoint = "ws://127.0.0.1:" + str(port)
	app.vision.enabled = true
	var directory: String = ProjectSettings.globalize_path("res://..").simplify_path()
	child = OS.create_process(directory.path_join(".venv/bin/python"), PackedStringArray([
		directory.path_join("vision/tests/throttle_fixture.py"), "--port", str(port), "--duration", "15"]))
	begun = Time.get_ticks_msec()
	app.vision.retry_at = begun + 400
	if child <= 0: finish(false, "Could not start marker fixture")

func _process(delta: float) -> bool:
	if app == null or child <= 0 or verified: return false
	app.vision.poll(delta)
	app._physics_process(delta)
	if Time.get_ticks_msec() - begun > 12000:
		finish(false, "Timed out waiting for 75% marker input to reach engine")
	elif app.vision.throttle_confidence>.4 and absf(app.flight.throttle-.75)<.015 and app.flight.engine>.55:
		finish(not app.copilot and not app.vision.tracking, "75% slider controls actual throttle and engine without a yoke")
	return false

func finish(success: bool, message: String) -> void:
	verified = true
	if child>0 and OS.is_process_running(child): OS.kill(child)
	if success: print("RELATIVE THROTTLE GAME PASS: " + message)
	else: push_error("RELATIVE THROTTLE GAME FAIL: " + message)
	if app != null: app.queue_free()
	quit(0 if success else 1)
