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
const Cockpit = preload("res://scenes/cockpit.gd")
const SKY_YAW_DEGREES := -79.8
const SUN_ENERGY := 3.0
## The game's own pilot eye point and cockpit field of view, copied from
## systems/camera_rig.gd (_cockpit_view: camera.position = f.position+eye_basis*EYE,
## camera.near = 0.12, base fov 76 for the cockpit). Goal 7 is about what the PILOT sees,
## so the cockpit shots are taken from here through the real interior - never from an
## exterior camera parked outside the jet with app.cockpit flipped to true.
const EYE := Vector3(0,2.6,-5.0)
const COCKPIT_FOV := 76.0
const COCKPIT_NEAR := 0.12

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
var cockpit_frame: DetailedCockpit
var folder := ""
var failures: Array[String] = []

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
	var states := ["cruise","reheat","reheatcockpit","ign010","ign030","vapour","demovapour","slowvapour","gun","guncockpit"]
	var cameras := ["chase","rear","side","quarter","low"]
	for state: String in states:
		var shots: Array = cameras
		if state=="gun": shots = ["gun","quarter"]
		elif state=="guncockpit": shots = ["cockpit","gun"]
		elif state=="reheatcockpit": shots = ["cockpit"]
		elif state in ["demovapour","slowvapour"]: shots = ["chase","quarter","side"]
		for camera: String in shots:
			var shot_name: String = state+"-"+camera
			if not _requested(wanted,shot_name,state,camera): continue
			await _stage(state,camera,shot_name)
	if wanted.is_empty() or "contract" in wanted: await _contract()
	if wanted.is_empty() or "budget" in wanted: await _budget()
	if failures.is_empty():
		print("PASS studio_burner")
		quit(0)
	else:
		for line: String in failures: printerr("FAIL ",line)
		printerr("failures: ",failures.size())
		quit(1)

## "-- budget" or "-- contract" alone means that section ONLY - it used to fall through the
## shot filter and re-render all 33 shots before getting there.
func _requested(wanted: PackedStringArray, shot_name: String, state: String, camera: String) -> bool:
	if wanted.is_empty(): return true
	var only_sections := true
	for item: String in wanted:
		if item not in ["budget","contract"]: only_sections = false
	if only_sections: return false
	return shot_name in wanted or state in wanted or camera in wanted

func check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL "),label)
	if not ok: failures.append(label)

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
	# The REAL interior, hung off the camera exactly as scenes/main.gd hangs it, so the
	# cockpit shots look through the tub, the coaming and the canopy the pilot flies behind.
	cockpit_frame = Cockpit.new(); app.camera.add_child(cockpit_frame)
	cockpit_frame.build(Catalog.PROFILE)
	cockpit_frame.set_presentation_visible(false)

## One simulation tick: the airframe animation the game runs, then the effects.
func _tick(dt: float) -> void:
	visuals.update_visuals(dt,app.flight,Vector3.ZERO)
	if visuals._engine_glow!=null:
		visuals._engine_glow.visible = app.flight.engine>0.15
		visuals._engine_material.emission_energy_multiplier = app.flight.engine*(2.0 if app.flight.afterburner else 0.35)
	fx.update(dt)
	if is_instance_valid(cockpit_frame) and cockpit_frame.visible:
		cockpit_frame.update_instruments(app.flight,Vector3.ZERO,dt)
		cockpit_frame.set_sun(app.world.sun.global_basis.z,app.world.sun.light_energy/3.2)
		cockpit_frame.set_tactical({})

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
		"demovapour":
			# The SHIPPING cinematic showcase's own numbers, not studio-only ones. Measured
			# over the whole 121 s sortie (route sf, cinematic, auto-flown): the jet spends
			# 45 s in the 350-375 m/s bucket, pulls above 3 g for 28.9 s and banks past
			# 0.70 rad for 21.6 s. So this is a state the player is actually flown through.
			f.speed = 358; f.engine = 0.78; f.afterburner = false
			f.roll = -0.86; f.pitch = 0.14; f.roll_velocity = -0.55
		"slowvapour":
			# The other end: the slow free-flight route, where the same probe measures a
			# 156 m/s top speed and only 1.8 s above 3 g. The old gates (Mach 0.88, 3.0 g,
			# 3.2 g) drew nothing at all here; these numbers must still show vapour.
			f.speed = 152; f.engine = 0.55; f.afterburner = false
			f.roll = 0.64; f.pitch = 0.10; f.roll_velocity = 0.95
		"reheatcockpit":
			# The frame that was never rendered: the pilot's view WITH reheat lit. The
			# exhaust light sits ~12 m behind the head and runs to energy 7 (about 35 in the
			# ignition flash), so this is where an unmasked burner light shows up.
			f.speed = 400; f.engine = 1.0; f.afterburner = true
			app.cockpit = true
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
	if state=="demovapour":
		# Ramped, not assigned: the tip rope keys off the ONSET of wing loading, so a step
		# change would read as a value the game never passes through.
		f.g_load = 2.6
		for i in range(12): _tick(1.0/60.0)
		f.g_load = 3.4
		for i in range(8): _tick(1.0/60.0)
	if state=="slowvapour":
		f.g_load = 1.5
		for i in range(12): _tick(1.0/60.0)
		f.g_load = 1.9
		for i in range(8): _tick(1.0/60.0)
	_pose()
	_park(camera)
	_tick(1.0/60.0)
	for i in 6: await process_frame
	await _shot(shot_name)
	if state=="guncockpit" and camera=="cockpit": await _strobe_check()
	if state=="reheatcockpit" and camera=="cockpit": await _burner_strobe_check()

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
	var up_axis: Vector3 = Vector3.UP
	# scenes/main.gd hides the exterior airframe in cockpit mode and hangs the interior off
	# the camera; mirror both so the cockpit shot is the pilot's actual view, not an
	# outside-the-jet shot with app.cockpit flipped on.
	var inside: bool = camera=="cockpit"
	if is_instance_valid(cockpit_frame):
		cockpit_frame.position = Vector3.ZERO
		cockpit_frame.basis = Basis()
		cockpit_frame.set_presentation_visible(inside)
	app.aircraft.visible = not inside
	app.camera.near = COCKPIT_NEAR if inside else 0.6
	match camera:
		"cockpit":
			at = f.position+basis*EYE
			look = at+basis*Vector3(0,0,-40)
			up_axis = basis*Vector3.UP
			fov = COCKPIT_FOV
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
	app.camera.look_at(look,up_axis)
	app.camera.fov = fov

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+shot_name+".png")
	print("SHOT ",shot_name," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," prims=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if app.combat.active:
		print("     GUN flash_visible=",fx.gun_flash.visible," scale=",snappedf(fx.gun_flash.scale.x,0.001)," light=",snappedf(fx.gun_light.light_energy,0.01),"/",fx.gun_light.omni_range," cull=",fx.gun_light.light_cull_mask," cockpit=",app.cockpit," gas=",is_instance_valid(fx.gun_gas) and fx.gun_gas.emitting)
		if shot_name.ends_with("-cockpit"): print("     EYE ",_muzzle_from_eye())
	print("     slice=",fx.exhaust.visible," vis=",fx.exhaust_material.get_shader_parameter("visibility")," bright=",fx.exhaust_material.get_shader_parameter("brightness"),
		" sheath=",fx.exhaust_sheath.visible,"/",fx.sheath_material.get_shader_parameter("power"),
		" stack=",fx.plume_stack.visible,"/",fx.stack_mesh.visible_instance_count,
		" flare=",fx.nozzle_flare.visible,"/",fx.flare_material.get_shader_parameter("size"),
		" glow=",fx.nozzle_glow.visible," haze=",fx.haze.visible," len=",snappedf(fx.plume_length,0.01))
	print("     VAPOUR shell=",fx.vapor_shock.visible,"/",fx.shock_material.get_shader_parameter("amount"),
		" wing=",fx.vapor_wings[0].visible,"/",fx.vapor_material.get_shader_parameter("amount"),
		" tip=",fx.condensation[0].visible,"/",fx.tip_materials[0].get_shader_parameter("amount"),
		" speed=",snappedf(app.flight.speed,1)," mach=",snappedf(app.flight.speed/335.0,0.01),
		" g=",snappedf(app.flight.g_load,0.01)," roll=",snappedf(app.flight.roll,0.01))

## Where the gun sits relative to the pilot's eye, in eye-local metres and degrees off the
## forward axis. A wing-root cannon is below and BEHIND the eye on this airframe, so the
## flash itself cannot enter the forward view: what a pilot would actually get from an
## unmasked gun light is the interior strobing, which is what _strobe_check() measures.
func _muzzle_from_eye() -> String:
	var f: FlightDynamics = app.flight
	var basis := Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	var local: Vector3 = basis.inverse()*(fx.gun_muzzle_position(f.position+basis*Vector3(-1.2,-0.21,-3.53))-(f.position+basis*EYE))
	var forward: float = -local.z
	var off: float = rad_to_deg(acos(clampf(forward/maxf(local.length(),0.0001),-1.0,1.0)))
	return "muzzle_local=%s range=%.2fm off_axis=%.1fdeg in_forward_fov=%s" % [
		Vector3(snappedf(local.x,0.01),snappedf(local.y,0.01),snappedf(local.z,0.01)),
		local.length(),off,off<COCKPIT_FOV*0.5]

## Mean luminance of the lower 45% of the frame - the tub, the coaming and the side
## consoles. Anything the gun light does to the interior shows up here.
func _interior_luma() -> float:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var w: int = image.get_width()
	var h: int = image.get_height()
	var total := 0.0
	var count := 0
	for y in range(int(h*0.55),h,6):
		for x in range(0,w,6):
			var pixel: Color = image.get_pixel(x,y)
			total += pixel.r*0.2126+pixel.g*0.7152+pixel.b*0.0722
			count += 1
	return total/maxf(1.0,float(count))

## Goal 7, measured instead of asserted: render the pilot's view with the cannon firing and
## with it silent, and compare the interior's brightness. gun_light pulses at ~22 Hz a few
## metres from the pilot's head, so an unmasked light would show up here as a large delta -
## the HUD and the aiming view flickering, which the brief forbids.
func _strobe_check() -> void:
	var firing: float = await _interior_luma()
	app.combat.active = false; app.combat.gun_firing_time = 0.0
	for i in range(8): _tick(1.0/60.0)
	for i in 4: await process_frame
	var quiet: float = await _interior_luma()
	app.combat.active = true; app.combat.gun_firing_time = 1.0
	for i in range(8): _tick(1.0/60.0)
	var swing: float = absf(firing-quiet)/maxf(quiet,0.0001)
	print("     STROBE interior_luma firing=",snappedf(firing,0.0001)," quiet=",snappedf(quiet,0.0001)," swing=",snappedf(swing*100.0,0.01),"%")
	# Threshold calibrated against the real regression: with gun_light unmasked at range 14
	# this frame measures 1.69%, with the layer-2 cull mask it measures 0.02%. 0.35% sits
	# well clear of both, so removing the mask again fails here instead of shipping.
	check(swing<0.0035,"gun light does not strobe the cockpit interior (swing %.2f%% < 0.35%%)"%(swing*100.0))

## The same measurement as _strobe_check(), for the OTHER light that sits near the pilot.
## exhaust_light is ~12.3 m behind the head (Fighter.NOZZLE z = +7.28, eye ~5 m forward of
## the origin), reaches omni_range 26 and light_energy 7 at steady reheat - around 35 during
## the ignition flash. Unmasked it floods the interior the cardboard-yoke player aims
## through, from behind. Three frames of the pilot's view: as shipped, with the light gone
## entirely, and with the layer-1 mask deliberately removed. The first two must be the same
## frame, and the third must be measurably different - otherwise this probe is not sensitive
## enough to catch the regression it exists for.
func _burner_strobe_check() -> void:
	var shipped: float = await _interior_luma()
	var mask: int = fx.exhaust_light.light_cull_mask
	fx.exhaust_light.visible = false
	for i in 4: await process_frame
	var dark: float = await _interior_luma()
	# The worst case this mask exists for is the LIGHT-UP, where light_energy is multiplied
	# by (1 + 4*flash) and reaches ~38. At steady reheat the light sits ~15 m from the tub
	# inside a 26 m range, so even unmasked it only moves the interior by a fraction of a
	# percent - which is why this probe checks itself against the flash energy instead.
	var energy: float = fx.exhaust_light.light_energy
	fx.exhaust_light.visible = true
	fx.exhaust_light.light_cull_mask = mask|1
	fx.exhaust_light.light_energy = energy*5.0
	for i in 4: await process_frame
	var unmasked: float = await _interior_luma()
	fx.exhaust_light.light_cull_mask = mask
	fx.exhaust_light.light_energy = energy
	for i in 4: await process_frame
	var swing: float = absf(shipped-dark)/maxf(dark,0.0001)
	var regression: float = absf(unmasked-dark)/maxf(dark,0.0001)
	print("     BURNER interior_luma shipped=",snappedf(shipped,0.0001)," light_off=",snappedf(dark,0.0001),
		" unmasked_at_flash_energy=",snappedf(unmasked,0.0001)," swing=",snappedf(swing*100.0,0.01),
		"% unmasked_swing=",snappedf(regression*100.0,0.01),"% steady_energy=",snappedf(energy,0.01),
		" range=",snappedf(fx.exhaust_light.omni_range,0.01)," cull=",mask)
	check(swing<0.0035,"reheat light does not reach the cockpit interior (swing %.2f%% < 0.35%%)"%(swing*100.0))
	check(regression>swing+0.002,"the interior probe can still see an UNMASKED reheat light at light-up energy (%.2f%% vs %.2f%%)"%[regression*100.0,swing*100.0])

## The design contract the owner and the reviewers keep restating, measured rather than
## eyeballed: plume length, the ignition lunge, no camera-driven length change, and the
## halo cap that keeps the airframe silhouette readable from astern.
func _contract() -> void:
	print("CONTRACT")
	var f: FlightDynamics = app.flight
	var limit: float = Effects.halo_limit()
	fx.reset()
	f.spawn_airborne(Vector3(0,150,0),400)
	f.heading = 0.35; f.pitch = 0.04; f.roll = 0.0; f.gear = false; f.g_load = 1.0
	app.cockpit = false; app.combat.active = false
	f.engine = 1.0; f.afterburner = true
	_pose(); _park("side")
	for i in range(300): _tick(1.0/60.0)
	var low := 1e9
	var high := 0.0
	var flare_max := 0.0
	for i in range(180):
		_tick(1.0/60.0)
		low = minf(low,fx.plume_length); high = maxf(high,fx.plume_length)
		flare_max = maxf(flare_max,float(fx.flare_material.get_shader_parameter("size")))
	print("  steady reheat length ",snappedf(low,0.01)," .. ",snappedf(high,0.01)," m")
	check(low>=8.0 and high<=11.0,"steady reheat plume is 8-11 m (owner's window), got %.2f-%.2f"%[low,high])
	# The same jet, same throttle, seen from the game's own chase rig: the length must not
	# move. A camera-driven length is a constant-size bar welded to the screen.
	_park("chase")
	for i in range(120): _tick(1.0/60.0)
	var chase: float = fx.plume_length
	print("  chase-rig length ",snappedf(chase,0.01)," m")
	check(absf(chase-high)<0.6,"chase camera does not shorten the plume (%.2f vs %.2f)"%[chase,high])
	# Dead astern: the additive flare and the whole end-on disc stack must stay inside the
	# cap, so the fuselage silhouette survives however low the chase eye line goes.
	_park("rear")
	for i in range(120): _tick(1.0/60.0)
	var disc_max := 0.0
	for i in range(fx.stack_mesh.visible_instance_count):
		disc_max = maxf(disc_max,fx.stack_mesh.get_instance_custom_data(i).r)
	var flare_now: float = float(fx.flare_material.get_shader_parameter("size"))
	print("  halo limit ",snappedf(limit,0.001)," m : flare ",snappedf(flare_now,0.001)," disc ",snappedf(disc_max,0.001))
	check(flare_now<=limit+0.001,"nozzle flare radius within the halo cap (%.2f <= %.2f m)"%[flare_now,limit])
	check(disc_max<=limit+0.001,"end-on disc radius within the halo cap (%.2f <= %.2f m)"%[disc_max,limit])
	# Light-up: keep the lunge, but it must not double the plume.
	fx.reset()
	f.engine = 0.55; f.afterburner = false
	_pose(); _park("side")
	for i in range(120): _tick(1.0/60.0)
	f.engine = 1.0; f.afterburner = true
	var peak := 0.0
	for i in range(120):
		_tick(1.0/60.0)
		peak = maxf(peak,fx.plume_length)
		flare_max = maxf(flare_max,float(fx.flare_material.get_shader_parameter("size")))
	print("  ignition peak ",snappedf(peak,0.01)," m ; peak flare ",snappedf(flare_max,0.001)," m")
	check(peak<=11.2,"ignition lunge peaks near 11 m, not 18 (%.2f)"%peak)
	check(peak>=high+0.7,"the ignition lunge still reads as a kick (%.2f >= %.2f+0.7)"%[peak,high])
	check(flare_max<=limit+0.001,"the ignition flare stays inside the halo cap (%.2f <= %.2f m)"%[flare_max,limit])
	check((fx.gun_light.light_cull_mask&1)==0,"gun light cannot reach the cockpit tub (layer 1 masked out)")
	check((fx.exhaust_light.light_cull_mask&1)==0,"reheat light cannot reach the cockpit tub (layer 1 masked out)")
	# The plume must dissolve by its own STATION, not only by distance to the lens: at the
	# game's chase distance the near-camera fade cannot fire, which is how the beam survived
	# every previous fix. Both plume materials must carry the station dissolve.
	for material: ShaderMaterial in [fx.exhaust_material,fx.sheath_material]:
		var from_value: Variant = material.get_shader_parameter("fade_from")
		var to_value: Variant = material.get_shader_parameter("fade_to")
		check(from_value!=null and float(from_value)<=0.62 and to_value!=null and float(to_value)<=1.0,
			"plume carries a station dissolve that starts by u=0.62 (got %s..%s)"%[from_value,to_value])
	# The vapour must be reachable with the numbers the SHIPPING demo actually flies.
	# Measured over the full cinematic showcase: 45 s in the 350-375 m/s bucket, 28.9 s above
	# 3 g, 21.6 s past 0.70 rad of bank. The old gates (Mach 0.88 band, g>3.0, g>3.2 with a
	# positive G rate) drew nothing at all on the slower free-flight routes.
	fx.reset()
	f.spawn_airborne(Vector3(0,150,0),358)
	f.heading = 0.35; f.pitch = 0.14; f.roll = -0.86; f.roll_velocity = -0.55; f.gear = false
	f.speed = 358; f.engine = 0.78; f.afterburner = false; f.g_load = 2.6
	app.cockpit = false
	_pose(); _park("quarter")
	for i in range(40): _tick(1.0/60.0)
	f.g_load = 3.4
	for i in range(20): _tick(1.0/60.0)
	var demo_shell: float = float(fx.shock_material.get_shader_parameter("amount"))
	var demo_wing: float = float(fx.vapor_material.get_shader_parameter("amount"))
	var demo_tip: float = float(fx.tip_materials[0].get_shader_parameter("amount"))
	print("  demo-state vapour shell=",snappedf(demo_shell,0.001)," wing=",snappedf(demo_wing,0.001)," tip=",snappedf(demo_tip,0.001))
	check(demo_shell>0.10,"the shock shell appears at the demo's own speed and bank (%.3f > 0.10)"%demo_shell)
	check(demo_wing>0.10,"the wing blister appears at the demo's own g and bank (%.3f > 0.10)"%demo_wing)
	check(demo_tip>0.05,"the tip vortex appears at the demo's own loading (%.3f > 0.05)"%demo_tip)
	# ...and at the slow free-flight route's ceiling, which never reaches 3 g at all.
	fx.reset()
	f.spawn_airborne(Vector3(0,150,0),152)
	f.heading = 0.35; f.pitch = 0.10; f.roll = 0.64; f.roll_velocity = 0.95; f.gear = false
	f.speed = 152; f.engine = 0.55; f.afterburner = false; f.g_load = 1.5
	_pose(); _park("quarter")
	for i in range(40): _tick(1.0/60.0)
	f.g_load = 1.9
	for i in range(20): _tick(1.0/60.0)
	var slow_wing: float = float(fx.vapor_material.get_shader_parameter("amount"))
	var slow_tip: float = float(fx.tip_materials[0].get_shader_parameter("amount"))
	print("  slow-route vapour wing=",snappedf(slow_wing,0.001)," tip=",snappedf(slow_tip,0.001))
	check(slow_wing>0.05,"the wing blister still appears on the slow route (%.3f > 0.05)"%slow_wing)
	check(slow_tip>0.03,"the tip vortex still appears on the slow route (%.3f > 0.03)"%slow_tip)
	fx.reset()
	f.spawn_airborne(Vector3(0,150,0),400)
	f.heading = 0.35; f.pitch = 0.04; f.roll = 0.0; f.roll_velocity = 0.0; f.g_load = 1.0
	f.engine = 1.0; f.afterburner = true

func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate(); sorted.sort()
	var n: int = sorted.size()
	if n==0: return 0.0
	return sorted[n/2] if n%2==1 else (sorted[n/2-1]+sorted[n/2])*0.5

## Inter-quartile range: the noise floor of this estimator, in the same units as the number
## it is guarding. Not the min/max, which one scheduler hiccup can blow out.
func _iqr(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate(); sorted.sort()
	var n: int = sorted.size()
	if n<4: return INF
	return sorted[int(n*0.75)]-sorted[int(n*0.25)]

## GPU cost of the burner. The A/B here is a DIFFERENCE OF TWO NOISY FRAME TIMES, and the
## burner is small enough that the difference can land inside the noise - earlier versions
## of this harness printed a negative cost (-0.226 ms) as if it were a result. So: hide
## every burner node including its two lights, interleave the passes, take medians over
## many rounds, and refuse to print a millisecond figure unless the delta is positive AND
## larger than the estimator's own spread. The draw-call delta is exact and always printed.
func _budget() -> void:
	var f: FlightDynamics = app.flight
	fx.reset()
	f.spawn_airborne(Vector3(0,150,0),400)
	f.heading = 0.35; f.engine = 1.0; f.afterburner = true; f.gear = false
	app.cockpit = false; app.combat.active = false
	_pose(); _park("chase")
	for i in range(120): _tick(1.0/60.0)
	_pose(); _park("chase"); _tick(1.0/60.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("BUDGET vsync=",DisplayServer.window_get_vsync_mode()," max_fps=",Engine.max_fps)
	var viewport: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	# exhaust_light (omni_range up to 26) and airframe_fill are burner cost too: leaving
	# them lit in both passes measured the quads and silently excused the lights.
	var nodes: Array[Node3D] = [fx.exhaust,fx.exhaust_sheath,fx.plume_stack,fx.nozzle_glow,
		fx.nozzle_flare,fx.haze,fx.exhaust_light,fx.airframe_fill]
	var samples := {"with-burner":([] as Array[float]),"no-burner":([] as Array[float])}
	var draws := {"with-burner":0.0,"no-burner":0.0}
	for round_index in range(9):
		for pass_name: String in ["with-burner","no-burner"]:
			for node: Node3D in nodes: node.visible = pass_name=="with-burner"
			for i in 12: await process_frame
			# force_draw(false) renders without presenting, so the compositor's 120 Hz
			# pacing does not swallow the measurement.
			for i in range(15): RenderingServer.force_draw(false)
			var began := Time.get_ticks_usec()
			for i in range(120): RenderingServer.force_draw(false)
			var sample: Array[float] = samples[pass_name]
			sample.append(float(Time.get_ticks_usec()-began)/120000.0)
			draws[pass_name] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var noise := 0.0
	for pass_name: String in ["with-burner","no-burner"]:
		var sample: Array[float] = samples[pass_name]
		noise = maxf(noise,_iqr(sample))
		print("BUDGET ",pass_name," gpu_ms median=",snappedf(_median(sample),0.001),
			" iqr=",snappedf(_iqr(sample),0.001)," n=",sample.size()," draws=",draws[pass_name])
	var delta: float = _median(samples["with-burner"])-_median(samples["no-burner"])
	var extra_draws: float = draws["with-burner"]-draws["no-burner"]
	if delta>0.0 and delta>noise:
		print("BUDGET burner_gpu_ms=",snappedf(delta,0.001)," (noise floor ",snappedf(noise,0.001),
			") extra_draws=",extra_draws," viewport=",root.size)
	else:
		# Not a failure - a burner too cheap to measure is the outcome we want. It is only a
		# failure to quote the number anyway.
		print("BUDGET burner_gpu_ms=inconclusive delta=",snappedf(delta,0.001)," noise_floor=",snappedf(noise,0.001),
			" -> the burner is at or below this rig's measurement floor; quote extra_draws=",extra_draws,
			" only. viewport=",root.size)
	check(extra_draws<=12.0,"the burner costs at most 12 extra draw calls (%d)"%int(extra_draws))
	check(delta<0.6,"the burner is nowhere near the 16.6 ms frame budget (delta %.3f ms)"%delta)
	RenderingServer.viewport_set_measure_render_time(viewport,false)
	for node: Node3D in nodes: node.visible = true
