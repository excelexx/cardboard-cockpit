extends SceneTree
## Weapons studio. No world, no mission: just the sunset sky, the key light and
## one subject, so a look pass is seconds rather than minutes.
##
##   Godot --path simulator --windowed --resolution 1600x1000 \
##         --script tests/studio_weapons.gd -- cannon plasma tracer beam impact
##
## Writes build/weapons/*.png. Groups are optional; with none it renders all.

const Models = preload("res://systems/weapon_models.gd")
const Art = preload("res://systems/weapon_visuals.gd")
const FX = preload("res://systems/impact_fx.gd")
const Goose = preload("res://systems/goose_model.gd")
const SKY_YAW_DEGREES := -79.8

var stage: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var env: Environment
var water: MeshInstance3D
var folder: String

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless": printerr("Native GPU required"); quit(2); return
	folder = ProjectSettings.globalize_path("res://../build/weapons")
	DirAccess.make_dir_recursive_absolute(folder)
	var wanted: PackedStringArray = OS.get_cmdline_user_args()
	_build()
	for i in 12: await process_frame
	if _want(wanted,"cannon"): await _cannon()
	if _want(wanted,"plasma"): await _plasma()
	if _want(wanted,"tracer"): await _tracer()
	if _want(wanted,"beam"): await _beam()
	if _want(wanted,"impact"): await _impact()
	print("STUDIO done -> ",folder)
	quit(0)

func _want(wanted: PackedStringArray, group: String) -> bool:
	return wanted.is_empty() or group in wanted

# ------------------------------------------------------------------- stage --

func _build() -> void:
	stage = Node3D.new(); stage.name = "Studio"; root.add_child(stage)
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/look/sunset_sky.gdshader")
	material.set_shader_parameter("panorama",load("res://assets/look/kloppenheim_06_puresky_8k.hdr"))
	var sky := Sky.new(); sky.sky_material = material; sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
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
	env.glow_enabled = true
	env.glow_intensity = .22
	env.glow_bloom = .0
	env.glow_hdr_threshold = 2.2
	env.glow_hdr_scale = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level in range(0,7): env.set_glow_level(level,1.0 if level in [1,2,4,5] else 0.0)
	var holder := WorldEnvironment.new(); holder.environment = env; stage.add_child(holder)

	sun = DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-10.0,-110,0)
	sun.light_color = Color(1.0,0.66,0.38); sun.light_energy = 3.0
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 60
	sun.shadow_bias = 0.02; sun.shadow_normal_bias = 0.6; stage.add_child(sun)
	# A cool kicker from behind so a near-black weapon still shows an edge.
	fill = DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-18,68,0)
	fill.light_color = Color(0.46,0.60,0.82); fill.light_energy = 0.9
	fill.shadow_enabled = false; stage.add_child(fill)

	water = MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2(9000,9000)
	water.mesh = plane
	var sea := StandardMaterial3D.new()
	sea.albedo_color = Color(0.020,0.035,0.052); sea.metallic = 0.75; sea.roughness = 0.26
	water.material_override = sea
	water.position.y = -60.0
	water.visible = false
	stage.add_child(water)

	camera = Camera3D.new(); camera.fov = 34; camera.far = 6000; camera.current = true
	stage.add_child(camera)

func _look(from: Vector3, at: Vector3, fov: float = 34.0) -> void:
	camera.fov = fov
	camera.position = from
	camera.look_at(at,Vector3.UP)

func _dark(on: bool) -> void:
	env.background_mode = Environment.BG_COLOR if on else Environment.BG_SKY
	env.background_color = Color(0.016,0.021,0.030)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if on else Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.10,0.13,0.19)
	env.ambient_light_energy = 0.55 if on else 0.85

func _clear() -> void:
	for child in stage.get_children():
		if child==camera or child==water or child is WorldEnvironment or child is DirectionalLight3D: continue
		child.queue_free()
	await process_frame

func shot(name: String, settle: int = 6) -> void:
	for i in range(settle): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+name+".png")
	print("  shot ",name)

## Hold for `seconds` of real time so TIME-driven shaders actually advance.
func hold(seconds: float) -> void:
	var began: int = Time.get_ticks_msec()
	while Time.get_ticks_msec()-began<int(seconds*1000.0): await process_frame

# ------------------------------------------------------------------ groups --

func _cannon() -> void:
	await _clear()
	_dark(false)
	var gun: Node3D = Models.rotary_cannon()
	stage.add_child(gun)
	var rotor: Node3D = gun.get_node("GatlingRotor")
	var views := {
		"quarter": [Vector3(-1.95,0.82,-2.35),Vector3(0,0.0,0.45),30.0],
		"side": [Vector3(3.10,0.16,0.62),Vector3(0,0.0,0.62),30.0],
		"muzzle": [Vector3(-0.42,0.30,-2.05),Vector3(-0.02,0.0,-0.30),26.0],
		"aft": [Vector3(1.75,1.05,2.85),Vector3(0,0.05,1.10),32.0],
		"macro": [Vector3(-0.30,0.18,-1.28),Vector3(-0.02,0.0,-0.62),24.0],
		"barrels": [Vector3(0.90,0.10,-0.42),Vector3(0.0,0.0,-0.42),26.0]}
	for state in ["idle","hot"]:
		Models.set_heat(gun,0.0 if state=="idle" else 0.92)
		rotor.rotation.z = 0.0 if state=="idle" else 0.62
		for view: String in views:
			var v: Array = views[view]
			_look(v[0],v[1],v[2])
			await shot("cannon_%s_%s" % [view,state])

func _plasma() -> void:
	await _clear()
	_dark(false)
	var gun: Node3D = Models.plasma_cannon()
	stage.add_child(gun)
	var views := {
		"quarter": [Vector3(-1.45,0.62,-1.75),Vector3(0,0.0,0.25),30.0],
		"side": [Vector3(2.35,0.10,0.35),Vector3(0,0.0,0.35),30.0],
		"muzzle": [Vector3(-0.34,0.26,-1.55),Vector3(0,0.0,-0.35),26.0]}
	for state: Array in [["idle",0.0,0.0],["charged",0.85,0.0],["firing",1.0,1.0]]:
		Models.set_charge(gun,state[1],state[2])
		for view: String in views:
			var v: Array = views[view]
			_look(v[0],v[1],v[2])
			await shot("plasma_%s_%s" % [view,state[0]])

func _tracer() -> void:
	# The real stream combat.gd fires: Tune.GUN_MUZZLE_SPEED 1040 m/s, a 2-round
	# packet every Tune.GUN_INTERVAL (.0333 s), so packet NODES sit 34.63 m apart
	# and each one paints itself plus WeaponVisuals.GHOST_ROUNDS visual-only
	# rounds, giving a needle every 11.54 m.
	for backdrop in ["water","sky"]:
		await _clear()
		_dark(false)
		water.visible = backdrop=="water"
		var line := Node3D.new(); stage.add_child(line)
		var muzzle := Vector3(1.6,-0.6,-6.0)
		var aim: Vector3 = (Vector3(-38,26,-900) if backdrop=="sky" else Vector3(-26,-12,-900)).normalized()
		for i in range(26):
			var shot_node: Node3D = Art.projectile("cannon")
			line.add_child(shot_node)
			var travel: float = 6.0+i*34.63
			shot_node.position = muzzle+aim*travel
			shot_node.look_at(shot_node.position+aim,Vector3.UP)
			shot_node.scale.z = clampf(travel/9.0,0.01,1.0)
		_look(muzzle-aim*14.0+Vector3(0.6,1.4,0),muzzle+aim*420.0,38.0)
		await shot("tracer_"+backdrop)
		# Close in on the first rounds leaving the gun.
		_look(muzzle+Vector3(-3.6,1.5,-1.2),muzzle+aim*90.0,30.0)
		await shot("tracer_"+backdrop+"_near")
		# Broadside rig: the only view that shows a round's real streak shape.
		for child in line.get_children(): child.queue_free()
		await process_frame
		for i in range(5):
			var round_node: Node3D = Art.projectile("cannon")
			line.add_child(round_node)
			round_node.position = Vector3(-76.0+i*38.0,0,0)
			round_node.look_at(round_node.position+Vector3.RIGHT,Vector3.UP)
			round_node.scale.z = 1.0
		_look(Vector3(0,5,112),Vector3.ZERO,26.0)
		await shot("tracer_"+backdrop+"_side")
	water.visible = false

func _beam() -> void:
	# TWO configurations, because they are not the same picture:
	#   "beam_*"      the full stack WeaponVisuals can build - core + braid +
	#                 halo + crawling arcs + muzzle and impact coronas.
	#   "beamlive_*"  what combat_visuals.gd._update_designator actually draws
	#                 today: beams[0] only, its "Arcs" child hidden, lateral
	#                 scale 0.35, no blooms. This is the one a player sees, so
	#                 the gradient has to survive it.
	for backdrop in ["sky","dark"]:
		for rig_kind in ["full","live"]:
			await _clear()
			_dark(backdrop=="dark")
			water.visible = backdrop=="sky"
			var rig := Node3D.new(); stage.add_child(rig)
			var beams: Array[MeshInstance3D] = []
			beams.append(Art.beam(rig,Color(.72,.94,1),.10,1))
			beams.append(Art.energy_sheath(rig,.38,0))
			beams.append(Art.energy_sheath(rig,.72,1.4))
			var start := Vector3(0.8,-0.4,0.0)
			var end := Vector3(0.0,6.0,-600.0)
			for b in beams: Art.align_beam(b,start,end)
			var muzzle_glow: MeshInstance3D = null
			var impact_glow: MeshInstance3D = null
			if rig_kind=="full":
				muzzle_glow = Art.beam_bloom(rig,true); muzzle_glow.position = start
				impact_glow = Art.beam_bloom(rig,false); impact_glow.position = end
			else:
				# Exactly combat_visuals.gd:546-550.
				for index in range(beams.size()): beams[index].visible = index==0
				beams[0].scale.x = .35
				beams[0].scale.z = .35
				var arcs: Node = beams[0].get_node_or_null("Arcs")
				if arcs!=null: arcs.visible = false
			var prefix: String = "beam" if rig_kind=="full" else "beamlive"
			for view: String in ["chase","side"]:
				for step in range(3):
					if view=="chase": _look(Vector3(2.6,3.4,14.0),Vector3(0.2,2.0,-260.0),40.0)
					else: _look(Vector3(-155.0,26.0,-300.0),Vector3(0.0,3.0,-300.0),36.0)
					if muzzle_glow!=null:
						Art.drive_bloom(muzzle_glow,2.4,0.0,1.1)
						Art.drive_bloom(impact_glow,2.0,600.0,7.0)
					await shot("%s_%s_%s_t%d" % [prefix,backdrop,view,step])
					if step<2: await hold(0.5)
	water.visible = false

func _impact() -> void:
	for distance: float in [60.0,250.0]:
		for effect in ["cannon","plasma","kill"]:
			await _clear()
			_dark(false)
			var bird: Node3D = Goose.create()
			bird.scale = Vector3.ONE*3.0
			bird.position = Vector3(0,0,-distance)
			bird.rotation.y = deg_to_rad(28.0)
			stage.add_child(bird)
			# Hit point on the near flank, shot direction going away from us.
			var at: Vector3 = bird.position+Vector3(-1.6,0.7,2.4)
			# Oblique so the spray is not hidden behind the bird.
			var direction := Vector3(-0.85,0.22,-0.75).normalized()
			var nodes: Array[Node3D] = []
			for step in range(3):
				var fx: Node3D
				if effect=="cannon": fx = FX.cannon_hit(at,direction,3.0,false)
				# Radius 2.4, not 5.0: the arcs are meant to CRAWL the bird's
				# silhouette. At 5 m they swept a sphere twice the goose's span and
				# the capture was not showing what a hit looks like.
				elif effect=="plasma": fx = FX.plasma_hit(at,direction,3.0,Color(0,0,0,0),false)
				else: fx = FX.kill_accent(at,direction,3.2,false)
				stage.add_child(fx)
				nodes.append(fx)
				fx.visible = false
			var fov: float = 34.0 if distance<100.0 else 12.0
			_look(Vector3(0,2.0,10.0),bird.position,fov)
			for step in range(3):
				for i in range(nodes.size()): nodes[i].visible = i==step
				# Sampled where the effect actually LIVES. A cannon hit is a ~0.15 s
				# event on a 0.62 s schedule, so 0.12/0.34/0.66 spent two of its
				# three frames on an empty sky and told the reviewer nothing.
				FX.set_time(nodes[step],[0.06,0.20,0.45][step])
				await shot("impact_%s_%dm_t%d" % [effect,int(distance),step])
