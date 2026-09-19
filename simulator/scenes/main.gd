extends Node3D

const Catalog = preload("res://data/aircraft.gd")
const Dynamics = preload("res://systems/flight_dynamics.gd")
const Hud = preload("res://ui/hud.gd")
const Hangar = preload("res://scenes/hangar.gd")
const World = preload("res://scenes/world.gd")
const Audio = preload("res://systems/engine_audio.gd")
const Vision = preload("res://systems/vision_client.gd")
const CHECKPOINTS: Array[Vector3] = [Vector3(0,180,-2000),Vector3(-450,420,-4200),Vector3(450,650,-6500),Vector3(150,420,-9000),Vector3(0,200,-11800)]
const RING_RADIUS: float = 280.0

var mode := "hangar"
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
	return Catalog.PLANES[selected]

func _ready() -> void:
	get_window().title = "Cardboard Cockpit — Flight Experience"
	load_settings()
	world = World.new()
	add_child(world)
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
			select_plane(clampi(arg.trim_prefix("--plane=").to_int(),0,4))
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
	update_camera(1.0)

func select_plane(index: int) -> void:
	selected = index
	if is_instance_valid(preview):
		preview.queue_free()
	preview = load_plane()
	hangar.pedestal.add_child(preview)
	preview.position.y = 3.0
	# Keep the fighter visually substantial while respecting real proportions in flight.
	var factor: float = clampf(66.0 / maxf(float(profile().span),float(profile().length)),0.85,3.6)
	preview.scale = Vector3.ONE * factor
	preview.position.y = 3.0 * factor
	hangar_angle = 2.40
	save_settings()

func load_plane() -> Node3D:
	var id: String = str(profile().id)
	var path: String = "res://assets/aircraft/%s/%s.tscn" % [id,id]
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		return scene.instantiate() as Node3D
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
		ring_nodes[i].visible = mode != "hangar" and mode != "briefing" and i >= ring_index
		var mesh: MeshInstance3D = ring_nodes[i].get_child(0)
		var mat: StandardMaterial3D = mesh.material_override
		mat.albedo_color = Color(1,0.68,0.30) if i == ring_index else Color(0.5,0.7,0.75)
		mat.emission_energy_multiplier = 2.2 if i == ring_index else 0.6

func start_flight() -> void:
	help_visible = false
	calibration_visible = false
	credits_visible = false
	for child: Node in aircraft.get_children():
		child.queue_free()
	aircraft.add_child(load_plane())
	var tune: Dictionary = profile().duplicate()
	tune.clearance = 3.0
	flight.reset(tune)
	mode = "flight"
	ring_index = 0
	copilot = false
	used_copilot = false
	mission_success = false
	look = Vector2.ZERO
	toast_time = 0
	control = Vector3.ZERO
	update_rings()
	update_camera(1.0)

func overlay_visible() -> bool:
	return help_visible or calibration_visible or credits_visible

func _notification(what: int) -> void:
	# Never leave an aircraft flying unattended after switching apps.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == "flight" and not test_mode:
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
		match event.keycode:
			KEY_F1: on_action("help")
			KEY_M: on_action("mute")
			KEY_ENTER:
				if mode == "hangar": on_action("brief")
				elif mode == "briefing": on_action("fly")
				elif mode == "results": on_action("restart")
			KEY_ESCAPE:
				if credits_visible: credits_visible = false
				elif help_visible: help_visible = false
				elif calibration_visible: calibration_visible = false
				elif mode == "flight": mode = "paused"
				elif mode == "paused": mode = "flight"
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
				if mode in ["flight","paused","results"]: start_flight()
			KEY_H:
				if mode == "flight":
					copilot = not copilot
					used_copilot = used_copilot or copilot
					show_toast("Training copilot engaged" if copilot else "You have control")
			KEY_1,KEY_2,KEY_3,KEY_4,KEY_5:
				if mode == "hangar": select_plane(event.keycode-KEY_1)
	if overlay_visible():
		return
	if event is InputEventMouseMotion:
		if mode == "hangar" and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and event.position.y<735:
			hangar_angle += event.relative.x*0.006
		if mode == "flight" and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			look.x = clampf(look.x-event.relative.x*0.003,-1.5,1.5)
			look.y = clampf(look.y-event.relative.y*0.003,-0.8,0.8)
	if event is InputEventMouseButton and mode == "hangar":
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: hangar_zoom = maxf(0.65,hangar_zoom-0.06)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: hangar_zoom = minf(1.45,hangar_zoom+0.06)

func on_action(action: String) -> void:
	match action:
		"brief": mode = "briefing"
		"fly", "restart": start_flight()
		"hangar":
			mode = "hangar"
			help_visible = false
			calibration_visible = false
			credits_visible = false
			update_rings()
		"resume": mode = "flight"
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
	audio.update(flight.engine,flight.speed,mode == "flight" and not overlay_visible())
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
	if mode != "flight" or overlay_visible():
		return
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
	if flight.contact != "":
		finish_mission()
	if ring_index<CHECKPOINTS.size() and flight.airborne:
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
	if aircraft.get_child_count()>0:
		var gear_node: Node3D = aircraft.get_child(aircraft.get_child_count()-1).get_node_or_null("Airframe/LandingGear")
		if gear_node: gear_node.visible = flight.gear

func take_manual_control(steering: bool) -> void:
	if copilot:
		show_toast("You have control")
	copilot = false
	if steering:
		mouse_yoke = false
	vision.enabled = false
	vision.status = "KEYBOARD / MOUSE"

func pilot_controls() -> Vector3:
	var target: Vector3 = target_position()
	var desired_speed: float = 115.0
	if not flight.airborne:
		flight.throttle = 1.0
		return Vector3(0,0.7 if flight.speed>float(profile().rotation_speed) else 0,0)
	if ring_index>=5:
		# Broad, forgiving glideslope to the destination runway.
		var remaining: float = -14250.0-flight.position.z
		target = Vector3(0,maxf(3.0,(-remaining)*0.055),flight.position.z-650)
		desired_speed = maxf(float(profile().rotation_speed)*1.06,70.0)
		flight.gear = true
		if flight.position.z < -13850:
			target.y = 2.4
			desired_speed = float(profile().rotation_speed)*1.03
	else:
		flight.gear = flight.airborne_time<10
	var delta: Vector3 = target-flight.position
	var desired_heading: float = atan2(delta.x,maxf(-delta.z,850.0))
	var heading_error: float = wrapf(desired_heading-flight.heading,-PI,PI)
	var desired_roll: float = clampf(heading_error*2.0,-0.55,0.55)
	var desired_pitch: float = clampf(atan2(delta.y,maxf(Vector2(delta.x,delta.z).length(),300)),-0.15,0.23)
	if ring_index>=5 and flight.position.z < -13850:
		desired_pitch = -0.035 if flight.position.y>5 else -0.012
	var pitch_input: float = clampf((desired_pitch-flight.pitch)*5.5,-1,1)
	var roll_input: float = clampf((desired_roll-flight.roll)*4.0,-1,1)
	flight.throttle = clampf(0.20+(desired_speed-flight.speed)*0.045,0,1)
	return Vector3(roll_input,pitch_input,0)

func target_position() -> Vector3:
	return CHECKPOINTS[ring_index] if ring_index<5 else Vector3(0,3,-14300)

func phase_label() -> String:
	if mode == "hangar": return "HANGAR"
	if not flight.ever_airborne: return "RUNWAY 36 · CLEARED FOR DEPARTURE"
	if ring_index>=5: return "FINAL APPROACH · NORTH FIELD"
	return "AIRBORNE · VALLEY CHECKPOINTS"

func flight_prompt() -> String:
	if flight.contact!="": return "Flight complete"
	if flight.stall_time>0.8: return "LOW AIRSPEED  ·  Add power and lower the nose gently"
	if not flight.airborne:
		if flight.speed<float(profile().rotation_speed): return "Hold W for power  ·  Rotate at %d knots" % int(float(profile().rotation_speed)*1.94384)
		return "ROTATE  ·  Hold ↑ gently to take off"
	if ring_index>=5:
		if not flight.gear: return "FINAL APPROACH  ·  Press G to lower landing gear"
		return "Reduce power  ·  Line up with runway 36  ·  Land below 200 knots"
	if flight.position.z < CHECKPOINTS[ring_index].z-500: return "Checkpoint behind you  ·  Turn back, or press R to restart"
	if flight.position.y-world.ground_height(flight.position.x,flight.position.z)<45: return "LOW ALTITUDE  ·  Gently raise the nose"
	return "Follow the amber rings  ·  Checkpoint %d of 5" % (ring_index+1)

func finish_mission() -> void:
	mission_success = flight.contact=="landed" and ring_index==5 and absf(flight.position.z+15000)<1600
	if mission_success:
		result_reason = "Smooth landing. All five checkpoints collected." if flight.touchdown_sink > -4 else "Safe arrival. All five checkpoints collected."
	elif flight.contact=="landed": result_reason = "Safe touchdown. Collect all five checkpoints and land at North Field to complete the route."
	elif flight.contact=="excursion": result_reason = "Runway excursion. Keep centered with A / D and rotate at the indicated speed."
	elif flight.contact=="boundary": result_reason = "You left the flight area. Restart and follow the amber valley route."
	else: result_reason = "Landing was too hard or outside a runway. Try less speed, level wings, and gear down."
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
	if mode in ["hangar","briefing"]:
		camera.environment = hangar_environment
		aircraft.visible = false
		hangar.visible = true
		cockpit_frame.visible = false
		var orbit := Vector3(sin(hangar_angle)*87,24,cos(hangar_angle)*87)*hangar_zoom
		camera.position = hangar.position+orbit
		var screen_right := Vector3(cos(hangar_angle),0,-sin(hangar_angle))
		camera.look_at(hangar.position+Vector3(0,7,0)-screen_right*19.0)
		camera.fov = 58
	else:
		camera.environment = null
		aircraft.visible = not cockpit
		hangar.visible = false
		cockpit_frame.visible = cockpit
		var plane_basis := Basis.from_euler(Vector3(flight.pitch,-flight.heading,-flight.roll))
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): look = look.lerp(Vector2.ZERO,1-exp(-dt*2.0))
		if cockpit:
			camera.position = flight.position+plane_basis*Vector3(0,3.0,-float(profile().length)*0.29)
			camera.basis = plane_basis * Basis.from_euler(Vector3(look.y,look.x,0))
			camera.fov = 77
		else:
			var length: float = maxf(float(profile().length),30.0)
			var offset := Vector3(sin(look.x)*length*1.15,length*0.22+6.0+look.y*15.0,cos(look.x)*length*1.05)
			var wanted: Vector3 = flight.position+Basis(Vector3.UP,-flight.heading)*offset
			camera.position = camera.position.lerp(wanted,1-exp(-dt*5)) if camera.position.distance_to(wanted)<1000 else wanted
			camera.look_at(flight.position+plane_basis*Vector3(0,3,-length*0.30))
			camera.fov = 65

func create_cockpit() -> void:
	cockpit_frame = Node3D.new()
	camera.add_child(cockpit_frame)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.025,0.038,0.046)
	mat.roughness = 0.65
	# A custom instrument hood and windshield pillars; model-specific study-level interiors are out of scope.
	for spec: Array in [[Vector3(0,-1.0,-1.7),Vector3(4.2,0.35,1.7)],[Vector3(-1.9,0,-1.9),Vector3(0.09,2.3,0.12)],[Vector3(1.9,0,-1.9),Vector3(0.09,2.3,0.12)],[Vector3(0,1.05,-1.9),Vector3(4.1,0.08,0.12)]]:
		var instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = spec[1]
		instance.mesh = mesh
		instance.position = spec[0]
		instance.material_override = mat
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cockpit_frame.add_child(instance)

func set_quality(high: bool) -> void:
	high_quality = high
	get_viewport().scaling_3d_scale = 1.0 if high else 0.8
	get_viewport().msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_2X
	save_settings()

func load_settings() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://settings.cfg") == OK:
		selected = clampi(int(settings.get_value("flight","aircraft",0)),0,4)
		high_quality = bool(settings.get_value("video","high_quality",false))

func save_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("flight","aircraft",selected)
	settings.set_value("video","high_quality",high_quality)
	if is_instance_valid(audio): settings.set_value("audio","muted",audio.muted)
	settings.save("user://settings.cfg")
