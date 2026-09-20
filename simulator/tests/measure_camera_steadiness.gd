extends SceneTree
# Measures how steady the picture is in straight and level flight, with the game running
# its real loops (flight at the physics rate, camera at the render rate). A probe node that
# processes after everything else records, per rendered frame, how far the camera turned,
# how far the jet moved on screen and how far the airframe model rotated.
# Usage: Godot --path simulator --windowed --resolution 1280x800 --script tests/measure_camera_steadiness.gd
class Probe extends Node:
	var app: Node3D
	var armed:=false
	var last_forward:=Vector3.ZERO;var last_screen:=Vector2.ZERO;var last_model:=Basis.IDENTITY
	var turn_sum:=0.0;var turn_max:=0.0;var wander_sum:=0.0;var wander_max:=0.0;var model_sum:=0.0;var model_max:=0.0;var frames:=0
	func begin() -> void:
		armed=false;turn_sum=0;turn_max=0;wander_sum=0;wander_max=0;model_sum=0;model_max=0;frames=0
	func _process(_dt: float) -> void:
		var forward: Vector3=-app.camera.global_basis.z
		var screen: Vector2=app.camera.unproject_position(app.aircraft.global_position)
		var model: Basis=app.aircraft.global_basis.orthonormalized()
		if armed:
			var turn: float=rad_to_deg(forward.angle_to(last_forward))
			var wander: float=screen.distance_to(last_screen)
			var spin: float=rad_to_deg((last_model.inverse()*model).get_rotation_quaternion().get_angle())
			turn_sum+=turn;turn_max=maxf(turn_max,turn);wander_sum+=wander;wander_max=maxf(wander_max,wander)
			model_sum+=spin;model_max=maxf(model_max,spin);frames+=1
		last_forward=forward;last_screen=screen;last_model=model;armed=true
var app: Node3D
func _initialize() -> void:call_deferred("run")
func run() -> void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	for i in 30:await process_frame
	app.audio.muted=true
	app.capture_file="review"
	var probe:=Probe.new();probe.app=app;probe.process_priority=10000;root.add_child(probe)
	# name, cockpit, speed m/s, height above sea, afterburner
	var cases:=[["chase supersonic high",false,345.0,1500.0,false],["chase transonic high",false,322.0,1500.0,false],["chase transonic burner",false,322.0,1500.0,true],["chase low over water",false,322.0,70.0,false],["cockpit transonic",true,322.0,1500.0,false],["cockpit low burner",true,322.0,70.0,true]]
	for entry in cases:
		app.start_flight("combat");app.copilot=false;app.cockpit=entry[1];app.text_hud=true
		app.flight.spawn_airborne(Vector3(-9000,entry[3],-9000),entry[2]);app.flight.gear=false;app.flight.throttle=.8
		app.flight.heading=-1.2;app.apply_aircraft_pose();app.combat.spawn_clock=999
		app.camera_rig.reset()
		for i in 150:
			await process_frame
			app.flight.speed=entry[2];app.flight.afterburner=entry[4]
		probe.begin()
		var began:=Time.get_ticks_msec()
		while Time.get_ticks_msec()-began<2500:
			await process_frame
			app.flight.speed=entry[2];app.flight.afterburner=entry[4]
		var n: float=maxf(probe.frames,1)
		print("STEADY ",entry[0]," fps=",snappedf(n/2.5,1)," mach=",snappedf(app.flight.mach,0.01)," agl=",snappedf(app.flight.position.y,1),
			" | camera turn mean/max deg=",snappedf(probe.turn_sum/n,0.001),"/",snappedf(probe.turn_max,0.001),
			" | jet on screen mean/max px=",snappedf(probe.wander_sum/n,0.01),"/",snappedf(probe.wander_max,0.01),
			" | model spin mean/max deg=",snappedf(probe.model_sum/n,0.001),"/",snappedf(probe.model_max,0.001))
	quit()
