extends SceneTree
const Rig=preload("res://systems/camera_rig.gd")
const Flight=preload("res://systems/flight_dynamics.gd")
class FlatWorld extends RefCounted:
	func ground_height(_x: float,_z: float) -> float:return 0
class Frame extends Node3D:
	func set_presentation_visible(_value: bool) -> void:pass
class App extends Node3D:
	var route_id:="alpine"
	var mode:="flight"
	var cockpit:=false
	var pilot_ejected:=false
	var look:=Vector2.ZERO
	var control:=Vector3.ZERO
	var flight=Flight.new()
	var world=FlatWorld.new()
	var cockpit_frame=Frame.new()
	var fighter_fx:Node
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var failures:=0
	for cockpit: bool in [false,true]:
		var app=App.new();root.add_child(app);app.add_child(app.cockpit_frame);app.cockpit=cockpit
		app.flight.position=Vector3(0,50,0);app.flight.speed=335;app.flight.mach=.98;app.flight.g_load=5;app.flight.afterburner=true
		var rig=Rig.new();rig.app=app;app.add_child(rig);rig.reset()
		var previous:=Basis.IDENTITY;var at:=Vector3.ZERO;var angle_peak:=0.0;var shift_peak:=0.0
		for i in range(420):
			rig.impulse(.15);rig.update(1.0/60)
			if i>120:
				angle_peak=maxf(angle_peak,rad_to_deg(previous.get_rotation_quaternion().angle_to(rig.camera.basis.get_rotation_quaternion())))
				shift_peak=maxf(shift_peak,at.distance_to(rig.camera.position))
			previous=rig.camera.basis;at=rig.camera.position
		print("CAMERA COMFORT cockpit=",cockpit," peak_frame_rotation_deg=",angle_peak," peak_frame_shift_m=",shift_peak)
		if "--measure-only" not in OS.get_cmdline_user_args() and (angle_peak>.16 or shift_peak>.025):failures+=1;push_error("Camera shake exceeds the reduced-motion ceiling")
		app.queue_free();await process_frame
	print("CAMERA COMFORT: ",failures," failures");quit(1 if failures else 0)
