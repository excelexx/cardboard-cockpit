extends SceneTree

var app: Node
var child := -1
var begun := 0
var stage := 0
var finished := false
var saw_preview := false
var captured := false
var held_position := Vector3.ZERO
var held_clock := 0.0
var visual := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Engine.max_fps = 60
	app = load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override", "alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.test_mode = true; app.audio.muted = true
	if not unit_checks(): return
	app.start_flight("combat", true)
	app.vision.enabled = false; app.vision.enabled = true
	visual = "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	var probe := TCPServer.new()
	if probe.listen(0, "127.0.0.1") != OK:
		finish(false, "Cannot reserve fixture port"); return
	var port := probe.get_local_port(); probe.stop()
	app.vision.endpoint = "ws://127.0.0.1:" + str(port)
	var directory := ProjectSettings.globalize_path("res://..").simplify_path()
	child = OS.create_process(directory.path_join(".venv/bin/python"), PackedStringArray([
		directory.path_join("vision/tests/yoke_recovery_fixture.py"), "--port", str(port), "--duration", "15"]))
	begun = Time.get_ticks_msec(); app.vision.retry_at = begun + 400
	if child <= 0: finish(false, "Could not start recovery fixture")

func check(condition: bool, message: String) -> bool:
	if not condition: finish(false, message)
	return condition

func unit_checks() -> bool:
	app.start_flight("combat", true)
	app.vision.enabled = true; app.vision.tracking = true
	app.vision.throttle_confidence = 0
	app._physics_process(.02)
	if not check(not app.yoke_recovery_visible(), "Throttle loss alone must not pause a visible yoke"): return false
	app.vision.tracking = false; app.vision.gun_trigger = true
	app.fire_guard = 0
	var position: Vector3 = app.flight.position
	var clock: float = app.combat.elapsed
	var flight_clock: float = app.flight.elapsed
	for i in range(60): app._physics_process(1.0/60.0)
	if not check(app.yoke_recovery_visible() and app.flight.position == position and app.combat.elapsed == clock and app.flight.elapsed == flight_clock, "Yoke loss freezes aircraft and combat clocks"): return false
	if not check(app.combat.rounds_fired == 0, "No weapons while recovering yoke"): return false
	if not check(app.world.visible, "The original flight world remains visible behind recovery"): return false
	# Input events are another firing path and must be blocked by the screen.
	app.test_mode = false
	var press := InputEventKey.new(); press.pressed = true; press.keycode = KEY_SPACE
	app._input(press)
	var click := InputEventMouseButton.new(); click.pressed = true; click.button_index = MOUSE_BUTTON_RIGHT
	app._input(click)
	app.test_mode = true
	if not check(app.combat.rounds_fired == 0, "Recovery screen blocks keyboard and mouse shooting"): return false
	app.vision.tracking = true
	for i in range(20): app._physics_process(1.0/60.0)
	if not check(app.flight.position == position, "Brief detection must not immediately resume flight"): return false
	app.vision.tracking = false; app._physics_process(.02)
	app.vision.tracking = true
	for i in range(20): app._physics_process(1.0/60.0)
	if not check(app.flight.position == position, "Another loss resets the recovery delay"): return false
	for i in range(12): app._physics_process(1.0/60.0)
	if not check(not app.yoke_recovery_visible() and app.flight.position != position, "Stable yoke automatically resumes the same flight"): return false
	app.mode = "paused"; app.resume_mode = "flight"
	position = app.flight.position
	for i in range(40): app._physics_process(1.0/60.0)
	if not check(app.mode == "paused" and app.flight.position == position, "Recovery must not cancel a manual pause"): return false
	app.mode = "rollout"; app.vision.tracking = false
	app._physics_process(.02)
	if not check(app.yoke_recovery_visible() and app.flight.position == position, "Rollout also pauses on lost yoke"): return false
	app.on_action("keyboard")
	if not check(not app.yoke_recovery_visible() and not app.vision.enabled, "Keyboard button provides an explicit exit"): return false
	app.mode = "flight"; app.vision.enabled = true; app.vision.yoke_enabled = false
	app._physics_process(.02)
	if not check(not app.yoke_recovery_visible() and app.flight.position != position, "Throttle-only mode remains playable without a yoke"): return false
	return true

func _process(delta: float) -> bool:
	if app == null or child <= 0 or finished: return false
	app.vision.poll(delta)
	app.vision_preview.poll(app.yoke_recovery_visible(), app.vision.endpoint)
	app._physics_process(delta)
	if Time.get_ticks_msec()-begun > 12000:
		finish(false, "Timed out at stage %d" % stage); return false
	if stage == 0 and app.vision.tracking and not app.yoke_recovery_visible():
		stage = 1
	elif stage == 1 and app.yoke_recovery_visible():
		held_position = app.flight.position; held_clock = app.combat.elapsed; stage = 2
	elif stage == 2:
		if app.yoke_recovery_visible():
			if not check(app.flight.position == held_position and app.combat.elapsed == held_clock, "Live socket loss must hold simulation still"): return false
			if app.vision_preview.texture != null:
				saw_preview = true
				if visual and not captured:
					captured = true; capture_review()
		else:
			finish(saw_preview and app.vision.tracking and app.flight.position != held_position, "Rendered tags -> camera loop -> live JPEG -> flight overlay recovery -> resumed flight")
	return false

func capture_review() -> void:
	await RenderingServer.frame_post_draw
	var destination := ProjectSettings.globalize_path("res://../build/yoke-recovery-review.png")
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	root.get_texture().get_image().save_png(destination)
	print("RECOVERY SCREEN: " + destination)

func finish(success: bool, message: String) -> void:
	finished = true
	if child > 0 and OS.is_process_running(child): OS.kill(child)
	if success: print("YOKE RECOVERY PASS: " + message)
	else: push_error("YOKE RECOVERY FAIL: " + message)
	if app != null:
		app.vision_preview.stop(); app.queue_free()
	quit(0 if success else 1)
