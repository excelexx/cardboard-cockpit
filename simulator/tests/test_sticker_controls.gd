extends SceneTree
var failures: Array[String]=[]
func check(ok: bool, message: String="Regression check failed") -> void:
	if not ok:failures.append(message);push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.test_mode=true
	app.audio.muted=true
	app.vision.enabled=true
	app.on_action("fly")
	check(not app.copilot,"Play must respect sticker control mode")
	app.start_flight("combat")
	app.mouse_yoke=true
	app.vision.tracking=true; app.vision.yoke=Vector2(.8,.5)
	app.vision.throttle_confidence=1; app.vision.throttle=.9
	app.flight.throttle=.2
	app._physics_process(.1)
	check(app.control.x>0 and app.control.y>0,"Marker steering must not be overwritten by mouse position")
	check(app.flight.throttle>.2,"Throttle marker changes engine power")
	app.take_manual_control(true)
	check(not app.vision.enabled,"Keyboard override remains available")
	app.paper_test=true; app.vision.enabled=true
	app.start_flight("paper")
	app.vision.tracking=false
	var held_position: Vector3=app.flight.position
	app._physics_process(.1)
	check(app.flight.position==held_position,"Single-card test holds aircraft when marker is lost")
	app.vision.tracking=true; app.vision.yoke=Vector2(.7,.4)
	for i in range(12):app._physics_process(.05)
	check(app.flight.position!=held_position and app.control.x>0,"Single-card steering resumes flight")
	app.on_action("restart")
	check(app.vision.enabled and not app.copilot and app.flight.position.y>500,"Single-card restart preserves marker control and airborne test")
	print("STICKER INPUT: PASS")
	app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
