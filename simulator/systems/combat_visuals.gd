extends Node3D
## Composes the existing weapon primitives, sprites, material overlays and light pools.
const Art = preload("res://systems/weapon_visuals.gd")
var combat: Node
var projectile_pool := {"cannon":[],"missile":[]}
var sprites: Array[Dictionary] = []
var sprite_pool: Array[Sprite3D] = []
var lights: Array[Dictionary] = []
var light_pool: Array[OmniLight3D] = []
var rings: Array[Dictionary] = []
var beams: Array[MeshInstance3D] = []
var lead_mesh: MeshInstance3D
var beam_light: OmniLight3D
var ghost_clock := 0.0
var effects_clock := 0.0
var scan_time := 0.0
var handoff_origin:=Vector3.ZERO
var handoff_time:=0.0
var impact_emphasis := 0.0
var flash_texture: Texture2D
var smoke_texture: Texture2D
func _ready() -> void:
	flash_texture=load("res://assets/vfx/flash.png");smoke_texture=load("res://assets/sourced_flight/smoke.png")
	beams.append(Art.beam(self,Color(.72,.94,1),.10,1))
	beams.append(Art.energy_sheath(self,.38,0))
	beams.append(Art.energy_sheath(self,.72,1.4))
	for beam in beams:beam.visible=false
	beam_light=OmniLight3D.new();beam_light.light_color=Color(.15,.7,1);beam_light.omni_range=35;beam_light.shadow_enabled=false;beam_light.visible=false;add_child(beam_light)
	lead_mesh=MeshInstance3D.new();lead_mesh.mesh=ImmediateMesh.new();lead_mesh.material_override=Art.emissive(Color(.08,.55,.8),1.3,.15);lead_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(lead_mesh)
	for i in range(96):
		var sprite:=Sprite3D.new();sprite.texture=flash_texture;sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED;sprite.shaded=false;sprite.visible=false;sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(sprite);sprite_pool.append(sprite)
	for i in range(8):
		var light:=OmniLight3D.new();light.shadow_enabled=false;light.visible=false;add_child(light);light_pool.append(light)
	# Warm the actual meshes/materials before the first salvo.
	for kind in ["cannon","missile"]:
		for i in range(48 if kind=="cannon" else 48):
			var node:=Art.projectile(kind);node.set_meta("projectile_kind",kind);add_child(node);node.visible=false
			if kind=="missile":_equip_missile(node)
			projectile_pool[kind].append(node)
	if DisplayServer.get_name()!="headless":call_deferred("_warm_pipeline")
func _warm_pipeline() -> void:
	if combat.app.mode!="title":return
	var preview: Node3D=projectile_pool.missile[0];preview.position=Vector3(0,0,-12);preview.visible=true
	for beam in beams:beam.position=Vector3(-1,0,-8);beam.visible=true
	await get_tree().process_frame
	await get_tree().process_frame
	preview.visible=false
	for beam in beams:beam.visible=false
func _equip_missile(node: Node3D) -> void:
	var flare:=Sprite3D.new();flare.name="EngineFlare";flare.texture=flash_texture;flare.billboard=BaseMaterial3D.BILLBOARD_ENABLED;flare.shaded=false;flare.position.z=1.65;flare.modulate=Color(4,2.8,1.6,.8);flare.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.add_child(flare)
	var light:=OmniLight3D.new();light.name="MotorLight";light.light_color=Color(.6,.82,1);light.omni_range=24;light.shadow_enabled=false;node.add_child(light)
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		if mesh.name in ["Ignition","MotorFlame"]:continue
		for i in range(mesh.mesh.get_surface_count()):
			var original=mesh.get_active_material(i)
			if original is StandardMaterial3D:
				var material: StandardMaterial3D=original.duplicate();material.metallic=.72;material.roughness=.22;material.clearcoat_enabled=true;material.clearcoat=.65
				mesh.set_surface_override_material(i,material)
func take_projectile(kind: String) -> Node3D:
	var key: String="missile" if kind=="missile" else "cannon"
	var node: Node3D
	if not projectile_pool[key].is_empty():node=projectile_pool[key].pop_back()
	else:
		node=Art.projectile(key);node.set_meta("projectile_kind",key);add_child(node)
		if key=="missile":_equip_missile(node)
	node.visible=true;node.scale=Vector3.ONE*(1.7 if key=="missile" else 1.0)
	return node
func release_projectile(node: Node3D,kind: String) -> void:
	if not is_instance_valid(node):return
	node.visible=false
	var key: String="missile" if kind=="missile" else "cannon"
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
	for beam in beams:beam.visible=false
	if lead_mesh!=null:lead_mesh.mesh.clear_surfaces()
	if beam_light!=null:beam_light.visible=false
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
func event(kind: String,at: Vector3,weight: float) -> void:
	if kind=="roll":combat.app.audio.play_spatial("sonic",at,-24,1.15);combat.app.camera_rig.impulse(.025)
	elif kind=="scan":scan_time=.35
	elif kind=="candidate":puff(at,Color(.12,.65,1,.22),16,.2)
	elif kind=="lock":puff(at,Color(.3,1,1,.75),28,.15);combat.app.audio.ping(1.35)
	elif kind=="salvo":
		illuminate(at,Color(.6,.85,1),5,16,.2)
		puff(at-combat.forward()*5,Color(.72,.86,1,.4),12,.5,true)
	elif kind=="near_miss":
		combat.app.audio.play_spatial("sonic",at,-19,1.35);combat.app.camera_rig.impulse(.08)
	elif kind in ["impact","armor_break","kill","boss_death"]:
		if kind in ["kill","boss_death"]:handoff_origin=at;handoff_time=.65
		var big: bool=kind=="boss_death"
		var radius: float=(22 if kind=="impact" else 34)*weight
		puff(at,Color(3,2.4,1.5,.95),radius,.10)
		puff(at,Color(1,.54,.20,.90),radius*1.4,.32,false,Vector3.ZERO,.045)
		puff(at,Color(.12,.65,1,.48),radius*1.8,.45,false,Vector3.ZERO,.08)
		puff(at,Color(.35,.4,.46,.72),radius*2.3,2.6 if big else 1.3,true,Vector3.UP*8,.16)
		illuminate(at,Color(1,.64,.35),9 if big else 4,180 if big else 45,.55 if big else .25)
		combat.app.audio.play_spatial("explosion" if kind in ["kill","boss_death"] else "impact",at,-10 if big else -19,.65 if big else 1)
		for i in range(16 if big else 5):
			var velocity:=Vector3(sin(i*2.4),cos(i*1.7)*.5,cos(i*2.4))*weight*15
			puff(at,Color(.2,.85,1,.8),3*weight,.7,false,velocity,.04*i if big else 0)
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
	for i in range(3):
		var arc:=MeshInstance3D.new();var segments:=ImmediateMesh.new();segments.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for sector in range(4):
			for point in range(5):
				var a: float=sector*PI*.5+.12+point*.16;var b: float=a+.16
				var va:=Vector3(cos(a),sin(a),0);var vb:=Vector3(cos(b),sin(b),0)
				for v: Vector3 in [va*2.6,va*2.635,vb*2.6,vb*2.6,va*2.635,vb*2.635]:segments.surface_add_vertex(v)
		segments.surface_end()
		arc.mesh=segments;arc.material_override=material;arc.rotation=Vector3(PI/2,i*.75,i*.4);arc.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(arc)
	if enemy.kind=="boss":
		for side in [-1,0,1]:
			var marker:=Sprite3D.new();marker.name="Weak"+str(side);marker.texture=flash_texture;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;marker.pixel_size=.0013;marker.position.x=side*.75;root.add_child(marker)
	rings.append({"node":root,"id":enemy.id,"material":material})
func update_projectile(shot: Dictionary,dt: float) -> void:
	if shot.kind!="missile":return
	var flare: Sprite3D=shot.node.get_node_or_null("EngineFlare")
	var motor: OmniLight3D=shot.node.get_node_or_null("MotorLight")
	var burning: bool=shot.age>.15 and shot.age<4
	var distance: float=combat.app.camera.global_position.distance_to(shot.position)
	if flare!=null:
		flare.visible=burning;flare.pixel_size=clampf(distance*.000020,.007,.05)
		flare.modulate=Color(4,3,1.8,.68+.16*sin(shot.age*91))
	if motor!=null:
		motor.visible=burning and distance<450;motor.light_energy=3.5 if burning else 0
	if burning and shot.age-float(shot.get("ghost_at",0))>.09:
		shot.ghost_at=shot.age
		puff(shot.position,Color(.12,.65,1,.24),clampf(distance*.014,2,12),.24)
func tick(dt: float) -> void:
	effects_clock+=dt;handoff_time=maxf(0,handoff_time-dt);scan_time=maxf(0,scan_time-dt);impact_emphasis=maxf(0,impact_emphasis-dt)
	for i in range(sprites.size()-1,-1,-1):
		var e: Dictionary=sprites[i]
		if e.delay>0:e.delay-=dt;continue
		e.node.visible=true;e.life-=dt
		if e.life<=0:e.node.visible=false;sprite_pool.append(e.node);sprites.remove_at(i);continue
		e.node.position+=e.velocity*dt;var t: float=1-e.life/e.duration
		e.node.scale=Vector3.ONE*(1+t*(1.5 if e.smoke else .7));var color: Color=e.color;color.a*=1-smoothstep(.08,1,t);e.node.modulate=color
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
		var strength: float=(.25+combat.lock_progress*.6) if selected else .18 if enemy.kind=="boss" else .05 if scan_time>0 else .012
		entry.node.visible=selected or scan_time>0 or enemy.kind=="boss"
		entry.node.rotation.z+=dt*(.12 if selected and combat.lock_progress>=1 else .5)
		entry.node.scale=Vector3.ONE*lerpf(1.30,.78,combat.lock_progress if selected else 0)
		entry.material.albedo_color=Color(.13,.8,1,strength*(.2 if enemy.health<=0 else 1))
		entry.material.emission_energy_multiplier=2+enemy.hit_flash*4
		if enemy.kind=="boss":
			for side in [-1,0,1]:
				var marker: Sprite3D=entry.node.get_node("Weak"+str(side))
				marker.modulate=Color(3,2,1,.85) if side==int(enemy.weak_side) and enemy.damage_stage>0 else Color(.1,.5,.8,.06)
		for geometry in enemy.node.find_children("*","MeshInstance3D",true,false):
			for surface in range(geometry.mesh.get_surface_count()):
				var mat=geometry.get_active_material(surface)
				if mat is StandardMaterial3D and mat.stencil_mode!=0:
					mat.stencil_mode=BaseMaterial3D.STENCIL_MODE_XRAY if selected and combat.lock_progress>=1 else BaseMaterial3D.STENCIL_MODE_OUTLINE
					mat.stencil_color=Color(.02,.12,.28,.85) if combat.app.camera.global_position.y<enemy.position.y else Color(.08,.7,1,.8 if selected else .45)
					mat.emission_energy_multiplier=.7+enemy.hit_flash*3+enemy.damage_stage*.3
					mat.stencil_outline_thickness=.5 if selected else .25
	for beam in beams:beam.visible=combat.beam_active
	beam_light.visible=combat.beam_active and combat.beam_hit_id>=0
	if combat.beam_active:
		var f: FlightDynamics=combat.app.flight;var basis:=Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll));var start: Vector3=f.position+basis*Vector3(.75,-.30,-3.8)
		for beam in beams:Art.align_beam(beam,start,combat.beam_end)
		beam_light.position=combat.beam_end;beam_light.light_energy=3+sin(effects_clock*31)
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
