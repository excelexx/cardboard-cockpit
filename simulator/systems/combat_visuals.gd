extends Node3D
## Composes the existing weapon primitives, sprites, material overlays and light pools.
const Art = preload("res://systems/weapon_visuals.gd")
const Tune = preload("res://data/balance.gd")
var combat: Node
var projectile_pool := {"cannon":[]}
var sprites: Array[Dictionary] = []
var sprite_pool: Array[Sprite3D] = []
var lights: Array[Dictionary] = []
var light_pool: Array[OmniLight3D] = []
var rings: Array[Dictionary] = []
var lead_mesh: MeshInstance3D
var ghost_clock := 0.0
var effects_clock := 0.0
var scan_time := 0.0
var handoff_origin:=Vector3.ZERO
var handoff_time:=0.0
var impact_emphasis := 0.0
var flash_texture: Texture2D
var smoke_texture: Texture2D
## Bird-strike debris. Three pooled feather/down emitter pairs, reused across
## kills by restart(); they live outside the 96-sprite / 8-light pools the
## visual budget gate counts.
const FEATHER_RIGS := 3
var feather_rigs: Array[Dictionary] = []
var feather_cursor := 0
## Countermeasures: one shared ImmediateMesh for the whole salvo, the pattern
## every other streak in this codebase already uses.
var flare_mesh: MeshInstance3D
var flare_head_material: StandardMaterial3D
var flare_smoke_material: StandardMaterial3D
var flare_items: Array[Dictionary] = []
var last_flares_fired := 0
var rng := RandomNumberGenerator.new()
func _ready() -> void:
	flash_texture=load("res://assets/vfx/flash.png");smoke_texture=load("res://assets/sourced_flight/smoke.png")
	lead_mesh=MeshInstance3D.new();lead_mesh.mesh=ImmediateMesh.new();lead_mesh.material_override=Art.emissive(Color(.08,.55,.8),1.3,.15);lead_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(lead_mesh)
	for i in range(96):
		var sprite:=Sprite3D.new();sprite.texture=flash_texture;sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED;sprite.shaded=false;sprite.visible=false;sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(sprite);sprite_pool.append(sprite)
	for i in range(8):
		var light:=OmniLight3D.new();light.shadow_enabled=false;light.visible=false;add_child(light);light_pool.append(light)
	_build_flare_ribbon()
	_build_feather_rigs()
	# Warm the actual meshes/materials before the first salvo.
	for kind in ["cannon"]:
		for i in range(48):
			var node:=Art.projectile(kind);node.set_meta("projectile_kind",kind);add_child(node);node.visible=false
			projectile_pool[kind].append(node)
func _build_feather_rigs() -> void:
	# GPUParticles3D needs a rendering device; headless regression runs skip it
	# entirely and every call site tolerates an empty rig list.
	if DisplayServer.get_name()=="headless":return
	var shader: Shader=load("res://assets/vfx/feather.gdshader")
	if shader==null:return
	for i in range(FEATHER_RIGS):
		feather_rigs.append({"feathers":_feather_emitter(shader,false),"down":_feather_emitter(shader,true)})

func _feather_emitter(shader: Shader,down: bool) -> GPUParticles3D:
	var node:=GPUParticles3D.new()
	node.name=("Down" if down else "Feathers")+str(feather_rigs.size())
	node.amount=96 if down else 64
	node.lifetime=3.5 if down else 2.2
	node.one_shot=true
	node.explosiveness=1.0
	node.emitting=false
	node.local_coords=false
	node.fixed_fps=30
	node.interpolate=true
	node.draw_order=GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad:=QuadMesh.new()
	quad.size=Vector2(0.12,0.12) if down else Vector2(0.20,0.70)
	node.draw_pass_1=quad
	var material:=ShaderMaterial.new()
	material.shader=shader
	material.set_shader_parameter("down_mode",1.0 if down else 0.0)
	material.set_shader_parameter("quill_tint",Color(.34,.26,.20))
	material.set_shader_parameter("vane_tint",Color(.88,.86,.80))
	material.set_shader_parameter("translucency",.52 if down else .38)
	node.material_override=material
	var process:=ParticleProcessMaterial.new()
	process.particle_flag_disable_z=false
	process.direction=Vector3(0,0,-1)
	process.spread=65.0 if down else 35.0
	process.initial_velocity_min=2.0 if down else 6.0
	process.initial_velocity_max=9.0 if down else 22.0
	process.damping_min=4.5 if down else 3.0
	process.damping_max=6.0 if down else 4.0
	# Feathers hang. Real gravity would drop them out of frame before a novice
	# reads the kill, so this is deliberately about a quarter of g.
	process.gravity=Vector3(0,-0.6,0) if down else Vector3(0,-2.2,0)
	process.angle_min=-180.0
	process.angle_max=180.0
	process.angular_velocity_min=-60.0 if down else -180.0
	process.angular_velocity_max=60.0 if down else 180.0
	process.scale_min=1.0
	process.scale_max=1.0
	process.color_ramp=_feather_ramp()
	node.process_material=process
	add_child(node)
	return node

func _feather_ramp() -> GradientTexture1D:
	# Brightness and the fade only: the shader owns the brown-to-off-white hue
	# along the feather itself.
	var gradient:=Gradient.new()
	gradient.offsets=PackedFloat32Array([0.0,0.35,0.60,1.0])
	gradient.colors=PackedColorArray([Color(.78,.76,.74,1),Color(.95,.94,.92,1),Color(1,1,1,1),Color(1,1,1,0)])
	var texture:=GradientTexture1D.new()
	texture.gradient=gradient
	texture.width=64
	return texture

## A bird strike is feathers: a burst of tumbling primaries and a slower puff of
## down. `velocity` is the direction the round was travelling; `weight` is the
## contact's size factor.
func feather_burst(at: Vector3,velocity: Vector3,weight: float=1.0) -> void:
	if feather_rigs.is_empty():return
	var direction: Vector3=velocity.normalized()
	if direction.length_squared()<.5:direction=Vector3.FORWARD
	# Kills happen at 300-600 m. Life-size feathers are sub-pixel there, so the
	# burst is scaled up with range to stay readable - the guard explicitly
	# allows bending physics for legibility.
	var range_to_camera: float=combat.app.camera.global_position.distance_to(at)
	var readability: float=clampf(1.0+range_to_camera/260.0,1.0,5.0)
	var rig: Dictionary=feather_rigs[feather_cursor%feather_rigs.size()]
	feather_cursor+=1
	for key in ["feathers","down"]:
		var node: GPUParticles3D=rig[key]
		if not is_instance_valid(node):continue
		var process: ParticleProcessMaterial=node.process_material
		process.direction=direction
		var spread_scale: float=readability*clampf(weight,.6,2.4)
		process.scale_min=spread_scale*(1.6 if key=="down" else 1.0)
		process.scale_max=spread_scale*(2.6 if key=="down" else 1.7)
		var speed: float=clampf(weight,.7,2.0)
		process.initial_velocity_min=(2.0 if key=="down" else 6.0)*speed
		process.initial_velocity_max=(9.0 if key=="down" else 22.0)*speed
		node.global_position=at
		node.global_basis=Basis.IDENTITY
		node.restart()
		node.emitting=true

func _stop_feathers() -> void:
	for rig: Dictionary in feather_rigs:
		for key in ["feathers","down"]:
			var node: GPUParticles3D=rig[key]
			if is_instance_valid(node):node.emitting=false

# --- countermeasures ----------------------------------------------------
func _build_flare_ribbon() -> void:
	flare_head_material=Art.emissive(Color(1,.68,.32),3.2,.92)
	flare_head_material.vertex_color_use_as_albedo=true
	flare_head_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	flare_smoke_material=StandardMaterial3D.new()
	flare_smoke_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	flare_smoke_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	flare_smoke_material.vertex_color_use_as_albedo=true
	flare_smoke_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	flare_smoke_material.albedo_color=Color(1,1,1,1)
	flare_mesh=MeshInstance3D.new()
	flare_mesh.mesh=ImmediateMesh.new()
	flare_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flare_mesh)

## Eight MJU-class cartridges ejected in the AIRCRAFT frame, then flown
## ballistically: gravity plus quadratic drag, so they fall down-and-aft and the
## jet runs away from them. One light for the whole salvo.
func flare_salvo() -> void:
	var f=combat.app.flight
	if f==null:return
	var basis:=Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	var origin: Vector3=f.position+basis*Vector3(0,-1.1,1.6)
	for i in range(8):
		var side: float=1.0 if i%2==0 else -1.0
		var ejection: Vector3=Vector3(side*rng.randf_range(1.8,5.4),-rng.randf_range(7.0,11.5),rng.randf_range(5.0,13.0))
		flare_items.append({
			"position":origin+basis*Vector3(side*0.9,-0.35,rng.randf_range(0.0,1.6)),
			"velocity":Vector3(f.velocity)+basis*ejection,
			"life":rng.randf_range(3.6,4.5),
			"duration":4.5,
			"path":PackedVector3Array(),
			"path_clock":0.0})
	# Clamped to 3.2 so a near cluster does not blow out the AgX golden-hour
	# grade, and shadow-disabled like every other pooled light.
	illuminate(origin,Color(1,.70,.38),3.2,46,.85)

func _update_flares(dt: float) -> void:
	for i in range(flare_items.size()-1,-1,-1):
		var item: Dictionary=flare_items[i]
		item.life-=dt
		if item.life<=0:
			flare_items.remove_at(i);continue
		var speed: float=Vector3(item.velocity).length()
		# Quadratic drag: a 0.2 kg cartridge sheds a 380 m/s jet's speed in well
		# under a second, which is exactly why flares appear to stop dead.
		item.velocity+=Vector3(0,-9.81,0)*dt-Vector3(item.velocity)*speed*0.0016*dt
		item.position+=Vector3(item.velocity)*dt
		item.path_clock-=dt
		if item.path_clock<=0:
			item.path_clock=0.055
			var path: PackedVector3Array=item.path
			path.append(item.position)
			if path.size()>10:path.remove_at(0)
			item.path=path

func _draw_flares() -> void:
	var ribbon: ImmediateMesh=flare_mesh.mesh
	ribbon.clear_surfaces()
	if flare_items.is_empty():return
	var eye: Vector3=combat.app.camera.global_position
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES,flare_smoke_material)
	for item: Dictionary in flare_items:
		var path: PackedVector3Array=item.path
		for p in range(path.size()-1):
			var a: Vector3=path[p]
			var b: Vector3=path[p+1]
			var fade: float=float(p+1)/maxf(path.size(),1)
			var width: float=lerpf(2.6,.5,fade)
			var side: Vector3=(b-a).cross(eye-a).normalized()*width
			if side.length_squared()<.0001:continue
			var alpha: float=(1.0-fade)*.30*clampf(item.life/1.2,0,1)
			for v: Vector3 in [a-side,a+side,b-side,b-side,a+side,b+side]:
				ribbon.surface_set_color(Color(.70,.69,.66,alpha))
				ribbon.surface_add_vertex(v)
	ribbon.surface_end()
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES,flare_head_material)
	for item: Dictionary in flare_items:
		var at: Vector3=item.position
		var burn: float=clampf(item.life/0.9,0,1)*clampf((float(item.duration)-float(item.life))/0.10,0,1)
		var size: float=clampf(eye.distance_to(at)*0.0045,.6,4.5)*(.7+.3*sin(effects_clock*57.0+at.x))
		var right: Vector3=(at-eye).cross(Vector3.UP).normalized()
		if right.length_squared()<.0001:right=Vector3.RIGHT
		var up: Vector3=(at-eye).cross(right).normalized()
		var colour:=Color(3.2,1.95,.78,burn)
		for v: Vector3 in [at-right*size-up*size,at+right*size-up*size,at-right*size+up*size,
				at-right*size+up*size,at+right*size-up*size,at+right*size+up*size]:
			ribbon.surface_set_color(colour)
			ribbon.surface_add_vertex(v)
	ribbon.surface_end()

# --- pools --------------------------------------------------------------
func take_projectile(kind: String) -> Node3D:
	var key: String="cannon"
	var node: Node3D
	if not projectile_pool[key].is_empty():node=projectile_pool[key].pop_back()
	else:
		node=Art.projectile(key);node.set_meta("projectile_kind",key);add_child(node)
	node.visible=true;node.scale=Vector3.ONE
	return node
func release_projectile(node: Node3D,kind: String) -> void:
	if not is_instance_valid(node):return
	node.visible=false
	var key: String="cannon"
	if not projectile_pool[key].has(node):projectile_pool[key].append(node)
func reset() -> void:
	for effect in sprites:
		effect.node.visible=false;sprite_pool.append(effect.node)
	sprites.clear()
	for effect in lights:
		effect.node.visible=false;light_pool.append(effect.node)
	lights.clear()
	for entry in rings:
		if is_instance_valid(entry.node):entry.node.queue_free()
	rings.clear()
	if lead_mesh!=null:lead_mesh.mesh.clear_surfaces()
	_stop_feathers()
	flare_items.clear()
	if flare_mesh!=null:flare_mesh.mesh.clear_surfaces()
	last_flares_fired=int(combat.flares_fired) if combat!=null else 0
	for child in get_children():
		if child is Node3D and child.has_meta("projectile_kind"):
			release_projectile(child,str(child.get_meta("projectile_kind")))
func puff(at: Vector3,color: Color,size: float,life: float,smoke: bool=false,velocity: Vector3=Vector3.ZERO,delay: float=0.0) -> void:
	if sprite_pool.is_empty():return
	var node: Sprite3D=sprite_pool.pop_back();node.texture=smoke_texture if smoke else flash_texture;node.position=at;node.modulate=color;node.pixel_size=size/maxf(node.texture.get_width(),1);node.scale=Vector3.ONE;node.visible=delay<=0
	sprites.append({"node":node,"life":life,"duration":life,"delay":delay,"color":color,"velocity":velocity,"smoke":smoke})
func illuminate(at: Vector3,color: Color,energy: float,radius: float,life: float) -> void:
	if light_pool.is_empty():return
	var node: OmniLight3D=light_pool.pop_back();node.position=at;node.light_color=color;node.light_energy=energy;node.omni_range=radius;node.visible=true
	lights.append({"node":node,"life":life,"duration":life,"energy":energy})

func _enemy_near(at: Vector3) -> Dictionary:
	var best: Dictionary={}
	var best_distance: float=1.0e20
	for item: Dictionary in combat.enemies:
		var d: float=Vector3(item.position).distance_squared_to(at)
		if d<best_distance:best_distance=d;best=item
	return best

func event(kind: String,at: Vector3,weight: float) -> void:
	if kind=="roll":combat.app.audio.play_spatial("sonic",at,-24,1.15);combat.app.camera_rig.impulse(.025)
	elif kind=="scan":scan_time=.35
	elif kind=="candidate":puff(at,Color(.12,.65,1,.22),16,.2)
	elif kind=="lock":puff(at,Color(.3,1,1,.75),28,.15);combat.app.audio.ping(1.35)
	elif kind=="near_miss":
		combat.app.audio.play_spatial("sonic",at,-19,1.35);combat.app.camera_rig.impulse(.08)
	elif kind in ["impact","armor_break","kill","boss_death"]:
		var lethal: bool=kind in ["kill","boss_death"]
		if lethal:handoff_origin=at;handoff_time=.65
		var big: bool=kind=="boss_death"
		var radius: float=(22 if kind=="impact" else 34)*weight
		# The one bright thing left. It has to carry "scored hit" to a novice
		# 600 m away, so it stays hot - but it is 0.07 s, not a fireball.
		puff(at,Color(2.6,2.2,1.6,.95),radius*.6,.07)
		if kind=="impact":
			# A missile warhead genuinely burns. This is the only warm fireball
			# left in the kill path.
			puff(at,Color(1,.52,.20,.88),radius*1.15,.26,false,Vector3.ZERO,.045)
			puff(at,Color(.52,.50,.47,.42),radius*1.25,.40,true,Vector3.UP*5,.10)
			illuminate(at,Color(1,.60,.30),3.0,42,.18)
		else:
			# Bird strike: a short puff of dust, then feathers. No fireball, no
			# cyan shockwave, no cyan sparks, no 45 m orange light. The old
			# smoke ball was 78 m across for 1.3 s and smeared into a grey
			# streak under FSR2 whenever the camera moved.
			puff(at,Color(.55,.50,.45,.48),radius*.85,.28,true,Vector3.UP*4)
		if lethal or kind=="armor_break":
			var victim: Dictionary=_enemy_near(at)
			# Feathers spray along the round's path, canted by the bird's own
			# track so the burst leans the way the goose was going.
			var direction: Vector3=(at-combat.app.flight.position).normalized()
			if not victim.is_empty():
				var track: Vector3=Vector3(victim.velocity).normalized()
				if track.length_squared()>.5:direction=(direction*2.0+track).normalized()
			feather_burst(at,direction,weight*(2.2 if big else (1.0 if lethal else .55)))
		# Speed of sound: engine_audio queues this by range, and the flat
		# non-positional bang combat.gd plays next is folded into the same cue.
		var audio=combat.app.audio
		if audio!=null and audio.has_method("mark_event_position"):
			audio.mark_event_position("explosion" if lethal else "impact",at,-10 if big else -19,.65 if big else 1.0)
		else:
			audio.play_spatial("explosion" if lethal else "impact",at,-10 if big else -19,.65 if big else 1.0)
		if big or kind=="armor_break":
			impact_emphasis=.055;combat.app.camera_rig.impulse(.22 if big else .10)
	elif kind=="boss_signature":scan_time=1.0;puff(at,Color(.06,.6,1,.25),180,2.0)
func add_target(enemy: Dictionary) -> void:
	var shell: ShaderMaterial
	if DisplayServer.get_name()!="headless":
		shell=ShaderMaterial.new();shell.shader=load("res://assets/vfx/spectral_target.gdshader")
		for geometry in enemy.node.find_children("*","MeshInstance3D",true,false):geometry.material_overlay=shell
	enemy.spectral_material=shell
	var root:=Node3D.new();root.name="SpectralTracking";enemy.node.add_child(root)
	var material:=Art.emissive(Color(.12,.75,1),2,.12)
	# The three rotating cyan arcs that used to live here are gone: the HUD
	# brackets do the designation work and nothing may veil the view.
	if enemy.kind=="boss":
		for side in [-1,0,1]:
			var marker:=Sprite3D.new();marker.name="Weak"+str(side);marker.texture=flash_texture;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;marker.pixel_size=.0013;marker.position.x=side*.75;root.add_child(marker)
	rings.append({"node":root,"id":enemy.id,"material":material})
func tick(dt: float) -> void:
	effects_clock+=dt;handoff_time=maxf(0,handoff_time-dt);scan_time=maxf(0,scan_time-dt);impact_emphasis=maxf(0,impact_emphasis-dt)
	# Countermeasures are owned here: combat.gd only counts them, so the salvo
	# is picked up from its own counter rather than reaching into that file.
	var fired: int=int(combat.flares_fired)
	if fired>last_flares_fired:
		last_flares_fired=fired
		flare_salvo()
	elif fired<last_flares_fired:
		last_flares_fired=fired
	_update_flares(dt)
	_draw_flares()
	var audio=combat.app.audio
	if audio!=null and audio.has_method("update_flock"):audio.update_flock(combat,dt)
	for i in range(sprites.size()-1,-1,-1):
		var e: Dictionary=sprites[i]
		if e.delay>0:e.delay-=dt;continue
		e.node.visible=true;e.life-=dt
		if e.life<=0:e.node.visible=false;sprite_pool.append(e.node);sprites.remove_at(i);continue
		e.node.position+=e.velocity*dt;var t: float=1-e.life/e.duration
		# Smoke used to grow 2.5x, which is what FSR2 smeared into grey streaks.
		e.node.scale=Vector3.ONE*(1+t*(.85 if e.smoke else .7));var color: Color=e.color;color.a*=1-smoothstep(.08,1,t);e.node.modulate=color
	for i in range(lights.size()-1,-1,-1):
		var e: Dictionary=lights[i];e.life-=dt
		if e.life<=0:e.node.visible=false;light_pool.append(e.node);lights.remove_at(i)
		else:e.node.light_energy=e.energy*e.life/e.duration
	var target: Dictionary=combat.target()
	for entry in rings:
		if not is_instance_valid(entry.node):continue
		var enemy: Dictionary={}
		for item: Dictionary in combat.enemies:
			if item.id==entry.id:enemy=item;break
		if enemy.is_empty():continue
		var selected: bool=enemy.id==combat.target_id
		var shell: ShaderMaterial=enemy.get("spectral_material")
		if shell!=null:
			shell.set_shader_parameter("confidence",combat.lock_progress if selected else .12)
			shell.set_shader_parameter("hit",enemy.hit_flash)
			shell.set_shader_parameter("damage",float(enemy.damage_stage)/3)
			shell.set_shader_parameter("visibility",enemy.fade)
		entry.node.visible=enemy.kind=="boss"
		if enemy.kind=="boss":
			for side in [-1,0,1]:
				var marker: Sprite3D=entry.node.get_node("Weak"+str(side))
				marker.modulate=Color(3,2,1,.85) if side==int(enemy.weak_side) and enemy.damage_stage>0 else Color(.1,.5,.8,.06)
		var designated: bool=selected and combat.lock_progress>=1
		for geometry in enemy.node.find_children("*","MeshInstance3D",true,false):
			for surface in range(geometry.mesh.get_surface_count()):
				var mat=geometry.get_active_material(surface)
				if mat is StandardMaterial3D and mat.stencil_mode!=0:
					# One thin outline while designated. The always-on X-ray
					# silhouette is gone: it read as a cyan ghost through the
					# whole airframe and veiled the bird it was marking.
					mat.stencil_mode=BaseMaterial3D.STENCIL_MODE_OUTLINE
					mat.stencil_color=Color(.52,.64,.76,.55 if designated else 0.0)
					mat.emission_energy_multiplier=.7+enemy.hit_flash*3+enemy.damage_stage*.3
					mat.stencil_outline_thickness=.35 if designated else .0
	_draw_lead(target)
func _draw_lead(target: Dictionary) -> void:
	var ribbon: ImmediateMesh=lead_mesh.mesh;ribbon.clear_surfaces()
	if target.is_empty() or combat.intent.confidence<.3:return
	var f: FlightDynamics=combat.app.flight;var end: Vector3=combat.lead_point(target)
	var start: Vector3=handoff_origin if handoff_time>0 else f.position+combat.forward()*70
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(12):
		if i%2==1:continue
		var a: Vector3=start.lerp(end,float(i)/12);var b: Vector3=start.lerp(end,float(i+1)/12)
		var side: Vector3=(b-a).cross(combat.app.camera.global_position-a).normalized()*.4
		for p: Vector3 in [a-side,a+side,b-side,b-side,a+side,b+side]:ribbon.surface_add_vertex(p)
	ribbon.surface_end()
