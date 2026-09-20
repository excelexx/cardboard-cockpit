extends SceneTree
const Vision=preload("res://systems/vision_client.gd")
class LocalVision extends Vision:
	func poll(_dt:float)->void:pass
var app:Node
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","sf");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true;app.vision=LocalVision.new()
	app.on_action("keyboard_training")
	check(app.flight_kind=="demo" and not app.mission is TrainingMission,"Tutorial and Play enter the same mission")
	check(not app.mission.has_method("build_rings"),"The shared mission does not build navigation rings")
	app.vision.enabled=true;app.vision.connected=true;app.vision.tracking=true;app.vision.yoke_enabled=true;app.vision.throttle_confidence=1;app.vision.throttle=.3
	app.flight.gear=false;app.flight.flaps=0;app.gear_override=0;app.flaps_override=0
	var event:=InputEventKey.new();event.keycode=KEY_D;event.pressed=true;app._input(event)
	check(not app.landing_started,"D no longer starts landing")
	event.keycode=KEY_B;app._input(event)
	check(not app.mouse_yoke,"B does not enable the former mouse-yoke binding")
	check(app.landing_started and app.mission.phase=="approach" and not app.copilot and app.vision.enabled,"B immediately begins a camera-controlled landing, without kill quotas")
	check(not app.combat.active and app.combat.launch_queue.is_empty(),"Choosing landing stops waves and automatic weapons")
	var first:Vector3=app.flight.position
	check(first.z==3400 and first.y==115,"The landing approach starts farther out at matching height")
	app.flight.position+=Vector3(100,-20,-500);event.keycode=KEY_B;app._input(event)
	check(app.flight.position==first and app.mode=="flight","Pressing B again restarts at the original approach position")
	if not app.flight.gear:app.toggle_gear()
	check(app.flight.gear and app.flight.flaps==2,"A/G configures landing gear and flaps together")
	app.vision.yoke=Vector2(.7,0)
	for i in range(24):app._physics_process(1.0/60)
	check(absf(app.flight.roll)>.03 and not app.copilot,"The pilot can still bank and steer during landing")
	for sample in [Vector3(220,-180,1.2),Vector3(90,-35,-.8),Vector3(40,-90,2.0)]:
		app.on_action("keyboard_play");app.begin_landing()
		app.vision.enabled=true;app.vision.tracking=true;app.vision.yoke=Vector2(1,-1);app.vision.throttle=1;app.vision.throttle_confidence=1
		app.flight.position=Vector3(100,app.surface_height(100,0)+3.1,0)
		app.flight.speed=sample.x;app.flight.pitch=-1;app.flight.roll=sample.z;app.flight.vertical_speed=sample.y;app.flight.velocity=Vector3(0,sample.y,-sample.x)
		app.flight.gear=false;app.flight.flaps=0;app.gear_override=0;app.flaps_override=0
		app._physics_process(1.0/30)
		check(app.mode=="rollout" and app.flight.contact=="landed" and not app.flight.airborne,"A hard steep touchdown is accepted instead of crashing or respawning")
		app.vision.yoke=Vector2(0,1);app.vision.tracking=false
		var bounced:=false
		for i in range(1200):
			app._physics_process(1.0/60)
			if app.flight.airborne or app.flight.contact!="landed":bounced=true
			if app.mode=="results":break
		check(not bounced and app.flight.speed==0 and app.mode=="results" and app.mission_success,"Touchdown stays on the ground and finishes safely even with full throttle, nose-up input or lost tracking")
		check(app.combat.kills==0,"Safe demo landing never requires clearing a wave")
		await process_frame
	app.on_action("keyboard_play");app.flight.spawn_airborne(Vector3(0,500,0),150);app.toggle_gear()
	check(app.flight.gear and app.flight.flaps==1,"Gear control preserves a meaningful in-flight configuration")
	app.toggle_gear();check(not app.flight.gear and app.flight.flaps==0,"A/G retracts both gear and flaps after takeoff")
	app.queue_free();await process_frame
	print("JUDGE LANDING: ",checks," checks / ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
