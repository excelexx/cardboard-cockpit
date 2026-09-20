extends SceneTree
const Gameplay=preload("res://systems/gameplay_settings.gd")
class ScriptedBadge extends BadgeLink:
	var next_press:=0
	func poll() -> void:
		connected=true;pressed=next_press;released=0;mask=next_press;next_press=0
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","alpine");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true;app.on_action("sensitivity_reset")
	check(app.gameplay_settings.pitch_agility==1.3 and app.gameplay_settings.bank_agility==1.3 and app.gameplay_settings.yaw_agility==1.3,"Unchanged default handling")
	app.on_action("settings");app.hud.update_sensitivity_sliders()
	check(app.settings_visible and app.overlay_visible(),"Settings blocks flight controls")
	for axis: String in ["pitch","bank","yaw"]:
		app.hud.sensitivity_sliders[axis].value=1.75;check(is_equal_approx(app.vision.get(axis+"_sensitivity"),1.75),"Live sensitivity: "+axis)
	for axis: String in ["pitch_agility","bank_agility","yaw_agility"]:
		app.hud.sensitivity_sliders[axis].value=1.8;check(is_equal_approx(app.flight.get(axis),1.8),"Live agility: "+axis)
	app.set_sensitivity("auto_aim",0);check(not app.combat.assist and app.combat.aim_strength==0,"Zero aim disables assistance")
	app.on_action("sensitivity_reset");check(app.flight.pitch_agility==1.3 and app.combat.aim_strength==1.4,"Reset restores XLX agility and aiming defaults")
	app.on_action("camera_previews");check(not app.camera_previews,"Camera overlay has a setting")
	app.on_action("badge_prompts");check(not app.badge_prompts,"Badge coaching has a setting")
	app.on_action("badge_prompts");app.on_action("camera_previews")
	app.on_action("keyboard_training");check(app.flight_kind=="training" and app.mission is TrainingMission,"Separate takeoff/combat/landing tutorial")
	check(app.mission.phase=="takeoff" and not app.flight.airborne and app.combat.training_target_limit==16,"Tutorial begins on runway and targets sixteen geese")
	app.badge.close();app.badge=ScriptedBadge.new();app.badge.next_press=1<<0;app._physics_process(1.0/60)
	check(not app.flight.gear and app.flight.flaps==0,"Physical badge A routes to tutorial gear/flap configuration")
	app.begin_landing();check(not app.landing_started and app.toast_time>0,"Landing assist cannot skip the combat lesson")
	app.mission.transition("combat");check(app.combat.enemies.size()==16,"Sixteen targets spawned")
	app.combat.spawn_contact();check(app.combat.enemies.size()==16,"Normal respawns cannot extend the tutorial target count")
	app.combat.kills=16;app.badge.next_press=1<<1;app._physics_process(1.0/60);check(app.landing_started and app.flight.gear and app.flight.flaps==2 and app.copilot,"Badge B/L assistance configures the tutorial landing")
	check(app.mission.phase=="return" and app.mission.instruction().length()>0,"Landing remains on the imported return route")
	app.mode="paused";app.resume_mode="flight";app.settings_visible=true;app.badge.next_press=1<<2;app._physics_process(.01)
	check(not app.settings_visible and app.mode=="paused","Badge HOME closes settings without restarting the flight")
	app.badge.next_press=1<<2;app._physics_process(.01);check(app.mode=="flight","Badge HOME resumes from pause")
	var old_tactical: bool=app.badge.tactical
	app.badge.next_press=1<<5;app._physics_process(.01)
	check(app.badge.tactical!=old_tactical and app.combat.missiles_fired==0,"Badge RIGHT toggles tactical display without firing")
	app.on_action("keyboard_play");check(app.flight_kind=="demo" and not app.mission is TrainingMission,"Normal Play remains this branch's mission")
	check(app.combat.training_target_limit==-1,"Normal combat limit restored")
	# Fresh visible/covered gun packets directly control firing without latches.
	app.start_flight("combat");app.vision.enabled=true;app.vision.tracking=true;app.fire_guard=0
	var camera_packet: Dictionary={"version":1,"sequence":10,"timestamp":100,"tracking":true,"yoke":{"roll":0,"pitch":0,"yaw":0,"confidence":1},"throttle":{"value":.4,"confidence":1},"weapons":{"gun":true}}
	check(app.vision._accept_packet(JSON.stringify(camera_packet).to_utf8_buffer(),100),"Visible gun tag accepted")
	check(app.gun_requested(),"Visible tag directly requests firing")
	camera_packet.sequence=11;camera_packet.weapons={"gun":false}
	check(app.vision._accept_packet(JSON.stringify(camera_packet).to_utf8_buffer(),110),"Covered gun tag accepted")
	check(not app.gun_requested(),"Covering the tag immediately stops the firing request")
	camera_packet.sequence=12;camera_packet.weapons={"primary":true,"salvo":true,"primary_confidence":1,"salvo_confidence":1}
	check(not app.vision._accept_packet(JSON.stringify(camera_packet).to_utf8_buffer(),120) and not app.gun_requested(),"Obsolete switch packet cannot start firing")
	var settings=Gameplay.new();settings.pitch_agility=1.9;settings.bank_agility=.75;settings.yaw_agility=2.1
	var config:=ConfigFile.new();settings.save_config(config);var loaded=Gameplay.new();loaded.load_config(config)
	check(loaded.pitch_agility==1.9 and loaded.bank_agility==.75 and loaded.yaw_agility==2.1,"Independent settings persist")
	app.queue_free();await process_frame
	print("TEAM INTEGRATION: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
