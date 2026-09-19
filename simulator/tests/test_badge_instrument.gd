extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true
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
	print("BADGE INSTRUMENT SNAPSHOT: PASS")
	app.queue_free();await process_frame;quit()
