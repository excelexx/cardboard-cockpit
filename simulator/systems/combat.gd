extends Node3D
class_name CombatDirector
const WeaponArt = preload("res://systems/weapon_visuals.gd")
var flash_texture: Texture2D
## Fictional arcade interception. All tuning is game balance, not weapon performance.
var wave_counts: Array[int] = [3, 4, 5]
var automatic_waves := true
var app: Node
var active := false
var wave := 0
var kills := 0
var score := 0
var hull := 100.0
var base_health := 100.0
var ammo := 480
var missiles := 8
var flares := 6
var gun_heat := 0.0
var gun_cooldown := 0.0
var missile_cooldown := 0.0
var flare_cooldown := 0.0
var lock_progress := 0.0
var target_id := -1
var next_id := 0
var wave_delay := 2.0
var elapsed := 0.0
var assist := true
var pitch_latched := false
var roll_latched := false
var eject_hold := 0.0
var enemies: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var bursts: Array[Dictionary] = []
var parachute: Node3D
var eject_position := Vector3.ZERO
var eject_clock := 0.0
var message := ""
var message_time := 0.0
var rng := RandomNumberGenerator.new()
var hit_flash := 0.0

func reset(enabled: bool) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	enemies.clear()
	shots.clear()
	bursts.clear()
	parachute = null
	active = enabled
	wave = 0
	kills = 0
	score = 0
	hull = 100
	base_health = 100
	ammo = 480
	missiles = 8
	flares = 6
	gun_heat = 0
	gun_cooldown = 0
	missile_cooldown = 0
	flare_cooldown = 0
	lock_progress = 0
	target_id = -1
	next_id = 0
	wave_delay = 2
	elapsed = 0
	pitch_latched = false
	roll_latched = false
	eject_hold = 0
	eject_clock = 0
	message = "SKY SHIELD  /  Protect the valley from three drone waves"
	message_time = 5
	rng.seed = 22535

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

func drone() -> Node3D:
	var result := Node3D.new()
	var body := CapsuleMesh.new()
	body.radius = 1.1
	body.height = 8.0
	mesh(result,body,Vector3.ZERO,Color(0.32,0.37,0.41)).rotation.x = PI/2
	box(result,Vector3(15,0.25,2.2),Vector3(0,0,0.4),Color(0.22,0.28,0.33))
	box(result,Vector3(5,0.2,1.2),Vector3(0,0.2,3),Color(0.25,0.3,0.35))
	box(result,Vector3(0.25,2.5,1.3),Vector3(0,1.1,3),Color(0.27,0.33,0.38))
	var light := SphereMesh.new()
	light.radius = 0.45
	light.height = 0.9
	mesh(result,light,Vector3(0,0.3,4),Color(1,0.22,0.07),3)
	return result

func forward() -> Vector3:
	return Vector3(sin(app.flight.heading)*cos(app.flight.pitch),sin(app.flight.pitch),-cos(app.flight.heading)*cos(app.flight.pitch)).normalized()

func target() -> Dictionary:
	for enemy: Dictionary in enemies:
		if enemy.id == target_id:
			return enemy
	return {}

func spawn_wave() -> void:
	wave += 1
	var ahead: Vector3 = forward()
	var right := Vector3(cos(app.flight.heading),0,sin(app.flight.heading))
	for i: int in wave_counts[wave-1]:
		var node := drone()
		add_child(node)
		var spread: float = (float(i)-float(wave_counts[wave-1]-1)*0.5)*240.0
		var pos: Vector3 = app.flight.position+ahead*(1300.0+i*170.0)+right*spread
		pos.y = maxf(app.flight.position.y+60*sin(i*2.1),350)
		node.position = pos
		enemies.append({"id":next_id,"node":node,"position":pos,"health":100.0,"cooldown":7.0+i*1.5,"age":0.0,"phase":float(i)})
		next_id += 1
	ammo = mini(ammo+120,480)
	missiles = mini(missiles+2,8)
	flares = mini(flares+1,6)
	announce("WAVE %d / 3  ·  %d incoming drones" % [wave,wave_counts[wave-1]])
	app.audio.ping()

func announce(value: String) -> void:
	message = value
	message_time = 3.0

func tick(dt: float) -> void:
	if not active:
		return
	elapsed += dt
	message_time = maxf(0,message_time-dt)
	hit_flash = maxf(0,hit_flash-dt*2)
	gun_cooldown = maxf(0,gun_cooldown-dt)
	missile_cooldown = maxf(0,missile_cooldown-dt)
	flare_cooldown = maxf(0,flare_cooldown-dt)
	gun_heat = maxf(0,gun_heat-dt*0.28)
	if enemies.is_empty() and automatic_waves:
		wave_delay -= dt
		if wave_delay <= 0:
			if wave >= wave_counts.size():
				complete(true,"All three drone waves intercepted. The valley is secure.")
				return
			spawn_wave()
			wave_delay = 4.0
	var aim: Vector3 = forward()
	var best := -1
	var current_alignment := -1.0
	var best_dot: float = cos(deg_to_rad(12.0))
	for enemy: Dictionary in enemies:
		if enemy.health<=0: continue
		enemy.age += dt
		var toward: Vector3 = (app.flight.position-enemy.position).normalized()
		var distance: float = app.flight.position.distance_to(enemy.position)
		var sideways: Vector3 = toward.cross(Vector3.UP).normalized()
		var velocity: Vector3 = toward*(80.0 if distance>700 else -25.0)+sideways*sin(enemy.age*0.35+enemy.phase)*28.0
		enemy.velocity = velocity+enemy.get("inherited_velocity",Vector3.ZERO)
		enemy.position += velocity*dt
		enemy.position.y = maxf(enemy.position.y,250)
		enemy.node.position = enemy.position
		if velocity.length()>0.1:
			enemy.node.look_at(enemy.position+velocity,Vector3.UP)
		enemy.cooldown -= dt
		if enemy.cooldown<=0 and distance<2800:
			enemy.cooldown = 9.5-float(wave)
			spawn_shot(enemy.position,toward*210.0,"hostile",-1,14.0)
		var alignment: float = aim.dot((enemy.position-app.flight.position).normalized())
		if enemy.id==target_id and distance<3500: current_alignment = alignment
		if alignment>best_dot and distance<3500:
			best_dot = alignment
			best = enemy.id
		if enemy.age>55.0:
			enemy.age = 35.0
			base_health = maxf(0,base_health-8)
	# Retain a near-centre track rather than hopping between geese every frame.
	if current_alignment>cos(deg_to_rad(10)) and acos(clampf(current_alignment,-1,1))-acos(clampf(best_dot,-1,1))<deg_to_rad(3):
		best = target_id
		best_dot = current_alignment
	if best != target_id:
		target_id = best
		lock_progress = 0.0
	if target_id>=0 and best_dot>=cos(deg_to_rad(6.0)):
		var was_locked: bool = lock_progress>=1
		lock_progress = minf(1,lock_progress+dt/0.85)
		if not was_locked and lock_progress>=1:
			app.audio.ping()
			app.audio.radio.say("target_locked")
	else:
		lock_progress = move_toward(lock_progress,0,dt*3)
	update_shots(dt)
	update_bursts(dt)
	if hull<=0 or base_health<=0:
		complete(false,"Aircraft lost." if hull<=0 else "Valley defenses overwhelmed. Intercept drones sooner.")

func fire_gun() -> bool:
	if not active or ammo<=0 or gun_cooldown>0 or gun_heat>0.92:
		return false
	gun_cooldown = 0.09
	gun_heat = minf(1,gun_heat+0.038)
	ammo -= 1
	var direction: Vector3 = assisted_direction()
	spawn_shot(app.flight.position+direction*14.0,direction*950.0,"cannon",-1,26)
	app.audio.play_effect("cannon",-19,1.0+rng.randf_range(-0.12,0.12))
	return true

func fire_missile() -> bool:
	if not active or missiles<=0 or missile_cooldown>0:
		return false
	if target_id<0 or lock_progress<1:
		announce("Keep a drone inside the reticle until TARGET LOCKED")
		return false
	missiles -= 1
	missile_cooldown = 1.3
	spawn_shot(app.flight.position+forward()*15,forward()*330,"missile",target_id,110)
	app.audio.play_effect("missile",-12)
	announce("MISSILE AWAY")
	return true

func deploy_flares() -> bool:
	if not active or flares<=0 or flare_cooldown>0:
		return false
	flares -= 1
	flare_cooldown = 5
	for shot: Dictionary in shots:
		if shot.kind=="hostile" and shot.position.distance_to(app.flight.position)<1600:
			shot.life = 0
	for i in range(8):
		burst(app.flight.position+Vector3(rng.randf_range(-12,12),rng.randf_range(-5,5),8),Color(1,0.75,0.35),8)
	app.audio.play_effect("flare",-13)
	announce("COUNTERMEASURES DEPLOYED")
	return true

func assisted_direction() -> Vector3:
	var direction: Vector3 = forward()
	var enemy: Dictionary = target()
	if enemy.is_empty(): return direction
	var wanted: Vector3 = (enemy.position-app.flight.position).normalized()
	var angle: float = direction.angle_to(wanted)
	if angle>deg_to_rad(12) or angle<0.0001: return direction
	# A small nudge, never target snapping. Ten degrees of poor aim still misses.
	return direction.slerp(wanted,minf(0.12,deg_to_rad(2.0)/angle)).normalized()

func spawn_shot(at: Vector3, velocity: Vector3, kind: String, target_value: int, damage: float, variant: String = "gatling") -> void:
	var node: Node3D = WeaponArt.projectile(kind,variant)
	add_child(node)
	node.position = at
	node.look_at(at+velocity,Vector3.UP)
	var shot: Dictionary = {"node":node,"position":at,"velocity":velocity,"kind":kind,"target":target_value,"damage":damage,"life":12.0 if kind=="missile" or kind=="hostile" else 2.5,"trail_points":[at],"trail_node":null}
	if kind=="missile":
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

func segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var delta := b-a
	var t: float = clampf((point-a).dot(delta)/maxf(delta.length_squared(),0.001),0,1)
	return point.distance_to(a+delta*t)

func update_shots(dt: float) -> void:
	for shot: Dictionary in shots:
		shot.life -= dt
		if shot.life<=0: continue
		var previous: Vector3 = shot.position
		if shot.kind=="missile":
			for enemy: Dictionary in enemies:
				if enemy.id==shot.target:
					var wanted: Vector3 = (enemy.position-shot.position).normalized()
					var current: Vector3 = shot.velocity.normalized()
					var angle: float = current.angle_to(wanted)
					if angle>deg_to_rad(65):
						shot.target = -1
					else:
						shot.velocity = current.slerp(wanted,minf(1,deg_to_rad(45)*dt/maxf(angle,0.0001)))*460
		shot.position += shot.velocity*dt
		shot.node.position = shot.position
		if shot.velocity.length()>0.1:
			shot.node.look_at(shot.position+shot.velocity,Vector3.UP)
		if shot.kind=="missile": update_trail(shot)
		if shot.kind=="hostile":
			if segment_distance(app.flight.position,previous,shot.position)<17:
				hull = maxf(0,hull-shot.damage)
				shot.life = 0
				hit_flash = 0.4
				app.audio.play_effect("impact",-10)
		else:
			for enemy: Dictionary in enemies:
				if enemy.health>0 and segment_distance(enemy.position,previous,shot.position)<(22.0 if shot.kind=="missile" else 15.0):
					enemy.health -= shot.damage
					shot.life = 0
					burst(enemy.position,Color(1,0.64,0.18),8)
					break
	for index in range(shots.size()-1,-1,-1):
		if shots[index].life<=0:
			free_shot(shots[index])
			shots.remove_at(index)
	for index in range(enemies.size()-1,-1,-1):
		var enemy: Dictionary = enemies[index]
		if enemy.health<=0:
			kills += 1
			app.audio.radio.say("target_down" if kills%2 else "target_down_alt")
			score += 100+wave*25
			burst(enemy.position,Color(1,0.39,0.09),18)
			app.audio.play_effect("explosion",-11)
			enemy.node.queue_free()
			enemies.remove_at(index)

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

func cardboard_controls() -> void:
	if not assist or not app.vision.enabled or not app.vision.tracking:
		pitch_latched = false
		roll_latched = false
		return
	if lock_progress>=1:
		fire_gun()
	var yoke: Vector2 = app.vision.yoke
	if yoke.y>0.72 and not pitch_latched:
		pitch_latched = true
		fire_missile()
	if absf(yoke.y)<0.3:
		pitch_latched = false
	if absf(yoke.x)>0.85 and not roll_latched:
		roll_latched = true
		app.flight.start_barrel_roll(signf(yoke.x))
	if absf(yoke.x)<0.3:
		roll_latched = false
	if hull<35 and flare_cooldown<=0:
		deploy_flares()

func eject() -> bool:
	if str(app.profile().id)!="f35" or not app.flight.airborne or app.mode!="flight":
		return false
	active = false
	app.mode = "ejected"
	app.copilot = false
	app.vision.enabled = false
	eject_clock = 0
	eject_position = app.flight.position+Vector3(0,15,0)
	parachute = Node3D.new()
	add_child(parachute)
	var canopy := SphereMesh.new()
	canopy.radius = 5
	canopy.height = 3
	mesh(parachute,canopy,Vector3(0,6,0),Color(0.85,0.88,0.78))
	var pilot := CapsuleMesh.new()
	pilot.radius = 0.3
	pilot.height = 1.8
	mesh(parachute,pilot,Vector3.ZERO,Color(0.28,0.36,0.24))
	for side in [-1,1]:
		box(parachute,Vector3(0.035,5.5,0.035),Vector3(side*1.2,3,0),Color(0.85,0.87,0.8))
	app.audio.play_effect("eject",-8)
	return true

func tick_ejection(dt: float) -> void:
	eject_clock += dt
	eject_position += Vector3(0,7.0 if eject_clock<0.7 else -4.0,-3)*dt
	parachute.position = eject_position
	app.aircraft.position += Vector3(sin(app.flight.heading)*app.flight.speed,-20,-cos(app.flight.heading)*app.flight.speed)*dt
	app.aircraft.rotation.z += dt*0.2
	if eject_clock>6:
		complete(false,"Pilot recovered under parachute. Aircraft abandoned.")

func complete(success: bool, reason: String) -> void:
	active = false
	app.mission_success = success
	app.result_reason = reason
	app.mode = "results"
	app.audio.ping()
	if app.test_mode and not app.test_finished:
		app.test_finished = true
		print("COMBAT MISSION: ","PASS" if success else "FAIL"," waves=",wave," kills=",kills," hull=",hull," defense=",base_health," seconds=",elapsed)
		get_tree().quit(0 if success else 1)

func pilot_controls() -> Vector3:
	if enemies.is_empty():
		return Vector3(-app.flight.roll*3,-app.flight.pitch*4,0)
	var nearest: Dictionary = target()
	if nearest.is_empty():
		nearest = enemies[0]
		for enemy: Dictionary in enemies:
			if enemy.position.distance_to(app.flight.position)<nearest.position.distance_to(app.flight.position):
				nearest = enemy
	var delta: Vector3 = nearest.position-app.flight.position
	var heading: float = atan2(delta.x,-delta.z)
	var error: float = wrapf(heading-app.flight.heading,-PI,PI)
	var pitch: float = clampf(atan2(delta.y,maxf(Vector2(delta.x,delta.z).length(),1)),-0.25,0.25)
	app.flight.throttle = clampf(0.15+(140.0-app.flight.speed)*0.05,0,1)
	return Vector3(clampf((clampf(error*2,-0.9,0.9)-app.flight.roll)*5,-1,1),clampf((pitch-app.flight.pitch)*7,-1,1),clampf(error*2,-1,1))
