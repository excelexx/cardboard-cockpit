extends SceneTree
const Vision=preload("res://systems/vision_client.gd")
const Gameplay=preload("res://systems/gameplay_settings.gd")
class LocalVision extends Vision:
	func poll(_dt: float) -> void:pass
var app: Node
var checks:=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func packet(gun: bool,tracked: bool=true,power: float=.4) -> void:
	var v=app.vision
	var data: Dictionary={"version":1,"sequence":v.sequence+1,"timestamp":Time.get_ticks_msec(),"tracking":tracked,"yoke":{"roll":0,"pitch":0,"yaw":0,"confidence":1 if tracked else 0},"throttle":{"value":power,"confidence":1},"weapons":{"gun":gun}}
	check(v._accept_packet(JSON.stringify(data).to_utf8_buffer(),Time.get_ticks_msec()),"Fresh XLX gun packet accepted")
	v.tracking=tracked;v.connected=true
func tick(count: int) -> void:
	for i in range(count):app._physics_process(1.0/60)
func run() -> void:
	app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","alpine");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true;app.test_mode=true
	app.on_action("sensitivity_reset")
	check(app.gameplay_settings.pitch_agility==1.3 and app.gameplay_settings.bank_agility==1.3 and app.gameplay_settings.yaw_agility==1.3 and app.combat.aim_strength==1.4,"XLX default agility and auto-aim are restored")
	app.on_action("settings");app.hud.update_sensitivity_sliders()
	for axis: String in ["pitch","bank","yaw","pitch_agility","bank_agility","yaw_agility","auto_aim"]:
		var slider: HSlider=app.hud.sensitivity_sliders[axis]
		slider.value=2.2
		var actual: float=app.vision.get(axis+"_sensitivity") if axis in ["pitch","bank","yaw"] else app.gameplay_settings.get(axis)
		check(is_equal_approx(actual,2.2),"Settings slider drives "+axis)
	app.on_action("sensitivity_reset")
	app.vision=LocalVision.new();app.vision.enabled=true
	app.start_flight("combat");app.flight.spawn_airborne(Vector3(0,5000,0),180);app.combat.spawn_clock=999;app.fire_guard=0
	packet(true);tick(60)
	check(app.combat.primary_used and app.combat.beam_active and app.combat.beam_ends.size()==2,"Visible printed gun tag fires both plasma emitters continuously")
	var fired: int=app.combat.rounds_fired
	packet(false);tick(30)
	check(app.combat.rounds_fired==fired and not app.combat.beam_active,"Covering the tag stops both primary effects without a toggle")
	check(not app.combat.has_method("fire_missile") and not app.combat.has_method("fire_gun") and app.combat.has_method("update_swarm_missiles") and app.fighter_fx.stores.size()==4,"Dual plasma and automatic missile support retain four mounted stores without manual ordnance APIs")
	check(app.combat.rounds_fired==0 and app.combat.shots.is_empty(),"Manual plasma creates no minigun bullets")
	packet(true,false)
	var at: Vector3=app.flight.position;var elapsed: float=app.flight.elapsed
	tick(60)
	check(app.yoke_recovery_visible() and app.flight.position==at and app.flight.elapsed==elapsed and app.combat.rounds_fired==fired,"Lost yoke pauses flight and shooting exactly where they were")
	packet(false,true);tick(29)
	check(app.flight.position==at,"A brief reappearance cannot resume flight before the steady interval")
	tick(3)
	check(not app.yoke_recovery_visible() and app.flight.elapsed>elapsed and app.fire_guard>0,"Stable return resumes flight with a fresh gun guard")
	app.flight.throttle=0;packet(false,true,1);tick(1)
	check(app.flight.throttle>0 and app.flight.throttle<=.014 and app.flight.power_input==0 and not app.flight.afterburner,"Throttle reacquisition is capped and does not force boost")
	app.vision.yoke_enabled=false;app.take_manual_control(true)
	check(app.vision.enabled,"Keyboard steering preserves a throttle-only camera")
	app.take_manual_control(false);check(not app.vision.enabled,"Keyboard power explicitly takes over camera controls")
	app.vision.enabled=true;app.vision.tracking=false;app.vision.yoke_enabled=true
	app.on_action("keyboard");check(not app.vision.enabled and not app.yoke_recovery_visible(),"Recovery keyboard button resumes without a camera")
	app.vision.enabled=false;app.on_action("keyboard_play")
	check(app.flight_kind=="demo" and not app.mission is TrainingMission,"Play opens the common judge demo")
	app.on_action("keyboard_training");check(app.flight_kind=="demo" and not app.mission is TrainingMission and app.combat.training_target_limit==-1,"Legacy Tutorial selects the same unlimited judge demo")
	var snapshot: Dictionary=app.badge.instrument_snapshot(app)
	check(not snapshot.systems&4,"Badge remains a secondary-controls display without a missile-ready bit")
	app.queue_free();await process_frame
	print("XLX CONTROLS: ",checks," checks / ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
