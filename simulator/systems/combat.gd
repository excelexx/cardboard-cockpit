extends Node3D
class_name CombatDirector
## One fighter, one permanent cannon-and-missile loadout. No progression system.
const WeaponArt = preload("res://systems/weapon_visuals.gd")
var app: Node
var active := false
var elapsed := 0.0
var duration := 180.0
var hull := 100.0
var ammo := 1200
var missiles := 8
var flares := 8
var kills := 0
var score := 0
var rounds_fired := 0
var rounds_hit := 0
var missiles_fired := 0
var missiles_evaded := 0
var gun_heat := 0.0
var gun_overheated := false
var gun_cooldown := 0.0
var missile_cooldown := 0.0
var flare_cooldown := 0.0
var lock_progress := 0.0
var target_id := -1
var next_id := 0
var spawn_clock := 2.0
var attack_spacing := 0.0
var launch_queue: Array[Dictionary] = []
var incoming_distance := INF
var incoming_bearing := 0.0
var threat_level := 0.0
var hit_flash := 0.0
var hit_confirm := 0.0
var assist := true
var last_missile: Node3D
var enemies: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var bursts: Array[Dictionary] = []
var flash_texture: Texture2D
var rng := RandomNumberGenerator.new()
var route_target := Vector3(0,500,-9000)
var patrol_south := false
var course_recovery := false
var safe_waypoint := Vector3.ZERO
var message := ""
var message_time := 0.0

func reset(enabled: bool = true) -> void:
	for child: Node in get_children():
		remove_child(child); child.queue_free()
	enemies.clear(); shots.clear(); bursts.clear(); launch_queue.clear()
	active = enabled; elapsed = 0; hull = 100
	ammo = 1200; missiles = 8; flares = 8
	kills = 0; score = 0; rounds_fired = 0; rounds_hit = 0; missiles_fired = 0; missiles_evaded = 0
	gun_heat = 0; gun_overheated = false; gun_cooldown = 0; missile_cooldown = 0; flare_cooldown = 0
	lock_progress = 0; target_id = -1; next_id = 0; spawn_clock = 2
	incoming_distance = INF; threat_level = 0; hit_flash = 0; hit_confirm = 0
	last_missile = null; message = ""; message_time = 0; attack_spacing = 0
	patrol_south = false; course_recovery = false; rng.seed = 260926

func forward() -> Vector3: return app.flight.forward().normalized()
func target() -> Dictionary:
	for enemy: Dictionary in enemies:
		if enemy.id==target_id and enemy.health>0: return enemy
	return {}
func announce(value: String) -> void:
	message = value; message_time = 2.5

func goose_model() -> Node3D:
	var root := Node3D.new()
	var body: Node3D = load("res://assets/goose/goose.glb").instantiate()
	body.scale = Vector3.ONE*0.065
	body.rotation.y = PI
	root.add_child(body)
	for side in [-1,1]:
		var wing := Node3D.new()
		wing.name = "WingL" if side<0 else "WingR"
		wing.position = Vector3(side*0.65,0,0)
		root.add_child(wing)
		for feather in range(7):
			var color := Color(0.37,0.34,0.28).lerp(Color(0.11,0.13,0.13),float(feather)/7)
			box(wing,Vector3(1.1,0.12,1.8-feather*0.12),Vector3(side*(0.65+feather*0.42),0,feather*0.11),color)
	root.scale = Vector3.ONE*5.5
	return root

func spawn_contact() -> void:
	var node := goose_model()
	add_child(node)
	var count: int = enemies.size()
	var right := Vector3(cos(app.flight.heading),0,sin(app.flight.heading))
	var distance: float = 800+rng.randf_range(0,700)
	var at: Vector3 = app.flight.position+forward()*distance+right*rng.randf_range(-450,450)
	at.y = maxf(at.y+rng.randf_range(-90,130),app.world.ground_height(at.x,at.z)+140)
	node.position = at
	var contact: Dictionary = {"id":next_id,"node":node,"position":at,"health":110.0,"max_health":110.0,"velocity":Vector3.ZERO,"cooldown":10.0+rng.randf_range(0,7),"age":0.0,"phase":rng.randf_range(0,TAU),"fade":0.0}
	enemies.append(contact); next_id += 1

func tick(dt: float) -> void:
	if not active: return
	elapsed += dt
	update_launches(dt)
	gun_cooldown = maxf(0,gun_cooldown-dt); missile_cooldown = maxf(0,missile_cooldown-dt); flare_cooldown = maxf(0,flare_cooldown-dt)
	gun_heat = maxf(0,gun_heat-dt*0.21)
	if gun_overheated and gun_heat<0.30: gun_overheated = false
	hit_flash = maxf(0,hit_flash-dt*2.4); hit_confirm = maxf(0,hit_confirm-dt*5)
	message_time = maxf(0,message_time-dt)
	spawn_clock -= dt
	attack_spacing = maxf(0,attack_spacing-dt)
	var desired_count: int = 3+int(minf(elapsed/35,4))
	if spawn_clock<=0 and enemies.size()<desired_count:
		spawn_contact()
		spawn_clock = 2.0 if elapsed<9 else 5.5
	var best := -1
	var best_dot: float = cos(deg_to_rad(13))
	var old_alignment := -1.0
	for enemy: Dictionary in enemies:
		if enemy.health<=0: continue
		enemy.age += dt
		enemy.fade = minf(1,enemy.fade+dt*1.8)
		var to_plane: Vector3 = app.flight.position-enemy.position
		var distance: float = to_plane.length()
		var lateral: Vector3 = to_plane.normalized().cross(Vector3.UP)
		var course: Vector3 = forward()*app.flight.speed*0.88
		var velocity: Vector3 = course+to_plane.normalized()*(35 if distance>900 else -20)+lateral*sin(enemy.age*0.6+enemy.phase)*35
		enemy.position += velocity*dt
		enemy.position.y = maxf(enemy.position.y,app.world.ground_height(enemy.position.x,enemy.position.z)+90)
		enemy.velocity = velocity
		enemy.node.position = enemy.position
		if velocity.length()>1: enemy.node.look_at(enemy.position+velocity,Vector3.UP)
		var flap: float = sin(elapsed*4.2+enemy.phase)*0.32
		enemy.node.get_node("WingL").rotation.z = flap
		enemy.node.get_node("WingR").rotation.z = -flap
		if enemy.fade<1:
			for geometry: Node in enemy.node.find_children("*","GeometryInstance3D",true,false): geometry.transparency = 1-enemy.fade
		enemy.cooldown -= dt
		if elapsed>16 and enemy.cooldown<=0 and attack_spacing<=0 and distance<2300:
			enemy.cooldown = rng.randf_range(13,19)
			attack_spacing = 5.0
			var aim: Vector3 = (app.flight.position+app.flight.velocity*0.6-enemy.position).normalized()
			spawn_shot(enemy.position,aim*270,"hostile_missile",-1,24)
		var alignment: float = forward().dot((enemy.position-app.flight.position).normalized())
		if enemy.id==target_id: old_alignment = alignment
		if distance<3200 and alignment>best_dot:
			best = enemy.id; best_dot = alignment
	if old_alignment>cos(deg_to_rad(9)) and acos(clampf(old_alignment,-1,1))-acos(clampf(best_dot,-1,1))<deg_to_rad(2.5):
		best = target_id; best_dot = old_alignment
	if best!=target_id: target_id = best; lock_progress = 0
	var locked_before: bool = lock_progress>=1
	if target_id>=0 and best_dot>cos(deg_to_rad(6)):
		lock_progress = minf(1,lock_progress+dt/0.75)
	else: lock_progress = maxf(0,lock_progress-dt*2)
	if not locked_before and lock_progress>=1:
		app.audio.radio.say("target_locked")
	update_shots(dt); update_bursts(dt)
	incoming_distance = INF
	for shot: Dictionary in shots:
		if shot.kind=="hostile_missile" and shot.life>0:
			var delta: Vector3 = shot.position-app.flight.position
			if delta.length()<incoming_distance:
				incoming_distance = delta.length()
				incoming_bearing = wrapf(atan2(delta.x,-delta.z)-app.flight.heading,-PI,PI)
	threat_level = 1-clampf(incoming_distance/2200,0,1)
	if incoming_distance<1800: app.audio.radio.say("warning")
	if hull<=0:
		active = false
		app.begin_crash()
	elif elapsed>=duration: complete(true,"Patrol complete. Return vector received.")

func assisted_direction() -> Vector3:
	var direction: Vector3 = forward()
	if not assist: return direction
	var enemy: Dictionary = target()
	if enemy.is_empty(): return direction
	var wanted: Vector3 = (enemy.position-app.flight.position).normalized()
	var angle: float = direction.angle_to(wanted)
	if angle>deg_to_rad(10) or angle<0.0001: return direction
	return direction.slerp(wanted,minf(0.08,deg_to_rad(1.5)/angle)).normalized()

func fire_gun() -> bool:
	if not active or ammo<=0 or gun_cooldown>0 or gun_overheated: return false
	gun_cooldown = 0.075
	gun_heat = minf(1,gun_heat+0.032)
	if gun_heat>=0.98: gun_overheated = true; app.audio.radio.say("reload")
	ammo -= 1; rounds_fired += 1
	var direction: Vector3 = assisted_direction()
	var basis: Basis = Basis.from_euler(Vector3(app.flight.pitch,-app.flight.heading,-app.flight.roll))
	var muzzle: Vector3 = app.flight.position+basis*Vector3(-0.9,0.7,-6.4)
	spawn_shot(muzzle,direction*1250+app.flight.velocity,"cannon",-1,28)
	burst(muzzle,Color(1,0.75,0.37),0.7)
	app.audio.play_effect("cannon",-20,rng.randf_range(0.96,1.06))
	app.camera_rig.impulse(0.10)
	return true

func fire_missile() -> bool:
	if not active or missiles<=0 or missile_cooldown>0: return false
	if target_id<0 or lock_progress<1:
		announce("ACQUIRE A STABLE TONE")
		return false
	missiles -= 1; missiles_fired += 1; missile_cooldown = 1.5
	var side: float = -1 if missiles_fired%2 else 1
	launch_queue.append({"target":target_id,"side":side,"internal":missiles_fired<=4,"store":maxi(0,missiles_fired-5),"delay":0.23 if missiles_fired<=4 else 0.05})
	if missiles_fired<=4:
		app.aircraft_visuals.open_weapon_bay(side)
		app.audio.play_effect("gear_motor",-28)
	return true

func update_launches(dt: float) -> void:
	for i in range(launch_queue.size()-1,-1,-1):
		var request: Dictionary = launch_queue[i]
		request.delay -= dt
		if request.delay>0: continue
		var basis: Basis = Basis.from_euler(Vector3(app.flight.pitch,-app.flight.heading,-app.flight.roll))
		var at: Vector3 = app.flight.position+basis*Vector3(request.side*0.58,-1.5,-1.0)
		if not request.internal and request.store<app.fighter_fx.stores.size(): at = app.fighter_fx.stores[request.store].global_position
		spawn_shot(at,forward()*310+app.flight.velocity*0.45,"missile",request.target,135)
		last_missile = shots.back().node
		app.audio.play_effect("missile",-11)
		app.camera_rig.impulse(0.28)
		app.fighter_fx.missile_launch(request.side)
		launch_queue.remove_at(i)

func deploy_flares() -> bool:
	if not active or flares<=0 or flare_cooldown>0: return false
	flares -= 1; flare_cooldown = 4
	for shot: Dictionary in shots:
		if shot.kind=="hostile_missile" and shot.position.distance_to(app.flight.position)<1800:
			shot.decoy = app.flight.position+Vector3(cos(app.flight.heading),0,sin(app.flight.heading))*(120 if rng.randf()>0.5 else -120)+Vector3(0,-35,60)
			shot.life = minf(shot.life,1.6)
	for i in range(10): burst(app.flight.position+Vector3(rng.randf_range(-9,9),rng.randf_range(-3,3),rng.randf_range(8,24)),Color(1,0.65,0.25),2.2)
	app.audio.play_effect("flare",-14)
	return true

func update_shots(dt: float) -> void:
	for shot: Dictionary in shots:
		shot.life -= dt
		if shot.life<=0: continue
		var previous: Vector3 = shot.position
		var wanted := Vector3.ZERO
		var guided := false
		if shot.kind=="missile":
			for enemy: Dictionary in enemies:
				if enemy.id==shot.target and enemy.health>0:
					wanted = (enemy.position+enemy.velocity*0.12-shot.position).normalized(); guided = true
		elif shot.kind=="hostile_missile":
			wanted = (Vector3(shot.get("decoy",app.flight.position+app.flight.velocity*0.35))-shot.position).normalized(); guided = true
		if guided:
			var current: Vector3 = shot.velocity.normalized()
			var angle: float = current.angle_to(wanted)
			var rate: float = deg_to_rad(28 if shot.kind=="hostile_missile" else 48)
			shot.velocity = current.slerp(wanted,minf(1,rate*dt/maxf(angle,0.0001)))*(280 if shot.kind=="hostile_missile" else 510)
		shot.position += shot.velocity*dt
		shot.node.position = shot.position
		shot.node.look_at(shot.position+shot.velocity,Vector3.UP)
		if shot.kind in ["missile","hostile_missile"]: update_trail(shot)
		if shot.kind=="hostile_missile":
			if segment_distance(app.flight.position,previous,shot.position)<8:
				hull = maxf(0,hull-shot.damage); shot.life = 0; shot.hit_player = true; hit_flash = 0.35
				app.camera_rig.impulse(0.65)
				app.audio.play_effect("impact",-11)
				burst(app.flight.position,Color(1,0.45,0.17),4)
		else:
			for enemy: Dictionary in enemies:
				if enemy.health>0 and segment_distance(enemy.position,previous,shot.position)<(19 if shot.kind=="missile" else 10):
					enemy.health -= shot.damage; shot.life = 0; hit_confirm = 1
					if shot.kind=="cannon": rounds_hit += 1
					burst(enemy.position,Color(1,0.66,0.27),4)
					break
	for i in range(shots.size()-1,-1,-1):
		if shots[i].life<=0:
			if shots[i].has("decoy") and not shots[i].get("hit_player",false): missiles_evaded += 1
			free_shot(shots[i]); shots.remove_at(i)
	for i in range(enemies.size()-1,-1,-1):
		var enemy: Dictionary = enemies[i]
		if enemy.health<=0:
			kills += 1; score += 100
			burst(enemy.position,Color(1,0.43,0.12),18)
			app.fighter_fx.debris(enemy.position)
			app.audio.play_effect("explosion",-13)
			app.audio.radio.say("target_down" if kills%2 else "target_down_alt")
			enemy.node.queue_free(); enemies.remove_at(i)

func pilot_controls() -> Vector3:
	var at: Vector3 = app.flight.position
	if at.z<-14500: patrol_south = true
	if at.z>1800: patrol_south = false
	if not course_recovery and (absf(at.x)>1300 or at.z<-13500 or at.z>1500):
		course_recovery = true
		safe_waypoint = Vector3(0,at.y,-6500)
	if course_recovery and Vector2(at.x-safe_waypoint.x,at.z-safe_waypoint.z).length()<900: course_recovery = false
	var recovery: bool = course_recovery
	var desired: Vector3 = safe_waypoint if recovery else Vector3(0,maxf(at.y,250),-4000 if patrol_south else -12000)
	var enemy: Dictionary = target()
	if not recovery and not enemy.is_empty(): desired = enemy.position
	var delta: Vector3 = desired-at
	var error: float = wrapf(atan2(delta.x,-delta.z)-app.flight.heading,-PI,PI)
	var bank: float = clampf(error*1.7,-1.0,1.0)
	var terrain: float = app.world.ground_height(at.x,at.z)
	for offset in [-0.9,-0.4,0.0,0.4,0.9]:
		for distance in [900.0,2000.0,3700.0]:
			var p: Vector3 = at+Vector3(sin(app.flight.heading+offset),0,-cos(app.flight.heading+offset))*distance
			terrain = maxf(terrain,app.world.ground_height(p.x,p.z))
	var altitude: float = maxf(desired.y,terrain+350)
	var pitch: float = clampf(atan2(altitude-at.y,maxf(Vector2(delta.x,delta.z).length(),1000)),-0.12,0.36)
	app.flight.throttle = clampf(0.20+(195-app.flight.speed)*0.04,0,1)
	app.flight.afterburner = incoming_distance<1600 and at.y-app.world.ground_height(at.x,at.z)>350
	if app.flight.afterburner: app.flight.throttle = 1.0
	if incoming_distance<650:
		for shot: Dictionary in shots:
			if shot.kind=="hostile_missile" and not shot.has("decoy") and shot.position.distance_to(at)<650:
				deploy_flares(); break
	return Vector3(clampf((bank-app.flight.roll)*1.6-app.flight.roll_velocity*0.3,-1,1),clampf((pitch-app.flight.pitch)*2.2-app.flight.pitch_velocity*0.25,-1,1),clampf(error*0.8,-1,1))

func complete(success: bool, reason: String) -> void:
	if not active: return
	active = false
	app.finish_sortie(success,reason)
func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.55
	if glow > 0:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = glow
	return result

func mesh(parent: Node3D, shape: Mesh, at: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = shape
	result.material_override = material(color,glow)
	result.position = at
	parent.add_child(result)
	return result

func box(parent: Node3D, dimensions: Vector3, at: Vector3, color: Color) -> void:
	var shape := BoxMesh.new()
	shape.size = dimensions
	mesh(parent,shape,at,color)

func segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var delta := b-a
	var t: float = clampf((point-a).dot(delta)/maxf(delta.length_squared(),0.001),0,1)
	return point.distance_to(a+delta*t)

func spawn_shot(at: Vector3, velocity: Vector3, kind: String, target_value: int, damage: float, variant: String = "gatling") -> void:
	var node: Node3D = WeaponArt.projectile("missile" if kind=="hostile_missile" else kind,variant)
	add_child(node)
	node.position = at
	node.look_at(at+velocity,Vector3.UP)
	var shot: Dictionary = {"node":node,"position":at,"velocity":velocity,"kind":kind,"target":target_value,"damage":damage,"life":12.0 if kind in ["missile","hostile_missile"] else 2.5,"trail_points":[at],"trail_node":null}
	if kind in ["missile","hostile_missile"]:
		var trail := MeshInstance3D.new()
		trail.mesh = ImmediateMesh.new()
		var smoke := StandardMaterial3D.new()
		smoke.albedo_color = Color.WHITE
		smoke.albedo_texture = load("res://assets/vfx/smoke.png")
		smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke.vertex_color_use_as_albedo = true
		smoke.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail.material_override = smoke
		trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(trail)
		shot.trail_node = trail
	shots.append(shot)

func update_trail(shot: Dictionary) -> void:
	var points: Array = shot.trail_points
	if Vector3(points.back()).distance_to(shot.position)>7:
		points.append(shot.position)
		if points.size()>25: points.pop_front()
	var ribbon: ImmediateMesh = shot.trail_node.mesh
	ribbon.clear_surfaces()
	if points.size()<2: return
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()-1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i+1]
		var width: float = lerpf(1.5,0.22,float(i)/maxf(points.size()-1,1))
		var side: Vector3 = (b-a).normalized().cross((app.camera.global_position-a).normalized()).normalized()
		if side.length()<0.1: side = Vector3.RIGHT
		side *= width
		var alpha: float = float(i)/maxf(points.size()-1,1)*0.34
		for vertex: Array in [[a-side,Vector2(0,0)],[a+side,Vector2(1,0)],[b-side,Vector2(0,1)],[b-side,Vector2(0,1)],[a+side,Vector2(1,0)],[b+side,Vector2(1,1)]]:
			ribbon.surface_set_color(Color(0.76,0.79,0.82,alpha))
			ribbon.surface_set_uv(vertex[1])
			ribbon.surface_add_vertex(vertex[0])
	ribbon.surface_end()

func free_shot(shot: Dictionary) -> void:
	shot.node.queue_free()
	if is_instance_valid(shot.get("trail_node")): shot.trail_node.queue_free()

func burst(at: Vector3, color: Color, radius: float) -> void:
	if bursts.size()>100: return
	if flash_texture==null: flash_texture = load("res://assets/vfx/flash.png")
	var node := Sprite3D.new()
	node.texture = flash_texture
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.shaded = false
	node.pixel_size = radius/maxf(flash_texture.get_width(),1)
	node.modulate = color
	node.position = at
	add_child(node)
	bursts.append({"node":node,"life":0.40,"color":color})

func update_bursts(dt: float) -> void:
	for index in range(bursts.size()-1,-1,-1):
		var effect: Dictionary = bursts[index]
		effect.life -= dt
		if effect.life<=0:
			effect.node.queue_free()
			bursts.remove_at(index)
		else:
			var progress: float = 1-effect.life/0.40
			effect.node.scale = Vector3.ONE*(0.65+progress*1.6)
			var color: Color = effect.color
			color.a = (1-progress)*(1-progress)
			effect.node.modulate = color
