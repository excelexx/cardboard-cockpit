extends Node3D
class_name CombatDirector
const Tune = preload("res://data/balance.gd")
## One fighter, one permanent cannon-and-missile loadout. No progression system.
const Fighter = preload("res://systems/fighter_model.gd")
const WeaponArt = preload("res://systems/weapon_visuals.gd")
var app: Node
var active := false
var engagement_enabled := true
var managed_mission := false
var elapsed := 0.0
var duration := Tune.PATROL_DURATION
var hull := Tune.PLAYER_HEALTH
var ammo := -1
var missiles := -1
var flares := -1
var flares_fired := 0
var kills := 0
var score := 0
var combo := 0
var best_combo := 0
var combo_time := 0.0
var reward_flash := 0.0
var last_reward := 100
var rounds_fired := 0
var rounds_hit := 0
var missiles_fired := 0
var missiles_evaded := 0
var hostile_launches := 0
var detonation_texture: Texture2D
var gun_cooldown := 0.0
var gun_firing_time := 0.0
var missile_cooldown := 0.0
var flare_cooldown := 0.0
var lock_progress := 0.0
var target_id := -1
var target_hold := 0.0
const ACQUIRE_ANGLE := Tune.ACQUIRE_DEGREES
const RELEASE_ANGLE := Tune.RETAIN_DEGREES
const MAX_CONTACTS := Tune.MAX_CONTACTS
var aim_direction := Vector3.FORWARD
var reticle_direction := Vector3.FORWARD
var arrival_index := 0
var detached_trails: Array[Dictionary] = []
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
	enemies.clear(); shots.clear(); bursts.clear(); launch_queue.clear(); detached_trails.clear()
	active = enabled; engagement_enabled = enabled; managed_mission = false; elapsed = 0; hull = Tune.PLAYER_HEALTH
	ammo = -1; missiles = -1; flares = -1; flares_fired = 0
	kills = 0; score = 0; combo = 0; best_combo = 0; combo_time = 0; reward_flash = 0; rounds_fired = 0; rounds_hit = 0; missiles_fired = 0; missiles_evaded = 0; hostile_launches = 0
	gun_firing_time = 0; gun_cooldown = 0; missile_cooldown = 0; flare_cooldown = 0
	lock_progress = 0; target_id = -1; target_hold = 0; aim_direction = forward(); reticle_direction = forward(); next_id = 0; spawn_clock = Tune.FIRST_ARRIVAL; arrival_index = 0
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
	root.scale = Vector3.ONE*Tune.CONTACT_MODEL_SCALE
	return root

func spawn_contact() -> void:
	var node := goose_model()
	add_child(node)
	var right := Vector3(cos(app.flight.heading),0,sin(app.flight.heading))
	var distance: float = Tune.SPAWN_DISTANCE+(next_id%Tune.GROUP_SIZE)*Tune.SPAWN_DISTANCE_STEP+rng.randf_range(0,Tune.SPAWN_DISTANCE_JITTER)
	var lane: float = Tune.SPAWN_LANES[next_id%Tune.SPAWN_LANES.size()]
	var at: Vector3 = app.flight.position+forward()*distance+right*distance*lane
	if managed_mission and absf(app.flight.position.x)<350: at.x = clampf(at.x,-460,460)
	at.y = maxf(at.y+rng.randf_range(-20,30),app.world.ground_height(at.x,at.z)+Tune.CONTACT_CLEARANCE)
	node.position = at
	for geometry: Node in node.find_children("*","GeometryInstance3D",true,false): geometry.transparency = 1
	var contact: Dictionary = {"id":next_id,"node":node,"position":at,"health":Tune.CONTACT_HEALTH,"max_health":Tune.CONTACT_HEALTH,"velocity":Vector3.ZERO,"course":forward()*clampf(app.flight.speed*Tune.CONTACT_SPEED_RATIO,Tune.CONTACT_MIN_SPEED,Tune.CONTACT_MAX_SPEED),"right":right,"cooldown":999.0,"age":0.0,"phase":rng.randf_range(0,TAU),"fade":0.0,"retiring":false}
	enemies.append(contact); next_id += 1

func tick(dt: float) -> void:
	if not active: return
	elapsed += dt
	gun_firing_time = maxf(0,gun_firing_time-dt)
	target_hold = maxf(0,target_hold-dt)
	update_launches(dt)
	gun_cooldown = maxf(0,gun_cooldown-dt);
	if gun_cooldown<.0001: gun_cooldown = 0
	missile_cooldown = maxf(0,missile_cooldown-dt); flare_cooldown = maxf(0,flare_cooldown-dt)
	hit_flash = maxf(0,hit_flash-dt*2.4); hit_confirm = maxf(0,hit_confirm-dt*5)
	combo_time = maxf(0,combo_time-dt); reward_flash = maxf(0,reward_flash-dt*1.4)
	if combo_time==0: combo = 0
	message_time = maxf(0,message_time-dt)
	if engagement_enabled: spawn_clock -= dt
	attack_spacing = maxf(0,attack_spacing-dt)
	if engagement_enabled and spawn_clock<=0 and enemies.size()<MAX_CONTACTS:
		spawn_contact(); arrival_index += 1
		spawn_clock = Tune.GROUP_BREATHER if arrival_index%Tune.GROUP_SIZE==0 else Tune.ARRIVAL_INTERVAL
	var best := -1
	var best_dot: float = cos(deg_to_rad(ACQUIRE_ANGLE))
	var old_alignment := -1.0
	for enemy: Dictionary in enemies:
		if enemy.health<=0: continue
		enemy.age += dt
		var to_plane: Vector3 = app.flight.position-enemy.position
		var distance: float = to_plane.length()
		if enemy.age>Tune.CONTACT_LIFETIME or distance>Tune.CONTACT_RETIRE_DISTANCE or forward().dot(-to_plane)<-Tune.CONTACT_RETIRE_BEHIND: enemy.retiring = true
		var present: bool = engagement_enabled and not enemy.retiring
		enemy.fade = minf(1,enemy.fade+dt*Tune.CONTACT_FADE_IN) if present else maxf(0,enemy.fade-dt*Tune.CONTACT_FADE_OUT)
		var lateral: Vector3 = enemy.get("right",Vector3.RIGHT)
		var velocity: Vector3 = enemy.get("course",forward()*150)+lateral*sin(enemy.age*.55+enemy.phase)*Tune.CONTACT_WEAVE_SPEED+Vector3.UP*cos(enemy.age*.4+enemy.phase)*Tune.CONTACT_VERTICAL_SPEED
		if not present: velocity += lateral*(60 if enemy.id%2 else -60)+Vector3.UP*25
		enemy.position += velocity*dt
		enemy.position.y = maxf(enemy.position.y,app.world.ground_height(enemy.position.x,enemy.position.z)+Tune.CONTACT_FLIGHT_CLEARANCE)
		enemy.velocity = velocity
		enemy.node.position = enemy.position
		if velocity.length()>1: enemy.node.look_at(enemy.position+velocity,Vector3.UP)
		var flap: float = sin(elapsed*4.2+enemy.phase)*0.32
		enemy.node.get_node("WingL").rotation.z = flap
		enemy.node.get_node("WingR").rotation.z = -flap
		if enemy.fade<1 or enemy.age<1.5:
			for geometry: Node in enemy.node.find_children("*","GeometryInstance3D",true,false): geometry.transparency = 1-enemy.fade
		var alignment: float = forward().dot((enemy.position-app.flight.position).normalized())
		if enemy.id==target_id: old_alignment = alignment
		if engagement_enabled and not enemy.retiring and enemy.fade>.45 and distance<Tune.TARGET_RANGE and alignment>best_dot:
			best = enemy.id; best_dot = alignment
	if old_alignment>cos(deg_to_rad(RELEASE_ANGLE)) and not target().get("retiring",true) and (target_hold>0 or acos(clampf(old_alignment,-1,1))-acos(clampf(best_dot,-1,1))<deg_to_rad(Tune.TARGET_SWITCH_MARGIN)):
		best = target_id; best_dot = old_alignment
	if best!=target_id: target_id = best; lock_progress = 0; target_hold = Tune.TARGET_STICK_TIME
	var locked_before: bool = lock_progress>=1
	lock_progress = minf(1,lock_progress+dt/Tune.LOCK_TIME) if target_id>=0 else 0.0
	if not locked_before and lock_progress>=1: app.audio.radio.say("target_locked")
	update_aim(dt)
	update_shots(dt); update_bursts(dt); update_detached_trails(dt)
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
	elif not managed_mission and elapsed>=duration: complete(true,"Patrol complete. Return vector received.")

func safe_direction_lerp(a: Vector3,b: Vector3,weight: float) -> Vector3:
	a = a.normalized(); b = b.normalized()
	var angle: float = a.angle_to(b)
	if angle<.002: return a.lerp(b,weight).normalized()
	var axis: Vector3 = a.cross(b)
	if axis.length_squared()<.0000001: axis = a.cross(Vector3.UP if absf(a.y)<.9 else Vector3.RIGHT)
	return a.rotated(axis.normalized(),angle*weight).normalized()

func assisted_direction() -> Vector3:
	return aim_direction if assist else forward()

func update_aim(dt: float) -> void:
	var desired: Vector3 = forward()
	var enemy: Dictionary = target()
	if assist and not enemy.is_empty():
		var wanted: Vector3 = (lead_point(enemy)-app.flight.position).normalized()
		if desired.angle_to(wanted)<deg_to_rad(RELEASE_ANGLE): desired = wanted
	if aim_direction.length_squared()<.5: aim_direction = forward()
	var angle: float = aim_direction.angle_to(desired)
	var weight: float = minf(1-exp(-dt*Tune.AIM_RESPONSE),deg_to_rad(Tune.AIM_SLEW_DEGREES)*dt/maxf(angle,.0001))
	aim_direction = safe_direction_lerp(aim_direction,desired,weight)
	var visual: Vector3 = forward()
	if assist and not enemy.is_empty() and forward().angle_to((enemy.position-app.flight.position).normalized())<deg_to_rad(RELEASE_ANGLE):
		visual = (enemy.position-app.flight.position).normalized()
	reticle_direction = safe_direction_lerp(reticle_direction,visual,1-exp(-dt*Tune.RETICLE_RESPONSE))

func reticle_point() -> Vector3:
	var enemy: Dictionary = target()
	var distance: float = app.flight.position.distance_to(enemy.position) if not enemy.is_empty() else 1200.0
	return app.flight.position+reticle_direction*distance


func lead_point(enemy: Dictionary) -> Vector3:
	var delta: Vector3 = enemy.position-app.flight.position
	var relative: Vector3 = enemy.velocity-app.flight.velocity
	var a: float = relative.length_squared()-Tune.GUN_MUZZLE_SPEED*Tune.GUN_MUZZLE_SPEED
	var b: float = 2*delta.dot(relative)
	var discriminant: float = maxf(0,b*b-4*a*delta.length_squared())
	var time: float = (-b-sqrt(discriminant))/(2*a) if absf(a)>.001 else delta.length()/Tune.GUN_MUZZLE_SPEED
	time = clampf(time,.0,3.0)
	time *= 1+.5*Tune.GUN_DRAG*Tune.GUN_MUZZLE_SPEED*time
	return enemy.position+relative*time+Vector3.UP*4.905*time*time

func fire_gun() -> bool:
	if not active or not app.flight.airborne or gun_cooldown>0: return false
	if gun_firing_time<=0: app.audio.play_effect("gatling_attack",-15,1.0)
	gun_cooldown = Tune.GUN_INTERVAL
	gun_firing_time = Tune.GUN_RELEASE_TAIL
	var round_count := Tune.GUN_ROUNDS_PER_PACKET
	rounds_fired += round_count
	var direction: Vector3 = assisted_direction()
	var basis: Basis = Basis.from_euler(Vector3(app.flight.pitch,-app.flight.heading,-app.flight.roll))
	var muzzle: Vector3 = app.fighter_fx.gun_muzzle_position(app.flight.position+basis*Fighter.MUZZLE)
	spawn_shot(muzzle,direction*Tune.GUN_MUZZLE_SPEED+app.flight.velocity,"cannon",-1,Tune.GUN_DAMAGE_PER_ROUND*round_count)
	shots.back().round_count = round_count
	app.camera_rig.impulse(0.022)
	return true

func fire_missile() -> bool:
	if not active or not app.flight.airborne or missile_cooldown>0: return false
	var tracked: Dictionary = target()
	var chosen: int = target_id if not tracked.is_empty() and lock_progress>=1 and forward().angle_to((tracked.position-app.flight.position).normalized())<deg_to_rad(RELEASE_ANGLE) else -1
	missiles_fired += 1; missile_cooldown = Tune.MISSILE_INTERVAL
	var side: float = -1 if missiles_fired%2 else 1
	launch_queue.append({"target":chosen,"side":side,"internal":missiles_fired%2==1,"store":int((missiles_fired-1)/2)%4,"delay":Tune.MISSILE_BAY_DELAY if missiles_fired%2==1 else Tune.MISSILE_RAIL_DELAY})
	if missiles_fired%2==1:
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
		spawn_shot(at,app.flight.velocity+Vector3(0,-Tune.MISSILE_DROP_SPEED,0),"missile",request.target,Tune.MISSILE_DAMAGE)
		last_missile = shots.back().node
		app.audio.play_effect("gear_motor",-26,1.3)
		app.camera_rig.impulse(0.28)
		app.fighter_fx.missile_launch(request.side,request.store if not request.internal else -1)
		launch_queue.remove_at(i)

func deploy_flares() -> bool:
	if not active or flare_cooldown>0: return false
	flares_fired += 1; flare_cooldown = Tune.FLARE_INTERVAL
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
		shot.age += dt
		if shot.life<=0: continue
		var previous: Vector3 = shot.position
		if shot.kind=="cannon":
			var air_velocity: Vector3 = shot.velocity-app.flight.wind
			shot.velocity += (Vector3.DOWN*9.81-air_velocity*air_velocity.length()*Tune.GUN_DRAG)*dt
		var wanted := Vector3.ZERO
		var guided := false
		var target_distance := INF
		if shot.kind=="missile":
			var ignited: bool = shot.age>=Tune.MISSILE_IGNITION_DELAY and shot.age<Tune.MISSILE_MOTOR_TIME
			if ignited and not shot.get("ignited",false):
				shot.ignited = true; app.audio.play_effect("missile",-12,.90)
			for effect_name in ["Ignition","MotorFlame"]:
				var effect: Node3D = shot.node.get_node_or_null(effect_name)
				if effect!=null:
					effect.visible = ignited
					effect.scale = Vector3(1,1,1+sin(shot.age*93)*.12)
			for enemy: Dictionary in enemies:
				if enemy.id==shot.target and enemy.health>0:
					wanted = (enemy.position+enemy.velocity*Tune.MISSILE_LEAD_TIME-shot.position).normalized(); guided = true
					target_distance = enemy.position.distance_to(shot.position)
		elif shot.kind=="hostile_missile":
			wanted = (Vector3(shot.get("decoy",app.flight.position+app.flight.velocity*0.35))-shot.position).normalized(); guided = true
		if guided:
			var current: Vector3 = shot.velocity.normalized()
			var angle: float = current.angle_to(wanted)
			var rate: float = deg_to_rad(28 if shot.kind=="hostile_missile" else Tune.MISSILE_TURN_DEGREES)
			if shot.kind=="missile" and shot.age<Tune.MISSILE_IGNITION_DELAY: rate = 0
			shot.velocity = safe_direction_lerp(current,wanted,minf(1,rate*dt/maxf(angle,0.0001)))*shot.velocity.length()
		if shot.kind=="missile":
			var motor: bool = shot.age>=Tune.MISSILE_IGNITION_DELAY and shot.age<Tune.MISSILE_MOTOR_TIME
			var top_speed: float = Tune.MISSILE_SPEED*(Tune.MISSILE_TERMINAL_SPEED_RATIO if target_distance<Tune.MISSILE_TERMINAL_DISTANCE else 1.0)
			var acceleration: float = maxf(0,Tune.MISSILE_SPEED-float(shot.launch_speed))/Tune.MISSILE_ACCELERATION_TIME
			var speed: float = move_toward(shot.velocity.length(),top_speed,dt*acceleration) if motor else move_toward(shot.velocity.length(),Tune.MISSILE_COAST_SPEED,dt*Tune.MISSILE_COAST_DRAG) if shot.age>=Tune.MISSILE_MOTOR_TIME else shot.velocity.length()
			shot.velocity = shot.velocity.normalized()*speed
		elif shot.kind=="hostile_missile": shot.velocity = shot.velocity.normalized()*280
		shot.position += shot.velocity*dt
		var end_ground: float = app.world.ground_height(shot.position.x,shot.position.z)
		var midpoint: Vector3 = previous.lerp(shot.position,.5)
		var mid_ground: float = app.world.ground_height(midpoint.x,midpoint.z)
		if shot.position.y<=end_ground or midpoint.y<=mid_ground:
			var lo := 0.0; var hi := 1.0 if shot.position.y<=end_ground else .5
			for probe in range(7):
				var t: float = (lo+hi)*.5
				var at: Vector3 = previous.lerp(shot.position,t)
				if at.y<=app.world.ground_height(at.x,at.z): hi = t
				else: lo = t
			shot.position = previous.lerp(shot.position,hi); shot.life = 0
			burst(shot.position,Color(1,.70,.32),1.6 if shot.kind=="cannon" else 12)
			continue
		if shot.kind=="cannon": shot.node.scale.z = clampf(shot.age*shot.velocity.length()/9,.01,1)
		shot.node.position = shot.position
		shot.node.look_at(shot.position+shot.velocity,Vector3.UP)
		if shot.kind=="cannon" or (shot.kind in ["missile","hostile_missile"] and shot.age>Tune.MISSILE_IGNITION_DELAY): update_trail(shot)
		if shot.kind=="hostile_missile":
			if segment_distance(app.flight.position,previous,shot.position)<8:
				hull = maxf(0,hull-shot.damage); shot.life = 0; shot.hit_player = true; hit_flash = 0.35
				app.camera_rig.impulse(0.65)
				app.audio.play_effect("impact",-11)
				burst(app.flight.position,Color(1,0.45,0.17),4)
		else:
			for enemy: Dictionary in enemies:
				if enemy.health>0 and segment_distance(enemy.position,previous,shot.position)<(Tune.MISSILE_HIT_RADIUS if shot.kind=="missile" else Tune.GUN_HIT_RADIUS):
					enemy.health -= shot.damage; shot.life = 0; hit_confirm = 1
					app.audio.play_effect("impact",-24,1.15)
					if shot.kind=="cannon": rounds_hit += int(shot.get("round_count",1))
					burst(enemy.position,Color(1,0.66,0.27),3 if shot.kind=="cannon" else 9)
					break
	for i in range(shots.size()-1,-1,-1):
		if shots[i].life<=0:
			if shots[i].has("decoy") and not shots[i].get("hit_player",false): missiles_evaded += 1
			free_shot(shots[i]); shots.remove_at(i)
	for i in range(enemies.size()-1,-1,-1):
		var enemy: Dictionary = enemies[i]
		if enemy.fade<=0 and (not engagement_enabled or enemy.get("retiring",false)):
			enemy.node.queue_free(); enemies.remove_at(i); continue
		if enemy.health<=0:
			kills += 1; combo += 1; best_combo = maxi(best_combo,combo); combo_time = Tune.STREAK_TIME
			last_reward = Tune.BASE_SCORE*mini(Tune.MAX_MULTIPLIER,1+int(combo/Tune.STREAK_STEP)); score += last_reward; reward_flash = 1
			app.audio.ping(1+minf(combo,10)*.035)
			app.camera_rig.impulse(.16)
			burst(enemy.position,Color(1,0.43,0.12),18)
			app.fighter_fx.debris(enemy.position)
			app.audio.play_effect("explosion",-13-minf(13,enemy.position.distance_to(app.flight.position)/180))
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
	if kind=="cannon": node.scale.z = .01
	node.look_at(at+velocity,Vector3.UP)
	var shot: Dictionary = {"node":node,"position":at,"velocity":velocity,"kind":kind,"target":target_value,"damage":damage,"life":Tune.MISSILE_LIFETIME if kind in ["missile","hostile_missile"] else Tune.GUN_LIFETIME,"age":0.0,"launch_speed":velocity.length(),"trail_points":[at],"trail_node":null}
	if kind in ["missile","hostile_missile","cannon"]:
		var trail := MeshInstance3D.new()
		trail.mesh = ImmediateMesh.new()
		var smoke := StandardMaterial3D.new()
		smoke.albedo_color = Color.WHITE
		smoke.albedo_texture = load("res://assets/sourced_flight/smoke.png")
		if kind=="cannon":
			smoke.emission_enabled = true; smoke.emission = Color(1,.55,.18); smoke.emission_energy_multiplier = 1.1
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
		if points.size()>(4 if shot.kind=="cannon" else 46): points.pop_front()
	var ribbon: ImmediateMesh = shot.trail_node.mesh
	ribbon.clear_surfaces()
	if points.size()<2: return
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()-1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i+1]
		var cannon: bool = shot.kind=="cannon"
		var width: float = lerpf(.42,.13,float(i)/maxf(points.size()-1,1)) if cannon else lerpf(1.65,.12,float(i)/maxf(points.size()-1,1))
		var side: Vector3 = (b-a).normalized().cross((app.camera.global_position-a).normalized()).normalized()
		if side.length()<0.1: side = Vector3.RIGHT
		side *= width
		var alpha: float = float(i+1)/maxf(points.size(),1)*(.82 if cannon else .44)
		for vertex: Array in [[a-side,Vector2(0,0)],[a+side,Vector2(1,0)],[b-side,Vector2(0,1)],[b-side,Vector2(0,1)],[a+side,Vector2(1,0)],[b+side,Vector2(1,1)]]:
			ribbon.surface_set_color(Color(1,.72,.35,alpha) if cannon else Color(0.76,0.79,0.82,alpha))
			ribbon.surface_set_uv(vertex[1])
			ribbon.surface_add_vertex(vertex[0])
	ribbon.surface_end()

func free_shot(shot: Dictionary) -> void:
	shot.node.queue_free()
	if is_instance_valid(shot.get("trail_node")):
		if shot.kind=="missile": detached_trails.append({"node":shot.trail_node,"life":Tune.MISSILE_SMOKE_TIME})
		else: shot.trail_node.queue_free()

func update_detached_trails(dt: float) -> void:
	for i in range(detached_trails.size()-1,-1,-1):
		var trail: Dictionary = detached_trails[i]; trail.life -= dt
		if trail.life<=0: trail.node.queue_free(); detached_trails.remove_at(i)
		else:
			trail.node.material_override.albedo_color.a = trail.life/Tune.MISSILE_SMOKE_TIME
			trail.node.position += app.flight.wind*dt*.4+Vector3.UP*dt*.6

func burst(at: Vector3, color: Color, radius: float) -> void:
	if bursts.size()>100: return
	if flash_texture==null: flash_texture = load("res://assets/vfx/flash.png")
	var explosion: bool = radius>=10
	if explosion and detonation_texture==null: detonation_texture = load("res://assets/vfx/flash.png")
	var node := Sprite3D.new()
	node.texture = detonation_texture if explosion else flash_texture
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED; node.shaded = false
	node.pixel_size = radius/maxf(node.texture.get_width(),1)
	node.modulate = Color(1,.62,.28) if explosion else color
	node.position = at
	add_child(node)
	var duration: float = 1.15 if explosion else .075 if radius<1.5 else .30
	bursts.append({"node":node,"life":duration,"duration":duration,"color":node.modulate,"explosion":explosion})

func update_bursts(dt: float) -> void:
	for index in range(bursts.size()-1,-1,-1):
		var effect: Dictionary = bursts[index]
		effect.life -= dt
		if effect.life<=0:
			effect.node.queue_free(); bursts.remove_at(index)
		else:
			var progress: float = 1-effect.life/effect.duration
			effect.node.scale = Vector3.ONE*(.45+pow(progress,.45)*2.2 if effect.explosion else .8+progress*.6)
			var color: Color = effect.color
			color.a = (1-smoothstep(.35,1.0,progress)) if effect.explosion else (1-progress)*(1-progress)
			if effect.explosion: color = color.lerp(Color(.38,.35,.32,color.a),smoothstep(.25,1,progress)*.55)
			effect.node.modulate = color
