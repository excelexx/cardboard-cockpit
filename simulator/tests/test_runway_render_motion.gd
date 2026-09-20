extends "res://tests/test_camera_comfort.gd"
func run()->void:
	for cockpit:bool in [false,true]:
		var app=App.new();root.add_child(app);app.add_child(app.cockpit_frame);app.cockpit=cockpit
		app.flight.position=Vector3(0,3,0);app.flight.speed=90;app.flight.velocity=Vector3(0,0,-90);app.flight.airborne=false
		var rig=Rig.new();rig.app=app;app.add_child(rig);rig.reset()
		var interpolation:RefCounted=null
		if ResourceLoader.exists("res://systems/flight_render_state.gd"):interpolation=load("res://systems/flight_render_state.gd").new()
		if interpolation!=null:interpolation.record(app.flight)
		for i in range(120):rig.update(1.0/120)
		var previous:Vector3=rig.camera.position;var stopped:=0;var maximum:=0.0;var minimum:=INF
		for frame in range(240):
			if frame%2==0:
				app.flight.position+=app.flight.velocity/60.0
				if interpolation!=null:interpolation.record(app.flight)
			if interpolation!=null:rig.call("update",1.0/120,interpolation.sample(app.flight,float(frame%2)*.5))
			else:rig.update(1.0/120)
			var distance:float=absf(rig.camera.position.z-previous.z)
			if frame>4:
				if distance<.001:stopped+=1
				maximum=maxf(maximum,distance);minimum=minf(minimum,distance)
			previous=rig.camera.position
		check(stopped==0,"Runway camera advances on every rendered frame")
		check(maximum-minimum<.01,"Constant-speed movement does not alternate between stationary frames and jumps")
		print("RUNWAY RENDER cockpit=",cockpit," stopped=",stopped," min_step=",minimum," max_step=",maximum," failures=",failures.size())
		if interpolation!=null:
			var live:Vector3=app.flight.position
			var view:FlightDynamics=interpolation.sample(app.flight,.5)
			check(app.flight.position==live and view!=app.flight,"Rendering never changes the authoritative flight state")
			app.flight.position=Vector3(5000,1000,-10000);interpolation.record(app.flight)
			check(interpolation.sample(app.flight,.2).position==app.flight.position,"Approach teleports snap instead of sweeping across the map")
			app.flight.heading=deg_to_rad(179);interpolation.reset(app.flight)
			app.flight.heading=deg_to_rad(-179);interpolation.record(app.flight)
			check(absf(absf(interpolation.sample(app.flight,.5).heading)-PI)<.001,"Heading interpolation takes the short path across wraparound")
		app.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
