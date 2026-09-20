extends SceneTree
const Vision=preload("res://systems/vision_client.gd")
class LocalVision extends Vision:
	func poll(_dt:float)->void:pass
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","sf");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true;app.vision=LocalVision.new()
	check(app.world.is_airport_surface(0,0),"Runway belongs to the airport")
	check(app.world.is_airport_surface(45,454),"Dry airport grass between authored paving surfaces is accepted")
	check(not app.world.is_airport_surface(0,3400) and not app.world.is_airport_surface(6000,-10000),"Water and remote terrain are outside the airport footprint")
	var apron:=Vector3(-500,0,-500)
	print("AIRPORT APRON ",app.world.is_airport_surface(apron.x,apron.z)," CELLS ",app.world.airport_cells.size())
	check(app.world.is_airport_surface(apron.x,apron.z) and not app.is_on_runway(apron),"Airport acceptance includes dry areas away from the runway")
	app.on_action("keyboard_play");app.begin_landing();app.flight.position=apron;app.settle_demo_touchdown()
	check(app.mode=="rollout" and not app.landing_recovery,"Off-runway airport touchdown remains accepted")
	for location: Vector3 in [Vector3(1500,0,2400),Vector3(4000,0,-3500)]:
		app.on_action("keyboard_play");app.begin_landing();app.flight.position=location;app.flight.position.y=app.surface_height(location.x,location.z)+3
		app.settle_demo_touchdown()
		check(app.mode=="flight" and app.flight.contact=="" and app.landing_recovery,"Off-airport touchdown starts automatic return without a landing animation")
		check(app.flight.position.x==location.x and app.flight.position.z==location.z,"Automatic return starts from the missed landing location")
		app.vision.enabled=true;app.vision.tracking=false;app.vision.throttle_confidence=1;app.vision.throttle=1;app.vision.yoke=Vector2(1,-1)
		for frame in range(60*360):
			app._physics_process(1.0/60)
			if app.mode=="results":break
			if frame%300==0:await process_frame
		print("RECOVERY END ",location," mode=",app.mode," at=",app.flight.position," final=",app.recovery_final," speed=",app.flight.speed)
		check(app.mode=="results" and app.mission_success and app.airport_touchdown_allowed(app.flight.position),"Auto return reaches the airport and stops without requiring yoke tracking")
	app.on_action("keyboard_play");app.begin_landing();app.flight.position=Vector3(1500,3,2400);app.settle_demo_touchdown()
	var retry:=InputEventKey.new();retry.keycode=KEY_B;retry.pressed=true;app._input(retry)
	check(not app.landing_recovery and not app.copilot and app.flight.position==Vector3(0,115,3400),"B cancels automatic return and restarts the manual approach")
	app.queue_free();await process_frame
	print("AIRPORT RECOVERY: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
