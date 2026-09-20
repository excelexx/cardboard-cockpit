extends SceneTree
class Probe extends Node:
	var app:Node
	var enabled:=false
	var times:Array[float]=[]
	var errors:Array[float]=[]
	var previous:=Vector3.ZERO
	var last_time:=0
	var stopped:=0
	func begin()->void:
		times.clear();errors.clear();stopped=0;previous=app.camera.position;last_time=Time.get_ticks_usec();enabled=true
	func _process(dt:float)->void:
		if not enabled:return
		var now:=Time.get_ticks_usec();times.append(float(now-last_time)/1000.0);last_time=now
		var distance:float=Vector2(app.camera.position.x-previous.x,app.camera.position.z-previous.z).length()
		if distance<.001:stopped+=1
		if app.flight.speed>10:errors.append(absf(distance/maxf(dt,.001)-app.flight.speed)/app.flight.speed)
		previous=app.camera.position
	func report(label:String)->void:
		enabled=false;times.sort();errors.sort()
		print("RUNWAY ",label," frames=",times.size()," stopped=",stopped," frame_p50_ms=",times[times.size()/2]," p99_ms=",times[int(times.size()*.99)]," max_ms=",times[-1]," motion_error_p50=",errors[errors.size()/2]," error_p95=",errors[int(errors.size()*.95)])
func _initialize()->void:call_deferred("run")
func run()->void:
	Engine.max_fps=120
	var app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","sf");root.add_child(app)
	app.audio.muted=true;app.capture_file="runway-profile";app.vision.enabled=false
	app.start_flight("demo");app.badge_launch_remaining=0;app.mission.active=false;app.combat.active=false;app.copilot=false
	app.flight.speed=55;app.flight.throttle=1;app.flight.engine=1
	var probe:=Probe.new();probe.app=app;probe.process_priority=10000;root.add_child(probe)
	await create_timer(2).timeout;probe.begin();await create_timer(4).timeout;probe.report("takeoff")
	app.begin_landing();app.flight.gear=true;app.flight.flaps=2;app.gear_override=1;app.flaps_override=2
	await create_timer(1).timeout;probe.begin();await create_timer(3).timeout;probe.report("approach")
	app.flight.position=Vector3(100,app.surface_height(100,0)+3.1,0);app.flight.speed=70;app.flight.pitch=-.1;app.flight.vertical_speed=-15;app.flight.velocity=Vector3(0,-15,-70)
	await create_timer(.5).timeout;probe.begin();await create_timer(2).timeout;probe.report("rollout")
	app.queue_free();await process_frame;quit()
