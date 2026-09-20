extends SceneTree
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);push_error(label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	app.on_action("keyboard_play")
	check(app.tutorial.active and app.mission.cinematic,"Coaching starts inside the real SF mission")
	var at: Vector3=app.flight.position
	for i in range(60):app._physics_process(1.0/60);app.tutorial.tick(1.0/60)
	check(app.flight.position!=at and app.mission.clock>.9,"Instructor never freezes flight or the mission")
	var age: float=app.tutorial.age;app.mode="paused";app.tutorial.tick(2)
	check(app.tutorial.age==age,"Explicit pause freezes coaching timers")
	app.mode="flight";app.fire_guard=0
	app.vision.enabled=true;app.vision.tracking=true;app.vision.gun_trigger=true
	app.combat.primary_used=true;app.tutorial.show(2);app.tutorial.tick(4)
	check(app.tutorial.index==3,"Plasma activity advances to aim and release coaching")
	app.tutorial.tick(4)
	check(app.tutorial.index==3,"Release coaching waits while the gun tag is visible")
	app.vision.gun_trigger=false;app.combat.gun_firing_time=0;app.tutorial.tick(.1)
	check(app.tutorial.index==4,"Covering the gun tag completes release coaching")
	app.vision.enabled=false
	var fire:=InputEventKey.new();fire.physical_keycode=KEY_SPACE;fire.keycode=KEY_SPACE;fire.pressed=true
	Input.parse_input_event(fire);Input.flush_buffered_events()
	for i in range(60*40):
		app._physics_process(1.0/60);app.tutorial.tick(1.0/60)
		if app.combat.kills>=3:break
		if i%120==0:await process_frame
	fire=fire.duplicate();fire.pressed=false;Input.parse_input_event(fire);Input.flush_buffered_events()
	check(app.combat.kills>=3 and app.tutorial.handoff_done and app.tutorial.index==5,"Third real goose kill triggers instructor handoff")
	var score: int=app.combat.score;var time: float=app.mission.clock
	app.tutorial.tick(13)
	check(not app.tutorial.active and app.audio.radio.enabled,"Handoff ends coaching and restores radio")
	check(app.mode=="flight" and app.combat.score==score and app.mission.clock==time,"Handoff does not restart, finish or change the mission")
	app.flight.contact="crash";app.flight.roll=2;app.flight.pitch=-.7;app.begin_crash()
	check(app.mode=="flight" and app.flight.contact=="" and app.flight.roll==0 and app.flight.pitch==0,"Crash returns aircraft to neutral flight")
	check(app.flight.position.y-app.world.ground_height(app.flight.position.x,app.flight.position.z)>=199,"Recovery restores safe ground clearance")
	check(app.combat.score==score and app.combat.kills>=3 and app.mission.clock==time,"Recovery preserves score, targets cleared and mission progress")
	app.begin_landing();app.flight.contact="overrun";app.mode="rollout";app.recover_flight()
	check(app.mode=="rollout" and app.flight.contact=="landed" and not app.flight.airborne and app.flight.gear and app.flight.flaps==2,"Landing mishap settles onto the ground instead of respawning airborne")
	check(app.hud.context_coach().title.contains("LANDED"),"Persistent coach follows the planted rollout")
	app.on_action("keyboard_play");check(app.tutorial.active and not app.tutorial.handoff_done,"Replay restores opening coaching")
	app.on_action("guided");check(not app.tutorial.active,"Watch demo does not require tutorial interaction")
	print("IN-MISSION COACHING / RECOVERY: ",failures.size()," failures")
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
