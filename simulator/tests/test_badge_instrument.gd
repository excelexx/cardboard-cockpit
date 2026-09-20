extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	assert(not app.badge._open,"Headless tests must never transmit to physical hardware")
	var s: Dictionary=app.badge.instrument_snapshot(app)
	assert(s.mode==0 and s.name=="PILOT" and s.pilot==1)
	app.on_action("next_pilot");s=app.badge.instrument_snapshot(app);assert(s.pilot==2 and app.mode=="title")
	app.on_action("fly");app.flight.spawn_airborne(Vector3(0,500,0),200);app.flight.roll=.5;app.flight.pitch=.1
	app.combat.spawn_contact();app.combat.target_id=app.combat.enemies[0].id;app.combat.lock_progress=1
	s=app.badge.instrument_snapshot(app)
	assert(s.mode==1 and s.contacts.size()==1 and s.flags&1 and s.roll>28 and s.pitch>5 and s.speed>380)
	app.mode="results";app.mission_success=false;app.flight.contact="landed";app.flight.speed=0;app.combat.score=1200
	s=app.badge.instrument_snapshot(app);assert(s.mode==2 and not s.flags&64 and s.landing==1 and s.score==1200)
	app.mission_success=true;s=app.badge.instrument_snapshot(app);assert(s.flags&64)
	app.mode="flight";app.badge_launch_remaining=2.6
	s=app.badge.instrument_snapshot(app);assert((s.detail>>5)&3==1)
	app.badge_launch_remaining=1.4;s=app.badge.instrument_snapshot(app);assert((s.detail>>5)&3==2)
	var position_before: Vector3=app.flight.position
	var clock_before: float=app.mission.clock
	app._physics_process(.2);assert(app.flight.position==position_before and app.mission.clock==clock_before and app.badge_launch_remaining<1.4)
	var old_count: int=app.combat.enemies.size()
	for i in range(15):app.combat.enemies.append({"id":1000+i,"health":1,"position":app.flight.position+Vector3(i*10,0,-1000),"kind":"goose"})
	app.combat.shots.append({"kind":"hostile_missile","position":app.flight.position+Vector3(-200,0,-400)})
	s=app.badge.instrument_snapshot(app);assert(s.contacts.size()==12 and s.contacts[0].kind==4)
	app.combat.enemies.resize(old_count);app.combat.shots.clear()
	app.badge_launch_remaining=0;app.badge.connected=true;app.badge.mask=1<<3
	app.badge.presentation_tick(app,.7);assert(app.badge.tactical and not app.badge.hud_toggle)
	app.badge.mask=0;app.badge.released=1<<3;app.badge.presentation_tick(app,.01);assert(not app.badge.hud_toggle)
	s=app.badge.instrument_snapshot(app);assert(s.detail&16)
	app.badge.mask=1<<3;app.badge.released=0;app.badge.presentation_tick(app,.1)
	app.badge.mask=0;app.badge.released=1<<3;app.badge.presentation_tick(app,.01);assert(app.badge.hud_toggle)
	app.badge.reset_presentation();assert(not app.badge.tactical)
	app.mode="crashed";s=app.badge.instrument_snapshot(app);assert(s.mode==1 and s.landing==3)
	app.mode="ejected";s=app.badge.instrument_snapshot(app);assert(s.mode==1 and s.landing==4)
	print("BADGE INSTRUMENT SNAPSHOT: PASS")
	app.queue_free();await process_frame;quit()
