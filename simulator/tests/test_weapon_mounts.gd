extends SceneTree
## Isolated aircraft/effects QA; never loads main.tscn or opens device inputs.
## --headless --audio-driver Dummy --script tests/test_weapon_mounts.gd
## Optional native -- --visual writes aircraft weapon views into build/weapons.
const Fighter = preload("res://systems/fighter_model.gd")
const Effects = preload("res://systems/fighter_effects.gd")
const Utils = preload("res://systems/model_utils.gd")
const Visuals = preload("res://systems/combat_visuals.gd")
const Tune = preload("res://data/balance.gd")

class CombatHarness extends Node:
	var app: Node
	var active := true
	var beam_active := false
	var beam_target_ids: Array[int]=[-1,-1]
	var beam_ends: Array[Vector3] = [Vector3(-100,0,-500), Vector3(100,0,-500)]
	var flares_fired := 0

class Harness extends Node3D:
	var aircraft: Node3D
	var combat: Node
	var fighter_fx: Node
	var flight := {"position": Vector3.ZERO}
	var overlay := false
	func overlay_visible() -> bool: return overlay
	func yoke_recovery_visible() -> bool: return false
	var mode := "flight"
	var cockpit := false

var checks := 0
var failures: Array[String] = []
var stage: Harness
var effects: Node3D

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error("WEAPON MOUNTS: " + label)

func run() -> void:
	stage = Harness.new()
	root.add_child(stage)
	stage.combat = CombatHarness.new()
	stage.combat.app = stage
	stage.add_child(stage.combat)
	stage.aircraft = Fighter.create()
	stage.add_child(stage.aircraft)
	effects = Effects.new()
	effects.app = stage
	stage.fighter_fx = effects
	stage.add_child(effects)
	effects.build()
	check(stage.aircraft.find_child("CG26",true,false) == null, "No rotary cannon is mounted")
	check(stage.aircraft.find_child("GatlingRotor",true,false) == null and stage.aircraft.find_child("GunMuzzle",true,false) == null, "No rotor or gun muzzle survives")
	check(effects.plasma_models.size() == 2 and effects.plasma_muzzles.size() == 2, "Two plasma emitters are bound")
	for index in range(2):
		var plasma: Node3D = effects.plasma_models[index]
		check(plasma != null and plasma.has_meta("charge_materials"), "Authored plasma cannon is mounted")
		check(effects.plasma_muzzle_position(Vector3.ZERO,index).is_equal_approx(Fighter.PLASMA_MUZZLES[index]), "Fallback agrees with actual scaled emitter")
		check(Utils.bounds(plasma).size.z > 2.5, "Mounted machinery has readable aircraft scale")
		for geometry: Node in plasma.find_children("*", "GeometryInstance3D", true, false):
			check(geometry.layers == 2, "Weapon geometry preserves aircraft rendering layer")
	check(effects.plasma_muzzle_position(Vector3.ZERO,0).x < -1.5 and effects.plasma_muzzle_position(Vector3.ZERO,1).x > 1.5, "Left and right emitters sit outside forward hull")
	stage.aircraft.position = Vector3(10, 20, 30)
	stage.aircraft.rotation.y = 0.7
	for index in range(2):
		check(effects.plasma_muzzle_position(Vector3.ZERO,index).is_equal_approx(stage.aircraft.to_global(Fighter.PLASMA_MUZZLES[index])), "Plasma origin follows aircraft world transform")
	stage.aircraft.transform = Transform3D.IDENTITY
	var emitter: Node3D = effects.plasma_muzzles[0]
	effects.plasma_muzzles[0] = null
	check(effects.plasma_muzzle_position(Vector3(4,5,6)) == Vector3(4,5,6), "Missing emitter uses caller fallback")
	effects.plasma_muzzles[0] = emitter
	check(effects.plasma_muzzle_position(Vector3(4,5,6),2) == Vector3(4,5,6), "Unknown emitter uses caller fallback")
	stage.combat.beam_active = true
	for frame in range(30): effects.update_plasma(1.0/60.0)
	check(effects.plasma_charge > 0.9, "Beam firing charges the mounted pair")
	for plasma in effects.plasma_models:
		var material: ShaderMaterial = plasma.get_meta("charge_materials")[0]
		check(float(material.get_shader_parameter("firing")) == 1.0, "Discharge reaches each cannon shader")
	stage.combat.beam_active = false
	for frame in range(90): effects.update_plasma(1.0/60.0)
	check(is_zero_approx(effects.plasma_charge), "Inactive machinery discharges")
	for plasma in effects.plasma_models:
		var material: ShaderMaterial = plasma.get_meta("charge_materials")[0]
		check(float(material.get_shader_parameter("firing")) == 0.0, "Release stops each discharge")
	check(effects.stores.size() == 4, "Four missile stores are attached")
	effects.missile_launch(-1, 0)
	check(not effects.stores[0].visible and effects.store_timers[0] > 0, "Missile launch hides the selected store")
	check(effects.stores[1].visible and effects.stores[2].visible and effects.stores[3].visible, "Other stores remain mounted")
	effects.reset()
	check(effects.stores[0].visible and effects.store_timers[0] == 0, "Reset replenishes the missile stores")
	var visuals := Visuals.new()
	visuals.combat = stage.combat
	stage.add_child(visuals)
	check(visuals.beams.size() == 6 and visuals.beam_lights.size() == 2, "Two independent three-layer beam sets")
	stage.combat.beam_active = true
	visuals.draw_plasma()
	for index in range(2):
		var origin: Vector3 = effects.plasma_muzzle_position(Vector3.ZERO,index)
		for layer in range(3):
			var beam: MeshInstance3D = visuals.beams[index*3+layer]
			check(beam.visible and beam.global_position.is_equal_approx(origin.lerp(stage.combat.beam_ends[index],0.5)), "Split beam uses its actual emitter and its own endpoint")
	stage.combat.beam_ends[1] = stage.combat.beam_ends[0]
	visuals.draw_plasma()
	check(not visuals.beams[0].global_position.is_equal_approx(visuals.beams[3].global_position), "Focused beams keep separate emitter origins")
	stage.overlay = true
	visuals.draw_plasma()
	check(not visuals.beams[0].visible and not visuals.beams[3].visible, "Overlay suppresses both beam groups")
	stage.overlay = false
	check(visuals.projectile_pool.keys() == ["missile"], "Only missile projectiles are pooled")
	check(visuals.take_projectile("cannon") == null, "Retired cannon cannot allocate a projectile")
	var missile: Node3D = visuals.take_projectile("missile")
	check(missile.visible and visuals.projectile_pool.missile.size() == Tune.MAX_MISSILES-1, "Missile checkout uses configured pool")
	visuals.reset()
	check(not missile.visible and visuals.projectile_pool.missile.size() == Tune.MAX_MISSILES, "Reset restores configured missile pool")
	stage.combat.beam_active = false
	visuals.queue_free()
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await capture_views()
	print("WEAPON MOUNTS: %d checks, %d failures" % [checks, failures.size()])
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture_views() -> void:
	root.size = Vector2i(1600, 1000)
	root.scaling_3d_scale = 1.0
	root.msaa_3d = Viewport.MSAA_4X
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.085, 0.105, 0.15)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.60, 0.70, 0.88)
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_color = Color(1.0, 0.84, 0.65)
	key.light_energy = 2.8
	stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 135, 0)
	rim.light_color = Color(0.40, 0.60, 1.0)
	rim.light_energy = 1.8
	stage.add_child(rim)
	var camera := Camera3D.new()
	camera.current = true
	stage.add_child(camera)
	var folder := ProjectSettings.globalize_path("res://../build/weapons")
	DirAccess.make_dir_recursive_absolute(folder)
	for view: Dictionary in [
		{"name": "mounted-overview", "from": Vector3(-15, 9, -19), "at": Vector3(0, 0, -1), "fov": 42.0},
		{"name": "mounted-plasma-left", "from": Vector3(-6, 2.6, -8.5), "at": Vector3(-1.55, 0.2, -2.75), "fov": 42.0},
		{"name": "mounted-plasma-right", "from": Vector3(6, 2.6, -8.5), "at": Vector3(1.55, 0.2, -2.9), "fov": 42.0}]:
		camera.position = view.from
		camera.look_at(view.at)
		camera.fov = view.fov
		stage.combat.beam_active = view.name != "mounted-overview"
		for frame in range(20):
			effects.update_plasma(1.0/60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "/" + view.name + ".png")
