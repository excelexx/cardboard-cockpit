extends Node3D
const Tune = preload("res://data/balance.gd")
const Catalog = preload("res://data/aircraft.gd")
const Dynamics = preload("res://systems/flight_dynamics.gd")
const World = preload("res://scenes/world.gd")
const Coast = preload("res://scenes/coastal_world.gd")
const SanFrancisco = preload("res://scenes/san_francisco_world.gd")
const Model = preload("res://systems/fighter_model.gd")
const Visuals = preload("res://systems/aircraft_visuals.gd")
const Effects = preload("res://systems/fighter_effects.gd")
const CameraRig = preload("res://systems/camera_rig.gd")
const Cockpit = preload("res://scenes/cockpit.gd")
const Combat = preload("res://systems/combat.gd")
const Audio = preload("res://systems/engine_audio.gd")
const Vision = preload("res://systems/vision_client.gd")
const Hud = preload("res://ui/hud.gd")
const Manual = preload("res://systems/arcade_controls.gd")
const Mission = preload("res://systems/demo_mission.gd")
const Badge = preload("res://systems/badge_link.gd")
const Tutorial = preload("res://systems/tutorial.gd")
const Results = preload("res://systems/sortie_result.gd")
var tutorial: FlightTutorial=Tutorial.new()
var result_headline:=""
var result_advice:=""
var result_code:=""
var landed_early:=false
const Approach = preload("res://systems/approach_guidance.gd")
var badge: BadgeLink=Badge.new()
var cv_weapon_revision:=-1
var primary_latched:=false
var salvo_latched:=false
var text_hud:=true
var gear_override:=-1
var flaps_override:=-1
var assisted_yoke_reference:=Vector2.ZERO
var mode := "title"
var resume_mode := "flight"
var flight_kind := "demo"
var mission: DemoMission = Mission.new()
var flight: FlightDynamics = Dynamics.new()
var vision: VisionClient = Vision.new()
var world: Node3D
var route_id := "sf"
var aircraft: Node3D
var aircraft_visuals: AircraftVisuals
var fighter_fx: FighterEffects
var camera_rig: FighterCameraRig
var camera: Camera3D
var cockpit_frame: DetailedCockpit
var combat: CombatDirector
var audio: EngineAudio
var hud: CockpitHUD
var cockpit := true
var copilot := false
var paper_test := false
var used_copilot := false
var demo_auto_fire := true
var help_visible := false
var calibration_visible := false
var credits_visible := false
var developer_mode := false
var high_quality := true
var mouse_yoke := false
var control := Vector3.ZERO
var look := Vector2.ZERO
var mission_success := false
var best_score := 0
var record_broken := false
var result_reason := ""
var pilot_ejected := false
var eject_hold := 0.0
var crash_clock := 0.0
var runtime := 0.0
var fire_guard := 0.0
var capture_at := -1.0
var capture_file := ""
var test_mode := false
var test_finished := false
var pending_capture := false
var toast := ""
var toast_time := 0.0
var near_obstacle_cooldown:=0.0
var landing_transition:=0.0
var landing_started:=false
func profile() -> Dictionary: return Catalog.PROFILE
func _ready() -> void:
	get_window().title = "Goose Protocol — SPECTRE X-26"
	mission.app = self
	if DisplayServer.get_name()!="headless":badge.open_inputs()
	load_settings()
	if DisplayServer.get_name()!="headless":route_id="sf"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--route="): route_id = argument.trim_prefix("--route=")
	route_id = str(get_meta("route_override",route_id))
	world = SanFrancisco.new() if route_id=="sf" else Coast.new() if route_id=="coast" else World.new(); add_child(world)
	world.set_conditions("golden")
	flight.reset(profile())
	if route_id=="sf": flight.position.y += world.ground_height(flight.position.x,flight.position.z)
	aircraft = Node3D.new(); add_child(aircraft)
	var model: Node3D = Model.create(); aircraft.add_child(model)
	aircraft_visuals = Visuals.new(); add_child(aircraft_visuals)
	aircraft_visuals.initialize(model,profile())
	camera_rig = CameraRig.new(); camera_rig.app = self; add_child(camera_rig)
	camera = camera_rig.camera
	cockpit_frame = Cockpit.new(); camera.add_child(cockpit_frame); cockpit_frame.build(profile())
	cockpit_frame.set_presentation_visible(false)
	audio = Audio.new(); add_child(audio); audio.set_aircraft(profile())
	var settings := ConfigFile.new()
	if settings.load("user://settings.cfg")==OK: audio.muted = bool(settings.get_value("audio","muted",false))
	combat = Combat.new(); combat.app = self; add_child(combat)
	fighter_fx = Effects.new(); fighter_fx.app = self; add_child(fighter_fx); fighter_fx.build()
	var layer := CanvasLayer.new(); add_child(layer)
	hud = Hud.new(); hud.app = self; layer.add_child(hud); hud.action.connect(on_action)
	tutorial.configure(self)
	set_quality(high_quality)
	get_viewport().size_changed.connect(_apply_render_scale)
	var start := false
	var guide := false
	for arg: String in OS.get_cmdline_user_args():
		if arg=="--flight": start = true
		elif arg=="--autotest": test_mode = true; start = true; guide = true; Engine.max_fps = 0
		elif arg=="--copilot": guide = true
		elif arg=="--approach" or arg=="--kind=approach": flight_kind = "approach"; start = true
		elif arg=="--runway": flight_kind = "runway"; start = true
		elif arg=="--combat": flight_kind = "combat"; start = true
		elif arg=="--demo": flight_kind = "demo"; start = true
		elif arg=="--cockpit": cockpit = true
		elif arg=="--stickers":
			vision.enabled = true
			mouse_yoke = false
			calibration_visible = true
		elif arg=="--paper-test":
			paper_test = true
			vision.enabled = true
			mouse_yoke = false
			cockpit = false
			flight_kind = "paper"
			start = true
		elif arg.begins_with("--capture="): capture_file = arg.trim_prefix("--capture="); capture_at = 4
		elif arg.begins_with("--capture-at="): capture_at = maxf(1,arg.trim_prefix("--capture-at=").to_float())
	if start:
		start_flight(flight_kind)
		copilot = guide; used_copilot = guide
		if paper_test: print("PAPER FLIGHT: enabled=",vision.enabled," endpoint=",vision.endpoint)
	else:
		world.visible = false; aircraft.visible = false; fighter_fx.visible = false

func start_flight(kind: String = "demo") -> void:
	tutorial.stop();result_headline="";result_advice="";result_code="";landed_early=false
	flight_kind = kind
	mode = "flight"; resume_mode = "flight"
	help_visible = false; calibration_visible = false; credits_visible = false
	copilot = false; used_copilot = false; mission_success = false; result_reason = ""
	pilot_ejected = false; record_broken = false; eject_hold = 0; crash_clock = 0; fire_guard = 0.3
	control = Vector3.ZERO; look = Vector2.ZERO
	landing_started=false;landing_transition=0
	primary_latched=false;salvo_latched=false;cv_weapon_revision=-1;gear_override=-1;flaps_override=-1;assisted_yoke_reference=vision.yoke
	flight.reset(profile())
	if route_id=="sf": flight.position.y += world.ground_height(flight.position.x,flight.position.z)
	if kind=="approach":
		flight.spawn_airborne(Vector3(0,160,4200) if route_id=="sf" else Vector3(0,155,-11200),75)
		flight.gear = true; flight.flaps = 2; flight.pitch = -atan(Approach.GLIDESLOPE)
		flight.throttle = 0.3; flight.engine = 0.3
	elif kind=="combat": flight.spawn_airborne(Vector3(0,220,-3500),185)
	elif kind=="paper":
		flight.spawn_airborne(Vector3(0,650,-2300),135)
		flight.throttle = .7; flight.engine = .7
	combat.reset(kind in ["combat","demo"])
	combat.managed_mission = kind=="demo"
	combat.engagement_enabled = kind=="combat"
	if kind=="demo": flight.flaps = 1
	mission.reset(kind=="demo")
	audio.reset_flight(); audio.radio.say("countdown" if kind=="demo" else "intro" if kind=="combat" else "cleared")
	aircraft_visuals.reset()
	if not flight.gear: aircraft_visuals.update_visuals(2.1,flight,Vector3.ZERO)
	fighter_fx.reset()
	aircraft.position = flight.position; aircraft.rotation = Vector3(flight.pitch,-flight.heading,-flight.roll)
	world.visible = true; aircraft.visible = not cockpit; fighter_fx.visible = true
	camera_rig.reset(); camera_rig.update(1.0/60.0)

func overlay_visible() -> bool: return help_visible or calibration_visible or credits_visible
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and mode in ["flight","rollout","ejected"] and not test_mode and not paper_test and capture_file.is_empty():
		resume_mode = mode; mode = "paused"
func _input(event: InputEvent) -> void:
	if test_mode: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if credits_visible: credits_visible = false
			elif help_visible: help_visible = false
			elif calibration_visible: calibration_visible = false
			elif mode=="paused": mode = resume_mode
			elif mode in ["flight","rollout","ejected"]: resume_mode = mode; mode = "paused"
			elif mode=="results": on_action("title")
			return
		if event.keycode==KEY_F1: help_visible = not help_visible; calibration_visible = false; credits_visible = false; return
		if event.keycode==KEY_C: calibration_visible = not calibration_visible; help_visible = false; credits_visible = false; return
		if event.keycode==KEY_M: audio.muted = not audio.muted; save_settings(); return
		if overlay_visible(): return
		match event.keycode:
			KEY_ENTER:
				if mode in ["title","results"]: on_action("fly")
			KEY_R:
				if mode in ["flight","rollout","paused","results"]:
					if paper_test: on_action("restart")
					elif flight_kind=="demo": on_action("guided" if demo_auto_fire else "fly")
					else: start_flight(flight_kind)
			KEY_V:
				if mode in ["flight","rollout","paused","results"]: cockpit = not cockpit; camera_rig.reset()
			KEY_X:
				if mode=="flight": camera_rig.missile_requested = not camera_rig.missile_requested
			KEY_H:
				if mode=="flight": copilot = not copilot; used_copilot = used_copilot or copilot
			KEY_B:
				if mode=="flight": mouse_yoke = not mouse_yoke
			KEY_G:
				if mode=="flight": flight.gear = not flight.gear;gear_override=int(flight.gear)
			KEY_L:
				begin_landing()
			KEY_F:
				if mode=="flight": flight.flaps = (flight.flaps+1)%3;flaps_override=flight.flaps
			KEY_Q:
				if mode=="flight":
					if flight.start_barrel_roll(-1 if control.x<0 else 1):combat.event("roll",flight.position,1);audio.play_effect("sonic",-23,1.5);camera_rig.impulse(.10)
			KEY_T:
				if mode=="flight" and fire_guard<=0:
					salvo_latched=not salvo_latched
					if salvo_latched:combat.fire_missile()
			KEY_Z:
				if mode=="flight": combat.deploy_flares()
			KEY_J:
				if mode=="flight": combat.assist = not combat.assist
			KEY_F9: developer_mode = not developer_mode
			KEY_F10: set_quality(not high_quality)
			KEY_F8: text_hud=not text_hud
			KEY_SPACE:
				if mode=="flight" and flight.airborne and fire_guard<=0:
					primary_latched=not primary_latched
					if primary_latched:combat.fire_gun()
		if mode=="flight":
			var physical: int = event.physical_keycode if event.physical_keycode else event.keycode
			if physical in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_A,KEY_D,KEY_W,KEY_S]: take_manual_control(physical not in [KEY_W,KEY_S])
	if overlay_visible() or mode!="flight": return
	if event is InputEventMouseMotion and (Input.is_key_pressed(KEY_ALT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)):
		look.x = clampf(look.x-event.relative.x*0.003,-1.4,1.4)
		look.y = clampf(look.y-event.relative.y*0.003,-0.6,0.6)
	if event is InputEventMouseButton and event.pressed and fire_guard<=0 :
		if event.button_index==MOUSE_BUTTON_RIGHT:salvo_latched=not salvo_latched
		elif event.button_index==MOUSE_BUTTON_LEFT:primary_latched=not primary_latched

func take_manual_control(steering: bool) -> void:
	copilot = false
	if steering: mouse_yoke = false
	vision.enabled = false; vision.status = "KEYBOARD / MOUSE"
func on_action(action: String) -> void:
	match action:
		"route": pass
		"fly":
			start_flight();copilot=not vision.enabled;used_copilot=copilot;demo_auto_fire=false
			if mission.cinematic:tutorial.start()
		"restart":
			if paper_test:
				vision.enabled=true
				start_flight("paper")
				copilot=false
			else:
				on_action("guided" if demo_auto_fire else "fly")
		"land": begin_landing()
		"approach": start_flight("approach")
		"runway": start_flight("runway")
		"guided": start_flight(); copilot = true; used_copilot = true; demo_auto_fire = true
		"resume": mode = resume_mode
		"help": help_visible = not help_visible; calibration_visible = false; credits_visible = false
		"camera": calibration_visible = not calibration_visible; help_visible = false; credits_visible = false
		"credits": credits_visible = not credits_visible
		"vision":
			vision.enabled = not vision.enabled
			if vision.enabled:
				mouse_yoke = false
				copilot = false
		"mute": audio.muted = not audio.muted; save_settings()
		"quality": set_quality(not high_quality)
		"title":
			tutorial.stop()
			mode = "title"; combat.active = false; mission.active = false; help_visible = false; calibration_visible = false; credits_visible = false
			world.visible = false; aircraft.visible = false; fighter_fx.visible = false; cockpit_frame.set_presentation_visible(false)
			audio.radio.reset(); camera_rig.reset()

func _process(dt: float) -> void:
	runtime += dt; toast_time = maxf(0,toast_time-dt)
	vision.poll(dt);tutorial.tick(dt)
	if vision.weapons_available and cv_weapon_revision!=vision.weapons_revision:
		cv_weapon_revision=vision.weapons_revision;primary_latched=vision.primary_switch;salvo_latched=vision.salvo_switch
	var paused: bool = mode=="paused" or overlay_visible()
	var active: bool = mode in ["flight","rollout"] and not paused
	if mode not in ["title"]:
		if not Input.is_key_pressed(KEY_ALT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE): look = look.lerp(Vector2.ZERO,1-exp(-dt*3))
		if not paused: camera_rig.update(dt)
		aircraft.visible = not cockpit or mode in ["ejected","crashed"]
		aircraft_visuals.update_visuals(dt if active else 0,flight,control)
		if aircraft_visuals._engine_glow!=null:
			aircraft_visuals._engine_glow.visible = flight.engine>0.15
			aircraft_visuals._engine_material.emission_energy_multiplier = flight.engine*(2.0 if flight.afterburner else 0.35)
		if not paused and DisplayServer.get_name()!="headless":
			fighter_fx.update(dt)
			world.update_local_shadows(flight.position,dt)
		if cockpit:
			cockpit_frame.update_instruments(flight,control,dt if active else 0)
			if world.get("sun")!=null: cockpit_frame.set_sun(world.sun.global_basis.z,world.sun.light_energy/3.2)
			cockpit_frame.set_tactical(tactical_state())
			cockpit_frame.set_navigation("sf" if route_id=="sf" else "free",mission.route_index)
	audio.gun_wanted = active and combat.active and combat.gun_firing_time>0
	audio.beam_wanted=active and combat.beam_active
	audio.instructor_speaking=tutorial.speaking()
	audio.flow_intensity=combat.intent.intensity
	audio.acquisition=combat.lock_progress if combat.target_id>=0 and combat.lock_progress<1 else 0
	audio.burner_wanted = flight.afterburner and active
	audio.set_context(mode,cockpit,flight.contact,paused)
	audio.observe_flight(flight)
	audio.update(flight.engine,flight.speed,active,dt)
	audio.set_music_active(flight_kind in ["combat","demo"] and mode in ["flight","results"])
	if capture_at>0 and runtime>=capture_at and not pending_capture:
		pending_capture = true; capture_frame()
	if test_mode and flight.elapsed>(1200 if route_id=="sf" else 420) and not test_finished:
		test_finished = true; printerr("SORTIE TIMEOUT"); get_tree().quit(2)
func capture_frame() -> void:
	await RenderingServer.frame_post_draw
	camera.get_viewport().get_texture().get_image().save_png(capture_file)
	print("CAPTURE ",capture_file)
	if not test_mode: get_tree().call_deferred("quit")

func _physics_process(dt: float) -> void:
	badge.poll();badge.tick(self,dt)
	near_obstacle_cooldown=maxf(0,near_obstacle_cooldown-dt)
	if badge.tapped(8):
		if mode in ["title","results"]:on_action("fly")
		elif mode=="paused":mode=resume_mode
	if badge.tapped(2) and mode in ["flight","paused"]:
		if mode=="paused":mode=resume_mode
		else:resume_mode=mode;mode="paused"
	if badge.tapped(0) and mode=="flight":flight.gear=not flight.gear;gear_override=int(flight.gear)
	if badge.tapped(1) and mode=="flight":
		if mission.cinematic or tutorial.active:begin_landing()
		else:flight.flaps=(flight.flaps+1)%3;flaps_override=flight.flaps
	if badge.tapped(4) and mode=="flight":cockpit=not cockpit;camera_rig.reset()
	if badge.tapped(5) and mode=="flight":camera_rig.missile_requested=not camera_rig.missile_requested
	if badge.tapped(6) and mode=="flight":copilot=not copilot;assisted_yoke_reference=vision.yoke
	if badge.tapped(3):text_hud=not text_hud
	# Paper testing must not fly away while centering or while the card is hidden.
	if paper_test and vision.enabled and not vision.tracking:
		control = Vector3.ZERO
		return
	if overlay_visible() or mode=="paused": return
	if mode=="ejected":
		fighter_fx.tick_ejection(dt)
		flight.position += flight.velocity*dt
		flight.velocity.y -= 9.8*dt
		aircraft.position = flight.position; aircraft.rotate_z(dt*0.35)
		if fighter_fx.chute_clock>6: finish_sortie(false,"Pilot recovered. Airframe abandoned.")
		return
	if mode=="crashed":
		crash_clock += dt
		flight.throttle = 0; flight.afterburner = false; flight.engine = move_toward(flight.engine,0,dt*0.6)
		flight.velocity.y -= dt*14
		flight.position += flight.velocity*dt
		flight.position.y = maxf(flight.position.y,world.ground_height(flight.position.x,flight.position.z)+1)
		aircraft.position = flight.position; aircraft.rotate_z(dt*0.65)
		if crash_clock>2: finish_sortie(false,"Airframe lost. Review approach and defensive timing.")
		return
	if mode=="rollout":
		if mission.active: mission.tick(dt)
		var steer: float = float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
		flight.rollout_step(dt,landing_started or copilot or Input.is_physical_key_pressed(KEY_SPACE),steer,is_on_runway(flight.position))
		if not is_on_runway(flight.position): flight.contact = "overrun"
		apply_aircraft_pose()
		if flight.contact=="overrun":
			if route_id=="sf":recover_flight()
			else:finish_sortie(false,"Runway excursion. Brake earlier and hold centerline.")
		elif flight.speed==0:
			var success: bool=combat.boss_defeated if mission.cinematic else true
			finish_sortie(success,"SFO LANDING COMPLETE — AIRCRAFT SECURED" if success else "SFO LANDING COMPLETE — INTERCEPT INCOMPLETE")
		return
	if mode!="flight": return
	landing_transition=maxf(0,landing_transition-dt)
	fire_guard = maxf(0,fire_guard-dt)
	eject_hold = eject_hold+dt if not test_mode and Input.is_physical_key_pressed(KEY_E) else 0
	if eject_hold>0.9 and flight.airborne:
		mode = "ejected"; pilot_ejected = true; combat.active = false; vision.enabled = false
		flight.afterburner = false; fighter_fx.begin_ejection(); audio.play_effect("eject",-10); return
	if mission.active: mission.tick(dt)
	if combat.active:
		combat.tick(dt)
		if mode!="flight": return
		if not test_mode and fire_guard<=0 and (primary_latched or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)): combat.fire_gun()
		if not test_mode and fire_guard<=0 and (salvo_latched or Input.is_physical_key_pressed(KEY_T) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)): combat.fire_missile()
	var input := Vector3(float(Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_DOWN)),float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)))
	input.x *= Tune.KEYBOARD_SCALE; input.y *= Tune.KEYBOARD_SCALE
	var power: float = float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))
	if test_mode: input = Vector3.ZERO; power = 0
	if input.length()>0 or power!=0: take_manual_control(input.length()>0)
	if vision.enabled and vision.tracking:
		if flight.airborne and vision.yoke.distance_to(assisted_yoke_reference)>.10:copilot=false
		input.x = vision.yoke.x; input.y = vision.yoke.y
		# Physical yoke weapon toggles own firing; tracking alone never shoots.
	flight.power_input = 0
	if copilot:
		input = mission.controls() if mission.active else combat.pilot_controls() if combat.active else approach_controls()
		if demo_auto_fire and combat.active and combat.engagement_enabled and combat.lock_progress>=1:
			var tracked: Dictionary = combat.target()
			if not tracked.is_empty():
				var lead: Vector3 = combat.lead_point(tracked)-flight.position
				if flight.forward().angle_to(lead.normalized())<(deg_to_rad(25) if combat.assist else atan2(10.0,maxf(lead.length(),100))): combat.fire_gun()
			combat.fire_missile()
	else:
		if mouse_yoke and not vision.enabled and not Input.is_key_pressed(KEY_ALT):
			var mouse: Vector2 = (get_viewport().get_mouse_position()-Vector2(800,470))/Tune.MOUSE_RANGE
			input.x = clampf(mouse.x,-1,1); input.y = clampf(-mouse.y,-1,1)
		if vision.enabled and vision.throttle_confidence>0.4:
			flight.throttle=move_toward(flight.throttle,vision.throttle,dt*Tune.THROTTLE_RATE)
			flight.power_input=clampf((vision.throttle-.5)*2,-1,1)
			flight.afterburner=vision.throttle>.94 and flight.airborne
		if paper_test and vision.enabled:
			flight.throttle = clampf(.45+(135-flight.speed)*.035,0,1)
		flight.throttle = clampf(flight.throttle+power*dt*Tune.THROTTLE_RATE,0,1)
		input=combat.intent.steering_assist(input,combat)
		if not (vision.enabled and vision.throttle_confidence>0.4) or power!=0:
			flight.power_input = power
			flight.afterburner = Input.is_physical_key_pressed(KEY_SHIFT) and flight.airborne
		var landing_assist: bool = flight.gear and (flight_kind=="approach" or (mission.active and mission.phase=="approach"))
		var clearance: float = flight.position.y-world.ground_height(flight.position.x,flight.position.z)
		if not landing_assist:
			for seconds in [.4,.9,1.4]:
				var ahead: Vector3 = flight.position+flight.forward()*flight.speed*seconds
				clearance = minf(clearance,flight.position.y-world.ground_height(ahead.x,ahead.z))
		input = Manual.command(flight,input,clearance,landing_assist)
		if not landing_assist and world.has_method("obstacle_proximity"):
			var near: Dictionary=world.obstacle_proximity(flight.position)
			if near.distance<65 and near_obstacle_cooldown<=0:
				combat.intent.event("near_miss");combat.event("near_miss",near.point,1);near_obstacle_cooldown=2.5
			var ahead: Dictionary=world.obstacle_proximity(flight.position+flight.velocity*.9)
			if ahead.distance<100:
				# Add bounded elevator demand. Aircraft position remains physical.
				input.y=maxf(input.y,.55*(1-clampf(ahead.distance/100,0,1)))
		if landing_assist and power==0 and not vision.enabled: flight.throttle = clampf(.22+(Tune.APPROACH_SPEED-flight.speed)*.055,0,1)
	control = control.lerp(input,1-exp(-dt*Tune.INPUT_RESPONSE))
	var agl: float = flight.position.y-world.ground_height(flight.position.x,flight.position.z)
	flight.wind = Vector3(3.5+sin(flight.elapsed*.23)*1.7,0,sin(flight.elapsed*.17)*2.0)*clampf((agl-20)/90,0,1)
	var was_airborne: bool = flight.airborne
	if gear_override>=0:flight.gear=gear_override==1
	if flaps_override>=0:flight.flaps=flaps_override
	flight.step(dt,control,not mission.active and Input.is_physical_key_pressed(KEY_SPACE),world.ground_height(flight.position.x,flight.position.z),is_on_runway(flight.position),false)
	flight.resolve_contact(world.ground_height(flight.position.x,flight.position.z),is_on_runway(flight.position))
	if flight.airborne and not was_airborne: audio.radio.say("cleared")
	if flight.airborne and world.obstacle_collision(flight.position,2.5): flight.contact = "crash"
	if flight.contact=="landed":
		mode = "rollout"; combat.active = false; flight.throttle = 0
		if mission.active: mission.transition("rollout")
		audio.play_effect("touchdown_tires",-17); audio.play_effect("touchdown_thump",-16); audio.radio.say("touchdown")
	elif flight.contact!="": begin_crash()
	if (absf(flight.position.x)>60000 or absf(flight.position.z)>60000) if route_id=="sf" else (absf(flight.position.x)>14500 or flight.position.z < -24500 or flight.position.z>8500):
		finish_sortie(false,"Operational sector exited. Turn back earlier.","sector")
	if flight.airborne and not flight.gear and flight.position.y-world.ground_height(flight.position.x,flight.position.z)<50: audio.radio.say("warning")
	if flight.stall_time>1: audio.radio.say("warning")
	apply_aircraft_pose()
func apply_aircraft_pose() -> void:
	aircraft.position = flight.position
	aircraft.rotation = Vector3(flight.pitch,-flight.heading,-flight.roll)
func begin_crash() -> void:
	if route_id=="sf":recover_flight();return
	mode = "crashed"; crash_clock = 0; combat.active = false; copilot = false
	fighter_fx.debris(flight.position); combat.burst(flight.position,Color(1,0.5,0.15),14)
	audio.play_effect("explosion",-10); camera_rig.impulse(0.8)
func recover_flight() -> void:
	# Arcade recovery keeps the existing mission, score and target progress.
	var approach: bool=landing_started or flight_kind=="approach"
	mode="flight";resume_mode="flight";flight.contact="";flight.airborne=true
	copilot=true;used_copilot=true;assisted_yoke_reference=vision.yoke;control=Vector3.ZERO
	if approach:
		landing_started=false;begin_landing()
	else:
		var at: Vector3=flight.position
		var safe_height: float=world.ground_height(at.x,at.z)+200
		for seconds in [.5,1.0,2.0]:
			var probe: Vector3=at+flight.forward()*180*seconds
			safe_height=maxf(safe_height,world.ground_height(probe.x,probe.z)+200)
		at.y=maxf(at.y,safe_height)
		var heading: float=flight.heading
		flight.spawn_airborne(at,180);flight.heading=heading;flight.pitch=0;flight.roll=0
		flight.pitch_velocity=0;flight.roll_velocity=0;flight.yaw_velocity=0;flight.barrel_remaining=0
		flight.velocity=flight.forward()*180;flight.vertical_speed=0
		flight.throttle=.65;flight.engine=.65;flight.afterburner=false;flight.power_input=0
		flight.gear=false;flight.flaps=0;gear_override=-1;flaps_override=-1
		combat.hull=Tune.PLAYER_HEALTH;combat.target_id=-1;combat.lock_progress=0
		fighter_fx.reset();camera_rig.reset();apply_aircraft_pose();fire_guard=.5
	toast="FLIGHT RECOVERED — KEEP GOING";toast_time=3

func finish_sortie(success: bool, reason: String, cause: String="") -> void:
	if mode=="results": return
	var result: Dictionary=Results.assess({"contact":flight.contact,"stopped":flight.speed<=.1,"boss":combat.boss_defeated,"cinematic":mission.cinematic,"ejected":pilot_ejected,"landing":landing_started or flight_kind=="approach","cause":cause,"early_landing":landed_early},success,reason)
	mission_success=result.success;result_headline=result.headline;result_reason=result.summary;result_advice=result.advice;result_code=result.code
	tutorial.stop()
	if mission.active and mission_success:mission.transition("secured")
	mode="results";combat.active=false
	if mission_success and not demo_auto_fire and combat.score>best_score:
		best_score=combat.score;record_broken=true;save_settings()
	audio.radio.reset();audio.radio.say(result.radio,3)
	if test_mode and not test_finished:
		test_finished=true
		print("SORTIE RESULT: ","PASS" if mission_success else "FAIL"," time=",flight.elapsed," contacts=",combat.kills," hull=",combat.hull," position=",flight.position," contact=",flight.contact)
		get_tree().quit(0 if mission_success else 1)
func begin_landing() -> void:
	if mode!="flight" or not flight.airborne or landing_started or route_id!="sf":return
	landed_early=mission.cinematic and mission.clock<107 and not combat.boss_defeated
	landing_started=true;landing_transition=1.2
	tutorial.landing_begun()
	primary_latched=false;salvo_latched=false;combat.active=false;combat.engagement_enabled=false
	combat.beam_active=false;combat.gun_firing_time=0;combat.visuals.reset()
	vision.enabled=false;copilot=true;used_copilot=true;control=Vector3.ZERO
	gear_override=1;flaps_override=2
	# A deliberate short demo transition to SFO final, retaining sortie score.
	flight.spawn_airborne(Vector3(0,49,2100),65)
	flight.heading=0;flight.roll=0;flight.pitch=-atan(Approach.GLIDESLOPE)
	flight.pitch_velocity=0;flight.roll_velocity=0;flight.yaw_velocity=0;flight.barrel_remaining=0
	flight.gear=true;flight.flaps=2;flight.throttle=.22;flight.engine=.3;flight.afterburner=false;flight.power_input=0
	if mission.active:mission.transition("approach")
	else:flight_kind="approach"
	fighter_fx.reset();camera_rig.reset();apply_aircraft_pose();camera_rig.update(.016)
	audio.radio.say("approach",2)

func approach_controls() -> Vector3:
	if not flight.airborne:
		flight.throttle = 1
		return Vector3(0,0.5 if flight.speed>flight.effective_rotation_speed() else 0,0)
	var approach_position := flight.position - Vector3(0,4,15400) if route_id=="sf" else flight.position
	var guidance: Dictionary = Approach.solution(approach_position)
	var heading: float = atan2(-flight.position.x,900)
	var error: float = wrapf(heading-flight.heading,-PI,PI)
	var wanted_pitch: float = clampf(-atan(Approach.GLIDESLOPE)+(float(guidance.ideal_height)-approach_position.y)*0.002,-0.15,0.08)
	if flight.position.y<14: wanted_pitch = -0.022 if flight.position.y>5 else -0.012
	flight.gear = true; flight.flaps = 2
	flight.throttle = clampf(0.22+(Tune.APPROACH_SPEED-flight.speed)*0.055,0,1)
	return Vector3(clampf((error*1.5-flight.roll)*1.8-flight.roll_velocity*0.3,-1,1),clampf((wanted_pitch-flight.pitch)*2.5-flight.pitch_velocity*0.3,-1,1),0)
func is_on_runway(at: Vector3) -> bool: return world.is_runway(at.x,at.z)
func approach_data() -> Dictionary: return Approach.solution(flight.position-Vector3(0,4,15400) if route_id=="sf" else flight.position)
func set_quality(high: bool) -> void:
	high_quality = high
	_apply_render_scale()
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().use_taa = high and RenderingServer.get_current_rendering_method()=="forward_plus"
	world.apply_quality(high)
	save_settings()
func _apply_render_scale() -> void:
	var width: float = maxf(get_window().size.x,1)
	get_viewport().scaling_3d_scale = minf(1.0,(1600.0 if high_quality else 1280.0)/width)
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg")==OK:
		high_quality = bool(config.get_value("video","spectre_quality",true))
		route_id = str(config.get_value("world","spectre_route_v10","sf"))
		best_score = int(config.get_value("arcade","best_score_v09",0))
func save_settings() -> void:
	if DisplayServer.get_name()=="headless": return
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("video","spectre_quality",high_quality)
	config.set_value("arcade","best_score_v09",best_score)
	config.set_value("world","spectre_route_v10",route_id)
	if is_instance_valid(audio): config.set_value("audio","muted",audio.muted)
	config.save("user://settings.cfg")

func select_route(value: String) -> void:
	if value==route_id: return
	route_id = value
	if is_instance_valid(world): remove_child(world); world.queue_free()
	world = SanFrancisco.new() if route_id=="sf" else Coast.new() if route_id=="coast" else World.new()
	add_child(world); world.set_conditions("golden"); world.apply_quality(high_quality)
	world.visible = mode!="title"
	save_settings()

func _exit_tree() -> void:
	tutorial.stop()
	badge.close()

## What the cockpit's panoramic display shows beyond raw flight data.
func tactical_state() -> Dictionary:
	var contacts: Array[Vector3] = []
	var boss := -1.0
	for enemy: Dictionary in combat.enemies:
		var delta: Vector3 = enemy.position-flight.position
		var relative: Vector2 = Vector2(delta.x,delta.z).rotated(-flight.heading)
		var important: bool = enemy.id==combat.boss_id or enemy.id==combat.target_id
		contacts.append(Vector3(relative.x,relative.y,1.0 if important else 0.0))
		if enemy.id==combat.boss_id and not combat.boss_defeated: boss = clampf(enemy.health/enemy.max_health,0,1)
	var waypoint := Vector2.ZERO
	if mission.active and mission.phase in ["opening","combat","return"]:
		var target: Vector3 = mission.route_target()-flight.position
		waypoint = Vector2(target.x,target.z).rotated(-flight.heading)
	return {"gun":primary_latched or combat.beam_active,"missiles":salvo_latched,"tracking":combat.target_id>=0 and combat.assist,
		"lock":combat.lock_progress,"contacts":contacts,"boss":boss,"waypoint":waypoint,"damaged":combat.hull<=65,
		"objective":hud.mission_line(),"clock":hud.clock_text()}
