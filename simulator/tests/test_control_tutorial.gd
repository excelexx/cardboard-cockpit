extends SceneTree
const Tutorial = preload("res://systems/control_tutorial.gd")
const Badge=preload("res://systems/badge_link.gd")
class PracticeBadge extends Badge:
	var next_press:=0
	func poll()->void:
		connected=true;pressed=next_press;mask=next_press;released=0;next_press=0
const Vision = preload("res://systems/vision_client.gd")
var now := 1000
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func observe(lesson, v, count: int, picture: bool = true) -> void:
	for i in range(count):
		now += 33; v.sequence += 1; v.last_received = now
		lesson.tick(.033, v, picture, now)
func pass_step(lesson, v, expected: int) -> void:
	for i in range(200):
		observe(lesson, v, 1)
		if lesson.index > expected: break
	check(lesson.index == expected+1, "Step %d completes exactly once" % expected)
func calibration_result(v, state: String, elapsed: float, id: String = "") -> bool:
	return v.yoke_calibration.accept_packet(JSON.stringify({"request_id": v.yoke_calibration.request_id if id.is_empty() else id, "state": state, "elapsed": elapsed, "reason": "show_yoke"}).to_utf8_buffer(), now)
func run() -> void:
	var v = Vision.new(); v.enabled = true; v.connected = true
	v.tracking = true; v.yoke_confidence = 1; v.throttle_confidence = 1
	var lesson = Tutorial.new()
	v.yoke_calibration.start()
	check(lesson.calibrating and lesson.focus()=="yoke" and lesson.step()[0]=="calibrate", "Tutorial begins with upright yoke calibration and laptop preview")
	observe(lesson, v, 120)
	check(lesson.calibrating, "Rendering for three seconds cannot substitute for a tracker calibration")
	check(not calibration_result(v,"complete",3,"old-request"), "Prior session completion cannot calibrate this tutorial")
	check(not calibration_result(v,"complete",2.9), "Calibration completion needs the full three seconds")
	check(calibration_result(v,"holding",1.5), "Matching calibration progress is accepted")
	observe(lesson,v,1)
	check(lesson.calibrating and is_equal_approx(lesson.progress(),.5), "Countdown reflects actual tracker samples")
	observe(lesson,v,10)
	check(lesson.progress()==0 and lesson.calibrating, "Stale calibration progress cannot advance tutorial")
	calibration_result(v,"complete",3)
	observe(lesson,v,1,false)
	check(lesson.calibrating, "Completed calibration without a live camera cannot advance")
	for i in range(20):
		calibration_result(v,"complete",3)
		observe(lesson,v,1)
	check(not lesson.calibrating and lesson.index==0 and not v.yoke_calibration.active, "Fresh completion advances to first throttle check and closes calibration connection")
	v.throttle = 1
	observe(lesson, v, 100)
	check(lesson.index == 0, "Full throttle cannot skip the initial idle check")
	v.throttle = 0
	observe(lesson, v, 100, false)
	check(lesson.index == 0, "Controls without live camera cannot pass")
	lesson.retry(); lesson.age = 2; v.last_received = now
	for i in range(100): lesson.tick(.033, v, true, now)
	check(lesson.index == 0 and lesson.held_ms == 0, "One packet repeated across render frames cannot pass")
	pass_step(lesson, v, 0)
	v.throttle = 1; v.throttle_confidence = 0
	observe(lesson, v, 90)
	check(lesson.index == 1, "Held throttle value with missing markers cannot pass")
	v.throttle_confidence = 1; pass_step(lesson, v, 1)
	v.throttle = 0; pass_step(lesson, v, 2)
	check(lesson.step()[0]=="yoke_info" and Tutorial.STEPS.size()==8,"One short yoke overview replaces all six movement exercises and centering checks")
	v.yoke = Vector2.ZERO; v.yoke_yaw = 0
	observe(lesson, v, 90)
	check(lesson.index==3,"Overview remains visible long enough to read")
	pass_step(lesson,v,3)
	check(v.yoke==Vector2.ZERO and v.yoke_yaw==0,"Overview advances without moving the yoke in any direction")
	v.gun_trigger = true; pass_step(lesson, v, 4)
	v.gun_trigger = false; v.tracking = false
	observe(lesson, v, 90)
	check(lesson.index == 5, "Losing the whole yoke view cannot count as covering the gun tag")
	v.tracking = true; v.connected = false; observe(lesson, v, 90)
	check(lesson.index == 5, "Disconnect cannot count as covering the gun tag")
	v.connected = true; pass_step(lesson, v, 5)
	check(lesson.step()[0]=="gear" and not v.gun_trigger,"Exactly uncover then cover leads directly to button checks without another uncover")
	observe(lesson,v,200)
	check(lesson.index==6 and not lesson.passed,"Button checks never advance from time or camera packets")
	lesson.press("landing");check(not lesson.passed,"Wrong button cannot pass the gear check")
	lesson.press("gear");pass_step(lesson,v,6)
	lesson.press("gear");check(not lesson.passed,"Prior gear press cannot pass the landing check")
	lesson.press("landing");pass_step(lesson,v,7)
	check(lesson.complete() and not lesson.can_start, "Throttle checks, yoke overview and gun checks reach the automatic ready stage")
	v.gun_trigger=true;observe(lesson, v, 90)
	check(not lesson.can_start, "Exposed gun cannot start flight")
	v.gun_trigger = false; v.throttle = .9
	observe(lesson, v, 90)
	check(not lesson.can_start, "High power cannot start flight")
	v.throttle = 0; observe(lesson, v, 20)
	check(not lesson.can_start, "Ready pose must remain steady for one second")
	var ready_status: String = lesson.status
	for i in range(8): lesson.tick(.005, v, true, now+i*5)
	check(lesson.status == ready_status, "Render frames between camera packets cannot flash the ready message")
	observe(lesson, v, 20)
	check(lesson.can_start, "Steady idle, centred yoke and covered gun permit automatic flight")
	for i in range(8): lesson.tick(.005, v, true, now+i*5)
	check(lesson.status == ready_status and lesson.can_start, "Ready remains stable without a new packet")
	lesson.tick(.033, v, true, now+151)
	check(not lesson.can_start, "Stale tracker cancels automatic flight")
	observe(lesson, v, 40)
	var app = load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override", "alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	check(app.mode == "title" and not app.world.visible and not app.overlay_visible(), "Normal startup including mode flags opens only the main menu")
	app.on_action("camera")
	check(app.mode == "control_setup" and app.vision.enabled, "Set up cardboard enters the guided physical checks")
	var first_request: String = app.vision.yoke_calibration.request_id
	app.on_action("setup_retry")
	check(app.controls_lesson.calibrating and app.vision.yoke_calibration.request_id != first_request, "Retry restarts neutral calibration")
	app.on_action("setup_start")
	check(app.mode == "control_setup", "Unfinished checks cannot start flight")
	var position: Vector3 = app.flight.position
	app.vision.gun_trigger = true
	for i in range(90): app._physics_process(1.0/60)
	var press := InputEventKey.new(); press.pressed = true; press.keycode = KEY_SPACE
	app._input(press)
	check(app.flight.position == position and not app.combat.primary_used and not app.combat.beam_active and app.combat.shots.is_empty(), "Setup freezes flight and prevents plasma or automatic missile firing")
	app.controls_lesson.calibrating=false;app.controls_lesson.index=6;app.controls_lesson.retry()
	var gear: bool=app.flight.gear;var flaps: int=app.flight.flaps
	press.keycode=KEY_B;app._input(press)
	check(not app.controls_lesson.passed,"Keyboard landing cannot skip gear practice")
	press.keycode=KEY_A;app._input(press)
	check(app.controls_lesson.passed and app.flight.gear==gear and app.flight.flaps==flaps,"Keyboard A confirms gear practice without changing the aircraft")
	app.controls_lesson.index=7;app.controls_lesson.retry();press.keycode=KEY_B;app._input(press)
	check(app.controls_lesson.passed and not app.landing_started and app.mode=="control_setup","Keyboard B confirms landing practice without starting an approach")
	var practice_badge=PracticeBadge.new();app.badge=practice_badge
	app.controls_lesson.index=6;app.controls_lesson.retry();practice_badge.next_press=1;app._physics_process(.016)
	check(app.controls_lesson.passed and app.flight.gear==gear,"Badge A confirms gear practice without actuating gear")
	app.controls_lesson.index=7;app.controls_lesson.retry();practice_badge.next_press=2;app._physics_process(.016)
	check(app.controls_lesson.passed and not app.landing_started and app.flight.position==position,"Badge B confirms landing practice while flight stays paused")
	app.controls_lesson = lesson; app.vision = v
	var frame := Image.create(20,20,false,Image.FORMAT_RGB8)
	app.yoke_preview.texture = ImageTexture.create_from_image(frame)
	v.last_received = Time.get_ticks_msec(); lesson.last_sample = v.last_received
	app.update_control_setup(.016)
	check(app.mode == "control_setup", "A laptop image cannot substitute for the missing phone at ready")
	app.throttle_preview.texture = ImageTexture.create_from_image(frame)
	observe(lesson, v, 40); v.last_received = Time.get_ticks_msec(); lesson.last_sample = v.last_received
	app.update_control_setup(.016)
	check(app.mode == "flight" and app.flight_kind == "demo" and not app.copilot and app.flight.throttle == 0, "Completed checks enter the shared judge demo at idle")
	check(not app.flight.airborne and app.flight.speed == 0, "The shared demo starts on the runway")
	app.on_action("camera")
	check(app.mode == "control_setup", "C/setup can retest controls during a flight")
	press.keycode = KEY_ESCAPE; app._input(press)
	check(app.mode == "flight" and not app.vision.yoke_calibration.active, "Escape restores the interrupted flight and cancels calibration")
	app.on_action("title");app.vision.enabled=false;app.on_action("keyboard_play")
	check(app.mode == "flight" and app.flight_kind == "demo", "Keyboard Play retains the existing route without camera setup")
	app.on_action("title");app.vision.enabled=true;app.on_action("training")
	check(app.mode == "control_setup" and app.controls_lesson.calibrating, "Legacy Tutorial entry starts the same camera calibration")
	app.on_action("setup_cancel");app.on_action("fly")
	check(app.mode == "control_setup", "Camera Play also teaches physical controls first")
	app.on_action("setup_keyboard")
	check(app.mode == "flight" and not app.vision.enabled and app.flight_kind == "demo", "Explicit keyboard choice bypasses camera requirements")
	app.route_id="sf"
	for entry: String in ["fly","enter","badge_start","camera","training"]:
		app.on_action("title")
		if entry=="enter":
			var start_key:=InputEventKey.new();start_key.pressed=true;start_key.keycode=KEY_ENTER;app._input(start_key)
		elif entry=="badge_start":practice_badge.next_press=1<<8;app._physics_process(.016)
		else:app.on_action(entry)
		var quick: bool=entry in ["fly","enter","badge_start"]
		check(app.mode=="control_setup" and app.controls_lesson.calibration_only==quick,"Entry %s chooses the intended calibration/tutorial flow" % entry)
		v.connected=true;v.tracking=true;v.throttle_confidence=1;v.yoke_confidence=1
		var current=app.controls_lesson
		for frame_index in range(20):calibration_result(v,"complete",3);observe(current,v,1)
		if quick:
			check(current.complete() and not current.can_start,"Start completes calibration without requiring throttle, gun or badge exercises")
			v.throttle=1;observe(current,v,40);check(not current.can_start,"Quick Start still requires idle throttle before takeoff")
			v.throttle=0;v.gun_trigger=false;v.tracking=true;v.yoke=Vector2.ZERO;v.yoke_yaw=0
			observe(current,v,40);v.last_received=Time.get_ticks_msec();app.finish_control_setup()
			check(app.mode=="flight" and not app.tutorial.active,"Quick Start launches without the introductory tutorial")
		else:
			check(not current.complete() and current.index==0 and current.step()[0]=="idle","Cardboard and legacy Tutorial continue to the first throttle exercise")
	app.start_flight("demo");app.vision.enabled=true;v.connected=true;v.tracking=true;v.yoke=Vector2.ZERO;v.yoke_yaw=0;v.throttle=0;v.throttle_confidence=1
	app.badge_launch_remaining=3.0
	check(app.flight.speed==0 and app.flight.engine==0 and app.flight.throttle==0,"SF flight starts fully stopped at zero power")
	var start_position: Vector3=app.flight.position
	for idle_frame in range(360):app._physics_process(1.0/60)
	check(app.flight.speed==0 and app.flight.position.distance_to(start_position)<.01,"Idle remains stopped through the launch countdown and afterward")
	app.queue_free(); await process_frame
	print("CONTROL TUTORIAL: ", checks, " checks / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
