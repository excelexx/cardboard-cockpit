extends Node3D
class_name FighterEffects
const Tune = preload("res://data/balance.gd")
const WeaponArt = preload("res://systems/weapon_visuals.gd")
const Fighter = preload("res://systems/fighter_model.gd")
const Utils = preload("res://systems/model_utils.gd")

# --- afterburner geometry -------------------------------------------------------
# The F135 nozzle exit measures ~1.0 m across (twelve petals, outer lip 0.65 m radius).
# PLUME LENGTH IS A DESIGN TARGET, NOT A PHOTOGRAPH. The owner asked for roughly 8-11 m on
# this 15.5 m airframe - clearly SHORTER than one jet length - so reheat reads as a burst of
# flame the jet is riding rather than a beam welded to the tail. Full throttle settles at
# PLUME_DRY_MAX+PLUME_REHEAT = 9.40 m (9.83 m at the top of the breathe) and the light-up
# lunge peaks near 11 m. Do NOT restore a 12-18 m target: it was tried and rejected twice.
const NOZZLE_RADIUS := 0.55
const PLUME_DRY_MIN := 1.15
const PLUME_DRY_MAX := 2.20
const PLUME_REHEAT := 7.20
# Light-up overshoot. This is applied to `want` BEFORE the length smoothing and while
# ab_power is still spooling, so most of it is eaten before it reaches the screen: what
# matters is the realised peak, which is 10.8 m against a 9.4 m steady - a visible kick,
# and nowhere near the 18 m the old 13.7 m plume lunged to. Anything at or below ~0.15
# here produces NO lunge at all (measured), and the lunge is the best moment in the effect.
# tests/studio_burner.gd -- contract asserts the realised peak, not this number.
const IGNITION_LUNGE := 0.42
const STACK_SLOTS := 16
const IGNITION_TIME := 0.45
# The plume keeps its honest world length; what changes near the camera is its OPACITY.
# A clearance LENGTH clamp shortens the plume whenever the camera closes in, which pins a
# constant-size bar to the screen in the most common view - the worst possible read of the
# effect. The shaders fade these last metres to nothing instead, so the tip dissolves.
const NEAR_FADE_IN := 3.5       # metres from the camera: gone
const NEAR_FADE_OUT := 13.5     # metres from the camera: full strength
## PLUME-STATION DISSOLVE - the control that actually tames the chase view.
## MEASURED: the game chase rig sits 22-26 m behind the jet, so with a 9.4 m plume the tip
## is still ~11.4 m from the lens. The near-camera fade above therefore never fires in the
## one view the owner judged ("it shouldn't be one continuous HEAVY beam"), whatever its
## numbers are. So the plume dissolves by its own STATION instead, which is view-independent:
## past FADE_FROM it breaks into wisps and by FADE_TO nothing is left. The physical length
## (and the 8-11 m contract) is unchanged - what changes is how much of it is lit.
const PLUME_FADE_FROM := 0.54
const PLUME_FADE_TO := 0.97
## Wingtip vortex rope. TIP_SPAN is just INBOARD of the 5.40 m wing half-span: at 5.73 m the
## puff sat outboard of the tip and read as a white ball floating free beside the jet.
## One billboard per side gave two detached orbs, so it is a short chain instead.
const TIP_PUFFS := 4
const TIP_SPAN := 5.30
const TIP_STATIONS := [1.90,3.35,4.80,6.35]
const TIP_SIZES := [0.72,0.60,0.48,0.38]
const TIP_STRETCH := 2.40
const TIP_WEIGHTS := [1.00,0.80,0.58,0.40]
# Nothing additive behind the jet may swallow its silhouette. The nozzle flare and the
# end-on disc stack both sit over the fuselage when seen from astern, so both are capped
# to this radius - about a quarter of the wing half-span, i.e. fuselage-width, never more.
const AIRFRAME_HALF_SPAN := 5.40
const HALO_CAP := 0.26
const TRAIL_LIFE := 1.1

## The largest radius, in metres, that any additive billboard behind the nozzle may take.
static func halo_limit() -> float:
	return AIRFRAME_HALF_SPAN*HALO_CAP

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
var tip_material: ShaderMaterial               # == tip_materials[0]
var tip_materials: Array[ShaderMaterial] = []
var trails: Array[MeshInstance3D] = []
var trail_points: Array[Array] = [[],[]]
var particles: Array[Dictionary] = []
var stores: Array[Node3D] = []
var parachute: Node3D
var chute_clock := 0.0
var sonic_armed := true
var clock := 0.0
var gun_gimbal: Node3D
var gun_rotor: Node3D
var gun_muzzle: Node3D
var plasma_emitter: Node3D
var gun_flash: Node3D
var gun_light: OmniLight3D
var gun_gas: GPUParticles3D
var gun_gas_anchor: Node3D
var tyre_puffs: Array[GPUParticles3D] = []
var rotor_speed := 0.0
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
## - gun gas, tyre smoke, the wingtip ribbons, the speed streaks - uses this instead.
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
	gun_gas = null; gun_gas_anchor = null; tyre_puffs.clear()
	gun_gimbal = app.aircraft.find_child("GunGimbal",true,false)
	gun_rotor = app.aircraft.find_child("GatlingRotor",true,false)
	gun_muzzle = app.aircraft.find_child("GunMuzzle",true,false)
	gun_flash = Node3D.new(); add_child(gun_flash)
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash_material.albedo_texture = load("res://assets/sourced_flight/muzzle.png")
	for angle in [0.0,PI/2]:
		var plane := MeshInstance3D.new(); var quad := QuadMesh.new(); quad.size = Vector2(2.1,.64)
		plane.mesh = quad; plane.material_override = flash_material
		plane.basis = Basis(Vector3.BACK,angle)*Basis(Vector3.UP,PI/2)
		plane.position.z = -1.02; plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gun_flash.add_child(plane)
	gun_light = OmniLight3D.new(); gun_light.light_color = Color(1,.62,.20)
	gun_light.omni_range = 11; gun_light.omni_attenuation = 1.6
	# Layer 2 is the airframe (fighter_model.gd puts every mesh it dresses there); the
	# cockpit tub and the canopy are on layer 1. The muzzle sits 3.4 m from the pilot's eye
	# and this light pulses at ~22 Hz, so unmasked it strobes the interior and the HUD -
	# the aiming view a cardboard-yoke player flies on. It lights the jet, never the office.
	gun_light.light_cull_mask = 2
	gun_light.shadow_enabled = false; add_child(gun_light)
	condensation.clear(); trails.clear(); stores.clear(); particles.clear(); trail_points = [[],[]]
	vapor_wings.clear()
	_build_burner()
	_build_vapour()   # also creates tip_material, used by the wingtip puffs below
	airframe_fill = OmniLight3D.new()
	airframe_fill.light_cull_mask = 2
	# COOL, DIM, AND IN FRONT. P7A briefly made this a bright warm key from above and behind
	# (1.0,.93,.84 at energy 2.6, basis*(0,7,5)); at ~8 m with range 24 / attenuation .6 that
	# is ~2.0 effective energy of cream light against a sun at 3.0, and it turned the black
	# "angel of death" airframe caramel brown in every burner render. Airframe lighting is
	# NOT this package's to set - the brief holds the global light regrade and the jet-only
	# rim light for the integrator - so this is the original sky-bounce fill, restored.
	airframe_fill.light_color = Color(.73,.84,1.0)
	airframe_fill.light_energy = 1.2
	airframe_fill.omni_range = 24
	airframe_fill.omni_attenuation = .6
	airframe_fill.shadow_enabled = false
	add_child(airframe_fill)
	for side in [-1,1]:
		# A ROPE of cloud leaving the tip, not one round ball floating beside it. Four small
		# procedural puffs at staggered stations aft, each smaller and thinner than the last,
		# feeding the ribbon below. (Procedural, not a photographic sprite: smoke.png shows
		# its own square texture border the moment it is scaled to wingtip-vortex size.)
		for k in range(TIP_PUFFS):
			var vapor := MeshInstance3D.new()
			var puff := QuadMesh.new(); puff.size = Vector2(2,2)
			vapor.mesh = puff
			vapor.material_override = tip_materials[k]
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
	for i in range(4):
		var store: Node3D = WeaponArt.missile()
		for geometry: Node in store.find_children("*","GeometryInstance3D",true,false): geometry.layers = 2
		var mount := Node3D.new()
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
	sheath_material.set_shader_parameter("near_fade_in",NEAR_FADE_IN)
	sheath_material.set_shader_parameter("near_fade_out",NEAR_FADE_OUT)
	sheath_material.set_shader_parameter("fade_from",PLUME_FADE_FROM)
	sheath_material.set_shader_parameter("fade_to",PLUME_FADE_TO)
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
	exhaust_material.set_shader_parameter("near_fade_in",NEAR_FADE_IN)
	exhaust_material.set_shader_parameter("near_fade_out",NEAR_FADE_OUT)
	exhaust_material.set_shader_parameter("fade_from",PLUME_FADE_FROM)
	exhaust_material.set_shader_parameter("fade_to",PLUME_FADE_TO)
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
	stack_material.set_shader_parameter("near_fade_in",NEAR_FADE_IN)
	stack_material.set_shader_parameter("near_fade_out",NEAR_FADE_OUT)
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
	# Layer 2 is the airframe; the cockpit tub, the coaming and the canopy are on layer 1.
	# Fighter.NOZZLE is z = +7.28 and the pilot's eye sits ~5 m forward of the origin, so
	# this light is ~12.3 m BEHIND the head - and it runs to energy 7 at steady reheat and
	# ~35 during the ignition flash. Unmasked it floods the interior the cardboard-yoke
	# player aims through, from behind, exactly the way the gun light did before it was
	# masked (see gun_light above). tests/studio_burner.gd measures this on the
	# "reheatcockpit" shot so it cannot come back.
	exhaust_light.light_cull_mask = 2
	exhaust_light.shadow_enabled = false
	add_child(exhaust_light)
	haze = MeshInstance3D.new()
	var haze_quad := QuadMesh.new(); haze_quad.size = Vector2(1,1)
	haze.mesh = haze_quad
	haze_material = ShaderMaterial.new()
	haze_material.shader = load("res://assets/vfx/heat_haze.gdshader")
	haze_material.set_shader_parameter("noise",burner_noise())
	haze_material.set_shader_parameter("near_fade_in",NEAR_FADE_IN)
	haze_material.set_shader_parameter("near_fade_out",NEAR_FADE_OUT)
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
	# HUGS the airframe. At 3.6 m / 7.5 m the shell reached from the canopy to past the fin
	# and 3.6 m clear above the spine, which from abeam is a big triangle laid over the jet
	# rather than condensation clinging to it.
	cone.top_radius = 2.85; cone.bottom_radius = 0.26; cone.height = 6.40
	cone.radial_segments = 28; cone.rings = 8; cone.cap_top = false; cone.cap_bottom = false
	vapor_shock = MeshInstance3D.new(); vapor_shock.mesh = cone
	shock_material = ShaderMaterial.new(); shock_material.shader = shader
	shock_material.set_shader_parameter("mode",0)
	shock_material.set_shader_parameter("noise",noise)
	# These caps were dead code until the mode 0 UV bug was fixed (the shell could not exceed
	# alpha 0.5^2.20 = 0.218 whatever `ceiling` said), so they are set against renders now.
	shock_material.set_shader_parameter("ceiling",0.20)
	# A gentle fresnel, not a concentrated one: at 1.65 the shell collapsed onto its own
	# silhouette and drew a hard straight line down the cone.
	shock_material.set_shader_parameter("rim",1.10)
	shock_material.render_priority = -4
	vapor_shock.material_override = shock_material
	vapor_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vapor_shock.visible = false
	add_child(vapor_shock)
	vapor_material = ShaderMaterial.new(); vapor_material.shader = shader
	vapor_material.set_shader_parameter("mode",1)
	vapor_material.set_shader_parameter("noise",noise)
	vapor_material.set_shader_parameter("ceiling",0.31)
	vapor_material.set_shader_parameter("rim",0.70)
	vapor_material.render_priority = -4
	# A SHALLOW blister lying on the wing, not a mound sitting on top of it. At 0.60 m of
	# bulge on a 4.4 x 6.4 m sheet this silhouetted from the chase camera as a chalk-white
	# lump stuck to the wing, which is exactly how the review read it.
	vapor_material.set_shader_parameter("bulge",0.30)
	tip_materials.clear()
	for k in range(TIP_PUFFS):
		var puff_material := ShaderMaterial.new(); puff_material.shader = shader
		puff_material.set_shader_parameter("mode",2)
		puff_material.set_shader_parameter("noise",noise)
		# Kimi's cap. It only started to mean anything once the shader stopped painting at
		# ALBEDO 1.55, which dragged the backdrop to clipped white whatever the alpha was.
		puff_material.set_shader_parameter("ceiling",0.35*float(TIP_WEIGHTS[k]))
		puff_material.set_shader_parameter("rim",0.70)
		puff_material.render_priority = -3
		puff_material.set_shader_parameter("size",float(TIP_SIZES[k]))
		puff_material.set_shader_parameter("stretch",TIP_STRETCH)
		tip_materials.append(puff_material)
	tip_material = tip_materials[0]
	for i in range(2):
		var sheet := PlaneMesh.new()
		sheet.size = Vector2(3.8,5.0); sheet.subdivide_width = 12; sheet.subdivide_depth = 14
		var node := MeshInstance3D.new(); node.mesh = sheet
		node.material_override = vapor_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-3,-1,-4),Vector3(6,3,8))
		node.visible = false
		add_child(node); vapor_wings.append(node)

func missile_launch(_side: float, index: int = -1) -> void:
	last_store += 1
	if index>=0 and index<stores.size():
		store_timers[index] = Tune.MISSILE_INTERVAL; stores[index].visible = false

func update(dt: float) -> void:
	clock += dt
	update_gun(dt)
	for i in range(stores.size()):
		store_timers[i] = maxf(0,store_timers[i]-dt)
		stores[i].visible = store_timers[i]<.22
		for geometry: Node in stores[i].find_children("*","GeometryInstance3D",true,false): geometry.transparency = clampf(store_timers[i]/.22,0,1)
	var f: FlightDynamics = app.flight
	var basis := Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	airframe_fill.position = f.position+basis*Vector3(0,6,-2)
	airframe_fill.visible = not app.cockpit
	update_wind(dt,basis)
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
	# Length, with a slow breathe and a lunge on light-up. This is the PHYSICAL length and
	# nothing trims it against the camera any more - see NEAR_FADE_IN.
	var want: float = lerpf(PLUME_DRY_MIN,PLUME_DRY_MAX,dry_power)+PLUME_REHEAT*pow(burn,0.85)
	want *= 1.0+0.028*sin(clock*17.3)+0.018*sin(clock*29.7+1.1)
	want *= 1.0+IGNITION_LUNGE*overshoot
	plume_length = lerpf(plume_length,want,1.0-exp(-dt*9.0))
	var length: float = maxf(plume_length,0.35)
	var radius: float = NOZZLE_RADIUS*lerpf(0.72,1.0,live)
	var spread: float = lerpf(1.55,1.90,burn)
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
	# PALETTE LOCK (amber / gunmetal / slate blue): the barrel-shock ring reads as a cool
	# slate edge around the amber gas. It used to lerp to a saturated violet, which is what
	# turned the dead-astern view into a purple bullseye.
	stack_material.set_shader_parameter("rim_tint",Color(0.34,0.46,1.0).lerp(Color(0.44,0.55,0.86),burn))
	_update_stack(nozzle,aft,length,radius,spread,cells,live,rear_w,flash,lit)
	# DEAD ASTERN the nozzle glow, the bloom flare and every slice of the disc stack land on
	# the same handful of pixels over the fuselage, and they are all additive. halo_limit()
	# caps their RADIUS; nothing capped the sum of their BRIGHTNESS, which is what turned
	# build/burner/reheat-rear into one featureless white-hot bullseye with no shock chain
	# in it. This steps the two solid discs back as the camera comes on axis, so the ring
	# chain has something to read against. Off axis it is 1.0 and nothing changes.
	var axial_relief: float = 1.0-0.72*rear_w
	nozzle_glow.visible = f.engine>0.06
	nozzle_glow.basis = basis*Basis.from_scale(Vector3(1.30,1.30,1.0))
	nozzle_glow.position = nozzle+aft*0.04
	glow_material.set_shader_parameter("power",clampf((0.16+dry_power*0.52+burn*0.98)*axial_relief,0.0,1.7))
	glow_material.set_shader_parameter("reheat",reheat)
	nozzle_flare.visible = lit and (live>0.01 or dry_power>0.05)
	nozzle_flare.position = nozzle+aft*0.55
	# HARD RULE: this is a flare, not a fireball. Dead astern the flare and the disc stack
	# both sit over the fuselage and both are additive, so either can erase the airframe.
	# halo_limit() caps them at fuselage width, which keeps the silhouette readable however
	# far the chase camera drops toward the engine axis.
	flare_material.set_shader_parameter("size",minf(lerpf(0.55,1.30,live)*(1.0+0.45*flash),halo_limit()))
	flare_material.set_shader_parameter("intensity",(lerpf(0.18,1.05,live)+0.14*dry_power)*(1.0+3.6*flash)*axial_relief)
	flare_material.set_shader_parameter("streak",0.10+0.22*burn)
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
	# DEAD ASTERN every slice projects concentrically and they simply sum, which is how this
	# view collapsed into one featureless orange-white bullseye (build/burner/reheat-rear).
	# The mid-cell fillers fade out as the camera comes on axis, so what survives straight up
	# the pipe is five or six distinct Mach-disk rings - a chain, which is the only reason
	# the stack exists. Off axis they fade back in and the side slice carries the train anyway.
	var fillers: float = 1.0-smoothstep(0.30,0.72,weight)
	for i in range(used):
		var u: float = samples[i].x
		var disk: float = samples[i].y
		# The disc is the plume's true cross-section, not a halo around it. It used to be
		# drawn 30-45% oversize, which is how eleven stacked discs grew into a bullseye wider
		# than the fuselage. Same profile exponent as the slice shader, and the same cap.
		var local_r: float = radius*(1.0+(spread-1.0)*pow(u,2.20))
		# A REAL LADDER. The side slice's own decay (exp(-2.35u) under pow(1-u,2.20)) leaves
		# ring 4 at about 1% of ring 1, so however many slices were placed, only the first was
		# ever visible - which is the other half of why dead astern rendered as one disc.
		# These five or six rings step down 1.00 / 0.68 / 0.42 / 0.22 / 0.09 while their radii
		# step UP, so the eye reads depth up the pipe instead of a bullseye.
		var train: float = exp(-1.05*u)
		var strength: float = live*pow(1.0-u*0.82,1.35)*(0.14+1.25*disk*train)*(1.0+1.2*flash)
		if disk<0.5: strength *= fillers
		stack_mesh.set_instance_transform(i,Transform3D(Basis(),nozzle+aft*(length*u)))
		stack_mesh.set_instance_custom_data(i,Color(minf(local_r*(1.02 if disk>0.5 else 1.10),halo_limit()),strength*pow(weight,2.5),disk*train,u))
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
			var lit_materials: Array[ShaderMaterial] = [vapor_material,shock_material]
			lit_materials.append_array(tip_materials)
			for material: ShaderMaterial in lit_materials:
				material.set_shader_parameter("light_dir",-lamp.global_basis.z)
				# Condensation is cool white that PICKS UP the golden hour, not paint that is
				# golden: too little white here and the wing sheet reads as tan dirt.
				material.set_shader_parameter("light_color",lamp.light_color.lerp(Color(1,1,1),0.84))
	# GATES ON REACHABLE QUANTITIES. Measured over the whole shipping cinematic showcase
	# (scripts/demoprobe: 121 s, route sf, cinematic): Mach 0.75-1.53, median 1.06, 16.5 s of
	# reheat, g to 7.0 with 28.9 s above 3 g, roll to 176 deg. On the slower free-flight
	# routes, though, the same probe measures max 156 m/s and only 1.8 s above 3 g - so a
	# textbook Prandtl-Glauert band (fully lit only between 322 and 342 m/s) plus a 3 g
	# threshold left the vapour nearly invisible there and a two-second flicker here.
	# The PLAYABILITY GUARD explicitly allows defying physics, so the shell also answers to
	# reheat and to a pull, which every route reaches. It stays an EVENT, not a permanent
	# sleeve: the base wisp is a third strength and only working the airframe blooms it.
	# Base: the transonic sweep, widened from the textbook Mach 0.88-1.14 band (fully lit
	# only between 322 and 342 m/s - about two seconds of a two-minute sortie) so it covers
	# the speeds the showcase actually cruises at. Bonus: a pull, at any speed worth the
	# name. Reheat alone does NOT summon it: at Mach 1.19 and one g the jet is well past its
	# own shock, and a permanent sleeve over the airframe is the veil the brief forbids.
	var transonic: float = smoothstep(0.72,0.88,mach)*(1.0-smoothstep(1.00,1.18,mach))
	var pulled: float = clampf((f.g_load-2.0)/2.6,0.0,1.0)*smoothstep(0.34,0.62,mach)
	var band: float = clampf(maxf(transonic,pulled*0.90),0.0,1.0)
	g_rate = lerpf(g_rate,(f.g_load-last_g)/maxf(dt,0.0001),1.0-exp(-dt*6.0))
	last_g = f.g_load
	var scroll: float = clock*0.55
	var shock_amount: float = band*humidity
	vapor_shock.visible = shock_amount>0.02 and f.airborne and not app.cockpit
	if vapor_shock.visible:
		vapor_shock.basis = basis*Basis(Vector3.RIGHT,PI/2)
		vapor_shock.position = f.position+basis*Vector3(0,-0.30,2.35)
		shock_material.set_shader_parameter("amount",shock_amount)
		shock_material.set_shader_parameter("humidity",humidity)
		shock_material.set_shader_parameter("scroll",scroll)
	# The wing blister keys off how hard the jet is WORKING the wing - bank angle and roll
	# rate as well as G - so it appears on routes that never pull 3 g. On a real pull the G
	# term still dominates, which is the read Kimi asked for.
	var worked_wing: float = maxf(clampf((f.g_load-2.1)/2.4,0,1),
		clampf((absf(f.roll)-0.42)/0.75,0,1)*0.78+clampf(absf(f.roll_velocity)*0.42,0,1)*0.30)
	var pull: float = clampf(worked_wing,0,1)*(0.25+humidity*0.75)
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
	# Wingtip vortex condensation: it should FLASH as the wing loads up and go away again,
	# not stream two permanent 500 m ribbons through every chase shot. Loading is G or roll
	# rate (a snap roll ropes the tips too); the onset term keeps it a flash rather than a
	# steady-state ribbon, and roll rate reaches it on every route.
	var loading: float = maxf(clampf((f.g_load-2.3)/2.6,0,1),clampf((absf(f.roll_velocity)-0.35)/1.10,0,1))
	var onset: float = clampf(maxf(g_rate*0.42,absf(f.roll_velocity)*0.55),0,1)
	var tip: float = clampf(loading*(0.34+0.66*onset),0,1)*(0.25+humidity*0.75)
	for k in range(TIP_PUFFS):
		tip_materials[k].set_shader_parameter("amount",clampf(tip*1.5*float(TIP_WEIGHTS[k]),0,1))
		tip_materials[k].set_shader_parameter("humidity",humidity)
		tip_materials[k].set_shader_parameter("scroll",scroll*(2.2+0.5*float(k)))
	for i in range(2):
		var side: float = -1.0 if i==0 else 1.0
		for k in range(TIP_PUFFS):
			var node: MeshInstance3D = condensation[i*TIP_PUFFS+k]
			node.visible = tip>0.01 and not app.cockpit
			# The shader stretches the puff along the node's own +Z, so the node has to carry
			# the aircraft's attitude: otherwise the rope trails along world north.
			node.basis = basis
			# The rope drifts slightly outboard and down as it leaves the tip, the way a
			# tip vortex does; it never starts outboard of the tip itself.
			node.position = f.position+basis*Vector3(side*(TIP_SPAN+0.055*float(k)),-0.30-0.085*float(k),float(TIP_STATIONS[k]))
		update_trail(i,f.position+basis*Vector3(side*(TIP_SPAN+0.24),-0.62,9.40),dt,clampf(tip*1.5,0,0.40) if f.airborne else 0.0)

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
	rotor_speed = 0
	if is_instance_valid(gun_flash): gun_flash.visible = false
	if is_instance_valid(gun_light): gun_light.visible = false
	if is_instance_valid(gun_gas): gun_gas.emitting = false
	for puff: GPUParticles3D in tyre_puffs:
		if is_instance_valid(puff): puff.emitting = false
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

func update_wind(dt: float, basis: Basis) -> void:
	if not is_instance_valid(wind_field): return
	var mesh: ImmediateMesh = wind_field.mesh
	mesh.clear_surfaces()
	var strength: float = clampf((app.flight.speed-125)/250,0,.85)
	if strength<.01 or not app.flight.airborne: return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(wind_points.size()):
		var local: Vector3 = wind_points[i]
		local.z += app.flight.speed*dt*.55
		if local.z>25:
			local = Vector3(wind_rng.randf_range(-24,24),wind_rng.randf_range(-18,18),-45)
		wind_points[i] = local
		if absf(local.x)<6 and absf(local.y)<7: continue
		var a: Vector3 = app.flight.position+basis*local
		var b: Vector3 = a+basis.z*clampf(app.flight.speed*.011,1.6,4.5)
		var view: Vector3 = app.camera.global_position-a
		if view.length()<4: continue
		var side: Vector3 = (b-a).normalized().cross(view.normalized()).normalized()*.11
		var alpha: float = strength*.085*clampf((25-local.z)/15,0,1)*clampf((local.z+45)/12,0,1)
		for vertex: Array in [[a-side,Vector2(0,0)],[a+side,Vector2(1,0)],[b-side,Vector2(0,1)],[b-side,Vector2(0,1)],[a+side,Vector2(1,0)],[b+side,Vector2(1,1)]]:
			mesh.surface_set_color(Color(.86,.93,1,alpha)); mesh.surface_set_uv(vertex[1]); mesh.surface_add_vertex(vertex[0])
	mesh.surface_end()

func gun_muzzle_position(fallback: Vector3) -> Vector3:
	return gun_muzzle.global_position if is_instance_valid(gun_muzzle) else fallback

func update_gun(dt: float) -> void:
	var firing: bool = app.combat.active and app.combat.gun_firing_time>0 and app.mode=="flight"
	rotor_speed = move_toward(rotor_speed,62.0 if firing else 0.0,dt*(480 if firing else 110))
	if is_instance_valid(gun_rotor): WeaponModels.advance_heat(gun_rotor,firing,dt)
	if not is_instance_valid(plasma_emitter): plasma_emitter = app.aircraft.find_child("PC26Emitter",true,false)
	if is_instance_valid(plasma_emitter): WeaponModels.advance_charge(plasma_emitter,app.combat.lock_progress>=1 and app.combat.target_id>=0,app.combat.beam_active,dt)
	# The cannon is fixed in the wing root; it does NOT slew toward the aim point.
	if is_instance_valid(gun_gimbal):
		gun_gimbal.position.z = .018*(.5+.5*sin(clock*145)) if firing else 0.0
	if is_instance_valid(gun_rotor): gun_rotor.rotate_z(rotor_speed*dt)
	# Visible in the cockpit too - just smaller. A cardboard-yoke player flies from here.
	gun_flash.visible = firing
	gun_light.visible = firing
	if is_instance_valid(gun_muzzle):
		gun_flash.global_transform = gun_muzzle.global_transform.orthonormalized()
		gun_flash.scale = Vector3.ONE*(.78+.22*sin(clock*137))*(0.45 if app.cockpit else 1.0)
		gun_light.global_position = gun_muzzle.global_position
	gun_light.light_energy = (3.2+sin(clock*137)*.7) if firing else 0.0
	if DisplayServer.get_name()!="headless":
		if gun_gas==null: _build_gun_gas()
		if is_instance_valid(gun_gas):
			if is_instance_valid(gun_muzzle): gun_gas_anchor.global_transform = gun_muzzle.global_transform.orthonormalized()
			gun_gas.emitting = firing and is_instance_valid(gun_muzzle)

func _build_gun_gas() -> void:
	gun_gas_anchor = Node3D.new(); add_child(gun_gas_anchor)
	gun_gas = GPUParticles3D.new()
	gun_gas.amount = 28
	gun_gas.lifetime = 0.42
	gun_gas.local_coords = true        # pinned to the jet, so FSR2 never smears it across the view
	gun_gas.fixed_fps = 30
	gun_gas.interpolate = true
	gun_gas.emitting = false
	gun_gas.visibility_aabb = AABB(Vector3(-4,-4,-9),Vector3(8,8,11))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	process.direction = Vector3(0,0,-1)
	process.spread = 17.0
	process.initial_velocity_min = 9.0
	process.initial_velocity_max = 23.0
	process.damping_min = 15.0
	process.damping_max = 24.0
	process.gravity = Vector3.ZERO
	process.scale_min = 0.30; process.scale_max = 0.85
	process.angular_velocity_min = -90.0; process.angular_velocity_max = 90.0
	var growth := Curve.new()
	growth.add_point(Vector2(0,0.35)); growth.add_point(Vector2(1,1.7))
	var growth_texture := CurveTexture.new(); growth_texture.curve = growth
	process.scale_curve = growth_texture
	var ramp := Gradient.new()
	ramp.set_color(0,Color(0.86,0.74,0.56,0.34)); ramp.set_offset(0,0.0)
	ramp.set_color(1,Color(0.50,0.50,0.48,0.0)); ramp.set_offset(1,1.0)
	var ramp_texture := GradientTexture1D.new(); ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	gun_gas.process_material = process
	gun_gas.draw_pass_1 = _puff_mesh(0.55)
	gun_gas_anchor.add_child(gun_gas)

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

## Touchdown hook for the landing package: tyre_smoke() derives its weight from the
## recorded sink rate, or takes an explicit 0..1 strength. The smoke is world-space and
## heavily damped, so it stops dead on the runway while the jet runs away from it.
func tyre_smoke(strength: float = -1.0) -> void:
	if DisplayServer.get_name()=="headless": return
	var f: FlightDynamics = app.flight
	var weight: float = strength
	if weight<0.0: weight = clampf(absf(f.touchdown_sink)/maxf(Tune.TOUCHDOWN_MAX_SINK,0.1),0.25,1.0)
	weight = clampf(weight,0.25,1.0)
	if tyre_puffs.is_empty(): _build_tyre_puffs()
	var basis := Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	var clearance: float = 2.2
	if f.profile is Dictionary and f.profile.has("clearance"): clearance = float(f.profile.clearance)
	for i in range(tyre_puffs.size()):
		var side: float = -1.0 if i==0 else 1.0
		var puff: GPUParticles3D = tyre_puffs[i]
		var process: ParticleProcessMaterial = puff.process_material
		process.initial_velocity_min = lerpf(2.0,6.0,weight)
		process.initial_velocity_max = lerpf(5.5,16.0,weight)
		process.direction = Vector3(side*0.45,0.55,1.0).normalized()
		puff.global_position = f.position+basis*Vector3(side*2.4,-clearance,1.1)
		puff.global_basis = basis
		puff.amount = int(lerpf(16.0,46.0,weight))
		puff.restart()
		puff.emitting = true

func _build_tyre_puffs() -> void:
	for i in range(2):
		var puff := GPUParticles3D.new()
		puff.amount = 32
		puff.lifetime = 1.6
		puff.one_shot = true
		puff.explosiveness = 0.85
		puff.local_coords = false        # the smoke stays on the runway; the jet runs away from it
		puff.fixed_fps = 30
		puff.interpolate = true
		puff.emitting = false
		puff.visibility_aabb = AABB(Vector3(-12,-4,-12),Vector3(24,14,24))
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 0.30
		process.spread = 28.0
		process.damping_min = 4.0; process.damping_max = 6.0
		process.gravity = Vector3(0,0.8,0)
		process.scale_min = 0.9; process.scale_max = 2.4
		var growth := Curve.new()
		growth.add_point(Vector2(0,0.45)); growth.add_point(Vector2(1,2.4))
		var growth_texture := CurveTexture.new(); growth_texture.curve = growth
		process.scale_curve = growth_texture
		var ramp := Gradient.new()
		ramp.set_color(0,Color(0.42,0.40,0.38,0.60)); ramp.set_offset(0,0.0)
		ramp.set_color(1,Color(0.66,0.65,0.62,0.0)); ramp.set_offset(1,1.0)
		var ramp_texture := GradientTexture1D.new(); ramp_texture.gradient = ramp
		process.color_ramp = ramp_texture
		puff.process_material = process
		puff.draw_pass_1 = _puff_mesh(1.6)
		add_child(puff)
		tyre_puffs.append(puff)
