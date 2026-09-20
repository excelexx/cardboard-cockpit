extends SceneTree
var app: Node
func _initialize()->void:call_deferred("run")
func run()->void:
	app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","sf");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.vision.enabled=false;app.capture_file="touchdown-profile"
	app.start_flight("demo");app.begin_landing();app.badge_launch_remaining=0
	for i in range(60):
		app._process(1.0/60);await process_frame
	var smoke_ids: Array=[]
	for puff in app.fighter_fx.tyre_puffs:smoke_ids.append(puff.get_instance_id())
	for trial in range(2):
		app.mode="flight";app.landing_started=true;app.flight.contact="";app.flight.airborne=true;app.flight.ever_airborne=true
		app.flight.position=Vector3(100,app.surface_height(100,0)+3.1,0);app.flight.speed=70;app.flight.vertical_speed=-15;app.flight.velocity=Vector3(0,-15,-70);app.flight.gear=true;app.flight.flaps=2;app.gear_override=1;app.flaps_override=2
		var baseline: Array[float]=[]
		for i in range(30):
			var before:=Time.get_ticks_usec();app._process(1.0/60);await process_frame;baseline.append((Time.get_ticks_usec()-before)/1000.0)
		var before:=Time.get_ticks_usec();app._physics_process(1.0/60);var cpu:float=(Time.get_ticks_usec()-before)/1000.0
		var frames: Array[float]=[]
		for i in range(12):
			var started:=Time.get_ticks_usec();app._process(1.0/60);await process_frame;frames.append((Time.get_ticks_usec()-started)/1000.0)
		if app.mode!="rollout":push_error("Touchdown probe did not land");quit(1);return
		for i in range(smoke_ids.size()):
			if app.fighter_fx.tyre_puffs[i].get_instance_id()!=smoke_ids[i]:push_error("Touchdown replaced a pooled smoke node");quit(1);return
		baseline.sort();frames.sort()
		print("TOUCHDOWN trial=",trial," mode=",app.mode," cpu_ms=",cpu," baseline_p50_ms=",baseline[15]," landing_peak_ms=",frames[-1]," particles=",app.fighter_fx.tyre_puffs.size())
	app.queue_free();await process_frame;quit()
