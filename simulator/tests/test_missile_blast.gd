extends SceneTree
## Isolated area-blast lifecycle/visual QA. No main scene or device inputs.
## COCKPIT_DISABLE_BADGE=1 Godot --headless --audio-driver Dummy --path simulator --script tests/test_missile_blast.gd
## Native -- --visual additionally writes build/weapons/blast/*.png.
const Visuals = preload("res://systems/combat_visuals.gd")
const Blast = preload("res://systems/missile_blast.gd")
var checks := 0
var failures: Array[String] = []
var stage: Node3D
var visuals: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label); push_error("MISSILE BLAST: " + label)
func run() -> void:
	stage = Node3D.new(); root.add_child(stage)
	visuals = Visuals.new(); stage.add_child(visuals)
	check(visuals.beams.size() == 6, "Twin plasma beam layers preserved")
	visuals.missile_blast(Vector3(15,20,-300),120.0)
	check(visuals.active_blast_count() == 1, "One detonation creates one blast")
	var blast: Node3D = visuals.missile_blasts[0]
	check(blast.global_position == Vector3(15,20,-300), "Detonation uses exact world position")
	visuals.position = Vector3(20,30,40)
	check(blast.global_position == Vector3(15,20,-300), "Blast stays fixed while owner moves")
	check(blast.find_children("*","OmniLight3D",true,false).size() == 1, "One bounded shadowless light per blast")
	check(not blast.light.shadow_enabled, "Blast light cannot spawn shadow renders")
	check(blast.find_children("*","GPUParticles3D",true,false).is_empty(), "Blast needs no GPU particle simulation")
	check(blast.shockwaves.size() == 2 and blast.clouds.size() == 10 and blast.fragments.size() == 8, "Layer counts are bounded")
	visuals.tick_missile_blasts(.20)
	check(not blast.get_node("IgnitionCore").visible, "White-hot core ends within 0.18 seconds")
	check(blast.shockwaves[0].node.visible and blast.shockwaves[0].node.scale.x > 30, "Shock ring expands in world metres")
	var elapsed: float = blast.elapsed
	blast.advance(-1.0); blast.advance(NAN)
	check(blast.elapsed == elapsed, "Invalid time cannot rewind or poison the effect")
	visuals.tick_missile_blasts(.40)
	check(not blast.light.visible, "Blast light extinguishes promptly")
	visuals.tick_missile_blasts(Blast.DURATION)
	check(visuals.active_blast_count() == 0 and not blast.visible, "Elapsed lifetime retires and hides blast")
	await process_frame
	check(not is_instance_valid(blast), "Retired geometry is freed")
	for index in range(12): visuals.missile_blast(Vector3(index*10,0,-500),120.0)
	check(visuals.active_blast_count() == Visuals.MAX_ACTIVE_BLASTS, "Rapid detonations respect active cap")
	await process_frame
	check(visuals.find_children("MissileAreaBlast*","Node3D",false,false).size() == Visuals.MAX_ACTIVE_BLASTS, "Replaced blast nodes are released")
	var light_count := 0
	for item in visuals.missile_blasts: light_count += item.find_children("*","OmniLight3D",true,false).size()
	check(light_count == Visuals.MAX_ACTIVE_BLASTS, "Blast lights obey same hard cap")
	visuals.missile_blast(Vector3(NAN,0,0),120); visuals.missile_blast(Vector3.ZERO,NAN); visuals.missile_blast(Vector3.ZERO,-2)
	check(visuals.active_blast_count() == Visuals.MAX_ACTIVE_BLASTS, "Invalid detonations allocate nothing")
	visuals.reset()
	check(visuals.active_blast_count() == 0, "Reset clears active lifecycle state")
	await process_frame
	check(visuals.find_children("MissileAreaBlast*","Node3D",false,false).is_empty(), "Reset frees every blast")
	visuals.position = Vector3.ZERO
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless": await capture()
	print("MISSILE BLAST: %d checks, %d failures" % [checks,failures.size()])
	stage.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

func capture() -> void:
	root.size = Vector2i(1600,1000); root.scaling_3d_scale = 1.0; root.msaa_3d = Viewport.MSAA_4X
	var env := Environment.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://assets/look/sunset_sky.gdshader")
	sky_material.set_shader_parameter("panorama",load("res://assets/look/kloppenheim_06_puresky_8k.hdr"))
	var sky := Sky.new(); sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY; env.sky = sky; env.sky_rotation = Vector3(0,-1.4,0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; env.ambient_light_energy = .8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true; env.glow_intensity = .30; env.glow_hdr_threshold = 2.2
	var world := WorldEnvironment.new(); world.environment = env; stage.add_child(world)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-22,-105,0)
	sun.light_color = Color(1,.72,.42); sun.light_energy = 2.2; stage.add_child(sun)
	var floor := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(10000,10000)
	floor.mesh = plane; floor.position.y = -140
	var sea := StandardMaterial3D.new(); sea.albedo_color = Color(.025,.05,.075); sea.metallic = .6; sea.roughness = .45
	floor.material_override = sea; stage.add_child(floor)
	var camera := Camera3D.new(); camera.current = true; camera.fov = 50; camera.far = 12000; stage.add_child(camera)
	var folder := ProjectSettings.globalize_path("res://../build/weapons/blast")
	DirAccess.make_dir_recursive_absolute(folder)
	for distance: float in [500.0,1500.0]:
		camera.position = Vector3(0,35,distance); camera.look_at(Vector3.ZERO)
		visuals.missile_blast(Vector3.ZERO,120.0)
		var effect: Node3D = visuals.missile_blasts[0]
		for time: float in [.06,.30,.70,1.40,2.60]:
			visuals.tick_missile_blasts(time-effect.elapsed)
			for frame in range(6): await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(folder+"/%dm-%03dms.png" % [int(distance),int(time*1000)])
		visuals.reset(); await process_frame
