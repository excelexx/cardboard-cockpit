extends SceneTree
## Regression checks for modal controls, input takeover and checkpoint recovery.

var app: Node3D
var failures: Array[String] = []
var checks := 0
var settings_backup: PackedByteArray
var settings_existed := false

func _initialize() -> void:
	settings_existed = FileAccess.file_exists("user://settings.cfg")
	if settings_existed:
		settings_backup = FileAccess.get_file_as_bytes("user://settings.cfg")
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("INTERACTION FAIL: " + message)

func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: Key) -> void:
	key(code)
	key(code, false)

func run_tests() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_physics_process(false)
	app.audio.muted = true
	app.on_action("help")
	tap(KEY_ENTER)
	check(app.mode == "hangar", "Enter cannot advance the hangar behind help")
	app.mode = "hangar"
	var selected: int = app.selected
	tap(KEY_1 if selected != 0 else KEY_2)
	check(app.selected == selected, "Aircraft cannot change behind help")
	tap(KEY_ESCAPE)
	app.start_flight()
	app.on_action("help")
	tap(KEY_G)
	check(app.flight.gear, "Gear cannot change behind help")
	tap(KEY_H)
	check(not app.copilot, "Copilot cannot engage behind help")
	app.flight.elapsed = 12
	tap(KEY_R)
	check(app.flight.elapsed == 12, "Restart shortcut cannot reset behind help")
	tap(KEY_ESCAPE)
	app.start_flight()
	app.mouse_yoke = true
	key(KEY_LEFT)
	app._physics_process(0.1)
	key(KEY_LEFT, false)
	check(not app.mouse_yoke and app.control.x < 0, "Keyboard steering takes over from mouse yoke")
	app.start_flight()
	app.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.mode == "paused", "Switching away from the app pauses flight")
	app.start_flight()
	app.help_visible = true
	app.calibration_visible = true
	app.credits_visible = true
	app.start_flight()
	check(not app.help_visible and not app.calibration_visible and not app.credits_visible, "New flight clears stale overlays")
	app.help_visible = false
	app.calibration_visible = false
	app.credits_visible = false
	app.flight.position = Vector3(0, 180, -2001)
	app.flight.heading = PI
	app.flight.speed = 120
	app.flight.airborne = true
	app.flight.ever_airborne = true
	app.flight.airborne_time = 20
	app._physics_process(1.0 / 60.0)
	check(app.ring_index == 1, "Returning through a missed ring counts in either direction")
	app.start_flight()
	app.flight.position = Vector3(49.9, 3.05, 0)
	app.flight.heading = PI / 2.0
	app.flight.pitch = -0.035
	app.flight.vertical_speed = -4.0
	app.flight.speed = 65
	app.flight.airborne = true
	app.flight.ever_airborne = true
	app.flight.airborne_time = 20
	app._physics_process(0.1)
	check(app.flight.position.x > 50 and app.flight.contact == "crash", "Touchdown uses the final position, not the previous runway sample")
	if settings_existed:
		FileAccess.open("user://settings.cfg", FileAccess.WRITE).store_buffer(settings_backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("INTERACTION RESULT: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
