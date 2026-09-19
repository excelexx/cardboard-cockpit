extends Node3D

const Catalog = preload("res://data/aircraft.gd")
const Dynamics = preload("res://systems/flight_dynamics.gd")
const Hud = preload("res://ui/hud.gd")
const Hangar = preload("res://scenes/hangar.gd")
const World = preload("res://scenes/world.gd")
const Audio = preload("res://systems/engine_audio.gd")
const Vision = preload("res://systems/vision_client.gd")
const Cockpit = preload("res://scenes/cockpit.gd")
const Visuals = preload("res://systems/aircraft_visuals.gd")
const Campaign = preload("res://systems/campaign.gd")
const Fantasy = preload("res://systems/fantasy_aircraft.gd")
const Combat = preload("res://systems/combat.gd")
const Approach = preload("res://systems/approach_guidance.gd")
const CHECKPOINTS: Array[Vector3] = [Vector3(0,180,-2000),Vector3(-450,420,-4200),Vector3(450,650,-6500),Vector3(150,420,-9000),Vector3(0,200,-11800)]
const RING_RADIUS: float = 280.0

var campaign_profile: Dictionary = {}
var showcase_mode := true
var developer_mode := false
var combat: CombatDirector
var mode := "hangar"
var resume_mode := "flight"
var flight_kind := "valley"
var conditions := "golden"
var expanded_hud := false
var aircraft_visuals: Node3D
var touchdown_valid := false
var selected: int = 0
var flight: FlightDynamics = Dynamics.new()
var vision: VisionClient = Vision.new()
var world: Node3D
var hangar: AircraftHangar
var aircraft: Node3D
var preview: Node3D
var camera: Camera3D
var cockpit_frame: Node3D
var hud: CockpitHUD
var audio: EngineAudio
var ring_nodes: Array[Node3D] = []
var ring_index: int = 0
var copilot := false
var used_copilot := false
var cockpit := true
var spectator := false
var help_visible := false
var calibration_visible := false
var credits_visible := false
var high_quality := false
var mission_success := false
var result_reason := ""
var toast := ""
var toast_time: float = 0.0
var hangar_angle: float = 2.40
var hangar_zoom: float = 1.0
var look := Vector2.ZERO
var mouse_yoke := false
var control := Vector3.ZERO
var runtime: float = 0.0
var capture_at: float = -1
var capture_file := ""
var test_mode := false
var test_finished := false
var test_limit: float = 500.0
var auto_capture_index: int = 0
var hangar_environment := Environment.new()

func profile() -> Dictionary:
	return campaign_profile if not campaign_profile.is_empty() else Catalog.PLANES[selected]

func _ready() -> void:
	get_window().title = "Cardboard Cockpit — Flight Experience"
	load_settings()
	world = World.new()
	add_child(world)
	world.set_conditions(conditions)
	hangar = Hangar.new()
	hangar.position = Vector3(50000,0,0)
	add_child(hangar)
	hangar.build()
	camera = Camera3D.new()
	camera.far = 38000
	camera.near = 0.5
	camera.fov = 65
	add_child(camera)
	camera.current = true
	hangar_environment.background_mode = Environment.BG_COLOR
	hangar_environment.background_color = Color(0.08,0.12,0.16)
	hangar_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	hangar_environment.ambient_light_color = Color(0.65,0.76,0.88)
	hangar_environment.ambient_light_energy = 0.7
	hangar_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	aircraft = Node3D.new()
	add_child(aircraft)
	create_cockpit()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.app = self
	layer.add_child(hud)
	hud.action.connect(on_action)
	hud.select_aircraft.connect(select_plane)
	audio = Audio.new()
	add_child(audio)
	combat = Combat.new()
	combat.app = self
	add_child(combat)
	var saved := ConfigFile.new()
	if saved.load("user://settings.cfg") == OK:
		audio.muted = bool(saved.get_value("audio","muted",false))
	build_rings()
	select_plane(selected)
	set_quality(high_quality)
	flight.reset(profile())
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_file = arg.trim_prefix("--capture=")
			capture_at = 4.0
		if arg.begins_with("--capture-at="):
			capture_at = maxf(1.0,arg.trim_prefix("--capture-at=").to_float())
		if arg.begins_with("--plane="):
			select_plane(clampi(arg.trim_prefix("--plane=").to_int(),0,Catalog.PLANES.size()-1))
		if arg.begins_with("--conditions="):
			conditions = arg.trim_prefix("--conditions=")
			world.set_conditions(conditions)
		if arg.begins_with("--kind="):
			flight_kind = arg.trim_prefix("--kind=")
		if arg == "--briefing":
			mode = "briefing"
		if arg == "--flight":
			start_flight()
		if arg == "--copilot":
			copilot = true
			used_copilot = true
		if arg == "--autotest":
			test_mode = true
			Engine.max_fps = 0
			start_flight()
			copilot = true
			used_copilot = true
		if arg == "--chase":
			cockpit = false
		if arg == "--airborne":
			start_flight()
			flight.position = Vector3(0,350,-4000)
			flight.speed = 150
			flight.throttle = 0.8
			flight.engine = 0.8
			flight.airborne = true
			flight.ever_airborne = true
			flight.airborne_time = 30
	if OS.get_cmdline_user_args().is_empty() and DisplayServer.get_name()!="headless": mode = "title"
	update_camera(1.0)

func select_plane(index: int) -> void:
	campaign_profile.clear()
	selected = index
	if is_instance_valid(preview):
		preview.queue_free()
	preview = load_plane()
	hangar.pedestal.add_child(preview)
	preview.position.y = 3.0
	# All previews share the same meter scale and camera distance.
	hangar_zoom = 1.0
	hangar_angle = 2.40
	save_settings()

func load_plane() -> Node3D:
	var id: String = str(profile().id)
	if id in ["trainer","vx9","falcon"]: return Fantasy.create(id)
	var path: String = "res://assets/aircraft/%s/%s.tscn" % [id,id]
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var model: Node3D = scene.instantiate() as Node3D
		var metadata_path := "res://assets/aircraft/%s/manifest.json" % id
		if FileAccess.file_exists(metadata_path):
			var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
			var dimensions: Dictionary = metadata.dimensions
			model.scale = Vector3(float(profile().span)/float(dimensions.wingspan),1.0,float(profile().length)/float(dimensions.length))
		return model
	# Only used while an asset is importing; imported web models are the shipped fleet.
	var placeholder := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 2
	mesh.height = 35
	placeholder.mesh = mesh
	placeholder.rotation.x = PI/2
	return placeholder

func build_rings() -> void:
	for i: int in CHECKPOINTS.size():
		var ring := Node3D.new()
		ring.position = CHECKPOINTS[i]
		var mesh_instance := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = RING_RADIUS-4
		mesh.outer_radius = RING_RADIUS+4
		mesh.rings = 96
		mesh.ring_segments = 8
		mesh_instance.mesh = mesh
		mesh_instance.rotation.x = PI/2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1,0.64,0.22)
		mat.emission_enabled = true
		mat.emission = Color(1,0.48,0.10)
		mat.emission_energy_multiplier = 2.5
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_instance.material_override = mat
		ring.add_child(mesh_instance)
		var label := Label3D.new()
		label.text = "%02d" % (i+1)
		label.font_size = 96
		label.pixel_size = 0.65
		label.position.y = RING_RADIUS+42
		label.modulate = Color(1,0.76,0.43)
		ring.add_child(label)
		add_child(ring)
		ring_nodes.append(ring)
	update_rings()

func update_rings() -> void:
	for i: int in ring_nodes.size():
		ring_nodes[i].visible = mode != "hangar" and mode != "briefing" and i >= ring_index and flight_kind == "valley"
		var mesh: MeshInstance3D = ring_nodes[i].get_child(0)
		var mat: StandardMaterial3D = mesh.material_override
		mat.albedo_color = Color(1,0.68,0.30) if i == ring_index else Color(0.5,0.7,0.75)
		mat.emission_energy_multiplier = 2.2 if i == ring_index else 0.6

func start_flight() -> void:
	campaign_profile.clear()
	if (flight_kind=="campaign") != (combat is GooseCampaign):
		remove_child(combat)
		combat.queue_free()
		combat = Campaign.new() if flight_kind=="campaign" else Combat.new()
		combat.app = self
		add_child(combat)
	if flight_kind == "combat" and str(profile().id)!="f35":
		select_plane(1)
	help_visible = false
	calibration_visible = false
	credits_visible = false
	for child: Node in aircraft.get_children():
		child.queue_free()
	var model: Node3D = load_plane()
	aircraft.add_child(model)
	aircraft_visuals = Visuals.new()
	aircraft.add_child(aircraft_visuals)
	aircraft_visuals.initialize(model,profile())
	cockpit_frame.build(profile())
	var tune: Dictionary = profile().duplicate()
	tune.clearance = 3.0
	flight.reset(tune)
	audio.set_aircraft(profile())
	mode = "flight"
	ring_index = 0
	copilot = false
	used_copilot = false
	mission_success = false
	look = Vector2.ZERO
	toast_time = 0
	control = Vector3.ZERO
	touchdown_valid = false
	combat.reset(flight_kind in ["combat","campaign"])
	if flight_kind == "combat":
		flight.position = Vector3(0,650,-3500)
		flight.speed = 145
		flight.throttle = 0.5
		flight.engine = 0.5
		flight.airborne = true
		flight.ever_airborne = true
		flight.airborne_time = 30
		flight.gear = false
		cockpit = false
	if flight_kind == "approach":
		ring_index = 5
		flight.position = Vector3(0,155,-11200)
		flight.speed = float(profile().rotation_speed)*1.25
		flight.throttle = 0.32
		flight.engine = 0.32
		flight.airborne = true
		flight.ever_airborne = true
		flight.airborne_time = 30.0
		flight.pitch = -atan(Approach.GLIDESLOPE)
		flight.flaps = 2
	update_rings()
	update_camera(1.0)

func overlay_visible() -> bool:
	return help_visible or calibration_visible or credits_visible

func _notification(what: int) -> void:
	# Never leave an aircraft flying unattended after switching apps.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode in ["flight", "rollout", "ejected"] and not test_mode and capture_file.is_empty():
		resume_mode = mode
		mode = "paused"
		look = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Overlays own input. Gameplay shortcuts must not mutate the hidden
		# flight or advance the hangar while the pilot is reading instructions.
		if overlay_visible() and event.keycode not in [KEY_ESCAPE, KEY_F1, KEY_C, KEY_M, KEY_Q]:
			return
		if mode == "flight":
			var physical: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			if physical in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D]:
				take_manual_control(true)
			elif physical in [KEY_W, KEY_S]:
				take_manual_control(false)
		if mode == "flight":
			if event.keycode == KEY_SHIFT:
				if flight.start_barrel_roll(-1 if control.x<0 else 1): show_toast("BARREL ROLL")
			if flight_kind == "combat":
				if event.keycode == KEY_T: combat.fire_missile()
				if event.keycode == KEY_Z: combat.deploy_flares()
				if event.keycode == KEY_J: combat.assist = not combat.assist
		if combat is GooseCampaign and mode=="flight":
			if event.keycode==KEY_F9:
				combat.developer = not combat.developer
				developer_mode = combat.developer
			if combat.developer:
				if event.keycode==KEY_N: combat.skip_to(combat.wave % 6)
				if event.keycode>=KEY_1 and event.keycode<=KEY_6: combat.skip_to(event.keycode-KEY_1)
		match event.keycode:
			KEY_F1: on_action("help")
			KEY_F2: expanded_hud = not expanded_hud
			KEY_F:
				if mode == "flight":
					flight.flaps = (flight.flaps+1)%3
					show_toast("Flaps " + ["UP","15°","30°"][flight.flaps])
			KEY_M: on_action("mute")
			KEY_ENTER:
				if mode == "title": on_action("demo")
				elif mode == "hangar": on_action("brief")
				elif mode == "briefing": on_action("fly")
				elif mode == "results": on_action("restart")
			KEY_ESCAPE:
				if credits_visible: credits_visible = false
				elif help_visible: help_visible = false
				elif calibration_visible: calibration_visible = false
				elif mode in ["flight","rollout","ejected"]:
					resume_mode = mode
					mode = "paused"
				elif mode == "paused": mode = resume_mode
				elif mode == "briefing": mode = "hangar"
			KEY_V: cockpit = not cockpit
			KEY_TAB: spectator = not spectator
			KEY_C: on_action("calibration")
			KEY_Q: set_quality(not high_quality)
			KEY_B:
				mouse_yoke = not mouse_yoke
				show_toast("Mouse yoke enabled" if mouse_yoke else "Keyboard yoke enabled")
			KEY_G:
				if mode == "flight":
					flight.gear = not flight.gear
					show_toast("Landing gear DOWN" if flight.gear else "Landing gear UP")
			KEY_R:
				if mode in ["flight","paused","results","rollout"]: start_flight()
			KEY_H:
				if mode == "flight":
					copilot = not copilot
					used_copilot = used_copilot or copilot
					show_toast("Training copilot engaged" if copilot else "You have control")
			KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6:
				if mode == "hangar": select_plane(event.keycode-KEY_1)
	if overlay_visible():
		return
	if event is InputEventMouseMotion:
		if mode == "hangar" and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and event.position.y<735:
			hangar_angle += event.relative.x*0.006
		if mode in ["flight","rollout"] and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			look.x = clampf(look.x-event.relative.x*0.003,-1.5,1.5)
			look.y = clampf(look.y-event.relative.y*0.003,-0.8,0.8)
	if event is InputEventMouseButton and mode == "hangar":
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: hangar_zoom = maxf(0.65,hangar_zoom-0.06)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: hangar_zoom = minf(1.45,hangar_zoom+0.06)

func on_action(action: String) -> void:
	if action=="brief_campaign":
		flight_kind = "campaign"
		mode = "briefing"
		return
	if action=="showcase":
		showcase_mode = not showcase_mode
		return
	if action=="developer":
		developer_mode = not developer_mode
		return
	if action=="demo":
		flight_kind = "campaign"
		showcase_mode = true
		start_flight()
		return
	if action.begins_with("weather_"):
		conditions = action.trim_prefix("weather_")
		world.set_conditions(conditions)
		save_settings()
		return
	if action.begins_with("kind_"):
		flight_kind = action.trim_prefix("kind_")
		return
	match action:
		"brief": mode = "briefing"
		"fly", "restart": start_flight()
		"hangar":
			campaign_profile.clear()
			mode = "hangar"
			help_visible = false
			calibration_visible = false
			credits_visible = false
			update_rings()
		"resume": mode = resume_mode
		"help":
			help_visible = not help_visible
			calibration_visible = false
			credits_visible = false
		"credits": credits_visible = not credits_visible
		"calibration":
			calibration_visible = not calibration_visible
			help_visible = false
			credits_visible = false
		"vision":
			vision.enabled = not vision.enabled
			if not vision.enabled: vision.status = "KEYBOARD / MOUSE"
		"mute":
			audio.muted = not audio.muted
			save_settings()

func _process(dt: float) -> void:
	runtime += dt
	toast_time = maxf(0,toast_time-dt)
	vision.poll(dt)
	if mode == "hangar":
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): hangar_angle += dt*0.025
	update_camera(dt)
	var active: bool = mode in ["flight","rollout"] and not overlay_visible()
	if is_instance_valid(aircraft_visuals):
		aircraft_visuals.update_visuals(dt if active else 0.0,flight,control)
	if cockpit and mode not in ["hangar","briefing"]:
		cockpit_frame.set_navigation(flight_kind,ring_index)
		cockpit_frame.update_instruments(flight,control,dt if active else 0.0)
	audio.update(flight.engine,flight.speed,active)
	audio.campaign_audio(flight_kind=="campaign" and mode in ["flight","results"])
	if capture_at>0 and runtime>=capture_at:
		capture_at = -1
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_file)
		print("SCREENSHOT: "+capture_file)
		if not test_mode: get_tree().quit()
	if test_mode and not test_finished and flight.elapsed>test_limit:
		print("AUTOTEST TIMEOUT: ",flight.position," ring=",ring_index)
		test_finished = true
		get_tree().quit(2)

func _physics_process(dt: float) -> void:
	if overlay_visible():
		return
	if mode == "ejected":
		combat.tick_ejection(dt)
		return
	if mode == "rollout":
		var steering: float = float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
		var brakes: bool = copilot or Input.is_physical_key_pressed(KEY_SPACE)
		flight.rollout_step(dt,brakes,steering,is_on_runway(flight.position))
		if not is_on_runway(flight.position): flight.contact = "overrun"
		aircraft.position = flight.position
		aircraft.rotation = Vector3(0,-flight.heading,0)
		if flight.contact=="overrun" or flight.speed<=0.1:
			if flight.speed<=0.1: flight.speed = 0.0
			finish_mission()
		return
	if mode != "flight":
		return
	if str(profile().id)=="f35" and flight.airborne:
		combat.eject_hold = combat.eject_hold+dt if Input.is_physical_key_pressed(KEY_E) else 0.0
		if combat.eject_hold>=1.0 and combat.eject(): return
	if flight_kind in ["combat","campaign"]:
		combat.tick(dt)
		if mode!="flight": return
		if Input.is_physical_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): combat.fire_gun()
		if vision.enabled and vision.tracking: copilot = false
		combat.cardboard_controls()
		if copilot and combat.lock_progress>=1:
			combat.fire_gun()
			combat.fire_missile()
	var keyboard := Vector3(float(Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_DOWN)),float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)))
	var throttle_delta: float = float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))
	if keyboard.length()>0 or throttle_delta!=0:
		take_manual_control(keyboard.length() > 0)
	if copilot:
		control = pilot_controls()
	else:
		var target_control: Vector3 = keyboard
		if mouse_yoke and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			var mouse: Vector2 = (get_viewport().get_mouse_position()-Vector2(800,435))/Vector2(450,300)
			target_control.x = clampf(mouse.x,-1,1)
			target_control.y = clampf(-mouse.y,-1,1)
		if vision.enabled and vision.tracking and keyboard.length()==0:
			target_control.x = vision.yoke.x
			target_control.y = vision.yoke.y
		if vision.enabled and vision.throttle_confidence>0.4:
			flight.throttle = move_toward(flight.throttle,vision.throttle,dt*0.8)
		flight.throttle = clampf(flight.throttle+throttle_delta*dt*0.30,0,1)
		control = control.lerp(target_control,1.0-exp(-dt*8.0))
	var prior: Vector3 = flight.position
	var ground: float = world.ground_height(flight.position.x,flight.position.z)
	var on_runway: bool = world.is_runway(flight.position.x, flight.position.z)
	var was_airborne: bool = flight.airborne
	flight.step(dt,control,Input.is_physical_key_pressed(KEY_SPACE),ground,on_runway,false)
	# Resolve against the surface reached by this frame, including runway edges
	# and rising terrain, rather than the point the aircraft just left.
	flight.resolve_contact(world.ground_height(flight.position.x, flight.position.z), world.is_runway(flight.position.x, flight.position.z))
	if flight.airborne and not was_airborne:
		show_toast("Positive climb. Welcome to the sky.")
		audio.ping()
	if flight.airborne and world.obstacle_collision(flight.position,2.5):
		flight.contact = "obstacle"
	if flight.contact == "landed":
		touchdown_valid = (flight_kind=="free" or ring_index==5) and (flight_kind=="free" or absf(flight.position.z+15000)<1600)
		mode = "rollout"
		flight.throttle = 0.0
		show_toast("Touchdown. Hold SPACE to brake to a stop.")
		audio.ping()
	elif flight.contact != "":
		finish_mission()
	if ring_index<CHECKPOINTS.size() and flight.airborne and flight_kind == "valley":
		var target: Vector3 = CHECKPOINTS[ring_index]
		if not is_equal_approx(prior.z, flight.position.z) and (prior.z-target.z)*(flight.position.z-target.z) <= 0.0:
			var fraction: float = inverse_lerp(prior.z,flight.position.z,target.z)
			var crossing: Vector3 = prior.lerp(flight.position,clampf(fraction,0,1))
			if Vector2(crossing.x-target.x,crossing.y-target.y).length()<RING_RADIUS:
				ring_index += 1
				show_toast("Checkpoint %d / 5  ·  Nice flying." % ring_index if ring_index<5 else "All checkpoints cleared. North Field is ahead.")
				audio.ping()
				update_rings()
				if test_mode: print("AUTOTEST CHECKPOINT ",ring_index," t=",flight.elapsed," pos=",flight.position)
	if flight.position.length()>80000 or flight.position.y>14000:
		flight.contact = "boundary"
		finish_mission()
	aircraft.position = flight.position
	aircraft.rotation = Vector3(flight.pitch,-flight.heading,-flight.roll)

func take_manual_control(steering: bool) -> void:
	if copilot:
		show_toast("You have control")
	copilot = false
	if steering:
		mouse_yoke = false
	vision.enabled = false
	vision.status = "KEYBOARD / MOUSE"

func pilot_controls() -> Vector3:
	if flight_kind in ["combat","campaign"]: return combat.pilot_controls()
	var target: Vector3 = target_position()
	var desired_speed: float = 115.0
	if not flight.airborne:
		flight.throttle = 1.0
		return Vector3(0,0.7 if flight.speed>flight.effective_rotation_speed() else 0,0)
	if ring_index>=5 or flight_kind == "free":
		var guidance: Dictionary = Approach.solution(flight.position)
		target = Vector3(0,float(guidance.ideal_height),flight.position.z-800)
		desired_speed = maxf(float(profile().rotation_speed)*1.14,65.0)
		flight.gear = true
		flight.flaps = 2
	else:
		flight.gear = flight.airborne_time<10
	var delta: Vector3 = target-flight.position
	var desired_heading: float = atan2(delta.x,maxf(-delta.z,850.0))
	var heading_error: float = wrapf(desired_heading-flight.heading,-PI,PI)
	var desired_roll: float = clampf(heading_error*2.0,-0.55,0.55)
	var desired_pitch: float = clampf(atan2(delta.y,maxf(Vector2(delta.x,delta.z).length(),300)),-0.15,0.23)
	if ring_index>=5 or flight_kind == "free":
		var approach: Dictionary = Approach.solution(flight.position)
		desired_pitch = clampf(-atan(Approach.GLIDESLOPE)+(float(approach.ideal_height)-flight.position.y)*0.002,-0.15,0.05)
		if flight.position.y<14.0:
			desired_pitch = -0.025 if flight.position.y>5.0 else -0.015
	var pitch_input: float = clampf((desired_pitch-flight.pitch)*5.5,-1,1)
	var roll_input: float = clampf((desired_roll-flight.roll)*4.0,-1,1)
	flight.throttle = clampf(0.20+(desired_speed-flight.speed)*0.045,0,1)
	return Vector3(roll_input,pitch_input,0)

func target_position() -> Vector3:
	if flight_kind in ["combat","campaign"]:
		var enemy: Dictionary = combat.target()
		return enemy.position if not enemy.is_empty() else flight.position+combat.forward()*1500
	return CHECKPOINTS[ring_index] if ring_index<5 and flight_kind=="valley" else Vector3(0,3,Approach.AIM_Z)

func phase_label() -> String:
	if flight_kind in ["combat","campaign"]: return "SKY SHIELD · INTERCEPTION"
	if mode == "hangar": return "HANGAR"
	if mode=="rollout" or (mode=="paused" and resume_mode=="rollout"): return "ROLLOUT · BRAKE TO A STOP"
	if flight_kind=="free" and flight.airborne: return "FREE FLIGHT · EXPLORE THE VALLEY"
	if not flight.ever_airborne: return "RUNWAY 36 · CLEARED FOR DEPARTURE"
	if ring_index>=5 or flight_kind == "free": return "FINAL APPROACH · NORTH FIELD"
	return "AIRBORNE · VALLEY CHECKPOINTS"

func flight_prompt() -> String:
	if mode=="ejected": return "EJECTION SUCCESSFUL · PARACHUTE DEPLOYED"
	if flight_kind in ["combat","campaign"]: return "SPACE fire · T missile · Z flares · SHIFT roll · Hold E eject"
	if mode=="rollout": return "Power idle  ·  Hold SPACE to brake  ·  A / D to stay centered"
	if flight.contact!="": return "Flight complete"
	if flight.stall_time>0.8: return "LOW AIRSPEED  ·  Add power and lower the nose gently"
	if not flight.airborne:
		if flight.speed<flight.effective_rotation_speed(): return "Hold W for power  ·  Rotate at %d knots" % int(flight.effective_rotation_speed()*1.94384)
		return "ROTATE  ·  Hold ↑ gently to take off"
	if flight_kind == "free": return "Explore the valley  ·  Land at either airport whenever you are ready"
	if ring_index>=5:
		if not flight.gear: return "FINAL APPROACH  ·  Press G to lower landing gear"
		return "Follow the approach diamonds  ·  F for flaps  ·  Aim for %d knots" % int(maxf(float(profile().rotation_speed)*1.14,65.0)*1.94384)
	if flight.position.z < CHECKPOINTS[ring_index].z-500: return "Checkpoint behind you  ·  Turn back, or press R to restart"
	if flight.position.y-world.ground_height(flight.position.x,flight.position.z)<45: return "LOW ALTITUDE  ·  Gently raise the nose"
	return "Follow the amber rings  ·  Checkpoint %d of 5" % (ring_index+1)

func finish_mission() -> void:
	mission_success = flight.contact=="landed" and touchdown_valid and flight.speed<=0.1 and is_on_runway(flight.position)
	if mission_success:
		result_reason = "Landing complete. Aircraft stopped safely."
		if flight_kind=="valley": result_reason += " Five checkpoints cleared."
		elif flight_kind=="free": result_reason = "Scenic flight complete. Parked safely after landing."
	elif flight.contact=="overrun": result_reason = "Runway overrun. Touch down earlier and hold SPACE to brake."
	elif flight.contact=="obstacle": result_reason = "Aircraft contacted an airport building. Keep clear of structures."
	elif flight.contact=="landed": result_reason = "Safe touchdown. Complete all checkpoints and land at North Field."
	elif flight.contact=="excursion": result_reason = "Runway excursion. Use A / D to stay centered during takeoff."
	elif flight.contact=="boundary": result_reason = "You left the flight area. Restart and follow the amber valley route."
	else: result_reason = "Unsafe landing. Approach gently with level wings and gear down."
	mode = "results"
	audio.ping()
	if test_mode and not test_finished:
		test_finished = true
		print("AUTOTEST RESULT: ","PASS" if mission_success else "FAIL"," plane=",profile().id," rings=",ring_index," seconds=",flight.elapsed," position=",flight.position," speed=",flight.touchdown_speed," sink=",flight.touchdown_sink," contact=",flight.contact)
		get_tree().quit(0 if mission_success else 1)

func show_toast(message: String) -> void:
	toast = message
	toast_time = 4.0

func update_camera(dt: float) -> void:
	if mode=="ejected" and is_instance_valid(combat.parachute):
		camera.environment = null
		cockpit_frame.set_presentation_visible(false)
		aircraft.visible = true
		camera.position = combat.eject_position+Vector3(15,8,22)
		camera.look_at(combat.eject_position+Vector3(0,3,0))
		return
	if mode in ["hangar","briefing","title"]:
		camera.environment = hangar_environment
		camera.near = 0.5
		aircraft.visible = false
		hangar.visible = true
		cockpit_frame.set_presentation_visible(false)
		var orbit := Vector3(sin(hangar_angle)*110,30,cos(hangar_angle)*110)*hangar_zoom
		camera.position = hangar.position+orbit
		var screen_right := Vector3(cos(hangar_angle),0,-sin(hangar_angle))
		camera.look_at(hangar.position+Vector3(0,7,0)-screen_right*19.0)
		camera.fov = 58
	else:
		camera.environment = null
		aircraft.visible = not cockpit
		hangar.visible = false
		cockpit_frame.set_presentation_visible(cockpit)
		var plane_basis := Basis.from_euler(Vector3(flight.pitch,-flight.heading,-flight.roll))
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): look = look.lerp(Vector2.ZERO,1-exp(-dt*2.0))
		if cockpit:
			camera.near = 0.05
			camera.position = flight.position+plane_basis*Vector3(0,3.0,-float(profile().length)*0.29)
			camera.basis = plane_basis * Basis.from_euler(Vector3(look.y,look.x,0))
			cockpit_frame.basis = Basis.from_euler(Vector3(look.y,look.x,0)).inverse()
			camera.fov = 77
		else:
			camera.near = 0.5
			var length: float = maxf(float(profile().length),30.0)
			var height: float = length*0.50+12.0 if flight_kind=="campaign" else length*0.22+6.0
			var offset := Vector3(sin(look.x)*length*1.15,height+look.y*15.0,cos(look.x)*length*1.05)
			var wanted: Vector3 = flight.position+Basis(Vector3.UP,-flight.heading)*offset
			camera.position = camera.position.lerp(wanted,1-exp(-dt*5)) if camera.position.distance_to(wanted)<1000 else wanted
			camera.look_at(flight.position+plane_basis*Vector3(0,3,-length*0.30))
			camera.fov = 65

func create_cockpit() -> void:
	cockpit_frame = Cockpit.new()
	camera.add_child(cockpit_frame)
	cockpit_frame.build(profile())

func is_on_runway(at: Vector3) -> bool:
	return absf(at.x)<50.0 and (absf(at.z)<1600.0 or absf(at.z+15000.0)<1600.0)

func approach_data() -> Dictionary:
	return Approach.solution(flight.position)

func flight_kind_label() -> String:
	return {"valley":"VALLEY MISSION","approach":"LANDING PRACTICE","free":"FREE FLIGHT"}.get(flight_kind,"VALLEY MISSION")

func set_quality(high: bool) -> void:
	high_quality = high
	get_viewport().scaling_3d_scale = 1.0 if high else 0.8
	get_viewport().msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_2X
	save_settings()

func load_settings() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://settings.cfg") == OK:
		selected = clampi(int(settings.get_value("flight","aircraft",0)),0,Catalog.PLANES.size()-1)
		high_quality = bool(settings.get_value("video","high_quality",false))
		conditions = str(settings.get_value("world","conditions","golden"))

func save_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("flight","aircraft",selected)
	settings.set_value("video","high_quality",high_quality)
	settings.set_value("world","conditions",conditions)
	if is_instance_valid(audio): settings.set_value("audio","muted",audio.muted)
	settings.save("user://settings.cfg")

func apply_campaign_aircraft(tune: Dictionary) -> void:
	campaign_profile = tune.duplicate(true)
	for child: Node in aircraft.get_children():
		aircraft.remove_child(child)
		child.queue_free()
	var model: Node3D = load_plane()
	aircraft.add_child(model)
	aircraft_visuals = Visuals.new()
	aircraft.add_child(aircraft_visuals)
	aircraft_visuals.initialize(model,profile())
	cockpit_frame.build(profile())
	flight.reset(tune)
	flight.position = Vector3(0,700,-3500)
	flight.speed = 110 if str(tune.id)=="trainer" else 140
	flight.throttle = 0.4
	flight.engine = 0.4
	flight.airborne = true
	flight.ever_airborne = true
	flight.airborne_time = 30
	flight.gear = false
	control = Vector3.ZERO
	cockpit = false
	audio.set_aircraft(profile())
	update_camera(1.0)
