extends Node3D
class_name CombatDirector
const Tune = preload("res://data/balance.gd")
const Intent = preload("res://systems/target_intent.gd")
var intent: TargetIntent = Intent.new()
var visuals: Node3D
var motif := "pursuit"
var runs_started:=0
var motif_history: Array[String] = []
var boss_id := -1
var boss_defeated := false
var boss_stage := 0
var primary_used := false
var near_miss_clock := 0.0
var event_log: Array[Dictionary] = []
func _ready() -> void:
	visuals=load("res://systems/combat_visuals.gd").new();visuals.combat=self;add_child(visuals)
func event(kind: String,at: Vector3=Vector3.ZERO,weight: float=1.0) -> void:
	event_log.append({"event":kind,"time":elapsed})
	if event_log.size()>120:event_log.pop_front()
	if is_instance_valid(visuals):visuals.event(kind,at,weight)
## One fighter, one permanent gun-only loadout. No progression system.
const Fighter = preload("res://systems/fighter_model.gd")
const WeaponArt = preload("res://systems/weapon_visuals.gd")
var app: Node
var active := false
var engagement_enabled := true
var managed_mission := false
var training_target_limit:=-1
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
var next_id := 0
var spawn_clock := 2.0
var attack_spacing := 0.0
var incoming_distance := INF
var incoming_bearing := 0.0
var threat_level := 0.0
var hit_flash := 0.0
var hit_confirm := 0.0
var assist := true
var aim_strength: float=1.0:
	set(value):aim_strength=clampf(value,0,3) if is_finite(value) else 1.0
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
	training_target_limit=-1
	for child: Node in get_children():
		if child==visuals:continue
		remove_child(child); child.queue_free()
	if is_instance_valid(visuals):visuals.reset()
	intent.reset();motif_history.clear();boss_id=-1;boss_defeated=false;boss_stage=0;primary_used=false;near_miss_clock=0;event_log.clear()
	enemies.clear(); shots.clear(); bursts.clear()
	active = enabled; engagement_enabled = enabled; managed_mission = false; elapsed = 0; hull = Tune.PLAYER_HEALTH
	ammo = -1; missiles = -1; flares = -1; flares_fired = 0
	kills = 0; score = 0; combo = 0; best_combo = 0; combo_time = 0; reward_flash = 0; rounds_fired = 0; rounds_hit = 0; missiles_fired = 0; missiles_evaded = 0; hostile_launches = 0
	gun_firing_time = 0; gun_cooldown = 0; flare_cooldown = 0
	lock_progress = 0; target_id = -1; target_hold = 0; aim_direction = forward(); reticle_direction = forward(); next_id = 0; spawn_clock = Tune.FIRST_ARRIVAL; arrival_index = 0
	incoming_distance = INF; threat_level = 0; hit_flash = 0; hit_confirm = 0
	message = ""; message_time = 0; attack_spacing = 0
	patrol_south = false; course_recovery = false; runs_started+=1;rng.seed = 260926+97*(runs_started-1)

func forward() -> Vector3: return app.flight.forward().normalized()
func acquire_angle() -> float:return ACQUIRE_ANGLE*aim_strength
func release_angle() -> float:return RELEASE_ANGLE*aim_strength
func target() -> Dictionary:
	for enemy: Dictionary in enemies:
		if enemy.id==target_id and enemy.health>0: return enemy
	return {}
func announce(value: String) -> void:
	message = value; message_time = 2.5

func goose_model() -> Node3D:
	var root: Node3D = GooseModel.create()
	root.scale = Vector3.ONE*Tune.CONTACT_MODEL_SCALE
	return root

func choose_motif() -> String:
	var choices: Array[String]=["pursuit","crossing","split","close_pass","vertical","climb","chain","landmark","head_on","post_roll","cloud_reveal","low_chase"]
	if elapsed<12:return "pursuit"
	if app.flight.barrel_remaining>0:return "post_roll"
	var chosen: String="pursuit";var best: float=-INF
	var clearance: float=app.flight.position.y-app.world.ground_height(app.flight.position.x,app.flight.position.z)
	for option in choices:
		var weight: float=rng.randf()
		if motif_history.slice(maxi(0,motif_history.size()-3)).has(option):weight-=1.2
		if app.flight.speed>300 and option in ["pursuit","head_on"]:weight+=.5
		if clearance<200 and option in ["low_chase","landmark"]:weight+=.5
		if intent.help_amount>.7 and option in ["pursuit","climb","chain"]:weight+=.45
		if intent.intensity>.65 and option in ["crossing","split","vertical"]:weight+=.5
		if app.route_id=="sf" and app.world.cloud_presence>.15 and option=="cloud_reveal":weight+=.8
		if app.flight.position.x>12000 and option=="landmark":weight+=.2
		if weight>best:best=weight;chosen=option
	motif_history.append(chosen)
	if motif_history.size()>8:motif_history.pop_front()
	return chosen

func demo_route_position(index: int) -> Vector3:
	var mission = app.mission
	var distance := 1400.0+index*500.0
	var side: float = [-200,260,-320,180,330,-240,280,-190][index%8]
	var height_offset: float = [-90,100,-140,60,-75,140,-110,95][index%8]
	var at: Vector3 = mission.airfield.to_global(Vector3(-550+distance/13000*330+side,0,mission.airfield.DISTANCE-distance))
	at.y = minf(mission.cruise_height,app.flight.position.y+distance*.16)+height_offset
	at.y = maxf(at.y,app.world.ground_height(at.x,at.z)+Tune.CONTACT_FLIGHT_CLEARANCE)
	return at

func extend_demo_route() -> void:
	# Uncleared geese circle ahead for another pass if the pilot needs more time.
	for enemy: Dictionary in enemies:
		if enemy.health<=0: continue
		enemy.position = demo_route_position(enemy.id)
		enemy.course = Vector3(sin(app.mission.airfield.heading),0,-cos(app.mission.airfield.heading))*20
		enemy.right = Vector3(cos(app.mission.airfield.heading),0,sin(app.mission.airfield.heading))
		enemy.fade = 0; enemy.age = 0
		enemy.node.position = enemy.position
	target_id = -1; lock_progress = 0

func spawn_contact(kind: String = "normal") -> void:
	if training_target_limit>=0 and next_id>=training_target_limit:return
	if training_target_limit<0 and kind=="normal" and elapsed>28 and next_id%5==3:kind="elite"
	if arrival_index%3==0:motif=choose_motif();event("scan",app.flight.position+forward()*700,.6)
	var node := goose_model();add_child(node)
	var right := Vector3(cos(app.flight.heading),0,sin(app.flight.heading))
	var distance: float=(430 if elapsed<15 else 570)+(next_id%3)*90
	var lane: float=0.0 if elapsed<8 else [-.09,.14,-.20,.04][next_id%4]
	var position_value: Vector3=app.flight.position+forward()*distance+right*distance*lane
	var course: Vector3=forward()*clampf(app.flight.speed*.74,110,250)
	var selected_motif:=motif
	if motif=="crossing":position_value+=right*distance*.18;course-=right*75
	elif motif=="split":course+=right*(50 if next_id%2==0 else -50)
	elif motif=="close_pass":position_value=app.flight.position+forward()*750+right*55;course=-forward()*90
	elif motif=="head_on":position_value=app.flight.position+forward()*1000+right*85;course=-forward()*120+right*15
	elif motif=="vertical":position_value.y+=160;course.y=-35
	elif motif=="climb":position_value.y-=70;course.y=35
	elif motif in ["low_chase","landmark"]:position_value.y-=80;course.y=-10
	elif motif=="cloud_reveal":position_value+=forward()*180
	elif motif=="chain":position_value+=right*(next_id%3-1)*30;course=forward()*app.flight.speed*.68
	elif motif=="post_roll":position_value=app.flight.position+forward()*540+right*45
	position_value.y=maxf(position_value.y+rng.randf_range(-10,15),app.world.ground_height(position_value.x,position_value.z)+90)
	var hp: float=Tune.ELITE_HEALTH if kind=="elite" else Tune.CONTACT_HEALTH
	var size_factor: float=1.45 if kind=="elite" else 1.0
	if kind=="boss":
		hp=Tune.BOSS_HEALTH;size_factor=5.2;position_value=app.flight.position+forward()*1600+Vector3.UP*110
		course=forward()*app.flight.speed*.82;boss_id=next_id;selected_motif="boss";event("boss_signature",position_value,4)
	if training_target_limit>0:
		position_value=demo_route_position(next_id);course=Vector3(sin(app.mission.airfield.heading),0,-cos(app.mission.airfield.heading))*20
	node.scale*=size_factor;node.position=position_value
	var contact: Dictionary={"id":next_id,"node":node,"position":position_value,"health":hp,"max_health":hp,"kind":kind,"size_factor":size_factor,"hit_radius":22.0*size_factor,"velocity":course,"course":course,"right":right,"cooldown":999.0,"age":0.0,"phase":rng.randf_range(0,TAU),"fade":0.0,"retiring":false,"motif":selected_motif,"presented":next_id%3==0,"hit_flash":0.0,"damage_stage":0,"dying":-1.0,"sensor_occluded":false,"weak_side":-1.0,"near_passed":false}
	enemies.append(contact);next_id+=1
	if is_instance_valid(visuals):visuals.add_target(contact)

func tick(dt: float) -> void:
	if not active: return
	elapsed += dt
	intent.tick(self,dt);near_miss_clock=maxf(0,near_miss_clock-dt)
	gun_firing_time = maxf(0,gun_firing_time-dt)
	target_hold = maxf(0,target_hold-dt)
	gun_cooldown = maxf(0,gun_cooldown-dt);
	if gun_cooldown<.0001: gun_cooldown = 0
	flare_cooldown = maxf(0,flare_cooldown-dt)
	hit_flash = maxf(0,hit_flash-dt*2.4); hit_confirm = maxf(0,hit_confirm-dt*5)
	combo_time = maxf(0,combo_time-dt); reward_flash = maxf(0,reward_flash-dt*1.4)
	if combo_time==0: combo = 0
	message_time = maxf(0,message_time-dt)
	if engagement_enabled: spawn_clock -= dt
	attack_spacing = maxf(0,attack_spacing-dt)
	var desired_contacts: int=2 if elapsed<20 else 3 if intent.intensity<.7 else 4
	if boss_id>=0:desired_contacts=1
	if engagement_enabled and spawn_clock<=0 and enemies.size()<desired_contacts:
		spawn_contact(); arrival_index += 1
		spawn_clock = lerpf(2.8,1.25,intent.intensity) if arrival_index%3 else lerpf(3.2,1.8,intent.intensity)
	for enemy: Dictionary in enemies:
		if enemy.health<=0:
			enemy.dying+=dt;enemy.position+=enemy.velocity*dt*.3;enemy.node.position=enemy.position
			enemy.node.scale*=maxf(.01,1-dt*.8)
			continue
		enemy.age += dt
		enemy.hit_flash=maxf(0,enemy.hit_flash-dt*5)
		var to_plane: Vector3 = app.flight.position-enemy.position
		var distance: float = to_plane.length()
		if training_target_limit<0 and enemy.kind!="boss" and (enemy.age>24 or distance>2500 or forward().dot(-to_plane)<-90): enemy.retiring = true
		var present: bool = (engagement_enabled or enemy.kind=="boss") and not enemy.retiring
		enemy.fade = minf(.1 if enemy.kind=="boss" and enemy.age<4 else 1.0,enemy.fade+dt*Tune.CONTACT_FADE_IN) if present else maxf(0,enemy.fade-dt*Tune.CONTACT_FADE_OUT)
		var lateral: Vector3 = enemy.get("right",Vector3.RIGHT)
		var velocity: Vector3 = enemy.get("course",forward()*150)+lateral*sin(enemy.age*.55+enemy.phase)*Tune.CONTACT_WEAVE_SPEED+Vector3.UP*cos(enemy.age*.4+enemy.phase)*Tune.CONTACT_VERTICAL_SPEED
		if training_target_limit>0:
			velocity=enemy.course+lateral*sin(enemy.age*.55+enemy.phase)*2+Vector3.UP*cos(enemy.age*.4+enemy.phase)
		elif enemy.kind=="boss":
			var anchor: Vector3=app.flight.position+Vector3(forward().x,0,forward().z).normalized()*950+lateral*sin(elapsed*.18)*110
			anchor.y=clampf(app.flight.position.y+sin(elapsed*.22)*35,300,650)
			velocity=app.flight.velocity+(anchor-enemy.position)*.65+lateral*sin(elapsed*.7)*25
			enemy.weak_side=-1.0 if enemy.damage_stage==1 else 1.0 if enemy.damage_stage==2 else 0.0
		elif training_target_limit<0 and enemy.age>8 and distance>1200 and not enemy.retiring:
			velocity=velocity.lerp(app.flight.velocity*.72+(app.flight.position+forward()*700-enemy.position)*.22,.03)
		if distance<130 and not enemy.near_passed:
			enemy.near_passed=true;intent.event("near_miss");event("near_miss",enemy.position,1)
		if not present: velocity += lateral*(60 if enemy.id%2 else -60)+Vector3.UP*25
		enemy.position += velocity*dt
		enemy.position.y = maxf(enemy.position.y,app.world.ground_height(enemy.position.x,enemy.position.z)+Tune.CONTACT_FLIGHT_CLEARANCE)
		enemy.velocity = velocity
		enemy.node.position = enemy.position
		if velocity.length()>1: enemy.node.look_at(enemy.position+velocity,Vector3.UP)
		var flap: float = sin(elapsed*(1.4 if enemy.kind=="boss" else 4.2)+enemy.phase)*(.24+enemy.hit_flash*.2)
		enemy.node.get_node("WingL").rotation.z = flap
		enemy.node.get_node("WingR").rotation.z = -flap
		if enemy.fade<1 or enemy.age<1.5:
			for geometry: Node in enemy.node.find_children("*","GeometryInstance3D",true,false): geometry.transparency = 1-enemy.fade
	var best := -1
	var best_dot: float=cos(deg_to_rad(acquire_angle()))
	var old_alignment := -1.0
	for enemy: Dictionary in enemies:
		if enemy.health<=0:continue
		var delta: Vector3=enemy.position-app.flight.position
		var alignment: float=forward().dot(delta.normalized())
		if enemy.id==target_id:old_alignment=alignment
		if engagement_enabled and not enemy.retiring and enemy.fade>.45 and delta.length()<Tune.TARGET_RANGE and alignment>best_dot:
			best=enemy.id;best_dot=alignment
	if old_alignment>cos(deg_to_rad(release_angle())) and not target().get("retiring",true) and (target_hold>0 or acos(clampf(old_alignment,-1,1))-acos(clampf(best_dot,-1,1))<deg_to_rad(Tune.TARGET_SWITCH_MARGIN*aim_strength)):
		best=target_id
	if best!=target_id:
		target_id=best;lock_progress=0;target_hold=Tune.TARGET_STICK_TIME*aim_strength;event("candidate",target().get("position",app.flight.position),.5)
	var locked_before: bool=lock_progress>=1
	lock_progress=minf(1,lock_progress+dt*aim_strength/Tune.LOCK_TIME) if target_id>=0 else 0.0
	intent.confidence=lock_progress
	if not locked_before and lock_progress>=1:
		intent.metrics.locks+=1;app.audio.radio.say("target_locked");event("lock",target().get("position",app.flight.position),1)
	update_aim(dt)
	update_shots(dt); update_bursts(dt)
	if is_instance_valid(visuals):visuals.tick(dt)
	incoming_distance = INF;threat_level=0
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
	return aim_direction if assist and aim_strength>0 else forward()

func update_aim(dt: float) -> void:
	var desired: Vector3 = forward()
	var enemy: Dictionary = target()
	if assist and aim_strength>0 and not enemy.is_empty():
		var wanted: Vector3 = (lead_point(enemy)-app.flight.position).normalized()
		if desired.angle_to(wanted)<deg_to_rad(release_angle()): desired = wanted
	if aim_direction.length_squared()<.5: aim_direction = forward()
	var angle: float = aim_direction.angle_to(desired)
	var response: float = aim_strength if assist and aim_strength>0 else 1.0
	var weight: float = minf(1-exp(-dt*Tune.AIM_RESPONSE*response),deg_to_rad(Tune.AIM_SLEW_DEGREES)*response*dt/maxf(angle,.0001))
	aim_direction = safe_direction_lerp(aim_direction,desired,weight)
	var visual: Vector3 = forward()
	if assist and aim_strength>0 and not enemy.is_empty() and forward().angle_to((enemy.position-app.flight.position).normalized())<deg_to_rad(release_angle()):
		visual = (enemy.position-app.flight.position).normalized()
	reticle_direction = safe_direction_lerp(reticle_direction,visual,1-exp(-dt*Tune.RETICLE_RESPONSE*response))

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
	if not active or not app.flight.airborne: return false
	var starting: bool=gun_firing_time<=0
	gun_firing_time=Tune.GUN_RELEASE_TAIL;primary_used=true
	if gun_cooldown>0:return false
	if shots.size()>=Tune.MAX_SHOTS:return false
	if starting: app.audio.play_effect("gatling_attack",-15,1.0)
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

func deploy_flares() -> bool:
	if not active or flare_cooldown>0: return false
	flares_fired += 1; flare_cooldown = Tune.FLARE_INTERVAL
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
			burst(shot.position,Color(1,.70,.32),1.6)
			continue
		if shot.kind=="cannon": shot.node.scale.z = clampf(shot.age*shot.velocity.length()/9,.01,1)
		shot.node.position = shot.position
		shot.node.look_at(shot.position+shot.velocity,Vector3.UP)
		update_trail(shot)
		for enemy: Dictionary in enemies:
			if enemy.health>0 and segment_distance(enemy.position,previous,shot.position)<Tune.GUN_HIT_RADIUS:
				hurt_enemy(enemy,shot.damage,"cannon",shot.position);shot.life=0;shot.hit=true;hit_confirm=1
				app.audio.play_effect("impact",-24,1.15)
				rounds_hit+=int(shot.get("round_count",1))
				burst(enemy.position,Color(1,.66,.27),3)
				break
	for i in range(shots.size()-1,-1,-1):
		if shots[i].life<=0:
			free_shot(shots[i]); shots.remove_at(i)
	for i in range(enemies.size()-1,-1,-1):
		var enemy: Dictionary = enemies[i]
		if enemy.fade<=0 and (not engagement_enabled or enemy.get("retiring",false)):
			enemy.node.queue_free(); enemies.remove_at(i); continue
		if enemy.health<=0 and enemy.dying>2.4:
			enemy.node.queue_free();enemies.remove_at(i)

func hurt_enemy(enemy: Dictionary,damage: float,source: String,at: Vector3) -> void:
	if enemy.health<=0:return
	if enemy.kind=="boss" and (enemy.age<3 or app.mission.phase=="anticipation"):damage*=.12
	if enemy.kind=="boss" and enemy.damage_stage>0:
		var weak: Vector3=enemy.position+Vector3(enemy.right)*enemy.weak_side*35
		if weak.distance_to(at)<45:damage*=1.25
	if enemy.kind=="boss" and app.mission.clock>125:damage*=1.5
	enemy.health=maxf(0,enemy.health-damage);enemy.hit_flash=1.0;hit_confirm=1
	var stage: int=mini(3,int((1-enemy.health/enemy.max_health)*4))
	if stage>enemy.damage_stage:
		enemy.damage_stage=stage;event("armor_break",at,3 if enemy.kind=="boss" else 1)
	if enemy.kind=="boss":boss_stage=stage
	if enemy.health>0:return
	enemy.dying=0.0;kills+=1;combo+=1;best_combo=maxi(best_combo,combo);combo_time=Tune.STREAK_TIME
	last_reward=Tune.BASE_SCORE*(20 if enemy.kind=="boss" else 3 if enemy.kind=="elite" else 1)*mini(Tune.MAX_MULTIPLIER,1+int(combo/Tune.STREAK_STEP))
	score+=last_reward;reward_flash=1;intent.event("kill");app.audio.ping(1+minf(combo,10)*.035)
	event("boss_death" if enemy.kind=="boss" else "kill",enemy.position,5 if enemy.kind=="boss" else enemy.size_factor)
	app.fighter_fx.debris(enemy.position);app.audio.play_effect("explosion",-12 if enemy.kind=="boss" else -18,.7 if enemy.kind=="boss" else 1)
	app.camera_rig.impulse(.38 if enemy.kind=="boss" else .15)
	if enemy.kind=="boss":boss_defeated=true
	else:spawn_clock=minf(spawn_clock,.75);app.audio.radio.say("target_down" if kills%2 else "target_down_alt")

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
	app.flight.afterburner=false
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
	assert(kind=="cannon","Only XLX cannon projectiles are supported")
	if kind!="cannon":return
	var node: Node3D=visuals.take_projectile("cannon") if is_instance_valid(visuals) else WeaponArt.projectile("cannon",variant)
	if node.get_parent()==null:add_child(node)
	node.position=at;node.scale.z=.01;node.look_at(at+velocity,Vector3.UP)
	var shot: Dictionary={"node":node,"position":at,"velocity":velocity,"kind":"cannon","target":target_value,"damage":damage,"life":Tune.GUN_LIFETIME,"age":0.0,"trail_points":[at],"trail_node":null,"trail_clock":0.0,"hit":false}
	var trail:=MeshInstance3D.new();trail.mesh=ImmediateMesh.new()
	var smoke:=StandardMaterial3D.new();smoke.albedo_color=Color.WHITE
	smoke.albedo_texture=load("res://assets/sourced_flight/smoke.png")
	smoke.emission_enabled=true;smoke.emission=Color(1,.55,.18);smoke.emission_energy_multiplier=1.1
	smoke.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;smoke.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;smoke.vertex_color_use_as_albedo=true;smoke.cull_mode=BaseMaterial3D.CULL_DISABLED
	trail.set_meta("smoke_material",smoke);trail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail);shot.trail_node=trail;shots.append(shot)

func update_trail(shot: Dictionary) -> void:
	if elapsed-float(shot.trail_clock)<.025:return
	shot.trail_clock=elapsed
	var points: Array = shot.trail_points
	if Vector3(points.back()).distance_to(shot.position)>7:
		points.append(shot.position)
		if points.size()>(4 if shot.kind=="cannon" else 52): points.pop_front()
	var ribbon: ImmediateMesh = shot.trail_node.mesh
	ribbon.clear_surfaces()
	if points.size()<2: return
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES,shot.trail_node.get_meta("smoke_material"))
	for i in range(points.size()-1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i+1]
		var cannon: bool = shot.kind=="cannon"
		var width: float = lerpf(.42,.13,float(i)/maxf(points.size()-1,1)) if cannon else lerpf(3.8,.32,float(i)/maxf(points.size()-1,1))
		var side: Vector3 = (b-a).normalized().cross((app.camera.global_position-a).normalized()).normalized()
		if side.length()<0.1: side = Vector3.RIGHT
		side *= width
		var alpha: float = float(i+1)/maxf(points.size(),1)*(.82 if cannon else .58)
		for vertex: Array in [[a-side,Vector2(0,0)],[a+side,Vector2(1,0)],[b-side,Vector2(0,1)],[b-side,Vector2(0,1)],[a+side,Vector2(1,0)],[b+side,Vector2(1,1)]]:
			ribbon.surface_set_color(Color(1,.72,.35,alpha) if cannon else Color(.32,.39,.43,alpha) if app.camera.global_position.y<shot.position.y else Color(.72,.82,.9,alpha))
			ribbon.surface_set_uv(vertex[1])
			ribbon.surface_add_vertex(vertex[0])
	ribbon.surface_end()
func free_shot(shot: Dictionary) -> void:
	if is_instance_valid(visuals):visuals.release_projectile(shot.node,"cannon")
	else:shot.node.queue_free()
	if is_instance_valid(shot.get("trail_node")):shot.trail_node.queue_free()

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
