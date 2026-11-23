extends SceneTree
## Standalone look harness for the flock. It builds the sky, sun and grading of
## the San Francisco world without loading a single terrain chunk, then drives
## real contacts through systems/goose_flight.gd so what is photographed is the
## code the game runs, not a posed mock-up.
##
##   Godot --path simulator --windowed --resolution 1600x1000 --script tests/studio_goose.gd
##   ... -- skein bank fall            # only those views
##   Godot --headless --path simulator --script tests/studio_goose.gd -- probe
##
## PNGs land in build/goose/.
const Model = preload("res://systems/goose_model.gd")
const Tune = preload("res://data/balance.gd")

const SKY_YAW_DEGREES := -79.8
const SUN_ENERGY := 3.0
const CRUISE := 20.0

class StubFlight extends RefCounted:
	var position := Vector3(0,0,260)
	var velocity := Vector3.ZERO
	var wind := Vector3.ZERO
	var heading := 0.0
	func forward() -> Vector3: return Vector3(sin(heading),0,-cos(heading))

class StubWorld extends RefCounted:
	var floor_height := -600.0
	func ground_height(_x: float,_z: float) -> float: return floor_height

class StubApp extends Node:
	var flight := StubFlight.new()
	var world := StubWorld.new()

class Flock extends Node:
	var app: Node
	var enemies: Array[Dictionary] = []
	var falling: Array[Dictionary] = []
	var skein_ids: Array[int] = []
	var engagement_enabled := true
	var next_id := 0
	func forward() -> Vector3: return app.flight.forward().normalized()
	func event(_kind: String,_at: Vector3 = Vector3.ZERO,_weight: float = 1.0) -> void: pass

# name: [flock size, seconds to settle, beat position (-1 = leave it running),
#        camera offset, look offset, fov, backdrop, frame around hero or flock]
# Beat positions: 0.00 wings fully up, 0.19 mid-downstroke (peak wing rate and
# peak tip flex), 0.38 wings fully down, 0.70 mid-recovery.
const VIEWS := {
	"skein":      [12, 7.0, -1.0, Vector3(90,70,300),  Vector3(0,0,0),  44.0, "water", "flock"],
	"skein_low":  [12, 9.0, -1.0, Vector3(150,-70,250),Vector3(0,0,0),  48.0, "sky",   "flock"],
	"skein_chase":[12, 7.0, -1.0, Vector3(0,34,330),   Vector3(0,0,-40),34.0, "water", "flock"],
	"beat_down":  [1,  2.0, 0.38, Vector3(30,10,26),   Vector3(0,0,0),  32.0, "water", "hero"],
	"beat_mid":   [1,  2.0, 0.19, Vector3(30,10,26),   Vector3(0,0,0),  32.0, "water", "hero"],
	"beat_up":    [1,  2.0, 0.00, Vector3(30,10,26),   Vector3(0,0,0),  32.0, "water", "hero"],
	"beat_sky":   [1,  2.0, 0.19, Vector3(26,-16,26),  Vector3(0,0,0),  32.0, "sky",   "hero"],
	"beat_top":   [1,  2.0, 0.38, Vector3(0,40,14),    Vector3(0,0,0),  32.0, "water", "hero"],
	"headon":     [1,  2.0, 0.30, Vector3(0,2,-44),    Vector3(0,0,0),  30.0, "hills", "hero"],
	"bank":       [1,  4.0, -1.0, Vector3(20,18,38),   Vector3(0,0,0),  36.0, "water", "hero"],
	"bank_rear":  [1,  4.0, -1.0, Vector3(-6,8,46),    Vector3(0,0,0),  34.0, "sky",   "hero"],
	"glide":      [1,  2.0, -1.0, Vector3(30,6,26),    Vector3(0,0,0),  32.0, "sky",   "hero"],
	"portrait":   [1,  2.0, 0.45, Vector3(-16,3,-16),  Vector3(0,1,-4), 26.0, "water", "hero"],
	"fall_early": [1,  0.35,-1.0, Vector3(30,12,30),   Vector3(0,0,0),  36.0, "water", "hero"],
	"fall_mid":   [1,  1.10,-1.0, Vector3(30,12,30),   Vector3(0,0,0),  36.0, "sky",   "hero"],
	"fall_late":  [1,  2.20,-1.0, Vector3(34,16,34),   Vector3(0,0,0),  36.0, "water", "hero"],
}
const ORDER := ["skein","skein_low","skein_chase","beat_down","beat_mid","beat_up","beat_sky","beat_top",
	"headon","bank","bank_rear","glide","portrait","fall_early","fall_mid","fall_late"]

var app: StubApp
var flock: Flock
var ground: MeshInstance3D
var water_material: StandardMaterial3D
var hill_material: StandardMaterial3D
var camera: Camera3D
var holder: Node3D

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var wanted := OS.get_cmdline_user_args()
	if "probe" in wanted:
		probe()
		return
	if DisplayServer.get_name()=="headless":
		printerr("Native GPU required (or pass -- probe)")
		quit(2)
		return
	var folder := ProjectSettings.globalize_path("res://../build/goose")
	DirAccess.make_dir_recursive_absolute(folder)
	_stage()
	for view: String in ORDER:
		if not wanted.is_empty() and view not in wanted: continue
		var spec: Array = VIEWS[view]
		_backdrop(str(spec[6]))
		_populate(int(spec[0]),view.begins_with("bank"),view=="glide")
		var hero: Dictionary = _settle(float(spec[1]),view.begins_with("fall"))
		if float(spec[2])>=0.0: _freeze(hero,float(spec[2]))
		camera.fov = float(spec[5])
		var basis: Basis = hero.node.transform.basis.orthonormalized()
		var centre: Vector3 = Vector3(hero.node.global_position)
		if str(spec[7])=="flock":
			centre = Vector3.ZERO
			for enemy: Dictionary in flock.enemies: centre += Vector3(enemy.position)
			centre /= maxf(float(flock.enemies.size()),1.0)
		camera.global_position = centre+basis*Vector3(spec[3])
		camera.look_at(centre+basis*Vector3(spec[4]),Vector3.UP)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+view+".png")
		print("GOOSE SHOT ",view," bank=%.1f deg beat=%.2f state=%s lod=%d prims=%d draws=%d" % [
			rad_to_deg(float(hero.get("bank",0.0))),float(hero.get("beat_u",0.0)),str(hero.get("reaction_state","-")),
			Model.current_lod(hero.node),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	quit(0)

## Headless sanity pass: the flock builds, flies, banks and dies without a GPU.
func probe() -> void:
	_harness()
	_populate(Tune.SKEIN_SIZE,false,false)
	var hero: Dictionary = _settle(8.0,false)
	var span := AABB(flock.enemies[0].position,Vector3.ZERO)
	for enemy: Dictionary in flock.enemies: span = span.expand(enemy.position)
	print("PROBE skein=",flock.enemies.size()," spread=",span.size.snapped(Vector3.ONE))
	print("PROBE hero bank=%.1f deg beat=%.2f lod=%d rank=%d" % [rad_to_deg(float(hero.bank)),float(hero.beat_u),int(hero.lod),int(hero.rank)])
	var leaders: Array[int] = []
	for enemy: Dictionary in flock.enemies:
		if int(enemy.rank)==0: leaders.append(int(enemy.id))
	print("PROBE point bird now id=",leaders," (rotates every ",Tune.SKEIN_LEAD_ROTATE,"s)")
	quit(0)

func _harness() -> void:
	app = StubApp.new(); root.add_child(app)
	flock = Flock.new(); flock.app = app; root.add_child(flock)

func _populate(count: int, turning: bool, gliding: bool) -> void:
	if flock==null: _harness()
	for enemy: Dictionary in flock.enemies + flock.falling:
		if is_instance_valid(enemy.node): enemy.node.queue_free()
	flock.enemies.clear(); flock.falling.clear(); flock.skein_ids.clear()
	var course := Vector3(0,0,-1)*CRUISE
	for rank in range(count):
		var slot: Vector3 = GooseFlight.formation_slot(rank)
		var node: Node3D = Model.create()
		node.scale = Vector3.ONE*Tune.CONTACT_MODEL_SCALE
		node.position = slot
		(holder if holder!=null else root as Node).add_child(node)
		var contact := {"id":rank,"node":node,"position":slot,"health":Tune.CONTACT_HEALTH,"max_health":Tune.CONTACT_HEALTH,
			"kind":"normal","size_factor":1.0,"hit_radius":Tune.CONTACT_HIT_RADIUS,"velocity":course,"course":course,
			"right":Vector3.RIGHT,"age":float(rank)*0.37,"phase":float(rank)*1.7,"fade":1.0,"retiring":false,
			"rank":rank,"hit_flash":0.0,"dying":-1.0}
		if gliding: contact["gliding"] = true; contact["glide_timer"] = 999.0
		if count>1: flock.skein_ids.append(rank)
		flock.enemies.append(contact)
	if turning: flock.enemies[0].right = Vector3.ZERO

func _settle(seconds: float, dying: bool) -> Dictionary:
	var hero: Dictionary = flock.enemies[0]
	var step := 1.0/120.0
	var elapsed := 0.0
	var killed := false
	while elapsed<seconds:
		if dying and not killed and elapsed>0.05:
			hero.health = 0.0
			GooseFlight.kill(flock,hero)
			killed = true
		if not killed:
			for enemy: Dictionary in flock.enemies:
				if flock.enemies.size()==1 and enemy.right==Vector3.ZERO:
					enemy.course = enemy.course.rotated(Vector3.UP,0.45*step)
				enemy.age = float(enemy.age)+step
				GooseFlight.update(flock,enemy,step)
		else:
			GooseFlight.update_falling(flock,step)
			if flock.falling.is_empty(): break
		# The camera rides with the flock instead of the flock outrunning it.
		app.flight.position = Vector3(hero.position)+Vector3(0,0,240)
		elapsed += step
	return hero

## Park the wingbeat at a chosen point in the cycle so the same pose can be
## photographed from several angles and compared between passes.
func _freeze(enemy: Dictionary, u: float) -> void:
	enemy.flap_phase = fposmod(u,1.0)*TAU
	enemy.gliding = false; enemy.glide_timer = 999.0; enemy.glide_blend = 0.0
	GooseFlight.update(flock,enemy,0.0001)

func _stage() -> void:
	_harness()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://assets/look/sunset_sky.gdshader")
	sky_material.set_shader_parameter("panorama",load("res://assets/look/kloppenheim_06_puresky_8k.hdr"))
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0,deg_to_rad(SKY_YAW_DEGREES),0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.16
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.25
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-10.0,-110,0)
	sun.light_color = Color(1.0,0.66,0.38)
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400
	root.add_child(sun)
	holder = Node3D.new(); root.add_child(holder)
	var plane := PlaneMesh.new()
	plane.size = Vector2(9000,9000)
	ground = MeshInstance3D.new()
	ground.mesh = plane
	ground.position = Vector3(0,-600,0)
	root.add_child(ground)
	water_material = StandardMaterial3D.new()
	water_material.albedo_color = Color(0.019,0.030,0.044)
	water_material.metallic = 0.85
	water_material.roughness = 0.10
	hill_material = StandardMaterial3D.new()
	hill_material.albedo_color = Color(0.095,0.230,0.072)
	hill_material.roughness = 0.92
	camera = Camera3D.new()
	camera.near = 0.2
	camera.far = 12000
	camera.current = true
	root.add_child(camera)

func _backdrop(kind: String) -> void:
	ground.visible = kind!="sky"
	ground.material_override = hill_material if kind=="hills" else water_material
