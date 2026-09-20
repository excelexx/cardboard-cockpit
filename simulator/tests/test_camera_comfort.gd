extends SceneTree
const Rig=preload("res://systems/camera_rig.gd")
const Flight=preload("res://systems/flight_dynamics.gd")
class FlatWorld extends RefCounted:
	func ground_height(_x:float,_z:float)->float:return 0
class Frame extends Node3D:
	func set_presentation_visible(_v:bool)->void:pass
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
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	check(Rig.SHAKE_STRENGTH==.6,"Kill shake is40percent below original amplitude")
	for cockpit:bool in [false,true]:
		var app=App.new();root.add_child(app);app.add_child(app.cockpit_frame);app.cockpit=cockpit
		app.flight.position=Vector3(0,50,0);app.flight.speed=335;app.flight.mach=.98;app.flight.g_load=5;app.flight.afterburner=true
		var rig=Rig.new();rig.app=app;app.add_child(rig);rig.reset()
		var previous:=Basis.IDENTITY;var at:=Vector3.ZERO;var idle_angle:=0.0;var idle_shift:=0.0
		for i in range(420):
			rig.impulse(1);rig.update(1.0/60)
			if i>120:
				idle_angle=maxf(idle_angle,(previous.inverse()*rig.camera.basis).get_euler().length())
				idle_shift=maxf(idle_shift,at.distance_to(rig.camera.position))
			previous=rig.camera.basis;at=rig.camera.position
		check(rig.trauma==0 and idle_angle<.0001 and idle_shift<.0001,"No shake from flight, ground proximity, boost or generic impacts")
		rig.kill_impulse();var kill_angle:=0.0
		for i in range(120):
			rig.update(1.0/60);kill_angle=maxf(kill_angle,(previous.inverse()*rig.camera.basis).get_euler().length());previous=rig.camera.basis
		check(kill_angle>.001 and rig.trauma==0,"Confirmed kills give a brief visible shake that settles away")
		rig.touchdown(.6);check(rig.trauma==0 and rig.settle==0,"Touchdown does not add camera shaking")
		print("KILL-ONLY CAMERA cockpit=",cockpit," idle_rotation_deg=",rad_to_deg(idle_angle)," idle_shift=",idle_shift," kill_peak_deg=",rad_to_deg(kill_angle))
		app.queue_free();await process_frame
	print("KILL-ONLY CAMERA: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
