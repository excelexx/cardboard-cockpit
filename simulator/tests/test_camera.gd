extends SceneTree
## Native camera regression. Run with:
## godot --headless --path simulator --script res://tests/test_camera.gd
## An optional -- --flight --view=top --expect-startup=top also checks CLI routing.
## Frames are advanced manually after disabling flight processing, so camera
## checks cannot accidentally exercise or change the flight simulation.

const VIEWS: Array[String] = ["cockpit", "chase", "tail", "top", "left", "right", "front"]
const FLIGHT_FIELDS: Array[String] = ["position", "speed", "throttle", "engine", "pitch", "roll", "heading", "vertical_speed", "airborne", "ever_airborne", "gear", "elapsed", "airborne_time", "distance", "roughness", "contact", "touchdown_speed", "touchdown_sink", "touchdown_bank", "stall_time", "flaps", "rollout_elapsed", "touchdown_center"]
var app: Node3D
var failures: Array[String] = []
var checks: int = 0
var settings_existed: bool = false
var settings_backup: PackedByteArray

func _initialize() -> void:
	settings_existed = FileAccess.file_exists("user://settings.cfg")
	if settings_existed:
		settings_backup = FileAccess.get_file_as_bytes("user://settings.cfg")
	call_deferred("run_checks")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("CAMERA FAIL: " + message)

func key(code: Key, pressed: bool, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: Key, shift: bool = false) -> void:
	key(code, true, shift)
	key(code, false, shift)

func snapshot_flight() -> Dictionary:
	var state: Dictionary = {}
	for field in FLIGHT_FIELDS:
		state[field] = app.flight.get(field)
	state["control"] = app.control
	state["ring_index"] = app.ring_index
	state["copilot"] = app.copilot
	state["used_copilot"] = app.used_copilot
	return state

func run_checks() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	app = scene.instantiate() as Node3D
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.audio.muted = true
	await process_frame
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--expect-startup="):
			expect(app.camera_view == argument.trim_prefix("--expect-startup="), "CLI selects requested startup view")
	if "--only-startup" in OS.get_cmdline_user_args():
		expect(app.camera.transform.is_finite(), "Startup camera transform is finite")
		finish()
		return
	app.on_action("hangar")
	for index in range(5):
		tap((KEY_1 + index) as Key)
		expect(app.selected == index, "Hangar key %d still selects its aircraft" % (index + 1))
	var selected_before: int = app.selected
	tap(KEY_6)
	tap(KEY_7)
	expect(app.selected == selected_before, "Hangar ignores aircraft number keys outside the fleet")
	app.on_action("fly")
	await process_frame
	app.set_camera_view("cockpit")
	for expected_view in VIEWS.slice(1) + ["cockpit"]:
		tap(KEY_V)
		expect(app.camera_view == expected_view, "V cycles forward to " + expected_view)
	for expected_view in ["front", "right", "left", "top", "tail", "chase", "cockpit"]:
		tap(KEY_V, true)
		expect(app.camera_view == expected_view, "Shift+V cycles backward to " + expected_view)
	for flight_mode: String in ["flight", "rollout", "paused", "results"]:
		app.mode = flight_mode
		var initial_state := snapshot_flight()
		for index in range(VIEWS.size()):
			tap((KEY_1 + index) as Key)
			expect(app.camera_view == VIEWS[index], "%s: number %d selects %s" % [flight_mode, index + 1, VIEWS[index]])
			expect(app.selected == selected_before, flight_mode + ": selecting a view preserves selected aircraft")
		expect(snapshot_flight() == initial_state, flight_mode + ": switching views preserves complete flight state")
	app.mode = "flight"
	app.set_camera_view("cockpit")
	app.on_action("views")
	expect(app.camera_menu_open, "Camera selector opens through its HUD action")
	app.on_action("view_top")
	expect(app.camera_view == "top" and not app.camera_menu_open, "Camera selector chooses top-down and closes")
	app.on_action("views")
	tap(KEY_ESCAPE)
	expect(not app.camera_menu_open and app.mode == "flight", "Escape closes camera selector before pausing flight")
	for view in VIEWS:
		app.on_action("view_" + view)
		expect(app.camera_view == view and not app.camera_view_label().is_empty(), "Every selector action has a readable camera label: " + view)
	app.set_camera_view("not-a-view")
	expect(app.camera_view in VIEWS, "Invalid camera identifiers never leave the camera in an unknown state")

	# Real imported aircraft have markedly different spans and lengths. Exercise
	# each camera across level, climbing and banked poses before checking orbit.
	for plane_index in range(5):
		app.select_plane(plane_index)
		app.start_flight()
		await process_frame
		var id: String = str(app.profile().id)
		for pose: Vector3 in [Vector3.ZERO, Vector3(0.2, 0.73, 0.45), Vector3(-0.15, -2.3, -0.8)]:
			app.flight.position = Vector3(120, 600, -6000)
			app.flight.pitch = pose.x
			app.flight.heading = pose.y
			app.flight.roll = pose.z
			app.flight.airborne = true
			app.flight.speed = 150.0
			app.aircraft.position = app.flight.position
			app.aircraft.rotation = Vector3(pose.x, -pose.y, -pose.z)
			var original_flight := snapshot_flight()
			for view in VIEWS:
				app.set_camera_view(view)
				app.look = Vector2.ZERO
				app.update_camera(10.0)
				var label: String = "%s/%s pose %s" % [id, view, pose]
				expect(app.camera.transform.is_finite(), label + ": finite camera transform")
				expect(is_equal_approx(app.camera.basis.determinant(), 1.0), label + ": orthonormal camera rotation")
				expect(app.cockpit == (view == "cockpit") and app.cockpit_frame.visible == app.cockpit and app.aircraft.visible != app.cockpit, label + ": interior/exterior visibility follows view")
				if view == "cockpit":
					expect(app.camera.near < 0.1, label + ": near clipping retains cockpit detail")
				else:
					var toward_plane: Vector3 = (app.flight.position - app.camera.global_position).normalized()
					expect(toward_plane.dot(-app.camera.global_basis.z) > 0.80, label + ": camera aims toward aircraft")
					expect(not app.camera.is_position_behind(app.flight.position), label + ": aircraft is in front of camera")
					if pose == Vector3.ZERO:
						check_view_direction(view, label)
						check_model_framing(label)
				expect(snapshot_flight() == original_flight, label + ": camera movement leaves aircraft state unchanged")
				var base_transform: Transform3D = app.camera.transform
				app.look = Vector2(0.7, -0.35)
				app.update_camera(0.0)
				expect(app.camera.transform.is_finite(), label + ": look-around has no singularity")
				# Some tracking cameras interpolate their positions; give them time
				# to respond while holding the right mouse button during the orbit.
				var mouse := InputEventMouseButton.new()
				mouse.button_index = MOUSE_BUTTON_RIGHT
				mouse.pressed = true
				Input.parse_input_event(mouse)
				Input.flush_buffered_events()
				app.update_camera(1.0)
				if view == "top":
					expect(app.camera.transform.is_equal_approx(base_transform), label + ": top-down view remains vertically aligned during look-around")
				else:
					expect(not app.camera.transform.is_equal_approx(base_transform), label + ": right-mouse look changes framing")
				var release_mouse := mouse.duplicate() as InputEventMouseButton
				release_mouse.pressed = false
				Input.parse_input_event(release_mouse)
				Input.flush_buffered_events()
				app.set_camera_view(view)
				expect(app.look.is_zero_approx(), label + ": reselecting a view recenters look-around")
		print("CAMERA PLANE COMPLETE: ", id)
	finish()

func check_view_direction(view: String, label: String) -> void:
	var offset: Vector3 = app.camera.global_position - app.flight.position
	match view:
		"chase", "tail": expect(offset.z > 0.0, label + ": camera sits behind tail")
		"top": expect(offset.y > absf(offset.x) and offset.y > absf(offset.z) and -app.camera.global_basis.z.dot(Vector3.DOWN) > 0.95, label + ": top-down camera faces ground without degeneracy")
		"left": expect(offset.x < 0.0, label + ": camera sits on port side")
		"right": expect(offset.x > 0.0, label + ": camera sits on starboard side")
		"front": expect(offset.z < 0.0, label + ": camera faces aircraft from ahead")

func check_model_framing(label: String) -> void:
	var bounds: AABB = app.aircraft_visuals.model_bounds
	var viewport: Rect2 = app.camera.get_viewport().get_visible_rect()
	# Bounding-box corners include some empty space around swept wings. A small
	# margin accommodates that conservatism while catching badly cropped planes.
	var allowed: Rect2 = viewport.grow(viewport.size.x * 0.04)
	var contained := true
	for x in [bounds.position.x, bounds.end.x]:
		for y in [bounds.position.y, bounds.end.y]:
			for z in [bounds.position.z, bounds.end.z]:
				var point: Vector3 = app.aircraft.global_transform * Vector3(x, y, z)
				contained = contained and not app.camera.is_position_behind(point) and allowed.has_point(app.camera.unproject_position(point))
	expect(contained, label + ": the real aircraft bounds fit the viewport")

func finish() -> void:
	if settings_existed:
		var file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		if file:
			file.store_buffer(settings_backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("CAMERA RESULT: ", checks, " checks, ", failures.size(), " failures")
	if not failures.is_empty():
		print("CAMERA FAILURES: ", failures)
	if is_instance_valid(app):
		app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
