extends SceneTree
var failed:=false
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","sf");root.add_child(app)
	await process_frame;app.set_process(false);app.set_physics_process(false);app.audio.muted=true;app.on_action("guided")
	var boss_seen:=false;var beam_seen:=false;var max_missiles:=0
	for frame in range(60*151):
		app._physics_process(1.0/60.0)
		boss_seen=boss_seen or app.combat.boss_id>=0;beam_seen=beam_seen or app.combat.beam_active
		var missiles:=0
		for shot in app.combat.shots:
			if shot.kind=="missile":missiles+=1
		max_missiles=maxi(max_missiles,missiles)
		if app.mode=="results":break
		if frame%300==0:await process_frame
	print("SPECTRAL RUN time=",app.mission.clock," mode=",app.mode," phase=",app.mission.phase," kills=",app.combat.kills," boss=",boss_seen," defeated=",app.combat.boss_defeated," beam=",beam_seen," missiles=",app.combat.missiles_fired," simultaneous=",max_missiles," position=",app.flight.position)
	failed=app.mode!="results" or app.mission.clock>150 or not boss_seen or not beam_seen or max_missiles<4 or app.flight.contact!="landed" or app.flight.speed>0.1
	# Replay with no shooting must reach an honest timed outcome; it cannot award
	# a boss kill automatically merely to satisfy the presentation deadline.
	app.on_action("fly")
	for frame in range(60*151):
		app._physics_process(1.0/60)
		if app.mode=="results":break
		if frame%300==0:await process_frame
	print("NO FIRE RUN time=",app.mission.clock," success=",app.mission_success," boss=",app.combat.boss_defeated," shots=",app.combat.rounds_fired)
	failed=failed or app.mode!="results" or app.mission.clock>150 or app.mission_success or app.combat.boss_defeated or app.combat.rounds_fired!=0 or app.flight.contact!="landed" or app.flight.speed>0.1
	app.on_action("guided")
	failed=failed or not app.combat.shots.is_empty() or not app.combat.enemies.is_empty() or app.combat.visuals.sprite_pool.size()!=96
	app.queue_free();await process_frame;quit(1 if failed else 0)
