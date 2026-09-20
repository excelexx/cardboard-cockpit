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
	app.start_flight("combat", true)
	app.mouse_yoke=true
	app.vision.tracking=true; app.vision.yoke=Vector2(.8,.5)
	app.vision.throttle_confidence=1; app.vision.throttle=.9
	app.flight.throttle=.2
	app._physics_process(.1)
	assert(app.control.x>0 and app.control.y>0,"Marker steering must not be overwritten by mouse position")
	assert(app.flight.throttle>.2,"Throttle marker changes engine power")
	app.take_manual_control(true)
	assert(not app.vision.enabled,"Keyboard override remains available")
	app.vision.enabled=true; app.vision.tracking=false; app.vision.yoke_enabled=false
	app.vision.throttle_confidence=1; app.vision.throttle=.75
	app.copilot=true; app.flight.throttle=.2
	app.take_manual_control(true)
	assert(app.vision.enabled,"Keyboard steering preserves throttle-only tracking")
	app.copilot=true
	app._physics_process(.1)
	assert(not app.copilot and app.flight.throttle>.2,"Throttle alone takes power from automatic flight")
	app.take_manual_control(false)
	assert(not app.vision.enabled,"Power keys explicitly take over from camera throttle")
	app.paper_test=true; app.vision.enabled=true; app.vision.yoke_enabled=true
	app.start_flight("paper", true)
	app.vision.tracking=false
	var held_position: Vector3=app.flight.position
	app._physics_process(.1)
	assert(app.flight.position==held_position,"Single-card test holds aircraft when marker is lost")
	app.vision.tracking=true; app.vision.yoke=Vector2(.7,.4)
	for i in range(32): app._physics_process(1.0/60.0)
	assert(app.flight.position!=held_position and app.control.x>0,"Single-card steering resumes flight")
	app.flight.throttle=.5; app.vision.throttle=0; app.vision.throttle_confidence=1
	app._physics_process(.1)
	assert(app.flight.throttle<.5,"Relative throttle overrides paper-test automatic speed")
	var held_power: float=app.flight.throttle
	app.vision.throttle_confidence=0
	app._physics_process(.1)
	assert(is_equal_approx(app.flight.throttle,held_power),"Lost throttle holds power instead of restoring automatic speed")
	app.on_action("restart")
	assert(app.vision.enabled and not app.copilot and not app.flight.airborne and app.flight.speed==0 and app.is_on_runway(app.flight.position),"Single-card restart preserves marker control and starts stationary on the runway")
	assert(not app.paper_throttle_seen,"Restart clears paper throttle ownership")
	# Hold the exact game setting while markers are covered, then blend from
	# that held value rather than from a newer unseen tracker target.
	app.paper_test=false; app.start_flight("combat", true)
	app.vision.yoke_enabled=false; app.vision.tracking=false
	for pair: Vector2 in [Vector2(.2,.9), Vector2(.9,.2)]:
		app.flight.throttle=pair.x; app.vision.throttle_confidence=0; app.vision.throttle=pair.y
		for i in range(20): app._physics_process(1.0/60.0)
		assert(is_equal_approx(app.flight.throttle,pair.x),"Covered throttle freezes actual power")
		app.vision.throttle_confidence=1
		var previous: float=app.flight.throttle
		for i in range(120):
			app._physics_process(1.0/60.0)
			assert(absf(app.flight.throttle-previous)<=.8/60+.00001,"Reacquisition limits power change per frame")
			assert(absf(app.flight.throttle-pair.y)<=absf(previous-pair.y)+.00001,"Power approaches the new slider position without overshoot")
			previous=app.flight.throttle
		assert(absf(app.flight.throttle-pair.y)<.005,"Reacquired power reaches target smoothly")
	print("STICKER INPUT: PASS")
	app.queue_free(); await process_frame; quit()
