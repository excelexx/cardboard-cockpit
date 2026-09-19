extends SceneTree
## End-to-end keyboard regression. Run:
## godot --headless --fixed-fps 60 --path simulator --script res://tests/test_keyboard_mission.gd
## The controller requests only real key events. It never steps the flight model
## directly or enables the copilot. The existing pilot is used as a target oracle;
## its throttle/gear/flap writes are restored before those targets are translated
## into W/S, G, and F key presses. Weather/mission selections use the HUD signals.

var app: Node3D
var held: Dictionary = {}
var pulse_error: Vector2 = Vector2.ZERO
var key_presses: Dictionary = {}
var failures: Array[String] = []
var last_ring: int = 0
var settings_existed: bool = false
var settings_backup: PackedByteArray
var finished: bool = false
var mission_frames: int = 0
var mission_plane: int = 3
var rollout_seen := false
var rollout_pause_checked := false


func _initialize() -> void:
	Engine.max_fps = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mission-plane="):
			mission_plane = clampi(argument.trim_prefix("--mission-plane=").to_int(), 0, 5)
	settings_existed = FileAccess.file_exists("user://settings.cfg")
	if settings_existed:
		settings_backup = FileAccess.get_file_as_bytes("user://settings.cfg")
	call_deferred("run_test")


func key(code: Key, pressed: bool) -> void:
	if bool(held.get(code, false)) == pressed:
		return
	held[code] = pressed
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	if pressed:
		key_presses[code] = int(key_presses.get(code, 0)) + 1


func tap(code: Key) -> void:
	key(code, true)
	key(code, false)


func release_all() -> void:
	for code in held.keys():
		key(code as Key, false)


func check(condition: bool, message: String) -> void:
	if condition:
		print("KEYBOARD CHECK PASS: ", message)
	else:
		failures.append(message)
		push_error("KEYBOARD CHECK FAIL: " + message)


func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func run_test() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	app = scene.instantiate() as Node3D
	root.add_child(app)
	await process_frame
	app.audio.muted = true
	check(app.mode == "hangar", "Application starts in the hangar")
	tap(KEY_4)
	check(app.selected == 3, "Number 4 selects the Boeing 737")
	# Invoke the same published action signals as the briefing buttons. Keeping
	# these checks independent of rendering also exercises them in headless CI.
	for weather: String in ["clear", "overcast", "golden"]:
		app.hud.action.emit("weather_" + weather)
		check(app.conditions == weather and app.world._condition_id == weather, "HUD weather selection reaches the world: " + weather)
		var saved := ConfigFile.new()
		check(saved.load("user://settings.cfg") == OK and str(saved.get_value("world", "conditions", "")) == weather, "Weather preference is saved: " + weather)
	app.hud.action.emit("kind_approach")
	check(app.flight_kind == "approach" and app.flight_kind_label() == "LANDING PRACTICE", "HUD landing-practice selection reaches mission routing")
	tap(KEY_ENTER)
	tap(KEY_ENTER)
	check(app.mode == "flight" and app.flight.airborne and app.flight.ever_airborne and app.ring_index == 5, "Landing practice starts airborne with route checkpoints skipped")
	check(app.flight.gear and app.flight.flaps == 2 and app.flight.speed > app.flight.effective_rotation_speed(), "Landing practice starts with gear, approach flaps, and flying airspeed")
	check(app.flight.position.is_equal_approx(Vector3(0,155,-11200)), "Landing practice starts lined up before North Field")
	check(app.approach_data() == ApproachGuidance.solution(app.flight.position), "HUD/controller approach data uses the shared guidance solution")
	for ring in app.ring_nodes:
		check(not ring.visible, "Landing practice hides valley checkpoint geometry")
	tap(KEY_R)
	check(app.flight.airborne and app.flight.flaps == 2 and app.ring_index == 5, "R restarts the selected landing-practice mission")
	app.hud.action.emit("hangar")
	app.hud.action.emit("kind_free")
	check(app.flight_kind == "free" and app.flight_kind_label() == "FREE FLIGHT", "HUD free-flight selection reaches mission routing")
	tap(KEY_ENTER)
	tap(KEY_ENTER)
	check(app.mode == "flight" and not app.flight.airborne and app.flight.position == Vector3(0,3,1100), "Free flight starts ready for runway departure")
	check(app.ring_index == 0 and app.flight.flaps == 0 and app.flight.speed == 0.0, "Free flight clears landing-practice progress and flap state")
	for ring in app.ring_nodes:
		check(not ring.visible, "Free flight hides valley checkpoint geometry")
	app.hud.action.emit("hangar")
	app.hud.action.emit("kind_valley")
	check(app.flight_kind == "valley", "HUD valley selection restores the five-checkpoint mission")
	tap(KEY_ENTER)
	check(app.mode == "briefing", "Enter opens the mission briefing")
	tap(KEY_ESCAPE)
	check(app.mode == "hangar", "Escape returns from briefing to hangar")
	tap(KEY_ENTER)
	tap(KEY_ENTER)
	check(app.mode == "flight", "Second Enter starts departure")

	var initial_hud: bool = app.expanded_hud
	tap(KEY_F2)
	check(app.expanded_hud != initial_hud, "F2 toggles expanded flight instruments")
	tap(KEY_F2)
	check(app.expanded_hud == initial_hud, "F2 restores the prior instrument view")
	for detent in [1, 2, 0]:
		tap(KEY_F)
		check(app.flight.flaps == detent, "F cycles flap detent to " + str(detent))
	app.set_camera_view("cockpit")
	tap(KEY_V)
	check(app.camera_view == "chase" and not app.cockpit, "V advances from cockpit to chase view")
	for expected: String in ["tail", "top", "left", "right", "front", "cockpit"]:
		tap(KEY_V)
		check(app.camera_view == expected, "V cycles through camera view: " + expected)
	check(app.cockpit, "The complete view cycle restores cockpit instruments")
	var first_spectator: bool = app.spectator
	tap(KEY_TAB)
	check(app.spectator != first_spectator, "Tab toggles spectator HUD")
	tap(KEY_TAB)
	tap(KEY_B)
	check(app.mouse_yoke, "B enables mouse yoke")
	tap(KEY_B)
	check(not app.mouse_yoke, "B restores keyboard yoke")

	tap(KEY_F1)
	check(app.help_visible, "F1 opens controls")
	var elapsed_before: float = app.flight.elapsed
	await frames(8)
	check(is_equal_approx(app.flight.elapsed, elapsed_before), "Help pauses flight simulation")
	tap(KEY_ESCAPE)
	check(not app.help_visible, "Escape closes controls")
	tap(KEY_C)
	check(app.calibration_visible, "C opens calibration")
	tap(KEY_ESCAPE)
	check(not app.calibration_visible, "Escape closes calibration")
	tap(KEY_ESCAPE)
	check(app.mode == "paused", "Escape pauses flight")
	tap(KEY_F)
	check(app.flight.flaps == 0, "Paused flight does not accept flap commands")
	elapsed_before = app.flight.elapsed
	await frames(8)
	check(is_equal_approx(app.flight.elapsed, elapsed_before), "Paused flight does not advance")
	tap(KEY_ESCAPE)
	check(app.mode == "flight", "Escape resumes flight")

	key(KEY_W, true)
	await frames(60)
	key(KEY_W, false)
	check(app.flight.throttle > 0.10, "Holding physical W increases throttle")
	var throttle_before: float = app.flight.throttle
	key(KEY_S, true)
	await frames(15)
	key(KEY_S, false)
	check(app.flight.throttle < throttle_before, "Holding physical S decreases throttle")
	key(KEY_UP, true)
	await frames(8)
	key(KEY_UP, false)
	check(app.control.y > 0.5, "Physical Up reaches pitch input")
	key(KEY_DOWN, true)
	await frames(16)
	key(KEY_DOWN, false)
	check(app.control.y < -0.5, "Physical Down reaches pitch input")
	key(KEY_LEFT, true)
	await frames(8)
	key(KEY_LEFT, false)
	check(app.control.x < -0.5, "Physical Left reaches roll input")
	key(KEY_RIGHT, true)
	await frames(16)
	key(KEY_RIGHT, false)
	check(app.control.x > 0.5, "Physical Right reaches roll input")
	key(KEY_A, true)
	await frames(8)
	key(KEY_A, false)
	check(app.control.z < -0.5, "Physical A reaches rudder input")
	key(KEY_D, true)
	await frames(16)
	key(KEY_D, false)
	check(app.control.z > 0.5, "Physical D reaches rudder input")
	var speed_before_braking: float = app.flight.speed
	key(KEY_SPACE, true)
	await frames(15)
	key(KEY_SPACE, false)
	check(speed_before_braking > 0.0 and app.flight.speed < speed_before_braking, "Holding Space brakes the rolling aircraft")
	tap(KEY_G)
	check(not app.flight.gear, "G retracts landing gear")
	tap(KEY_G)
	check(app.flight.gear, "G extends landing gear")
	tap(KEY_R)
	check(app.mode == "flight" and app.flight.speed == 0.0 and app.flight.throttle == 0.0 and app.flight.position == Vector3(0, 3, 1100), "R resets the runway departure")
	check(not app.copilot and not app.used_copilot, "Copilot remains off during input checks")
	if not failures.is_empty():
		finish(false)
		return

	app.select_plane(mission_plane)
	app.start_flight()
	print("KEYBOARD MISSION: ", app.profile().name, ", all controls injected as physical key events")
	while app.mode in ["flight", "rollout"] and app.flight.elapsed < 400.0:
		await physics_frame
		if app.mode not in ["flight", "rollout"]:
			break
		mission_frames += 1
		if app.copilot or app.used_copilot:
			failures.append("Copilot unexpectedly enabled during keyboard mission")
			break
		if app.mode == "rollout":
			if not rollout_seen:
				release_all()
			rollout_seen = true
			if not rollout_pause_checked:
				rollout_pause_checked = true
				var rollout_position: Vector3 = app.flight.position
				var rollout_time: float = app.flight.rollout_elapsed
				tap(KEY_ESCAPE)
				check(app.mode == "paused" and app.resume_mode == "rollout", "Escape pauses rollout with its own resume phase")
				await frames(8)
				check(app.flight.position == rollout_position and app.flight.rollout_elapsed == rollout_time, "Pause freezes wheel rollout")
				tap(KEY_ESCAPE)
				check(app.mode == "rollout", "Escape resumes rollout without re-entering flight")
			key(KEY_SPACE, true)
			continue
		var actual_throttle: float = app.flight.throttle
		var actual_gear: bool = app.flight.gear
		var actual_flaps: int = app.flight.flaps
		var wanted: Vector3 = app.pilot_controls()
		var wanted_throttle: float = app.flight.throttle
		var wanted_gear: bool = app.flight.gear
		var wanted_flaps: int = app.flight.flaps
		# Restore the oracle's side effects. Production input code must perform
		# every real throttle change and gear transition from keyboard events.
		app.flight.throttle = actual_throttle
		app.flight.gear = actual_gear
		app.flight.flaps = actual_flaps
		var roll_pulse: int = pulse(wanted.x, 0)
		var pitch_pulse: int = pulse(wanted.y, 1)
		key(KEY_RIGHT, roll_pulse > 0)
		key(KEY_LEFT, roll_pulse < 0)
		key(KEY_UP, pitch_pulse > 0)
		key(KEY_DOWN, pitch_pulse < 0)
		key(KEY_W, wanted_throttle - actual_throttle > 0.004)
		key(KEY_S, wanted_throttle - actual_throttle < -0.004)
		if wanted_gear != actual_gear:
			tap(KEY_G)
		for _detent in range(posmod(wanted_flaps - actual_flaps, 3)):
			tap(KEY_F)
		if app.ring_index != last_ring:
			last_ring = app.ring_index
			print("KEYBOARD CHECKPOINT ", last_ring, " t=", snappedf(app.flight.elapsed, 0.01), " position=", app.flight.position)
		if mission_frames % 1200 == 0:
			print("KEYBOARD STATUS t=", snappedf(app.flight.elapsed, 0.01), " rings=", app.ring_index, " position=", app.flight.position, " speed=", snappedf(app.flight.speed, 0.01))
	release_all()
	check(app.mission_success and app.ring_index == 5 and app.flight.contact == "landed", "Keyboard departure, all five rings, and North Field landing")
	check(rollout_seen and app.flight.rollout_elapsed > 0.0 and app.flight.speed == 0.0, "Keyboard mission brakes through rollout to a complete stop")
	check(app.is_on_runway(app.flight.position), "Successful mission stops entirely within the runway")
	check(not app.copilot and not app.used_copilot, "Copilot stayed off for the entire mission")
	check(int(key_presses.get(KEY_W, 0)) > 0 and int(key_presses.get(KEY_S, 0)) > 0 and int(key_presses.get(KEY_G, 0)) >= 4, "Throttle and gear changes used actual W/S/G events")
	check(int(key_presses.get(KEY_F, 0)) >= 6 and int(key_presses.get(KEY_SPACE, 0)) >= 2, "Flap transitions and rollout brakes used actual F/Space events")
	print("KEYBOARD RESULT: ", "PASS" if failures.is_empty() else "FAIL", " rings=", app.ring_index, " time=", app.flight.elapsed, " position=", app.flight.position, " speed=", app.flight.touchdown_speed, " sink=", app.flight.touchdown_sink, " contact=", app.flight.contact, " copilot=", app.copilot)
	if app.mode == "results":
		tap(KEY_ENTER)
		check(app.mode == "flight" and app.ring_index == 0 and app.flight.contact == "" and app.flight.speed == 0.0, "Enter restarts from results")
	finish(failures.is_empty())


func pulse(value: float, axis: int) -> int:
	# Error diffusion sends {-1,0,+1} keys whose long-run mean is the requested
	# analog command. The application's normal keyboard smoothing still applies.
	pulse_error[axis] += clampf(value, -1.0, 1.0)
	if pulse_error[axis] >= 0.5:
		pulse_error[axis] -= 1.0
		return 1
	if pulse_error[axis] <= -0.5:
		pulse_error[axis] += 1.0
		return -1
	return 0


func finish(success: bool) -> void:
	if finished:
		return
	finished = true
	release_all()
	if settings_existed:
		var file: FileAccess = FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		if file:
			file.store_buffer(settings_backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	if not failures.is_empty():
		print("KEYBOARD FAILURES: ", failures)
	if is_instance_valid(app):
		app.queue_free()
	await process_frame
	quit(0 if success else 1)
