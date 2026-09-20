extends SceneTree
## Afterburner studio: a FAST standalone GPU harness for systems/fighter_effects.gd.
## No world load, no scenes/main.tscn - just the graded sunset sky and sun copied from
## scenes/san_francisco_world.gd, a dark water plane far below, the fighter, and
## FighterEffects driven by a stub app. Renders every burner state from every camera
## that matters so the look can be iterated without flying the mission.
##
##   Godot --path simulator --windowed --resolution 1600x1000 --script tests/studio_burner.gd
##   optional user args: a list of "<state>-<camera>" shot names, or "budget"
const Model = preload("res://systems/fighter_model.gd")
const Effects = preload("res://systems/fighter_effects.gd")
const Dynamics = preload("res://systems/flight_dynamics.gd")
const Visuals = preload("res://systems/aircraft_visuals.gd")
const Catalog = preload("res://data/aircraft.gd")
const SKY_YAW_DEGREES := -79.8
const SUN_ENERGY := 3.0

class StubCombat extends Node:
	var active := false
	var gun_firing_time := 0.0
	func assisted_direction() -> Vector3: return Vector3.FORWARD

class StubAudio extends Node:
	var muted := true
	func play_effect(_name: String, _db: float = 0.0, _pitch: float = 1.0) -> void: pass

class StubRig extends Node:
	func impulse(_amount: float) -> void: pass

class StubWorld extends Node3D:
	var sun: DirectionalLight3D
	var cloud_presence := 0.0

class StubApp extends Node3D:
	var aircraft: Node3D
	var flight: FlightDynamics
	var camera: Camera3D
	var world: StubWorld
	var combat: StubCombat
	var audio: StubAudio
	var camera_rig: StubRig
	var cockpit := false
	var mode := "flight"

var app: StubApp
var fx: FighterEffects
var visuals: AircraftVisuals
var folder := ""

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("STUDIO burner requires a native GPU"); quit(2); return
	folder = ProjectSettings.globalize_path("res://../build/burner")
	DirAccess.make_dir_recursive_absolute(folder)
	root.size = Vector2i(1600,1000)
	_build()
	for i in 45: await process_frame          # shader compile + noise bake
	var wanted := OS.get_cmdline_user_args()
	var states := ["cruise","reheat","ign010","ign030","vapour","gun","guncockpit"]
	var cameras := ["chase","rear","side","quarter","low"]
	for state: String in states:
		var shots: Array = ["gun","quarter"] if state.begins_with("gun") else cameras
		for camera: String in shots:
			var shot_name: String = state+"-"+camera
			if not wanted.is_empty() and shot_name not in wanted and state not in wanted and camera not in wanted and "budget" not in wanted: continue
			await _stage(state,camera,shot_name)
	if wanted.is_empty() or "budget" in wanted: await _budget()
	quit(0)

func _build() -> void:
	app = StubApp.new(); root.add_child(app)
	app.combat = StubCombat.new(); app.add_child(app.combat)
	app.audio = StubAudio.new(); app.add_child(app.audio)
	app.camera_rig = StubRig.new(); app.add_child(app.camera_rig)
	app.world = StubWorld.new(); app.add_child(app.world)
	# --- sky and key light, copied from scenes/san_francisco_world.gd ---------
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://assets/look/sunset_sky.gdshader")
	sky_material.set_shader_parameter("panorama",load("res://assets/look/kloppenheim_06_puresky_8k.hdr"))
	var sky := Sky.new(); sky.sky_material = sky_material; sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0,deg_to_rad(SKY_YAW_DEGREES),0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = .85
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.16
	env.fog_enabled = true
	env.fog_density = 0.000026
	env.fog_light_color = Color(0.36,0.41,0.50)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.10
	env.fog_aerial_perspective = 0.25
	env.fog_sky_affect = 0.0
	env.fog_height = 40.0
	env.fog_height_density = 0.0004
	env.glow_enabled = true
	env.glow_intensity = .22
	env.glow_bloom = .0
	env.glow_hdr_threshold = 2.2
	env.glow_hdr_scale = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level in range(0,7): env.set_glow_level(level,1.0 if level in [1,2,4,5] else 0.0)
	var holder := WorldEnvironment.new(); holder.environment = env; app.add_child(holder)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-10.0,-110,0)
	sun.light_color = Color(1.0,0.66,0.38); sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 400
	app.add_child(sun); app.world.sun = sun
	# --- dark water far below -------------------------------------------------
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2(60000,60000); plane.subdivide_width = 1; plane.subdivide_depth = 1
	sea.mesh = plane
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.030,0.045,0.062)
	water.metallic = 0.35; water.roughness = 0.34
	sea.material_override = water
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	app.add_child(sea)
	# --- aircraft, camera, effects --------------------------------------------
	app.aircraft = Node3D.new(); app.add_child(app.aircraft)
	var model: Node3D = Model.create()
	app.aircraft.add_child(model)
	visuals = Visuals.new(); app.add_child(visuals)
	visuals.initialize(model,Catalog.PROFILE)
	app.camera = Camera3D.new(); app.camera.near = 0.6; app.camera.far = 40000
	app.add_child(app.camera); app.camera.current = true
	app.flight = Dynamics.new()
	app.flight.reset(Catalog.PROFILE)
	fx = Effects.new(); fx.app = app; app.add_child(fx); fx.build()

## One simulation tick: the airframe animation the game runs, then the effects.
func _tick(dt: float) -> void:
	visuals.update_visuals(dt,app.flight,Vector3.ZERO)
	if visuals._engine_glow!=null:
		visuals._engine_glow.visible = app.flight.engine>0.15
		visuals._engine_material.emission_energy_multiplier = app.flight.engine*(2.0 if app.flight.afterburner else 0.35)
	fx.update(dt)

func _pose() -> Basis:
	var f: FlightDynamics = app.flight
	app.aircraft.position = f.position
	app.aircraft.rotation = Vector3(f.pitch,-f.heading,-f.roll)
	return Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))

## Puts the jet and the burner into one named state, then parks one named camera.
func _stage(state: String, camera: String, shot_name: String) -> void:
	var f: FlightDynamics = app.flight
	fx.reset()
	var height: float = 22.0 if camera=="low" else 150.0
	f.spawn_airborne(Vector3(0,height,0),330)
	f.heading = 0.35; f.pitch = 0.04; f.roll = 0.0; f.gear = false; f.g_load = 1.0
	app.world.cloud_presence = 0.0
	app.cockpit = false; app.combat.active = false; app.combat.gun_firing_time = 0.0
	var steps := 90
	match state:
		"cruise":
			f.speed = 250; f.engine = 0.62; f.afterburner = false
		"reheat":
			f.speed = 400; f.engine = 1.0; f.afterburner = true
		"ign010":
			f.speed = 330; f.engine = 0.55; f.afterburner = false
		"ign030":
			f.speed = 330; f.engine = 0.55; f.afterburner = false
		"vapour":
			f.speed = 315; f.engine = 0.92; f.afterburner = true; f.roll = -0.85; f.pitch = 0.16
		"gun", "guncockpit":
			# Goal 7: the muzzle flash must be visible from the cockpit too, only smaller.
			f.speed = 300; f.engine = 0.80; f.afterburner = false
			app.cockpit = state=="guncockpit"
			app.combat.active = true; app.combat.gun_firing_time = 1.0
	_pose()
	# The burner cross-fades on the camera, so the camera must be parked BEFORE the state
	# is stepped - otherwise every shot is composed for the previous shot's viewpoint.
	_park(camera)
	# settle, then (for the ignition shots) light the burner and step an exact interval
	for i in range(steps): _tick(1.0/60.0)
	if state.begins_with("ign"):
		f.engine = 1.0; f.afterburner = true; f.speed = 360
		var frames: int = 6 if state=="ign010" else 18
		for i in range(frames): _tick(1.0/60.0)
	if state=="vapour":
		f.g_load = 5.6
		for i in range(14): _tick(1.0/60.0)
		f.g_load = 6.2
		for i in range(6): _tick(1.0/60.0)
	_pose()
	_park(camera)
	_tick(1.0/60.0)
	for i in 6: await process_frame
	await _shot(shot_name)

func _park(camera: String) -> void:
	var f: FlightDynamics = app.flight
	var basis := Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	var aft: Vector3 = basis.z
	var right: Vector3 = basis.x
	var up: Vector3 = basis.y
	var nozzle: Vector3 = f.position+basis*Model.NOZZLE
	var look: Vector3 = f.position+basis*Vector3(0,1.0,-7)
	var fov := 42.0
	var at := Vector3.ZERO
	match camera:
		"chase":
			# exactly the game's rig: systems/camera_rig.gd offset + fov formula
			var fraction: float = clampf((f.speed-130)/300,0,1)
			at = f.position+Basis(Vector3.UP,-f.heading)*Vector3(0,6.1+fraction*1.1,22.0+fraction*4)
			fov = 68.0+fraction*16+(3 if f.afterburner else 0)
		"rear":
			at = nozzle+aft*26.0; look = nozzle; fov = 30.0
		"side":
			# stand on the sunlit side so the jet is lit and the background sky is the dark
			# anti-sun half - the key art's staging, and the only way a plume reads at all
			var pick: float = 1.0 if right.dot(app.world.sun.global_basis.z)>0.0 else -1.0
			at = f.position+right*(31.0*pick)+up*2.5+aft*8.0; look = f.position+aft*7.0; fov = 36.0
		"quarter":
			at = nozzle+aft*19.0+right*13.0+up*5.5; look = f.position+aft*3.0; fov = 38.0
		"low":
			at = f.position+aft*19.0+right*9.0-up*7.0; look = f.position+aft*2.0; fov = 40.0
		"gun":
			at = f.position+basis*Vector3(-5.5,1.6,-9.0); look = f.position+basis*Vector3(-1.0,0.2,-4.0); fov = 46.0
	app.camera.global_position = at
	app.camera.look_at(look,Vector3.UP)
	app.camera.fov = fov

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+shot_name+".png")
	print("SHOT ",shot_name," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," prims=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if app.combat.active: print("     GUN flash_visible=",fx.gun_flash.visible," scale=",snappedf(fx.gun_flash.scale.x,0.001)," light=",snappedf(fx.gun_light.light_energy,0.01),"/",fx.gun_light.omni_range," cockpit=",app.cockpit," gas=",is_instance_valid(fx.gun_gas) and fx.gun_gas.emitting)
	print("     slice=",fx.exhaust.visible," vis=",fx.exhaust_material.get_shader_parameter("visibility")," bright=",fx.exhaust_material.get_shader_parameter("brightness"),
		" sheath=",fx.exhaust_sheath.visible,"/",fx.sheath_material.get_shader_parameter("power"),
		" stack=",fx.plume_stack.visible,"/",fx.stack_mesh.visible_instance_count,
		" flare=",fx.nozzle_flare.visible,"/",fx.flare_material.get_shader_parameter("size"),
		" glow=",fx.nozzle_glow.visible," haze=",fx.haze.visible," len=",snappedf(fx.plume_length,0.01))

## GPU cost of the burner, measured with the renderer's own timer (frame pacing is
## vsync-locked here, so wall-clock frame time says nothing): the same frame with every
## burner node shown and hidden, A/B/A/B, keeping the best reading of each.
func _budget() -> void:
	var f: FlightDynamics = app.flight
	fx.reset()
	f.spawn_airborne(Vector3(0,150,0),400)
	f.heading = 0.35; f.engine = 1.0; f.afterburner = true; f.gear = false
	_pose(); _park("chase")
	for i in range(120): _tick(1.0/60.0)
	_pose(); _park("chase"); _tick(1.0/60.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("BUDGET vsync=",DisplayServer.window_get_vsync_mode()," max_fps=",Engine.max_fps)
	var viewport: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	var nodes: Array[Node3D] = [fx.exhaust,fx.exhaust_sheath,fx.plume_stack,fx.nozzle_glow,fx.nozzle_flare,fx.haze]
	var best := {"with-burner":1e9,"no-burner":1e9}
	var draws := {"with-burner":0.0,"no-burner":0.0}
	for round_index in range(4):
		for pass_name in ["with-burner","no-burner"]:
			for node: Node3D in nodes: node.visible = pass_name=="with-burner"
			for i in 25: await process_frame
			# force_draw(false) renders without presenting, so the compositor's 120 Hz
			# pacing does not swallow the measurement.
			for i in range(20): RenderingServer.force_draw(false)
			var began := Time.get_ticks_usec()
			for i in range(120): RenderingServer.force_draw(false)
			best[pass_name] = minf(best[pass_name],float(Time.get_ticks_usec()-began)/120000.0)
			draws[pass_name] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	for pass_name in ["with-burner","no-burner"]:
		print("BUDGET ",pass_name," gpu_ms=",snappedf(best[pass_name],0.001)," draws=",draws[pass_name])
	print("BUDGET burner_gpu_ms=",snappedf(best["with-burner"]-best["no-burner"],0.001)," extra_draws=",draws["with-burner"]-draws["no-burner"]," viewport=",root.size)
	RenderingServer.viewport_set_measure_render_time(viewport,false)
	for node: Node3D in nodes: node.visible = true
