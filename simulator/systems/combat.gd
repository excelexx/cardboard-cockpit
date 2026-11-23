extends Node3D
class_name CombatDirector
const Tune = preload("res://data/balance.gd")
const Intent = preload("res://systems/target_intent.gd")
var intent: TargetIntent = Intent.new()
var visuals: Node3D
var motif := "pursuit"
var runs_started:=0
var motif_history: Array[String] = []
## THE FLOCK API. There is no boss any more: the last wave is a skein of
## ordinary geese, and these are the exact names scenes/main.gd,
## systems/demo_mission.gd, ui/hud.gd, systems/goose_flight.gd and
## systems/badge_link.gd look for.
##   skein_ids        every id in the flock, published the frame it spawns
##   skein_total      how many birds the flock was asked for
##   skein_down       how many of them this director has seen die
##   skein_cleared    the whole flock is down
##   skein_remaining() how many are still flying
##   spawn_skein(n,course) build the V
var skein_ids: Array[int] = []
var skein_total := 0
var skein_down := 0
var skein_cleared := false
## Deferred per-bird visual registration, drained a couple per frame so a
## twelve-bird arrival is never one long frame.
var pending_spawns: Array[Dictionary] = []
## Compatibility shims for files this package does not own. boss_id is never a
## live id again; boss_defeated is an alias of skein_cleared.
var boss_id := -1
var boss_defeated := false
var primary_used := false
var salvo_used := false
var salvo_count := 0
var beam_active := false
var beam_end := Vector3.ZERO
var beam_hit_id := -1
var beam_clock := 0.0
var near_miss_clock := 0.0
var event_log: Array[Dictionary] = []
func _ready() -> void:
	visuals=load("res://systems/combat_visuals.gd").new();visuals.combat=self;add_child(visuals)
func event(kind: String,at: Vector3=Vector3.ZERO,weight: float=1.0) -> void:
	event_log.append({"event":kind,"time":elapsed})
	if event_log.size()>120:event_log.pop_front()
	if is_instance_valid(visuals):visuals.event(kind,at,weight)
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
var trail_core_material: StandardMaterial3D
## One StandardMaterial3D per weapon and a pool of ribbon nodes: spawn_shot used
## to allocate a MeshInstance3D, an ImmediateMesh and a textured material for
## every packet, about sixty allocations and frees a second.
var trail_pool: Array[MeshInstance3D] = []
var cannon_trail_material: StandardMaterial3D
var missile_trail_material: StandardMaterial3D
var packet_index := 0
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
## A missile's corner is limited by MISSILE_G_LIMIT; this is only the rate cap
## that keeps a just-ignited, still slow missile from pirouetting.
const MISSILE_MAX_TURN_DEGREES := 110.0
## How long a corpse may keep falling before it is swept up regardless.
const CORPSE_HOLD := 5.0
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
		if child==visuals:continue
		remove_child(child); child.queue_free()
	if is_instance_valid(visuals):visuals.reset()
	intent.reset();motif_history.clear();primary_used=false;salvo_used=false;salvo_count=0;beam_active=false;beam_clock=0;near_miss_clock=0;event_log.clear()
	skein_ids.clear();skein_total=0;skein_down=0;skein_cleared=false;pending_spawns.clear();boss_id=-1;boss_defeated=false
	enemies.clear(); shots.clear(); bursts.clear(); launch_queue.clear(); detached_trails.clear()
	trail_pool.clear()  # the child sweep above already freed every pooled ribbon
	packet_index = 0
	active = enabled; engagement_enabled = enabled; managed_mission = false; elapsed = 0; hull = Tune.PLAYER_HEALTH
	ammo = -1; missiles = -1; flares = -1; flares_fired = 0
	kills = 0; score = 0; combo = 0; best_combo = 0; combo_time = 0; reward_flash = 0; rounds_fired = 0; rounds_hit = 0; missiles_fired = 0; missiles_evaded = 0; hostile_launches = 0
	gun_firing_time = 0; gun_cooldown = 0; missile_cooldown = 0; flare_cooldown = 0
	lock_progress = 0; target_id = -1; target_hold = 0; aim_direction = forward(); reticle_direction = forward(); next_id = 0; spawn_clock = Tune.FIRST_ARRIVAL; arrival_index = 0
	incoming_distance = INF; threat_level = 0; hit_flash = 0; hit_confirm = 0
	last_missile = null; message = ""; message_time = 0; attack_spacing = 0
	patrol_south = false; course_recovery = false; runs_started+=1;rng.seed = 260926+97*(runs_started-1)

func forward() -> Vector3: return app.flight.forward().normalized()
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

# =======================================================================
# systems/goose_flight.gd - guarded loader
# =======================================================================
## P6 owns the bird. Every call into it goes through here, so a missing file or
## a renamed method degrades to the local fallback instead of taking the sortie
## down mid-showcase.
const GOOSE_FLIGHT_PATH := "res://systems/goose_flight.gd"
var _goose: Variant = null
var _goose_methods: Dictionary = {}
var _goose_checked := false
func goose() -> Variant:
	if _goose_checked: return _goose
	_goose_checked = true
	if ResourceLoader.exists(GOOSE_FLIGHT_PATH):
		_goose = load(GOOSE_FLIGHT_PATH)
		if _goose!=null:
			for entry: Dictionary in _goose.get_script_method_list(): _goose_methods[entry.name]=true
	return _goose
func goose_can(method: String) -> bool:
	return goose()!=null and _goose_methods.has(method)

## The flock's own heading: goose cruise across the player's track, never the
## jet's vector and never scaled off the jet's speed.
func skein_course() -> Vector3:
	if goose_can("skein_course"):
		var supplied: Variant = _goose.skein_course(self)
		if supplied is Vector3 and (supplied as Vector3).length()>0.5: return supplied
	var track: float = app.flight.heading+deg_to_rad(112.0)
	return Vector3(sin(track),-.06,-cos(track)).normalized()*lerpf(Tune.CONTACT_MIN_SPEED,Tune.CONTACT_MAX_SPEED,.5)

## A seat on the V, leader relative: +x right, +y up, +z behind.
func formation_slot(rank: int) -> Vector3:
	if goose_can("formation_slot"):
		var slot: Variant = _goose.formation_slot(rank)
		if slot is Vector3: return slot
	if rank<=0: return Vector3.ZERO
	var step: int = int((rank+1)/2)
	var back: float = float(step)*Tune.SKEIN_SLOT_BACK
	return Vector3((1.0 if rank%2==1 else -1.0)*back*tan(deg_to_rad(Tune.SKEIN_V_DEGREES*.5)),float(step)*Tune.SKEIN_SLOT_RISE,back)

func skein_basis(course: Vector3) -> Basis:
	var flat := Vector3(course.x,0.0,course.z)
	flat = flat.normalized() if flat.length()>.01 else Vector3.FORWARD
	var wing: Vector3 = flat.cross(Vector3.UP)
	wing = wing.normalized() if wing.length()>.001 else Vector3.RIGHT
	return Basis(wing,Vector3.UP,-flat)

# =======================================================================
# the flock
# =======================================================================
## How many of the skein are still flying. Counts only live birds, so the
## mission can close the act the frame the last goose folds.
func skein_remaining() -> int:
	if skein_ids.is_empty(): return 0
	var left := 0
	for enemy: Dictionary in enemies:
		if float(enemy.health)>0.0 and skein_ids.has(int(enemy.id)): left += 1
	return left

## Build the V. Every bird is an ordinary goose, every id is published in
## skein_ids before this returns, and the expensive per-bird visual
## registration is queued and drained a couple per frame from tick().
func spawn_skein(n: int = Tune.SKEIN_SIZE, course: Vector3 = Vector3.ZERO) -> void:
	var size: int = maxi(1,n)
	var heading: Vector3 = course if course.length()>0.5 else skein_course()
	var right := Vector3(cos(app.flight.heading),0,sin(app.flight.heading))
	var lead: Vector3 = app.flight.position+forward()*Tune.SKEIN_SPAWN_DISTANCE+Vector3.UP*Tune.SKEIN_SPAWN_HEIGHT
	var basis: Basis = skein_basis(heading)
	skein_ids.clear(); skein_total = size; skein_down = 0; skein_cleared = false; boss_defeated = false
	for rank in range(size):
		var at: Vector3 = lead+basis*formation_slot(rank)
		at.y = maxf(at.y,app.world.ground_height(at.x,at.z)+Tune.CONTACT_FLIGHT_CLEARANCE)
		var bird: Dictionary = register_contact(at,heading,right,"skein",rank,true)
		skein_ids.append(int(bird.id))
	announce("BIG FLOCK INBOUND")

func contact_by_id(id_value: int) -> Dictionary:
	for enemy: Dictionary in enemies:
		if int(enemy.id)==id_value: return enemy
	return {}

## The one scene-tree walk a contact ever costs, taken here at spawn instead of
## sixty times a second in the enemy loop.
func collect_geometry(node: Node3D) -> Array:
	var out: Array = []
	for path: String in ["Body","WingL/Feathers","WingR/Feathers"]:
		var geometry: Node = node.get_node_or_null(path)
		if geometry is GeometryInstance3D: out.append(geometry)
	if out.is_empty():
		for geometry: Node in node.find_children("*","GeometryInstance3D",true,false): out.append(geometry)
	return out

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

## How many seconds of shooting an arriving goose is worth. A Canada goose
## cruises at 20 m/s, so the jet does nearly all of the closing and the old
## fixed 430-570 m arrival would be past the nose in under three seconds. The
## distance is derived from the closing speed instead, which keeps the window
## the player actually had before the birds slowed down to goose speed.
const ENGAGEMENT_SECONDS := 6.0
const ENGAGEMENT_MIN_DISTANCE := 520.0
const ENGAGEMENT_MAX_DISTANCE := 1500.0

## One ordinary Canada goose. `kind` survives only so the harnesses that still
## pass "goose", "elite" or "boss" keep running: there is exactly one enemy in
## this game and every one of them is a normal goose.
func spawn_contact(kind: String = "normal") -> void:
	if arrival_index%3==0:motif=choose_motif();event("scan",app.flight.position+forward()*700,.6)
	var right := Vector3(cos(app.flight.heading),0,sin(app.flight.heading))
	var cruise: float=lerpf(Tune.CONTACT_MIN_SPEED,Tune.CONTACT_MAX_SPEED,rng.randf())
	var course: Vector3=forward()*cruise
	var selected_motif:=motif
	var lane: float=0.0 if elapsed<8 else [-.09,.14,-.20,.04][next_id%4]
	var offset := Vector3.ZERO
	var extra := 0.0
	if motif=="crossing":offset+=right*95;course-=right*cruise*.9
	elif motif=="split":course+=right*(cruise*.5 if next_id%2==0 else -cruise*.5)
	elif motif=="close_pass":offset+=right*55;course=-forward()*15;extra=180
	elif motif=="head_on":offset+=right*85;course=-forward()*20+right*3;extra=260
	elif motif=="vertical":offset.y+=160;course.y=-3.5
	elif motif=="climb":offset.y-=70;course.y=3.5
	elif motif in ["low_chase","landmark"]:offset.y-=80;course.y=-1.5
	elif motif=="cloud_reveal":extra=180
	elif motif=="chain":offset+=right*(next_id%3-1)*30;course=skein_course()
	elif motif=="post_roll":offset+=right*45;extra=-140
	var closure: float=maxf(app.flight.speed-forward().dot(course),40.0)
	var distance: float=clampf(closure*ENGAGEMENT_SECONDS+float(next_id%3)*70.0+extra,ENGAGEMENT_MIN_DISTANCE,ENGAGEMENT_MAX_DISTANCE)
	var position_value: Vector3=app.flight.position+forward()*distance+right*distance*lane+offset
	position_value.y=maxf(position_value.y+rng.randf_range(-10,15),app.world.ground_height(position_value.x,position_value.z)+90)
	var contact: Dictionary=register_contact(position_value,course,right,selected_motif,0,false)
	if is_instance_valid(visuals):visuals.add_target(contact)

## Builds the contact Dictionary every other system reads. Every per-bird field
## systems/goose_flight.gd wants is seeded here as a literal, including the two
## wing pivots and the geometry list, so the per-frame update never searches the
## scene tree again.
func register_contact(at: Vector3,course: Vector3,right: Vector3,motif_name: String,rank: int,member: bool) -> Dictionary:
	var node := goose_model();add_child(node);node.position=at
	var id_value: int=next_id;next_id+=1
	var contact: Dictionary={"id":id_value,"node":node,"position":at,"health":Tune.CONTACT_HEALTH,"max_health":Tune.CONTACT_HEALTH,
		"kind":"normal","size_factor":1.0,"hit_radius":Tune.CONTACT_HIT_RADIUS,"velocity":course,"course":course,"right":right,
		"cooldown":999.0,"age":0.0,"phase":rng.randf_range(0,TAU),"fade":0.0,"retiring":false,"motif":motif_name,
		"presented":id_value%3==0,"hit_flash":0.0,"dying":-1.0,"sensor_occluded":false,"near_passed":false,
		"flap_phase":rng.randf_range(0,TAU),"bank":0.0,"prev_velocity":course,"reaction_state":"calm","reaction_clock":0.0,
		"spin":Vector3.ZERO,"rank":rank,"lod":0,"model_scale":node.scale.x,
		"wing_l":node.get_node_or_null("WingL"),"wing_r":node.get_node_or_null("WingR"),"geometry":collect_geometry(node),
		"damage_stage":0,"weak_side":-1.0}
	if member:
		contact["skein"]=1
		pending_spawns.append({"id":id_value})
	enemies.append(contact)
	return contact

func tick(dt: float) -> void:
	if not active: return
	elapsed += dt
	intent.tick(self,dt);near_miss_clock=maxf(0,near_miss_clock-dt)
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
	var desired_contacts: int=2 if elapsed<20 else 3 if intent.intensity<.7 else 4
	if not skein_ids.is_empty():desired_contacts=skein_ids.size()
	if engagement_enabled and spawn_clock<=0 and enemies.size()<desired_contacts:
		spawn_contact(); arrival_index += 1
		spawn_clock = lerpf(2.8,1.25,intent.intensity) if arrival_index%3 else lerpf(3.2,1.8,intent.intensity)
	for i in range(mini(Tune.SKEIN_SPAWN_PER_FRAME,pending_spawns.size())):
		var order: Dictionary=pending_spawns.pop_front()
		var queued: Dictionary=contact_by_id(int(order.id))
		if not queued.is_empty() and is_instance_valid(visuals):visuals.add_target(queued)
	for enemy: Dictionary in enemies:
		if enemy.health<=0:
			if not fall_contact(enemy,dt):enemy.corpse_done=true
			continue
		enemy.age += dt
		enemy.hit_flash=maxf(0,enemy.hit_flash-dt*5)
		var to_plane: Vector3 = app.flight.position-enemy.position
		var distance: float = to_plane.length()
		if should_retire(enemy,distance): enemy.retiring = true
		var present: bool = engagement_enabled and not enemy.retiring
		enemy.fade = minf(1.0,enemy.fade+dt*Tune.CONTACT_FADE_IN) if present else maxf(0,enemy.fade-dt*Tune.CONTACT_FADE_OUT)
		if distance<130 and not enemy.near_passed:
			enemy.near_passed=true;intent.event("near_miss");event("near_miss",enemy.position,1)
		fly_contact(enemy,dt)
	var best: int=intent.choose(self,dt) if engagement_enabled else -1
	if best!=target_id:target_id=best;lock_progress*=.35;target_hold=.38;event("candidate",target().get("position",app.flight.position),.5)
	var locked_before: bool=lock_progress>=1
	# A lock the player can actually read: LOCK_SECONDS_FAST..SLOW is the fill
	# time of the cockpit LOCKING bar. It never gates the trigger - fire_missile
	# still takes its target at .65 exactly as before.
	var rate: float=1.0/maxf(lerpf(Tune.LOCK_SECONDS_SLOW,Tune.LOCK_SECONDS_FAST,clampf(intent.confidence*.5+intent.help_amount*.5,0,1)),.05)
	lock_progress=minf(1,lock_progress+dt*rate) if target_id>=0 else maxf(0,lock_progress-dt*6)
	if not locked_before and lock_progress>=1:
		intent.metrics.locks+=1;app.audio.radio.say("target_locked");event("lock",target().get("position",app.flight.position),1)
	update_aim(dt)
	update_shots(dt); update_beam(dt); update_bursts(dt); update_detached_trails(dt)
	if is_instance_valid(visuals):visuals.tick(dt)
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

# =======================================================================
# per-contact delegation to systems/goose_flight.gd
# =======================================================================
## One living goose, one frame. Everything about how the bird moves, banks,
## beats its wings and fades lives in P6's file; this is only the fallback for
## a tree where that file is missing or has been renamed.
func fly_contact(enemy: Dictionary,dt: float) -> void:
	if goose_can("update"):
		_goose.update(self,enemy,dt)
		return
	var lateral: Vector3=enemy.get("right",Vector3.RIGHT)
	var velocity: Vector3=Vector3(enemy.course)+lateral*sin(enemy.age*.55+enemy.phase)*Tune.CONTACT_WEAVE_SPEED+Vector3.UP*cos(enemy.age*.4+enemy.phase)*Tune.CONTACT_VERTICAL_SPEED
	if not (engagement_enabled and not bool(enemy.retiring)):velocity+=lateral*(60 if int(enemy.id)%2 else -60)+Vector3.UP*25
	enemy.position+=velocity*dt
	enemy.position.y=maxf(enemy.position.y,app.world.ground_height(enemy.position.x,enemy.position.z)+Tune.CONTACT_FLIGHT_CLEARANCE)
	enemy.velocity=velocity
	enemy.node.position=enemy.position
	if velocity.length()>1:enemy.node.look_at(enemy.position+velocity,Vector3.UP)
	var flap: float=sin(elapsed*4.2+float(enemy.phase))*(.24+float(enemy.hit_flash)*.2)
	var left: Node3D=enemy.get("wing_l")
	var right_wing: Node3D=enemy.get("wing_r")
	if left!=null and is_instance_valid(left):left.rotation.z=flap
	if right_wing!=null and is_instance_valid(right_wing):right_wing.rotation.z=-flap
	if enemy.fade<1 or enemy.age<1.5:
		for geometry: GeometryInstance3D in enemy.get("geometry",[]):
			if is_instance_valid(geometry):geometry.transparency=1-float(enemy.fade)

## One dead goose, one frame. Returns false once the bird is on the water.
func fall_contact(enemy: Dictionary,dt: float) -> bool:
	if goose_can("fall_step"): return bool(_goose.fall_step(self,enemy,dt))
	enemy.dying=maxf(0.0,float(enemy.dying))+dt
	enemy.velocity=Vector3(enemy.velocity)+Vector3.DOWN*9.81*dt
	enemy.position+=Vector3(enemy.velocity)*dt
	if is_instance_valid(enemy.node):enemy.node.position=enemy.position
	return float(enemy.dying)<2.4 and enemy.position.y>app.world.ground_height(enemy.position.x,enemy.position.z)

## The skein gets a long leash so the final act cannot delete itself mid-pass.
func should_retire(enemy: Dictionary,distance: float) -> bool:
	if goose_can("should_retire"): return bool(_goose.should_retire(self,enemy,distance))
	if skein_ids.has(int(enemy.id)): return float(enemy.age)>Tune.SKEIN_DESPAWN_AGE or distance>Tune.SKEIN_DESPAWN_DISTANCE
	return float(enemy.age)>24 or distance>2500 or forward().dot(Vector3(enemy.position)-app.flight.position)<-90

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
		if desired.angle_to(wanted)<deg_to_rad(intent.retain_degrees(self)): desired = forward().slerp(wanted,clampf(.45+intent.confidence*.7,0,1))
	if aim_direction.length_squared()<.5: aim_direction = forward()
	var angle: float = aim_direction.angle_to(desired)
	var weight: float = minf(1-exp(-dt*Tune.AIM_RESPONSE),deg_to_rad(Tune.AIM_SLEW_DEGREES)*dt/maxf(angle,.0001))
	aim_direction = safe_direction_lerp(aim_direction,desired,weight)
	var visual: Vector3 = forward()
	if assist and not enemy.is_empty() and forward().angle_to((enemy.position-app.flight.position).normalized())<deg_to_rad(intent.retain_degrees(self)):
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
	# 25 mm gatling dispersion. 0.6 sigma of 5 mrad puts about 80% of the rounds
	# inside the GAU-22/A circle, which at this game's scale is under three
	# metres at 900 m against a 24 m hit sphere: a look change, never a miss.
	var sigma: float=Tune.GUN_DISPERSION_MRAD*0.001*0.6
	var aim: Vector3=(direction+basis.x*rng.randfn(0,sigma)+basis.y*rng.randfn(0,sigma)).normalized()
	# The packet carries the whole burst's damage. Half the packets light their
	# own round and the other half throw a visual-only ghost round from the next
	# barrel round the rotor, so the stream reads at the real sixty rounds a
	# second while the damage per packet, the hit accounting and the score rate
	# stay exactly where the balance profile put them.
	var lit: bool=packet_index%2==0
	packet_index+=1
	spawn_shot(muzzle,aim*Tune.GUN_MUZZLE_SPEED+app.flight.velocity,"cannon",-1,Tune.GUN_DAMAGE_PER_ROUND*round_count,"gatling",lit)
	shots.back().round_count = round_count
	if not lit and round_count>1 and shots.size()<Tune.MAX_SHOTS:
		var spin: float=float(packet_index)*2.3999
		var ghost: Vector3=(direction+basis.x*rng.randfn(0,sigma)+basis.y*rng.randfn(0,sigma)).normalized()
		spawn_shot(muzzle+basis*Vector3(cos(spin),sin(spin),0.0)*.09,ghost*Tune.GUN_MUZZLE_SPEED+app.flight.velocity,"cannon",-1,0.0,"gatling",true,true)
	app.camera_rig.impulse(0.022)
	return true

func fire_missile() -> bool:
	if not active or not app.flight.airborne or missile_cooldown>0:return false
	var tracked: Dictionary=target()
	var chosen: int=target_id if not tracked.is_empty() and lock_progress>=.65 else -1
	var flying_missiles:=0
	for shot: Dictionary in shots:
		if shot.kind=="missile":flying_missiles+=1
	if flying_missiles+launch_queue.size()>Tune.MAX_MISSILES-4:return false
	missile_cooldown=Tune.MISSILE_INTERVAL;salvo_count+=1;salvo_used=true;missiles_fired+=4
	for i in range(4):
		var store: int=[1,3,0,2][i]
		launch_queue.append({"target":chosen,"side":-1.0 if store<2 else 1.0,"internal":false,"store":store,"slot":i,"salvo":salvo_count,"delay":.015+i*Tune.SALVO_STAGGER})
	event("salvo",app.flight.position,1);app.audio.play_effect("gear_motor",-15,1.2);app.camera_rig.impulse(.12)
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
		shots.back().slot=request.slot;shots.back().salvo=request.salvo;shots.back().launch_basis=basis
		last_missile = shots.back().node
		app.audio.play_effect("gear_motor",-26,1.3)
		app.camera_rig.impulse(0.13)
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
		var command := Vector3.ZERO
		var navigating := false
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
				if enemy.id==shot.target and (enemy.health>0 or enemy.dying<1.2):
					# Proportional navigation: the seeker turns to null the
					# rotation of the line of sight. The old solver picked a
					# fresh lead point every frame and snapped the nose onto it,
					# which is what made the missile saw across the sky; this is
					# one smooth curved pursuit all the way in.
					var r: Vector3=Vector3(enemy.position)-shot.position
					var v_rel: Vector3=Vector3(enemy.velocity)-shot.velocity
					var omega: Vector3=r.cross(v_rel)/maxf(r.length_squared(),1.0)
					var closing: float=-v_rel.dot(r.normalized())
					var gain: float=Tune.MISSILE_PN_GAIN*(1.0+intent.help_amount*.25)
					command=omega.cross(shot.velocity.normalized())*(gain*maxf(closing,0.0))
					# Trim the drop while the seeker is flying, so the guidance
					# solves the intercept and not the ballistics.
					command+=Vector3.UP*9.81
					navigating=true;guided=true
					shot.last_target=enemy.position;shot.last_target_velocity=enemy.velocity
					target_distance=r.length()
					break
		elif shot.kind=="hostile_missile":
			wanted = (Vector3(shot.get("decoy",app.flight.position+app.flight.velocity*0.35))-shot.position).normalized(); guided = true
		if shot.kind=="missile" and not guided and shot.age>.18 and shot.age<2.3:
			var basis: Basis=shot.get("launch_basis",Basis.IDENTITY)
			var slot: int=shot.get("slot",0)
			var fan: float=sin(clampf((shot.age-.18)/2.0,0,1)*PI)
			wanted=(basis*Vector3([-.16,.16,-.07,.07][slot]*fan,[.06,.12,-.06,0.0][slot]*fan,-1)).normalized();guided=true
		if navigating:
			# The G limit is the turn limit, so a slow just-ignited missile
			# hauls round hard and a fast one turns wide, which is the whole
			# point of retiring the flat MISSILE_TURN_DEGREES rate. The rate cap
			# on top of it only keeps the corner readable as a missile's.
			var speed_now: float=maxf(shot.velocity.length(),1.0)
			var limit: float=minf(Tune.MISSILE_G_LIMIT*(1.0+intent.help_amount*.5)*9.81,speed_now*deg_to_rad(MISSILE_MAX_TURN_DEGREES))
			if command.length()>limit:command=command.normalized()*limit
			if shot.age<Tune.MISSILE_IGNITION_DELAY:command=Vector3.ZERO
			shot.velocity+=(command+Vector3.DOWN*9.81)*dt
		elif guided:
			var current: Vector3 = shot.velocity.normalized()
			var angle: float = current.angle_to(wanted)
			var rate: float = deg_to_rad(28 if shot.kind=="hostile_missile" else Tune.MISSILE_TURN_DEGREES*(1+intent.help_amount*.25))
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
			shot.position = previous.lerp(shot.position,hi); shot.life = 0; shot.terminated = true
			burst(shot.position,Color(1,.70,.32),1.6 if shot.kind=="cannon" else 12)
			continue
		if is_instance_valid(visuals):visuals.update_projectile(shot,dt)
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
		elif not bool(shot.get("ghost",false)):
			var struck: Dictionary={}
			var contact_point: Vector3=shot.position
			var armed: bool=shot.kind!="missile" or shot.age>=Tune.MISSILE_ARM_TIME
			for enemy: Dictionary in enemies:
				if float(enemy.health)<=0.0 and not (shot.kind=="missile" and float(enemy.dying)<.8):continue
				# The cannon term carries the forgiveness the designator beam
				# used to hand out for free, and the proximity fuse can never be
				# tighter than the plain contact test it replaces.
				var reach: float=float(enemy.hit_radius)+(5.0 if shot.kind=="missile" else 5.0+intent.help_amount*8)
				if shot.kind=="missile" and armed:reach=maxf(Tune.MISSILE_HIT_RADIUS,reach)
				var closest: Vector3=previous.lerp(shot.position,segment_parameter(enemy.position,previous,shot.position))
				if closest.distance_to(enemy.position)>=reach:continue
				struck=enemy;contact_point=closest
				break
			if not struck.is_empty():
				if float(struck.health)<=0.0:event("impact",contact_point,.7)
				shot.position=contact_point;shot.node.position=contact_point
				shot.life=0;shot.hit=true;shot.terminated=true;hit_confirm=1
				# Splash is capped so a dense flock cannot chain into a score
				# explosion off one warhead.
				var splash: Array[Dictionary]=[]
				if shot.kind=="missile":
					for other: Dictionary in enemies:
						if splash.size()>=Tune.MISSILE_SPLASH_MAX-1:break
						if int(other.id)==int(struck.id) or float(other.health)<=0.0:continue
						if Vector3(other.position).distance_to(contact_point)<Tune.MISSILE_HIT_RADIUS*1.7:splash.append(other)
				hurt_enemy(struck,shot.damage,shot.kind,contact_point)
				for other: Dictionary in splash:hurt_enemy(other,shot.damage*.6,"missile",contact_point)
				app.audio.play_effect("impact",-24,1.15)
				if shot.kind=="cannon": rounds_hit += int(shot.get("round_count",1))
				burst(contact_point,Color(1,0.66,0.27),3 if shot.kind=="cannon" else 9)
	for i in range(shots.size()-1,-1,-1):
		if shots[i].life<=0:
			if shots[i].has("decoy") and not shots[i].get("hit_player",false): missiles_evaded += 1
			# A missile that runs out of life detonates where it is. Nothing
			# this size may simply blink out in mid air.
			if shots[i].kind=="missile" and not bool(shots[i].get("terminated",false)):
				burst(shots[i].position,Color(1,.70,.32),9);event("impact",shots[i].position,1)
			free_shot(shots[i]); shots.remove_at(i)
	for i in range(enemies.size()-1,-1,-1):
		var enemy: Dictionary = enemies[i]
		# A dead goose stays in `enemies` while it falls: that corpse is the
		# only record the mission tally has that this bird was shot down rather
		# than simply gone, and GooseFlight.fall_step drives it the whole way.
		if float(enemy.health)<=0.0:
			if bool(enemy.get("corpse_done",false)) or float(enemy.dying)>CORPSE_HOLD:
				if is_instance_valid(enemy.node):enemy.node.queue_free()
				enemies.remove_at(i)
			continue
		if enemy.fade<=0 and (not engagement_enabled or enemy.get("retiring",false)):
			if is_instance_valid(enemy.node):enemy.node.queue_free()
			enemies.remove_at(i)

## A goose has no armour and no stages. One good burst and it is a falling bird.
func hurt_enemy(enemy: Dictionary,damage: float,source: String,at: Vector3) -> void:
	if enemy.health<=0:return
	enemy.health=maxf(0,enemy.health-damage);enemy.hit_flash=1.0;hit_confirm=1
	if source=="missile":event("impact",at,1)
	if enemy.health>0:return
	enemy.dying=0.0;kills+=1;combo+=1;best_combo=maxi(best_combo,combo);combo_time=Tune.STREAK_TIME
	last_reward=Tune.BASE_SCORE*mini(Tune.MAX_MULTIPLIER,1+int(combo/Tune.STREAK_STEP))
	score+=last_reward;reward_flash=1;intent.event("kill");app.audio.ping(1+minf(combo,10)*.035)
	event("kill",enemy.position,enemy.size_factor)
	app.fighter_fx.debris(enemy.position);app.audio.play_effect("explosion",-18,1)
	app.camera_rig.impulse(.15)
	# P6 owns the tumble: the corpse folds its wings and falls like a bird
	# instead of gliding on at a third of its speed while shrinking away.
	if goose_can("kill"):_goose.kill(self,enemy)
	if skein_ids.has(int(enemy.id)):
		skein_down=mini(maxi(skein_total,skein_ids.size()),skein_down+1)
		if skein_remaining()==0:
			skein_cleared=true;boss_defeated=true;event("skein_cleared",enemy.position,3)
	else:
		spawn_clock=minf(spawn_clock,.75)
	app.audio.radio.say("target_down" if kills%2 else "target_down_alt")

func update_beam(dt: float) -> void:
	beam_active=active and app.flight.airborne and gun_firing_time>0
	beam_hit_id=-1;beam_clock-=dt
	if not beam_active:return
	var basis:=Basis.from_euler(Vector3(app.flight.pitch,-app.flight.heading,-app.flight.roll))
	var start: Vector3=app.flight.position+basis*Vector3(.75,-.30,-3.8)
	var direction: Vector3=assisted_direction();var length: float=Tune.BEAM_RANGE;var hit: Dictionary={}
	for enemy: Dictionary in enemies:
		if enemy.health<=0:continue
		var along: float=(enemy.position-start).dot(direction)
		if along>0 and along<length and Vector3(enemy.position).distance_to(start+direction*along)<float(enemy.hit_radius)+4+intent.help_amount*5:
			length=along;hit=enemy
	beam_end=start+direction*length
	# The plasma cannon burns whatever it touches, on top of the rounds: it can only
	# make a goose easier to bring down, never harder.
	if not hit.is_empty():
		beam_hit_id=hit.id;hurt_enemy(hit,Tune.BEAM_DPS*dt,"beam",beam_end)
		if beam_clock<=0:
			beam_clock=.22
			if visuals!=null:visuals.add_child(ImpactFX.plasma_hit(beam_end,direction,6.0))

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

## Where along this frame's travel the round passed closest to `point`, so a
## proximity fuse can detonate at the interpolated point instead of wherever the
## missile happened to land at the end of the step.
func segment_parameter(point: Vector3, a: Vector3, b: Vector3) -> float:
	var delta := b-a
	return clampf((point-a).dot(delta)/maxf(delta.length_squared(),0.001),0,1)

# =======================================================================
# pooled tracer and motor-smoke ribbons
# =======================================================================
func trail_material(kind: String) -> StandardMaterial3D:
	if kind=="cannon":
		if cannon_trail_material==null:
			cannon_trail_material=StandardMaterial3D.new()
			cannon_trail_material.albedo_color=Color.WHITE
			cannon_trail_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			cannon_trail_material.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
			cannon_trail_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			cannon_trail_material.vertex_color_use_as_albedo=true
			cannon_trail_material.cull_mode=BaseMaterial3D.CULL_DISABLED
		return cannon_trail_material
	if missile_trail_material==null:
		missile_trail_material=StandardMaterial3D.new()
		missile_trail_material.albedo_color=Color.WHITE
		missile_trail_material.albedo_texture=load("res://assets/sourced_flight/smoke.png")
		missile_trail_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		missile_trail_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		missile_trail_material.vertex_color_use_as_albedo=true
		missile_trail_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	return missile_trail_material

func take_trail() -> MeshInstance3D:
	var node: MeshInstance3D
	if not trail_pool.is_empty():node=trail_pool.pop_back()
	else:
		node=MeshInstance3D.new();node.mesh=ImmediateMesh.new()
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	node.visible=true;node.transparency=0.0;node.position=Vector3.ZERO
	(node.mesh as ImmediateMesh).clear_surfaces()
	return node

func release_trail(node: MeshInstance3D) -> void:
	if not is_instance_valid(node):return
	(node.mesh as ImmediateMesh).clear_surfaces()
	node.visible=false;node.transparency=0.0;node.position=Vector3.ZERO
	if not trail_pool.has(node):trail_pool.append(node)

## `tracer` marks the round that carries a visible streak; `ghost` marks a round
## that is pure decoration - it does no damage and hits nothing.
func spawn_shot(at: Vector3, velocity: Vector3, kind: String, target_value: int, damage: float, variant: String = "gatling", tracer: bool = true, ghost: bool = false) -> void:
	var node: Node3D = visuals.take_projectile("missile" if kind=="hostile_missile" else kind) if is_instance_valid(visuals) else WeaponArt.projectile(kind,variant)
	if node.get_parent()==null:add_child(node)
	node.position = at
	if kind=="cannon": node.scale.z = .01
	node.look_at(at+velocity,Vector3.UP)
	var shot: Dictionary = {"node":node,"position":at,"origin":at,"velocity":velocity,"kind":kind,"target":target_value,"damage":damage,"life":Tune.MISSILE_LIFETIME if kind in ["missile","hostile_missile"] else Tune.GUN_LIFETIME,"age":0.0,"launch_speed":velocity.length(),"trail_points":[at],"trail_node":null,"trail_clock":0.0,"hit":false,"tracer":tracer,"ghost":ghost}
	if kind in ["missile","hostile_missile"] or (kind=="cannon" and tracer):
		shot.trail_node = take_trail()
	shots.append(shot)

func update_trail(shot: Dictionary) -> void:
	if not is_instance_valid(shot.get("trail_node")):return
	if elapsed-float(shot.trail_clock)<.025:return
	shot.trail_clock=elapsed
	var cannon: bool = shot.kind=="cannon"
	var points: Array = shot.trail_points
	var camera_distance: float = app.camera.global_position.distance_to(shot.position)
	# 90 points is about 1.35 km of motor smoke up close; at MAX_MISSILES 48 a
	# 128-point ribbon would be roughly 37k verts of alpha-blended geometry.
	var cap: int = 4 if cannon else (90 if camera_distance<900 else 48)
	if Vector3(points.back()).distance_to(shot.position)>7:
		points.append(shot.position)
		if points.size()>cap: points.pop_front()
	var ribbon: ImmediateMesh = shot.trail_node.mesh
	ribbon.clear_surfaces()
	if points.size()<2: return
	# A tracer fades out by about 1.2 km instead of laser-lining three
	# kilometres to the horizon.
	var reach: float = clampf(1.0-Vector3(shot.get("origin",points[0])).distance_to(shot.position)/1200.0,0.0,1.0) if cannon else 1.0
	if reach<=0.0: return
	var last: float = maxf(points.size()-1,1)
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES,trail_material(shot.kind))
	for i in range(points.size()-1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i+1]
		var age01: float = 1.0-float(i)/last          # 1 at the oldest point, 0 at the nozzle
		var width: float
		var alpha: float
		if cannon:
			width = lerpf(.42,.13,float(i)/last)
			alpha = float(i+1)/maxf(points.size(),1)*.82*reach
		else:
			# Real motor smoke: nearly clear for the first metres out of the
			# nozzle, an opaque plateau, then dissipation at the far end, and a
			# column that widens with the square root of its age. The old ramp
			# had the oldest point both widest AND most transparent.
			width = lerpf(.35,3.6,sqrt(age01))
			alpha = .58*smoothstep(0.0,.10,age01)*(1.0-smoothstep(.74,1.0,age01))
		var side: Vector3 = (b-a).normalized().cross((app.camera.global_position-a).normalized()).normalized()
		if side.length()<0.1: side = Vector3.RIGHT
		side *= width
		for vertex: Array in [[a-side,Vector2(0,0)],[a+side,Vector2(1,0)],[b-side,Vector2(0,1)],[b-side,Vector2(0,1)],[a+side,Vector2(1,0)],[b+side,Vector2(1,1)]]:
			ribbon.surface_set_color(Color(1,.72,.35,alpha) if cannon else Color(.32,.39,.43,alpha) if app.camera.global_position.y<shot.position.y else Color(.72,.82,.9,alpha))
			ribbon.surface_set_uv(vertex[1])
			ribbon.surface_add_vertex(vertex[0])
	ribbon.surface_end()
	if shot.kind=="missile":
		if trail_core_material==null:trail_core_material=WeaponArt.emissive(Color(.25,.72,1),3.0,.7)
		ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES,trail_core_material)
		for i in range(maxi(0,points.size()-12),points.size()-1):
			var a: Vector3=points[i];var b: Vector3=points[i+1]
			var width: float=clampf(app.camera.global_position.distance_to(b)*.00065,.18,1.1)
			var side: Vector3=(b-a).cross(app.camera.global_position-a).normalized()*width
			for v: Vector3 in [a-side,a+side,b-side,b-side,a+side,b+side]:ribbon.surface_add_vertex(v)
		ribbon.surface_end()

func free_shot(shot: Dictionary) -> void:
	if is_instance_valid(visuals):visuals.release_projectile(shot.node,shot.kind)
	else:shot.node.queue_free()
	if shot.kind=="missile" and not shot.get("hit",false) and shot.target>=0:intent.event("miss")
	if is_instance_valid(shot.get("trail_node")):
		if shot.kind=="missile": detached_trails.append({"node":shot.trail_node,"life":Tune.MISSILE_SMOKE_TIME})
		else: release_trail(shot.trail_node)

func update_detached_trails(dt: float) -> void:
	for i in range(detached_trails.size()-1,-1,-1):
		var trail: Dictionary = detached_trails[i]; trail.life -= dt
		if trail.life<=0: release_trail(trail.node); detached_trails.remove_at(i)
		else:
			trail.node.transparency = 1-trail.life/Tune.MISSILE_SMOKE_TIME
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
