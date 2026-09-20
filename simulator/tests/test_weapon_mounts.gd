extends SceneTree
## Isolated aircraft/effects QA; never loads main.tscn or opens device inputs.
## --headless --audio-driver Dummy --script tests/test_weapon_mounts.gd
## Optional native -- --visual writes aircraft weapon views into build/weapons.
const Fighter = preload("res://systems/fighter_model.gd")
const Effects = preload("res://systems/fighter_effects.gd")
const Utils = preload("res://systems/model_utils.gd")

class Harness extends Node3D:
	var aircraft: Node3D
	var combat := {"active": true, "gun_firing_time": 0.0, "beam_active": false}
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
	stage.aircraft = Fighter.create()
	stage.add_child(stage.aircraft)
	effects = Effects.new()
	effects.app = stage
	stage.add_child(effects)
	effects.build()
	var gun: Node3D = stage.aircraft.find_child("CG26", true, false)
	var plasma: Node3D = stage.aircraft.find_child("PC26", true, false)
	check(gun != null and gun.has_meta("heat_materials"), "Authored rotary cannon is mounted")
	check(plasma != null and plasma.has_meta("charge_materials"), "Authored plasma cannon is mounted")
	check(effects.gun_rotor != null and effects.gun_gimbal.is_ancestor_of(effects.gun_rotor), "Only named barrel assembly spins inside recoil gimbal")
	check(effects.gun_muzzle_position(Vector3.ZERO).is_equal_approx(Fighter.MUZZLE), "Gun fallback agrees with actual scaled barrel tip")
	check(effects.plasma_muzzle_position(Vector3.ZERO).is_equal_approx(Fighter.PLASMA_MUZZLE), "Plasma fallback agrees with actual scaled emitter")
	check(effects.gun_muzzle.global_position.x < -1.5 and effects.plasma_muzzle.global_position.x > 1.5, "Both emitters sit outboard of the forward hull")
	check(Utils.bounds(gun).size.z > 4.5 and Utils.bounds(plasma).size.z > 2.5, "Mounted machinery has readable aircraft scale")
	for weapon: Node3D in [gun, plasma]:
		for geometry: Node in weapon.find_children("*", "GeometryInstance3D", true, false):
			check(geometry.layers == 2, "Weapon geometry preserves aircraft rendering layer")
	stage.aircraft.position = Vector3(10, 20, 30)
	stage.aircraft.rotation.y = 0.7
	check(effects.plasma_muzzle_position(Vector3.ZERO).is_equal_approx(stage.aircraft.to_global(Fighter.PLASMA_MUZZLE)), "Plasma origin follows aircraft world transform")
	stage.aircraft.transform = Transform3D.IDENTITY
	var emitter: Node3D = effects.plasma_muzzle
	effects.plasma_muzzle = null
	check(effects.plasma_muzzle_position(Vector3(4,5,6)) == Vector3(4,5,6), "Missing emitter uses caller fallback")
	effects.plasma_muzzle = emitter
	stage.combat.gun_firing_time = 1.0
	stage.combat.beam_active = true
	for frame in range(30): effects.update_gun(1.0/60.0)
	check(effects.rotor_speed > 0 and effects.gun_flash.visible, "Actual gun firing state spins rotor and lights flash")
	check(effects.gun_heat > 0.3 and effects.plasma_charge > 0.9, "Actual firing states drive heat and plasma charge")
	var heat_material: ShaderMaterial = gun.get_meta("heat_materials")[0]
	var charge_material: ShaderMaterial = plasma.get_meta("charge_materials")[0]
	check(float(heat_material.get_shader_parameter("heat")) > 0.3, "Heat reaches the mounted gun shader")
	check(float(charge_material.get_shader_parameter("firing")) == 1.0, "Beam discharge reaches the mounted plasma shader")
	stage.combat.gun_firing_time = 0.0
	stage.combat.beam_active = false
	for frame in range(90): effects.update_gun(1.0/60.0)
	check(effects.rotor_speed == 0 and not effects.gun_flash.visible, "Release stops muzzle effects and coasts rotor down")
	check(is_zero_approx(effects.gun_heat) and is_zero_approx(effects.plasma_charge), "Inactive machinery cools and discharges")
	check(effects.stores.size() == 4, "Four missile stores are attached")
	effects.missile_launch(-1, 0)
	check(not effects.stores[0].visible and effects.store_timers[0] > 0, "Missile launch hides the selected store")
	check(effects.stores[1].visible and effects.stores[2].visible and effects.stores[3].visible, "Other stores remain mounted")
	effects.reset()
	check(effects.stores[0].visible and effects.store_timers[0] == 0, "Reset replenishes the missile stores")
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
		{"name": "mounted-cannon", "from": Vector3(-6, 2.6, -8.5), "at": Vector3(-1.55, 0.2, -2.75), "fov": 42.0},
		{"name": "mounted-plasma", "from": Vector3(6, 2.6, -8.5), "at": Vector3(1.55, 0.2, -2.9), "fov": 42.0}]:
		camera.position = view.from
		camera.look_at(view.at)
		camera.fov = view.fov
		stage.combat.beam_active = view.name == "mounted-plasma"
		for frame in range(20):
			effects.update_gun(1.0/60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "/" + view.name + ".png")
