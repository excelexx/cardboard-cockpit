extends SceneTree

var app: Node
var child := -1
var port := 0
var probe := WebSocketPeer.new()
var packet: Dictionary = {}
var probe_retry := 0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func start_tracker() -> void:
	var repo: String = ProjectSettings.globalize_path("res://..").simplify_path()
	child = OS.create_process(repo.path_join(".venv/bin/python"),PackedStringArray([repo.path_join("vision/tests/sensitivity_fixture.py"),"--port",str(port),"--duration","45"]))

func tick() -> void:
	app.vision.poll(.01)
	if probe.get_ready_state()==WebSocketPeer.STATE_CLOSED and Time.get_ticks_msec()>=probe_retry:
		probe = WebSocketPeer.new(); probe.connect_to_url(app.vision.endpoint)
		probe_retry = Time.get_ticks_msec()+250
	probe.poll()
	while probe.get_available_packet_count()>0:
		var data: Variant = JSON.parse_string(probe.get_packet().get_string_from_utf8())
		if data is Dictionary: packet = data
	await create_timer(.01).timeout

func wait_for_settings() -> bool:
	var end := Time.get_ticks_msec()+6000
	while Time.get_ticks_msec()<end:
		await tick()
		if app.vision.tracking and app.vision.tracker_settings.synced(app.vision.sensitivity_values()) and packet.get("sensitivity") == app.vision.sensitivity_values(): return true
	check(false,"Live camera settings must reach Python and return to the game: tracking=%s, applied=%s, packet=%s" % [app.vision.tracking,app.vision.tracker_settings.applied,packet])
	return false

func aircraft_rates() -> Vector3:
	app.settings_visible = false; app.mode = "flight"; app.control = Vector3.ZERO
	app.flight.reset(app.profile()); app.flight.spawn_airborne(Vector3(0,3000,0),160)
	app._physics_process(1.0/60)
	app.settings_visible = true
	return Vector3(app.flight.roll_velocity,app.flight.pitch_velocity,app.flight.yaw_velocity)

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	app.test_mode = true; app.combat.active = false; app.mission.active = false
	var server := TCPServer.new(); server.listen(0,"127.0.0.1"); port = server.get_local_port(); server.stop()
	app.vision.endpoint = "ws://127.0.0.1:"+str(port)
	app.vision.enabled = true
	start_tracker()
	await create_timer(.5).timeout
	probe.connect_to_url(app.vision.endpoint)
	app.settings_visible = true; app.hud.update_sensitivity_sliders()
	for axis: String in ["pitch","bank","yaw"]: app.hud.sensitivity_sliders[axis].value = .5
	if await wait_for_settings():
		# Let the physical filter settle before comparing the same stationary pose.
		for i in range(50): await tick()
		var raw: Dictionary = packet.raw_yoke.duplicate()
		var slow := aircraft_rates()
		for axis: String in ["pitch","bank","yaw"]:
			# Two edits before a poll exercise coalescing of a real slider drag.
			app.hud.sensitivity_sliders[axis].value = 1.0
			app.hud.sensitivity_sliders[axis].value = 1.5
		check(app.vision.steering().is_equal_approx(Vector3(raw.roll,raw.pitch,raw.yaw)*1.5),"The game responds before the settings round trip")
		if await wait_for_settings():
			var fast := aircraft_rates()
			var output: Vector3 = app.vision.steering()
			for index: int in range(3):
				var axis: String = ["roll","pitch","yaw"][index]
				check(absf(raw[axis])>.08,"Fixed rendered pose exercises "+axis)
				check(is_equal_approx(packet.raw_yoke[axis],raw[axis]),"Sensitivity preserves physical calibration: "+axis)
				check(is_equal_approx(packet.yoke[axis],raw[axis]*1.5),"Python preview and transmitted output use the slider: "+axis)
				check(is_equal_approx(output[index],packet.yoke[axis]),"Game and Python agree without double gain: "+axis)
				check(absf(fast[index])>absf(slow[index])*2.7,"Changing the slider changes actual aircraft angular speed: "+axis)
		# A tracker restart resets its gains. The game must restore them automatically.
		OS.kill(child)
		for i in range(50): await tick()
		app.hud.sensitivity_sliders.pitch.value = .8
		app.hud.sensitivity_sliders.bank.value = 1.1
		app.hud.sensitivity_sliders.yaw.value = 1.7
		start_tracker(); await create_timer(.5).timeout
		probe = WebSocketPeer.new(); packet = {}; probe.connect_to_url(app.vision.endpoint)
		check(await wait_for_settings(),"Reconnect restores latest independent values after an offline edit")
	if child>0 and OS.is_process_running(child): OS.kill(child)
	app.vision.enabled = false; probe.close(); app.queue_free(); await process_frame
	print("LIVE SENSITIVITY: ",checks," checks / ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
