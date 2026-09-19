extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.test_mode=true
	app.audio.muted=true
	app.vision.enabled=true
	app.on_action("fly")
	assert(not app.copilot,"Play must respect sticker control mode")
	app.start_flight("combat")
	app.mouse_yoke=true
	app.vision.tracking=true; app.vision.yoke=Vector2(.8,.5)
	app.vision.throttle_confidence=1; app.vision.throttle=.9
	app.flight.throttle=.2
	app._physics_process(.1)
	assert(app.control.x>0 and app.control.y>0,"Marker steering must not be overwritten by mouse position")
	assert(app.flight.throttle>.2,"Throttle marker changes engine power")
	app.take_manual_control(true)
	assert(not app.vision.enabled,"Keyboard override remains available")
	app.paper_test=true; app.vision.enabled=true
	app.start_flight("paper")
	app.vision.tracking=false
	var held_position: Vector3=app.flight.position
	app._physics_process(.1)
	assert(app.flight.position==held_position,"Single-card test holds aircraft when marker is lost")
	app.vision.tracking=true; app.vision.yoke=Vector2(.7,.4)
	app._physics_process(.1)
	assert(app.flight.position!=held_position and app.control.x>0,"Single-card steering resumes flight")
	app.on_action("restart")
	assert(app.vision.enabled and not app.copilot and app.flight.position.y>500,"Single-card restart preserves marker control and airborne test")
	# The chase camera must rotate with climbs/dives, not merely look up or
	# down from a fixed world-horizontal offset behind the aircraft.
	app.flight.position = Vector3(0,4000,0)
	app.cockpit = false
	app.flight.pitch = 0; app.flight.roll = 0; app.flight.heading = 0
	app.flight.wind = Vector3.ZERO
	app.camera_rig.reset()
	for _i in range(60): app.camera_rig.update(1.0/60)
	var level_angle: float = asin(-app.camera.basis.z.y)
	app.flight.pitch = deg_to_rad(20)
	for _i in range(30): app.camera_rig.update(1.0/60)
	var climb_angle: float = asin(-app.camera.basis.z.y)
	assert(absf((climb_angle-level_angle)-deg_to_rad(20))<deg_to_rad(1),"Camera follows the full climb angle within half a second")
	assert(app.camera.position.y<app.flight.position.y,"Climbing chase offset stays behind the pitched aircraft")
	app.flight.pitch = deg_to_rad(-20)
	for _i in range(30): app.camera_rig.update(1.0/60)
	var dive_angle: float = asin(-app.camera.basis.z.y)
	assert(absf((dive_angle-level_angle)-deg_to_rad(-20))<deg_to_rad(1),"Camera follows nose-down pitch as well as climbs")
	assert(app.camera.position.y>app.flight.position.y,"Diving chase offset stays behind the pitched aircraft")
	print("STICKER INPUT: PASS")
	app.queue_free(); await process_frame; quit()
