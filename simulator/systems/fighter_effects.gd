extends Node3D
class_name FighterEffects
const Tune = preload("res://data/balance.gd")
const WeaponArt = preload("res://systems/weapon_visuals.gd")
const Fighter = preload("res://systems/fighter_model.gd")
const WeaponModels = preload("res://systems/weapon_models.gd")
const Utils = preload("res://systems/model_utils.gd")

# --- afterburner geometry -------------------------------------------------------
# The F135 nozzle exit measures ~1.0 m across (twelve petals, outer lip 0.65 m radius);
# full reheat on a 15 m jet throws a structured plume of about 14 m, a little under one
# airframe length, which is what every reheat photograph of an F-15/F-16/F-35 shows.
const NOZZLE_RADIUS := 0.55
const PLUME_DRY_MIN := 1.15
const PLUME_DRY_MAX := 3.00
const PLUME_REHEAT := 10.70
const STACK_SLOTS := 16
const IGNITION_TIME := 0.45
const CAMERA_CLEARANCE := 5.5   # the plume tip never comes closer than this to the camera
const TRAIL_LIFE := 1.1

var app: Node
var exhaust: MeshInstance3D                 # the axial slice (side view)
var exhaust_material: ShaderMaterial
var exhaust_sheath: MeshInstance3D          # the rim-lit membrane around the column
var sheath_material: ShaderMaterial
var plume_stack: MultiMeshInstance3D        # stacked Mach-disk slices (rear view)
var stack_mesh: MultiMesh
var stack_material: ShaderMaterial
var nozzle_glow: MeshInstance3D             # the view into the nozzle
var glow_material: ShaderMaterial
var nozzle_flare: MeshInstance3D            # bloom + anamorphic streak
var flare_material: ShaderMaterial
var shock_ring: MeshInstance3D              # ignition burst
var ring_material: ShaderMaterial
var haze: MeshInstance3D
var haze_material: ShaderMaterial
var exhaust_light: OmniLight3D
var airframe_fill: OmniLight3D
var vapor_shock: MeshInstance3D
var vapor_wings: Array[MeshInstance3D] = []
var vapor_material: ShaderMaterial
var shock_material: ShaderMaterial
var condensation: Array[MeshInstance3D] = []
var tip_material: ShaderMaterial
var trails: Array[MeshInstance3D] = []
var trail_points: Array[Array] = [[],[]]
var particles: Array[Dictionary] = []
var stores: Array[Node3D] = []
var parachute: Node3D
var chute_clock := 0.0
var sonic_armed := true
var clock := 0.0
var plasma_models: Array[Node3D] = []
var plasma_muzzles: Array[Node3D] = []
var plasma_charge := 0.0
var tyre_puffs: Array[MeshInstance3D] = []
var tyre_smoke_age := 2.0
var tyre_smoke_strength := 0.0
var last_store := 0
var store_timers: Array[float] = [0,0,0,0]
var wind_field: MeshInstance3D
var wind_points: Array[Vector3] = []
var wind_rng := RandomNumberGenerator.new()
# burner state
var ab_power := 0.0
var dry_power := 0.0
var ignition := 0.0
var reheat_latched := false
var plume_length := 0.0
var last_g := 1.0
var g_rate := 0.0
static var _burner_noise: NoiseTexture2D
static var _soft_puff: GradientTexture2D

## assets/sourced_flight/smoke.png carries opaque pixels right up to its border, so any
## sprite scaled past a metre or two draws a visible square card. Everything that stretches
## - tyre smoke, wingtip ribbons and speed streaks - uses this instead.
static func soft_puff() -> GradientTexture2D:
	if _soft_puff==null:
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0,0.22,0.55,1.0])
		ramp.colors = PackedColorArray([Color(1,1,1,0.85),Color(1,1,1,0.46),Color(1,1,1,0.13),Color(1,1,1,0)])
		_soft_puff = GradientTexture2D.new()
		_soft_puff.width = 64; _soft_puff.height = 64
		_soft_puff.fill = GradientTexture2D.FILL_RADIAL
		_soft_puff.fill_from = Vector2(0.5,0.5); _soft_puff.fill_to = Vector2(1.0,0.5)
		_soft_puff.gradient = ramp
	return _soft_puff

static func burner_noise() -> NoiseTexture2D:
	if _burner_noise==null:
		var field := FastNoiseLite.new()
		field.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		field.frequency = 0.035; field.fractal_octaves = 3; field.fractal_gain = 0.45
		_burner_noise = NoiseTexture2D.new()
		_burner_noise.width = 256; _burner_noise.height = 256
		_burner_noise.seamless = true; _burner_noise.generate_mipmaps = true
		_burner_noise.noise = field
	return _burner_noise

func build() -> void:
	for store: Node3D in stores:
		if is_instance_valid(store): store.queue_free()
	for child: Node in get_children(): child.queue_free()
	tyre_puffs.clear()
	plasma_models.clear(); plasma_muzzles.clear(); plasma_charge = 0.0
	for name in ["PC26Left", "PC26Right"]:
		var model: Node3D = app.aircraft.find_child(name, true, false)
		plasma_models.append(model)
		plasma_muzzles.append(model.find_child("BeamMuzzle", true, false) if is_instance_valid(model) else null)
	condensation.clear(); trails.clear(); stores.clear(); particles.clear(); trail_points = [[],[]]
	vapor_wings.clear()
	_build_burner()
	_build_vapour()   # also creates tip_material, used by the wingtip puffs below
	_build_tyre_puffs()
	airframe_fill = OmniLight3D.new()
	airframe_fill.light_cull_mask = 2
	airframe_fill.light_color = Color(1.0,.93,.84)
	airframe_fill.light_energy = 2.6
	airframe_fill.omni_range = 24
	airframe_fill.omni_attenuation = .6
	airframe_fill.shadow_enabled = false
	add_child(airframe_fill)
	for side in [-1,1]:
		# A procedural puff, not a photographic sprite: smoke.png shows its own square
		# texture border the moment it is scaled up to wingtip-vortex size.
		var vapor := MeshInstance3D.new()
		var puff := QuadMesh.new(); puff.size = Vector2(2,2)
		vapor.mesh = puff
		vapor.material_override = tip_material
		vapor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vapor.custom_aabb = AABB(Vector3(-5,-5,-5),Vector3(10,10,10))
		vapor.visible = false
		add_child(vapor); condensation.append(vapor)
		var trail := MeshInstance3D.new(); trail.mesh = ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = soft_puff()
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail.material_override = material
		trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(trail); trails.append(trail)
	wind_rng.seed = 202609
	wind_field = MeshInstance3D.new(); wind_field.mesh = ImmediateMesh.new()
	var wind_material := StandardMaterial3D.new()
	wind_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wind_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wind_material.albedo_texture = soft_puff()
	wind_material.vertex_color_use_as_albedo = true
	wind_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	wind_field.material_override = wind_material
	wind_field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wind_field)
	for i in range(28):
		wind_points.append(Vector3(wind_rng.randf_range(-24,24),wind_rng.randf_range(-18,18),wind_rng.randf_range(-45,24)))

	store_timers = [0,0,0,0]
	for i in range(4):
		var store: Node3D = WeaponArt.missile()
		for geometry: Node in store.find_children("*","GeometryInstance3D",true,false): geometry.layers = 2
		var mount := Node3D.new()
		mount.name = "MissileStore%d" % (i + 1)
		mount.add_child(store)
		app.aircraft.add_child(mount)
		mount.position = Vector3((-1 if i<2 else 1)*(2.8+(i%2)*1.25),-1.14,2.85)
		stores.append(mount)

## The burner is five cooperating pieces, cross-faded by view angle so it reads from the
## side AND from straight up the pipe: an axial slice that carries the shock train, a
## rim-lit sheath for silhouette and the violet/blue outer flame, a stack of end-on slices
## for the chase view, the glowing nozzle interior, and one bloom flare over the exit.
func _build_burner() -> void:
	var noise: NoiseTexture2D = burner_noise()
	var burner: Shader = load("res://assets/vfx/afterburner.gdshader")
	# sheath: a unit tube the vertex stage bends to the plume profile
	var tube := CylinderMesh.new()
	tube.top_radius = 1.0; tube.bottom_radius = 1.0; tube.height = 1.0
	tube.radial_segments = 32; tube.rings = 20; tube.cap_top = false; tube.cap_bottom = false
	exhaust_sheath = MeshInstance3D.new(); exhaust_sheath.mesh = tube
	sheath_material = ShaderMaterial.new(); sheath_material.shader = burner
	sheath_material.set_shader_parameter("layer",1)
	sheath_material.set_shader_parameter("noise",noise)
	exhaust_sheath.material_override = sheath_material
	exhaust_sheath.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheath_material.render_priority = -2
	add_child(exhaust_sheath)
	# axial slice
	exhaust = MeshInstance3D.new()
	var slice := QuadMesh.new(); slice.size = Vector2(1,1)
	exhaust.mesh = slice
	exhaust_material = ShaderMaterial.new()
	exhaust_material.shader = load("res://assets/vfx/afterburner_core.gdshader")
	exhaust_material.set_shader_parameter("noise",noise)
	exhaust_material.set_shader_parameter("brightness",0.68)
	exhaust_material.render_priority = -1
	exhaust.material_override = exhaust_material
	exhaust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(exhaust)
	# end-on slices for the rear view
	var sprite: Shader = load("res://assets/vfx/glow_sprite.gdshader")
	var card := QuadMesh.new(); card.size = Vector2(2,2)   # half-extent 1 -> INSTANCE_CUSTOM.x is a radius
	stack_mesh = MultiMesh.new()
	stack_mesh.transform_format = MultiMesh.TRANSFORM_3D
	stack_mesh.use_custom_data = true
	stack_mesh.mesh = card
	stack_mesh.instance_count = STACK_SLOTS
	stack_mesh.visible_instance_count = 0
	plume_stack = MultiMeshInstance3D.new()
	plume_stack.multimesh = stack_mesh
	stack_material = ShaderMaterial.new(); stack_material.shader = sprite
	stack_material.set_shader_parameter("mode",2)
	stack_material.set_shader_parameter("intensity",1.0)
	stack_material.render_priority = 0
	plume_stack.material_override = stack_material
	plume_stack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plume_stack)
	# nozzle interior
	nozzle_glow = MeshInstance3D.new()
	var disc := QuadMesh.new(); disc.size = Vector2(1,1); nozzle_glow.mesh = disc
	glow_material = ShaderMaterial.new(); glow_material.shader = burner
	glow_material.set_shader_parameter("layer",2)
	glow_material.set_shader_parameter("noise",noise)
	glow_material.render_priority = 1
	nozzle_glow.material_override = glow_material
	nozzle_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(nozzle_glow)
	# nozzle flare and the ignition shock ring
	nozzle_flare = MeshInstance3D.new(); nozzle_flare.mesh = card
	flare_material = ShaderMaterial.new(); flare_material.shader = sprite
	flare_material.set_shader_parameter("mode",0)
	flare_material.set_shader_parameter("streak_tint",Color(0.48,0.70,1.0))
	flare_material.render_priority = 2
	nozzle_flare.material_override = flare_material
	nozzle_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nozzle_flare.custom_aabb = AABB(Vector3(-5,-5,-5),Vector3(10,10,10))
	add_child(nozzle_flare)
	shock_ring = MeshInstance3D.new(); shock_ring.mesh = card
	ring_material = ShaderMaterial.new(); ring_material.shader = sprite
	ring_material.set_shader_parameter("mode",1)
	ring_material.set_shader_parameter("tint",Color(1.0,0.84,0.66))
	ring_material.set_shader_parameter("streak",0.0)
	ring_material.set_shader_parameter("ring",1.0)
	ring_material.render_priority = 2
	shock_ring.material_override = ring_material
	shock_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shock_ring.custom_aabb = AABB(Vector3(-10,-10,-10),Vector3(20,20,20))
	shock_ring.visible = false
	add_child(shock_ring)
	exhaust_light = OmniLight3D.new()
	exhaust_light.light_color = Color(1,.42,.14)
	exhaust_light.omni_range = 26
	exhaust_light.omni_attenuation = 1.8
	exhaust_light.shadow_enabled = false
	add_child(exhaust_light)
	haze = MeshInstance3D.new()
	var haze_quad := QuadMesh.new(); haze_quad.size = Vector2(1,1)
	haze.mesh = haze_quad
	haze_material = ShaderMaterial.new()
	haze_material.shader = load("res://assets/vfx/heat_haze.gdshader")
	haze_material.set_shader_parameter("noise",burner_noise())
	haze.material_override = haze_material
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The refraction pass is the one blend_mix element here: it must draw BEFORE the additive
	# plume, or it mixes 30% of the plain backdrop back over the flame.
	haze_material.render_priority = -6
	add_child(haze)

## Condensation that clings to the jet: the transonic shock cloud over the rear fuselage
## and a shallow blister of cloud on each wing under G. Never a card across the view.
func _build_vapour() -> void:
	var shader: Shader = load("res://assets/vfx/vapor_cone.gdshader")
	var noise: NoiseTexture2D = burner_noise()
	var cone := CylinderMesh.new()
	# The audit asked for a 5.2 m / 9 m cone. That covers half the frame from abeam, which
	# is the veil the owner forbade, so it is a smaller, thinner-walled shell instead.
	cone.top_radius = 3.6; cone.bottom_radius = 0.30; cone.height = 7.5
	cone.radial_segments = 28; cone.rings = 6; cone.cap_top = false; cone.cap_bottom = false
	vapor_shock = MeshInstance3D.new(); vapor_shock.mesh = cone
	shock_material = ShaderMaterial.new(); shock_material.shader = shader
	shock_material.set_shader_parameter("mode",0)
	shock_material.set_shader_parameter("noise",noise)
	shock_material.set_shader_parameter("ceiling",0.24)
	shock_material.set_shader_parameter("rim",1.65)
	shock_material.render_priority = -4
	vapor_shock.material_override = shock_material
	vapor_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vapor_shock.visible = false
	add_child(vapor_shock)
	vapor_material = ShaderMaterial.new(); vapor_material.shader = shader
	vapor_material.set_shader_parameter("mode",1)
	vapor_material.set_shader_parameter("noise",noise)
	vapor_material.set_shader_parameter("ceiling",0.38)
	vapor_material.set_shader_parameter("rim",0.70)
	vapor_material.render_priority = -4
	vapor_material.set_shader_parameter("bulge",0.60)
	tip_material = ShaderMaterial.new(); tip_material.shader = shader
	tip_material.set_shader_parameter("mode",2)
	tip_material.set_shader_parameter("noise",noise)
	tip_material.set_shader_parameter("ceiling",0.30)
	tip_material.set_shader_parameter("rim",0.70)
	tip_material.render_priority = -3
	tip_material.set_shader_parameter("size",1.15)
	for i in range(2):
		var sheet := PlaneMesh.new()
		sheet.size = Vector2(4.4,6.4); sheet.subdivide_width = 12; sheet.subdivide_depth = 14
		var node := MeshInstance3D.new(); node.mesh = sheet
		node.material_override = vapor_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-3,-1,-4),Vector3(6,3,8))
		node.visible = false
		add_child(node); vapor_wings.append(node)

func missile_launch(_side: float, index: int = -1) -> void:
	last_store += 1
	if index>=0 and index<stores.size():
		store_timers[index] = Tune.MISSILE_INTERVAL
		stores[index].visible = false

func update(dt: float, visual_flight: FlightDynamics = null) -> void:
	_update_tyre_smoke(dt)
	clock += dt
	update_plasma(dt)
	for i in range(stores.size()):
		store_timers[i] = maxf(0,store_timers[i]-dt)
		stores[i].visible = store_timers[i]<.22
		for geometry: Node in stores[i].find_children("*","GeometryInstance3D",true,false): geometry.transparency = clampf(store_timers[i]/.22,0,1)
	var f: FlightDynamics = app.flight if visual_flight==null else visual_flight
	var basis := Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	airframe_fill.position = f.position+basis*Vector3(0,7,5)
	airframe_fill.visible = not app.cockpit
	update_wind(dt,basis,f)
	update_burner(dt,f,basis)
	update_vapour(dt,f,basis)
	# A supersonic crew outruns its own pressure wave: the boom is a distant muffled
	# thump plus the airframe jolt, not a bang in the pilot's headset.
	if f.speed>335 and sonic_armed:
		sonic_armed = false
		app.audio.play_effect("sonic",-26)
		app.camera_rig.impulse(0.23)
	if f.speed<320: sonic_armed = true
	for i in range(particles.size()-1,-1,-1):
		var item: Dictionary = particles[i]
		item.life -= dt
		if item.life<=0:
			item.node.queue_free(); particles.remove_at(i)
		else:
			item.velocity.y -= dt*8
			item.node.position += item.velocity*dt
			item.node.rotation += item.spin*dt
			item.node.transparency = clampf(1-item.life,0,1)

func update_burner(dt: float, f: FlightDynamics, basis: Basis) -> void:
	var demand: float = clampf(f.engine if f.afterburner else 0.0,0.0,1.0)
	ab_power = lerpf(ab_power,demand,1.0-exp(-dt*(7.5 if demand>ab_power else 3.4)))
	dry_power = lerpf(dry_power,clampf((f.engine-0.08)/0.80,0,1),1.0-exp(-dt*5.0))
	if demand>0.40 and not reheat_latched:
		reheat_latched = true; ignition = 1.0
	elif demand<0.15:
		reheat_latched = false
	ignition = maxf(0.0,ignition-dt/IGNITION_TIME)
	var flash: float = ignition*ignition
	var overshoot: float = sin(PI*ignition)
	var burn: float = ab_power
	var live: float = maxf(burn,dry_power*0.34)
	var nozzle: Vector3 = f.position+basis*Fighter.NOZZLE
	var aft: Vector3 = basis.z
	var lit: bool = f.engine>0.10 or burn>0.01
	# length, with a slow breathe and a lunge on light-up
	var want: float = lerpf(PLUME_DRY_MIN,PLUME_DRY_MAX,dry_power)+PLUME_REHEAT*pow(burn,0.85)
	want *= 1.0+0.028*sin(clock*17.3)+0.018*sin(clock*29.7+1.1)
	want *= 1.0+0.34*overshoot
	var to_camera: Vector3 = app.camera.global_position-nozzle
	var axial: float = to_camera.dot(aft)
	if axial>0.0 and (to_camera-aft*axial).length()<9.0:
		want = minf(want,maxf(1.6,axial-CAMERA_CLEARANCE))   # the tip never reaches the chase camera
	plume_length = lerpf(plume_length,want,1.0-exp(-dt*9.0))
	var length: float = maxf(plume_length,0.35)
	var radius: float = NOZZLE_RADIUS*lerpf(0.72,1.0,live)
	var spread: float = lerpf(1.70,2.55,burn)
	var cells: float = lerpf(3.2,6.6,burn)
	var reheat: float = clampf(0.40+burn*0.60,0.0,1.0)
	var mid: Vector3 = nozzle+aft*(length*0.5)
	# Cross-fade the side slice against the end-on stack by how far the camera is off axis.
	var view_dir: Vector3 = (app.camera.global_position-mid).normalized()
	var align: float = absf(view_dir.dot(aft))
	var side_w: float = clampf(1.45*sqrt(maxf(0.0,1.0-align*align)),0.0,1.0)
	# The end-on stack only takes over in the last few degrees; off axis the slice already
	# carries the shock train, and stacked sprites there would read as a chain of blobs.
	var rear_w: float = smoothstep(0.86,0.995,align)
	var share: float = 1.0/maxf(1.0,side_w+rear_w)
	side_w *= share; rear_w *= share
	var across: Vector3 = view_dir-aft*view_dir.dot(aft)
	if across.length()<0.001: across = basis.y
	across = across.normalized()
	var up_dir: Vector3 = across.cross(aft).normalized()
	var slice_basis := Basis(aft,up_dir,across)
	var half: float = radius*spread*1.55+0.45
	exhaust.visible = lit and side_w>0.004
	exhaust.basis = slice_basis*Basis.from_scale(Vector3(length,half*2.0,1.0))
	exhaust.position = mid
	exhaust_material.set_shader_parameter("power",live*(1.0+0.9*flash))
	exhaust_material.set_shader_parameter("reheat",reheat)
	exhaust_material.set_shader_parameter("visibility",side_w)
	exhaust_material.set_shader_parameter("cells",cells)
	exhaust_material.set_shader_parameter("core_radius",radius/half)
	exhaust_material.set_shader_parameter("spread",spread)
	exhaust_sheath.visible = lit and live>0.02
	exhaust_sheath.basis = basis*Basis(Vector3.RIGHT,PI/2)*Basis.from_scale(Vector3(1,length,1))
	exhaust_sheath.position = mid
	sheath_material.set_shader_parameter("power",live*(0.35+0.65*side_w))
	sheath_material.set_shader_parameter("reheat",reheat)
	sheath_material.set_shader_parameter("core_radius",radius)
	sheath_material.set_shader_parameter("spread",spread)
	stack_material.set_shader_parameter("tint",Color(0.42,0.60,1.0).lerp(Color(1.0,0.50,0.14),reheat))
	stack_material.set_shader_parameter("rim_tint",Color(0.34,0.46,1.0).lerp(Color(0.62,0.26,1.0),burn))
	_update_stack(nozzle,aft,length,radius,spread,cells,live,rear_w,flash,lit)
	nozzle_glow.visible = f.engine>0.06
	nozzle_glow.basis = basis*Basis.from_scale(Vector3(1.30,1.30,1.0))
	nozzle_glow.position = nozzle+aft*0.04
	glow_material.set_shader_parameter("power",clampf(0.16+dry_power*0.52+burn*0.98,0.0,1.7))
	glow_material.set_shader_parameter("reheat",reheat)
	nozzle_flare.visible = lit and (live>0.01 or dry_power>0.05)
	nozzle_flare.position = nozzle+aft*0.55
	flare_material.set_shader_parameter("size",lerpf(0.80,2.50,live)*(1.0+0.85*flash))
	flare_material.set_shader_parameter("intensity",(lerpf(0.24,1.60,live)+0.20*dry_power)*(1.0+3.6*flash))
	flare_material.set_shader_parameter("streak",0.18+0.34*burn)
	flare_material.set_shader_parameter("tint",Color(1.0,0.66,0.34).lerp(Color(1.0,0.46,0.12),burn))
	var ring_age: float = clampf((1.0-ignition)/0.62,0.0,1.0)
	shock_ring.visible = ignition>0.52
	if shock_ring.visible:
		shock_ring.position = nozzle+aft*(0.5+5.0*ring_age)
		ring_material.set_shader_parameter("size",lerpf(1.2,4.6,ring_age))
		ring_material.set_shader_parameter("intensity",0.42*pow(1.0-ring_age,1.9))
		ring_material.set_shader_parameter("ring_radius",lerpf(0.34,0.80,ring_age))
		ring_material.set_shader_parameter("ring_width",lerpf(0.16,0.42,ring_age))
	exhaust_light.visible = lit
	exhaust_light.position = nozzle+aft*minf(3.2,length*0.35)
	exhaust_light.light_color = Color(1,.62,.34).lerp(Color(1,.42,.14),burn)
	exhaust_light.omni_range = lerpf(11.0,26.0,live)
	exhaust_light.light_energy = (live*7.0+dry_power*0.55)*(1.0+4.0*flash)
	haze.visible = not app.cockpit and f.engine>0.30
	haze.basis = slice_basis*Basis.from_scale(Vector3(length*0.98,radius*spread*4.4,1.0))
	haze.position = nozzle+aft*(length*0.48)
	haze_material.set_shader_parameter("power",clampf((live-0.12)*1.50,0,1))

## Places the end-on slices. The Mach disks sit where the analytic shock phase
## cells*u*(1-0.30u) crosses a whole number - the same curve the slice shader walks -
## so the bright rings in the chase view land on the diamonds seen from the side.
func _update_stack(nozzle: Vector3, aft: Vector3, length: float, radius: float, spread: float, cells: float, live: float, weight: float, flash: float, lit: bool) -> void:
	var stations: Array[float] = []
	for k in range(1,7):
		var inner: float = 1.0-1.2*float(k)/maxf(cells,0.1)
		if inner<0.0: break
		var station: float = (1.0-sqrt(inner))/0.6
		if station>0.94: break
		stations.append(station)
	var samples: Array[Vector2] = [Vector2(0.012,0.0)]   # x = station, y = 1 on a Mach disk
	var previous := 0.012
	for station: float in stations:
		samples.append(Vector2((previous+station)*0.5,0.0))
		samples.append(Vector2(station,1.0))
		previous = station
	samples.append(Vector2(minf(0.96,(previous+1.0)*0.5),0.0))
	samples.append(Vector2(0.93,0.0))
	var used: int = mini(samples.size(),STACK_SLOTS)
	for i in range(used):
		var u: float = samples[i].x
		var disk: float = samples[i].y
		var local_r: float = radius*(1.0+(spread-1.0)*pow(u,1.30))
		var train: float = exp(-2.35*u)
		var strength: float = live*pow(1.0-u,1.35)*(0.18+1.80*disk*train)*(1.0+1.2*flash)*1.4
		stack_mesh.set_instance_transform(i,Transform3D(Basis(),nozzle+aft*(length*u)))
		stack_mesh.set_instance_custom_data(i,Color(local_r*(1.30 if disk>0.5 else 1.45),strength*pow(weight,1.8),disk*train,u))
	stack_mesh.visible_instance_count = used
	plume_stack.visible = lit and weight>0.01 and live>0.02
	plume_stack.custom_aabb = AABB(nozzle-Vector3.ONE*(length+6.0),Vector3.ONE*(length*2.0+12.0))

func update_vapour(dt: float, f: FlightDynamics, basis: Basis) -> void:
	var mach: float = f.speed/335.0
	var humidity: float = clampf(1.0-(f.position.y-150.0)/900.0,0.25,1.0)
	var world: Node = app.get("world")
	if is_instance_valid(world):
		var clouds: Variant = world.get("cloud_presence")
		if clouds!=null: humidity = maxf(humidity,clampf(float(clouds),0.0,1.0))
		var sun: Variant = world.get("sun")
		if sun is DirectionalLight3D:
			var lamp: DirectionalLight3D = sun
			for material: ShaderMaterial in [vapor_material,shock_material,tip_material]:
				material.set_shader_parameter("light_dir",-lamp.global_basis.z)
				material.set_shader_parameter("light_color",lamp.light_color.lerp(Color(1,1,1),0.70))
	# A continuous function of Mach, not a latch: it blooms across Mach 1 and dissolves.
	var band: float = smoothstep(0.88,0.96,mach)*(1.0-smoothstep(1.02,1.14,mach))
	g_rate = lerpf(g_rate,(f.g_load-last_g)/maxf(dt,0.0001),1.0-exp(-dt*6.0))
	last_g = f.g_load
	var scroll: float = clock*0.55
	var shock_amount: float = band*humidity
	vapor_shock.visible = shock_amount>0.02 and f.airborne and not app.cockpit
	if vapor_shock.visible:
		vapor_shock.basis = basis*Basis(Vector3.RIGHT,PI/2)
		vapor_shock.position = f.position+basis*Vector3(0,-0.35,1.6)
		shock_material.set_shader_parameter("amount",shock_amount)
		shock_material.set_shader_parameter("humidity",humidity)
		shock_material.set_shader_parameter("scroll",scroll)
	var pull: float = clampf((f.g_load-3.0)/2.6,0,1)*(0.25+humidity*0.75)
	var wing_on: bool = pull>0.02 and f.airborne and not app.cockpit
	for i in range(vapor_wings.size()):
		var side: float = -1.0 if i==0 else 1.0
		vapor_wings[i].visible = wing_on
		if wing_on:
			vapor_wings[i].basis = basis
			vapor_wings[i].position = f.position+basis*Vector3(side*3.25,-0.12,0.35)
	if wing_on:
		vapor_material.set_shader_parameter("amount",pull)
		vapor_material.set_shader_parameter("humidity",humidity)
		vapor_material.set_shader_parameter("scroll",scroll*1.4)
	# Wingtip vortex condensation: it should flash on a hard pull and go away again,
	# not stream two permanent 500 m ribbons through every chase shot.
	var tip: float = clampf((f.g_load-3.2)/2.5,0,1)*clampf(g_rate*0.35,0,1)*(0.25+humidity*0.75)
	tip_material.set_shader_parameter("amount",clampf(tip*1.5,0,1))
	tip_material.set_shader_parameter("humidity",humidity)
	tip_material.set_shader_parameter("scroll",scroll*2.2)
	for i in range(2):
		var side: float = -1.0 if i==0 else 1.0
		condensation[i].visible = tip>0.01 and not app.cockpit
		condensation[i].position = f.position+basis*Vector3(side*5.73,-0.30,2.6)
		update_trail(i,f.position+basis*Vector3(side*5.73,-0.47,3.55),dt,clampf(tip*1.5,0,0.40) if f.airborne else 0.0)

func update_trail(index: int, at: Vector3, dt: float, strength: float) -> void:
	var points: Array = trail_points[index]
	for point: Dictionary in points: point.life -= dt
	while not points.is_empty() and points[0].life<=0: points.pop_front()
	if strength>0.03 and (points.is_empty() or Vector3(points.back().position).distance_to(at)>5): points.append({"position":at,"life":TRAIL_LIFE,"alpha":strength})
	if points.size()>100: points.pop_front()
	var mesh: ImmediateMesh = trails[index].mesh
	mesh.clear_surfaces()
	if points.size()<2: return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()-1):
		var a: Vector3 = points[i].position; var b: Vector3 = points[i+1].position
		var side: Vector3 = (b-a).normalized().cross((app.camera.position-a).normalized()).normalized()*lerpf(0.65,0.07,float(i)/points.size())
		var alpha: float = float(points[i].alpha)*clampf(float(points[i].life)/TRAIL_LIFE,0,1)
		for vertex: Array in [[a-side,Vector2(0,0)],[a+side,Vector2(1,0)],[b-side,Vector2(0,1)],[b-side,Vector2(0,1)],[a+side,Vector2(1,0)],[b+side,Vector2(1,1)]]:
			mesh.surface_set_color(Color(0.8,0.87,0.95,alpha*0.55))
			mesh.surface_set_uv(vertex[1])
			mesh.surface_add_vertex(vertex[0])
	mesh.surface_end()

func debris(at: Vector3) -> void:
	for i in range(12):
		var node := MeshInstance3D.new()
		var shape := BoxMesh.new(); shape.size = Vector3(0.18,0.06,1.1)
		node.mesh = shape
		node.material_override = Utils.material(Color(0.23,0.23,0.18) if i%2 else Color(0.72,0.74,0.68),0.05,0.8)
		node.position = at
		add_child(node)
		particles.append({"node":node,"velocity":Vector3(randf_range(-24,24),randf_range(-4,20),randf_range(-24,24)),"spin":Vector3(randf_range(-5,5),randf_range(-5,5),randf_range(-5,5)),"life":randf_range(1.3,2.5)})

func begin_ejection() -> void:
	parachute = Node3D.new(); add_child(parachute); chute_clock = 0
	parachute.position = app.flight.position+Vector3(0,5,0)
	var canopy := MeshInstance3D.new()
	var shape := SphereMesh.new(); shape.radius = 3.8; shape.height = 2
	canopy.mesh = shape; canopy.material_override = Utils.material(Color(0.82,0.85,0.78),0,0.85)
	canopy.position.y = 5
	parachute.add_child(canopy)
	var pilot := CapsuleMesh.new(); pilot.radius = 0.25; pilot.height = 1.8
	var body := MeshInstance3D.new(); body.mesh = pilot; body.material_override = Utils.material(Color(0.18,0.24,0.18),0,0.8)
	parachute.add_child(body)
	for side in [-1,1]: Utils.box(parachute,Vector3(0.02,4.5,0.02),Vector3(side*0.8,2.7,0),Utils.material(Color(0.8,0.82,0.75),0,0.7))

func tick_ejection(dt: float) -> void:
	chute_clock += dt
	parachute.position += Vector3(0,8 if chute_clock<0.7 else -4,-2)*dt
	parachute.scale = Vector3.ONE*clampf(chute_clock/0.7,0.1,1)

func reset() -> void:
	plasma_charge = 0.0
	for model in plasma_models: WeaponModels.set_charge(model, 0.0, 0.0)
	for puff: MeshInstance3D in tyre_puffs:
		if is_instance_valid(puff): puff.visible = false
	tyre_smoke_age=2.0
	clock = 0; sonic_armed = true; last_store = 0; store_timers = [0,0,0,0]
	ab_power = 0; dry_power = 0; ignition = 0; reheat_latched = false
	plume_length = 0; last_g = 1.0; g_rate = 0.0
	if is_instance_valid(plume_stack): stack_mesh.visible_instance_count = 0
	if is_instance_valid(shock_ring): shock_ring.visible = false
	if is_instance_valid(vapor_shock): vapor_shock.visible = false
	for sheet: MeshInstance3D in vapor_wings:
		if is_instance_valid(sheet): sheet.visible = false
	for puff: MeshInstance3D in condensation:
		if is_instance_valid(puff): puff.visible = false
	for store: Node3D in stores:
		if is_instance_valid(store): store.visible = true
	for item: Dictionary in particles:
		if is_instance_valid(item.node): item.node.queue_free()
	particles.clear(); trail_points = [[],[]]
	if is_instance_valid(parachute): parachute.queue_free()
	parachute = null
	for trail: MeshInstance3D in trails: trail.mesh.clear_surfaces()

func update_wind(dt: float, basis: Basis, f: FlightDynamics) -> void:
	if not is_instance_valid(wind_field): return
	var mesh: ImmediateMesh = wind_field.mesh
	mesh.clear_surfaces()
	var strength: float = clampf((f.speed-125)/250,0,.85)
	if strength<.01 or not f.airborne: return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(wind_points.size()):
		var local: Vector3 = wind_points[i]
		local.z += f.speed*dt*.55
		if local.z>25:
			local = Vector3(wind_rng.randf_range(-24,24),wind_rng.randf_range(-18,18),-45)
		wind_points[i] = local
		if absf(local.x)<6 and absf(local.y)<7: continue
		var a: Vector3 = f.position+basis*local
		var b: Vector3 = a+basis.z*clampf(f.speed*.011,1.6,4.5)
		var view: Vector3 = app.camera.global_position-a
		if view.length()<4: continue
		var side: Vector3 = (b-a).normalized().cross(view.normalized()).normalized()*.11
		var alpha: float = strength*.085*clampf((25-local.z)/15,0,1)*clampf((local.z+45)/12,0,1)
		for vertex: Array in [[a-side,Vector2(0,0)],[a+side,Vector2(1,0)],[b-side,Vector2(0,1)],[b-side,Vector2(0,1)],[a+side,Vector2(1,0)],[b+side,Vector2(1,1)]]:
			mesh.surface_set_color(Color(.86,.93,1,alpha)); mesh.surface_set_uv(vertex[1]); mesh.surface_add_vertex(vertex[0])
	mesh.surface_end()

func plasma_muzzle_position(fallback: Vector3, index: int = 0) -> Vector3:
	if index < 0 or index >= plasma_muzzles.size(): return fallback
	var muzzle: Node3D = plasma_muzzles[index]
	return muzzle.global_position if is_instance_valid(muzzle) else fallback

func update_plasma(dt: float) -> void:
	var firing: bool = app.combat.active and app.combat.beam_active and app.mode == "flight"
	plasma_charge = move_toward(plasma_charge, 1.0 if firing else 0.0, dt * (3.5 if firing else 1.8))
	for model in plasma_models:
		WeaponModels.set_charge(model, plasma_charge, 1.0 if firing else 0.0)

func _puff_mesh(size: float) -> QuadMesh:
	var quad := QuadMesh.new(); quad.size = Vector2(size,size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = soft_puff()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	quad.material = material
	return quad

## Eight prebuilt quads replace first-touchdown GPU particle allocation/compilation.
## They remain in world space and fade while the aircraft rolls away.
func tyre_smoke(strength: float = -1.0) -> void:
	if DisplayServer.get_name()=="headless":return
	var f: FlightDynamics=app.flight
	tyre_smoke_strength=clampf(absf(f.touchdown_sink)/maxf(Tune.TOUCHDOWN_MAX_SINK,.1) if strength<0 else strength,.25,1.0)
	tyre_smoke_age=0.0
	var basis:=Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	var clearance: float=float(f.profile.get("clearance",2.2))
	for i in range(tyre_puffs.size()):
		var puff: MeshInstance3D=tyre_puffs[i]
		var side: float=-1.0 if i<4 else 1.0
		puff.global_position=f.position+basis*Vector3(side*(2.4+float(i%4)*.15),-clearance+.25,1.1+float(i%4)*.45)
		puff.scale=Vector3.ONE*.8;puff.transparency=.25;puff.visible=true

func _build_tyre_puffs() -> void:
	var mesh:=_puff_mesh(1.6)
	var material:=mesh.material as StandardMaterial3D
	material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color=Color(.56,.54,.51,.5)
	material.vertex_color_use_as_albedo=false
	for i in range(8):
		var puff:=MeshInstance3D.new();puff.name="TyrePuff%d"%i;puff.mesh=mesh
		puff.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.top_level=true;puff.visible=false;add_child(puff);tyre_puffs.append(puff)

func _update_tyre_smoke(dt: float) -> void:
	if tyre_smoke_age>=1.4:return
	tyre_smoke_age+=dt
	var progress: float=clampf(tyre_smoke_age/1.4,0,1)
	for i in range(tyre_puffs.size()):
		var puff: MeshInstance3D=tyre_puffs[i]
		puff.visible=progress<1
		puff.position+=Vector3((-1.0 if i<4 else 1.0)*.35,.8,0)*dt
		puff.scale=Vector3.ONE*lerpf(.8,2.5+tyre_smoke_strength,progress)
		puff.transparency=lerpf(.25,1.0,progress)
