extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","sf");root.add_child(app)
	await process_frame;app.set_process(false);app.set_physics_process(false);app.audio.muted=true;app.on_action("guided")
	var next:=64.0
	for frame in range(60*130):
		app._physics_process(1.0/60.0)
		var m=app.mission
		if m.clock>=next and m.phase in ["skein","aftermath"]:
			next+=2.0
			var centre:=Vector3.ZERO;var alive:=0
			for e in app.combat.enemies:
				if e.health>0 and m.skein_has(int(e.id)):centre+=e.position;alive+=1
			var d:=-1.0
			if alive>0:
				centre/=float(alive)
				d=centre.distance_to(app.flight.position)
			print("t=%5.1f ph=%s alive=%2d down=%2d rng=%7.1f spd=%5.1f hdg=%6.1f tgt=%3d lock=%.2f kills=%d" % [m.clock,m.phase,alive,m.skein_down,d,app.flight.speed,rad_to_deg(app.flight.heading),app.combat.target_id,app.combat.lock_progress,app.combat.kills])
		if m.phase=="aftermath" and m.phase_clock>1:break
		if app.mode=="results":break
		if frame%300==0:await process_frame
	print("END t=",app.mission.clock," phase=",app.mission.phase," down=",app.mission.skein_down,"/",app.mission.skein_total()," success=",app.mission.skein_success," kills=",app.combat.kills)
	app.queue_free();await process_frame;quit(0)
