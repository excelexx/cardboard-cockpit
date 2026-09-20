extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","sf");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true;app.vision.enabled=false
	app.on_action("training");app.copilot=true;app.demo_auto_fire=true
	var raised:=false;var assisted:=false;var seen: Array[String]=[]
	for frame in range(36000):
		if app.mission.phase not in seen:seen.append(app.mission.phase);print("TRAINING PHASE ",app.mission.phase," t=",app.mission.clock," kills=",app.combat.kills)
		if app.flight.airborne and not raised:app.toggle_gear();raised=true
		if app.mission.phase in ["return","approach"] and not assisted:app.begin_landing();assisted=true
		app._physics_process(1.0/60);app._process(1.0/60)
		if app.mode=="results":break
		if frame%60==0:await process_frame
	print("TRAINING FINAL mode=",app.mode," phase=",app.mission.phase," kills=",app.combat.kills," contact=",app.flight.contact," speed=",app.flight.speed," t=",app.mission.clock," pos=",app.flight.position)
	var success: bool=app.mode=="results" and app.mission_success and app.combat.kills>=16 and app.flight.contact=="landed" and app.flight.speed<=.1 and raised and assisted and "takeoff" in seen and "combat" in seen and "approach" in seen
	app.queue_free();await process_frame
	print("TRAINING SORTIE: ","PASS" if success else "FAIL");quit(0 if success else 1)
