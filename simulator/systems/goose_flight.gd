extends RefCounted
class_name GooseFlight
## Everything a goose does between spawning and hitting the water.
##
## systems/combat.gd owns the contact Dictionary and the target loop; this file
## owns the bird. It is deliberately a pile of static functions over that same
## Dictionary so combat.gd never has to reopen for a plumage note again:
##
##   GooseFlight.update(combat, enemy, dt)   per living contact, per frame
##   GooseFlight.kill(combat, enemy)         once, the frame it dies
##   GooseFlight.update_falling(combat, dt)  once per frame, drives the corpses
##   GooseFlight.formation_slot(rank)        a slot on the V, leader-relative
##   GooseFlight.skein_course(combat)        the flock's own heading
##
## PLAYABILITY GUARD. "Realism" here means how the bird MOVES and LOOKS. None of
## it may make a goose harder to shoot. Concretely, in this file:
##   * the startled reaction is COSMETIC ONLY - see REACTION_DISPLACEMENT_METRES.
##     A frightened goose flaps harder and rolls; it never moves off the track
##     the shooter has already led, so a burst aimed a moment ago still lands.
##   * the weave is SMALLER than the code it replaces (0.18 of cruise against a
##     flat 16 m/s), so contacts wander less across the sight than they used to.
##   * hit_radius, health and model scale are not touched here. They live in
##     data/balance.gd and systems/combat.gd.
##   * banking, the wingbeat, the body bob, the wing flex and the death tumble
##     are attitude and animation. None of them displace enemy.position.
const Tune = preload("res://data/balance.gd")
const Model = preload("res://systems/goose_model.gd")

# --- wingbeat -----------------------------------------------------------
## Canada geese beat at roughly 3-4 Hz. The old code sampled a global clock at
## 4.2 rad/s, which is 0.67 Hz: two thirds of one beat per second.
const FLAP_HZ := 3.4
const FLAP_REFERENCE_SPEED := 20.0
const FLAP_RATE_MIN := 0.75
const FLAP_RATE_MAX := 1.30
## The stroke is not a sine. The power (down) stroke takes 38% of the cycle and
## the recovery takes the rest; that asymmetry is most of what separates a bird
## from a flapping cardboard cut-out.
const DOWNSTROKE_FRACTION := 0.38
const FLAP_AMPLITUDE := 0.55            # rad, about 32 deg each way
const FLAP_SWEEP := 0.24                # wrist fold on the recovery stroke
const FLAP_FLEX_GAIN := 0.026           # tip lag per rad/s of wing rate
const FLAP_FLEX_LIMIT := 0.40
const BODY_BOB := 0.085                 # model units; the body rides the beat
const RANK_PHASE_STEP := 0.12           # the beat travels outward from the point bird
## Flap, then hold. Alternation is the other half of a live bird.
const GLIDE_HOLD_ANGLE := 0.08
const GLIDE_GAP_MIN := 2.5
const GLIDE_GAP_MAX := 5.0
const GLIDE_LENGTH_MIN := 1.0
const GLIDE_LENGTH_MAX := 2.0
const GLIDE_BLEND_RATE := 5.0

# --- attitude -----------------------------------------------------------
## look_at(..., Vector3.UP) forces the roll basis to world up, which pins bank
## to exactly zero through every turn the motifs exist to create. Bank instead
## comes from the lateral acceleration the bird is actually pulling.
const BANK_LIMIT := 0.9                 # rad
const BANK_RESPONSE := 4.0
const ACCEL_FILTER := 8.0
const BANK_FADE_START := 400.0
const BANK_FADE_SPAN := 500.0
const BANK_FADE_FLOOR := 0.35
const BODY_ALPHA := 0.06                # a little nose-up in level flight

# --- course -------------------------------------------------------------
## Fractions of the bird's own cruise, not the old absolute 16 m/s and 5 m/s,
## which at a goose's speed was a violent sideways slalom.
const WEAVE_FRACTION := 0.18
const VERTICAL_FRACTION := 0.10
const RETREAT_LATERAL := 12.0
const RETREAT_RISE := 8.0
const FORMATION_GAIN := 0.35
const FORMATION_RESPONSE := 1.6
const FORMATION_SPEED_MIN := 12.0
const FORMATION_SPEED_MAX := 32.0
## Only the skein crabs; a lone contact ignores the wind so the older routes
## behave exactly as they did.
const WIND_COUPLING := 0.5
const SKEIN_CROSS_DEGREES := 112.0
const SKEIN_CROSS_SPREAD := 7.0
const SKEIN_DESCENT := 0.06

# --- death --------------------------------------------------------------
const FALL_GRAVITY := 9.81
## 9.81 / 38^2: about 38 m/s terminal with the wings folded.
const FALL_DRAG := 0.0068
const FALL_TIMEOUT := 4.0
const FALL_FOLD_RATE := 9.0
const FALL_FOLD_ANGLE := 1.15
const FALL_FOLD_SWEEP := 0.85
const MAX_FALLING := 6

# --- reaction -----------------------------------------------------------
## Canada geese show a mean 4.1 s alert-time benefit to an approaching aircraft
## (Blackwell et al. 2012), so a skein realistically does see the jet coming.
## A bird pulling about 1 g sideways displaces roughly 5 m in that second and
## cannot actually dodge - and a goose that moved even that far after the
## player had already led it would be a difficulty change, not a realism one.
## So the reaction is posture and wingbeat ONLY. This constant is the entire
## positional budget of the reaction system and it is deliberately ZERO; it
## exists so a reviewer can see the decision instead of guessing at it.
const REACTION_DISPLACEMENT_METRES := 0.0
const ALERT_DISTANCE := 1000.0
const ALERT_CLOSURE := 40.0
const BREAK_DISTANCE := 380.0
const REACTION_LAG := 0.9
const ALERT_FLAP_SCALE := 1.12
const BREAK_FLAP_SCALE := 1.45
const SCATTER_FLAP_SCALE := 1.70
const BREAK_ROLL := 0.35
const SCATTER_ROLL := 0.60
## Offered to target_intent/combat so a lock cannot drop because a bird rolled.
## Widening the retain cone can only ever make holding a target easier.
const BREAK_RETAIN_BONUS_DEGREES := 6.0

# --- retirement ---------------------------------------------------------
const PLAIN_RETIRE_AGE := 24.0
const PLAIN_RETIRE_DISTANCE := 2500.0
const PLAIN_RETIRE_BEHIND := 90.0

# =======================================================================
# per-frame update
# =======================================================================
static func update(c: Node, enemy: Dictionary, dt: float) -> void:
	var node: Node3D = enemy.get("node")
	if node==null or not is_instance_valid(node): return
	_ensure(c,enemy,node)
	if float(enemy.get("health",1.0))<=0.0:
		fall_step(c,enemy,dt)
		return
	var flight = c.app.flight
	var to_plane: Vector3 = flight.position-enemy.position
	var distance: float = to_plane.length()
	var reaction: Dictionary = _reaction(c,enemy,dt,to_plane,distance)

	# --- where the bird is going -------------------------------------
	var lateral: Vector3 = enemy.get("right",Vector3.RIGHT)
	var course: Vector3 = enemy.get("course",Vector3.ZERO)
	var cruise: float = course.length()
	var phase: float = float(enemy.get("phase",0.0))
	var age: float = float(enemy.get("age",0.0))
	var velocity: Vector3 = course \
		+lateral*sin(age*0.55+phase)*cruise*WEAVE_FRACTION \
		+Vector3.UP*cos(age*0.40+phase)*cruise*VERTICAL_FRACTION
	velocity = _formation_steer(c,enemy,velocity,dt)
	var engaged: bool = bool(c.engagement_enabled) if "engagement_enabled" in c else true
	var present: bool = engaged and not bool(enemy.get("retiring",false))
	if not present:
		velocity += lateral*(RETREAT_LATERAL if int(enemy.get("id",0))%2 else -RETREAT_LATERAL)+Vector3.UP*RETREAT_RISE

	# --- integrate ----------------------------------------------------
	var previous: Vector3 = enemy.get("prev_velocity",velocity)
	var drift: Vector3 = Vector3.ZERO
	if _in_skein(c,enemy):
		drift = Vector3(flight.wind.x,0.0,flight.wind.z)*WIND_COUPLING
	enemy.position += (velocity+drift)*dt
	enemy.position.y = maxf(enemy.position.y,c.app.world.ground_height(enemy.position.x,enemy.position.z)+Tune.CONTACT_FLIGHT_CLEARANCE)
	enemy.velocity = velocity
	enemy.prev_velocity = velocity

	# --- bank ---------------------------------------------------------
	var forward_dir: Vector3 = velocity.normalized() if velocity.length()>0.05 else -node.transform.basis.z
	var right_dir: Vector3 = forward_dir.cross(Vector3.UP)
	right_dir = right_dir.normalized() if right_dir.length()>0.001 else Vector3.RIGHT
	var raw: float = (velocity-previous).dot(right_dir)/maxf(dt,0.0001)
	var filtered: float = lerpf(float(enemy.get("lat_accel",0.0)),raw,1.0-exp(-dt*ACCEL_FILTER))
	enemy.lat_accel = filtered
	var fade_bank: float = clampf(1.0-(distance-BANK_FADE_START)/BANK_FADE_SPAN,BANK_FADE_FLOOR,1.0)
	var wanted_bank: float = clampf(atan2(filtered,FALL_GRAVITY),-BANK_LIMIT,BANK_LIMIT)*fade_bank
	wanted_bank = clampf(wanted_bank+float(reaction.roll),-BANK_LIMIT,BANK_LIMIT)
	enemy.bank = lerpf(float(enemy.get("bank",0.0)),wanted_bank,1.0-exp(-dt*BANK_RESPONSE))

	# --- wingbeat -----------------------------------------------------
	var angle: float = _beat(enemy,dt,cruise,float(reaction.flap))
	var scale: float = float(enemy.get("model_scale",1.0))
	_pose(node,enemy,forward_dir,float(enemy.bank),angle,scale,dt)
	_skin(enemy)

	# --- level of detail and fade ------------------------------------
	_select_lod(enemy,node,distance,dt)
	var fade: float = float(enemy.get("fade",1.0))
	if fade<1.0 or age<1.5:
		var transparency: float = clampf(1.0-fade,0.0,1.0)
		for geometry: GeometryInstance3D in enemy.get("geometry",[]):
			if is_instance_valid(geometry): geometry.transparency = transparency

## The stroke shape. u is the cycle position in 0..1; -1 is wings fully up,
## +1 is wings fully down. Public so tests can measure the duty cycle.
static func stroke(u: float) -> float:
	var t: float = fposmod(u,1.0)
	if t<DOWNSTROKE_FRACTION: return -cos(PI*t/DOWNSTROKE_FRACTION)
	return cos(PI*(t-DOWNSTROKE_FRACTION)/(1.0-DOWNSTROKE_FRACTION))

static func flap_rate(speed: float) -> float:
	return FLAP_HZ*clampf(speed/FLAP_REFERENCE_SPEED,FLAP_RATE_MIN,FLAP_RATE_MAX)

static func _beat(enemy: Dictionary, dt: float, cruise: float, flap_scale: float) -> float:
	# Glide holds, on a per-bird deterministic clock so nothing here touches the
	# CombatDirector's rng and perturbs the spawn sequence.
	var gliding: bool = bool(enemy.get("gliding",false))
	var timer: float = float(enemy.get("glide_timer",-1.0))
	var phase: float = float(enemy.get("phase",0.0))
	if timer<0.0: timer = lerpf(GLIDE_GAP_MIN,GLIDE_GAP_MAX,fposmod(phase*0.7131,1.0))
	timer -= dt
	if timer<=0.0:
		gliding = not gliding
		var roll: float = fposmod(phase*0.7131+float(enemy.get("age",0.0))*0.37,1.0)
		timer = lerpf(GLIDE_LENGTH_MIN,GLIDE_LENGTH_MAX,roll) if gliding else lerpf(GLIDE_GAP_MIN,GLIDE_GAP_MAX,roll)
	enemy.gliding = gliding; enemy.glide_timer = timer
	var blend: float = lerpf(float(enemy.get("glide_blend",0.0)),1.0 if gliding else 0.0,1.0-exp(-dt*GLIDE_BLEND_RATE))
	enemy.glide_blend = blend
	# The accumulator is per bird, so pausing, slow motion and time scaling all
	# behave and two birds never beat in lockstep by accident.
	var rate: float = flap_rate(cruise)*flap_scale*(1.0-blend*0.85)
	enemy.flap_phase = fposmod(float(enemy.get("flap_phase",0.0))+dt*rate*TAU,TAU)
	enemy.flap_rate = rate
	var ripple: float = float(enemy.get("rank",0))*RANK_PHASE_STEP
	var u: float = fposmod(float(enemy.flap_phase)-ripple,TAU)/TAU
	enemy.beat_u = u
	var s: float = stroke(u)
	return lerpf(FLAP_AMPLITUDE*s,GLIDE_HOLD_ANGLE,blend)

## Attitude, wings and body bob. Nothing here reads or writes enemy.position.
static func _pose(node: Node3D, enemy: Dictionary, forward_dir: Vector3, bank: float, angle: float, scale: float, dt: float) -> void:
	var back: Vector3 = -forward_dir
	var x_axis: Vector3 = Vector3.UP.cross(back)
	if x_axis.length()<0.0001: x_axis = Vector3.RIGHT.cross(back)
	x_axis = x_axis.normalized()
	var y_axis: Vector3 = back.cross(x_axis)
	var rolled := Basis(x_axis.rotated(forward_dir,bank),y_axis.rotated(forward_dir,bank),back)
	rolled = rolled.rotated(rolled.x,-BODY_ALPHA)
	# Basis(x,y,z) is unit length, so the contact's model scale has to be put
	# back or every bird would snap to 1:1 the first time it banked.
	var beat: float = stroke(float(enemy.get("beat_u",0.0)))
	var bob: float = beat*BODY_BOB*scale
	node.transform = Transform3D(rolled.scaled(Vector3.ONE*scale),Vector3(enemy.position)+Vector3.UP*bob)
	var left: Node3D = enemy.get("wing_l")
	var right: Node3D = enemy.get("wing_r")
	if left==null or not is_instance_valid(left): return
	var previous_angle: float = float(enemy.get("wing_angle",angle))
	var rate: float = (angle-previous_angle)/maxf(dt,0.0001)
	enemy.wing_angle = angle
	# The recovery stroke folds at the wrist; a wing that only rotated rigidly
	# at the shoulder reads as a paper aeroplane.
	var sweep: float = FLAP_SWEEP*maxf(-beat,0.0)
	left.rotation = Vector3(0.0,sweep,angle)
	if right!=null and is_instance_valid(right): right.rotation = Vector3(0.0,-sweep,-angle)
	# Spanwise flex: the tips lag the roots by the wing's own angular rate.
	var flex: float = clampf(rate*FLAP_FLEX_GAIN,-FLAP_FLEX_LIMIT,FLAP_FLEX_LIMIT)
	for feathers: GeometryInstance3D in enemy.get("wing_geometry",[]):
		if is_instance_valid(feathers): feathers.set_instance_shader_parameter("flex",flex)

## Feathers shed, armour does not break: damage is an instance parameter on the
## shared material, never a per-bird material duplicate.
static func _skin(enemy: Dictionary) -> void:
	var maximum: float = maxf(float(enemy.get("max_health",1.0)),0.001)
	var damage: float = clampf(1.0-float(enemy.get("health",maximum))/maximum,0.0,1.0)
	if absf(damage-float(enemy.get("damage_shown",-1.0)))<0.02: return
	enemy.damage_shown = damage
	for geometry: GeometryInstance3D in enemy.get("geometry",[]):
		if is_instance_valid(geometry): geometry.set_instance_shader_parameter("damage",damage)

static func _select_lod(enemy: Dictionary, node: Node3D, distance: float, dt: float) -> void:
	var clock: float = float(enemy.get("lod_clock",0.0))-dt
	if clock>0.0:
		enemy.lod_clock = clock
		return
	enemy.lod_clock = 1.0
	var present: int = int(enemy.get("lod",Model.current_lod(node)))
	var wanted: int = Model.lod_for_distance(distance,present)
	if wanted==present: return
	Model.set_lod(node,wanted)
	enemy.lod = wanted
	enemy.geometry = _collect(node)
	enemy.wing_geometry = _wing_geometry(enemy,node)
	enemy.damage_shown = -1.0

# =======================================================================
# formation
# =======================================================================
## Slot for one rank on the V, in the leader's frame: +x right, +y up,
## +z behind. Rank 0 is the point bird. Odd ranks take the right arm, even
## ranks the left, so the skein fills outward in pairs and stays symmetric.
static func formation_slot(rank: int) -> Vector3:
	if rank<=0: return Vector3.ZERO
	var step: int = int((rank+1)/2)
	var arm: float = 1.0 if rank%2==1 else -1.0
	var back: float = float(step)*Tune.SKEIN_SLOT_BACK
	var side: float = back*tan(deg_to_rad(Tune.SKEIN_V_DEGREES*0.5))
	var rise: float = float(step)*Tune.SKEIN_SLOT_RISE
	# Deterministic wobble, mirrored across the two arms: a real skein is never
	# a drawn ruler, but the shape still has to read as a V.
	var wobble: float = sin(float(step)*12.9898)*Tune.SKEIN_SLOT_JITTER
	var lift: float = cos(float(step)*7.2331)*Tune.SKEIN_SLOT_JITTER*0.5
	return Vector3(arm*(side+wobble),rise+lift,back+wobble*0.6)

## The flock's own heading: a crossing course at goose cruise, never the
## player's vector and never scaled off the player's speed.
static func skein_course(c: Node) -> Vector3:
	var flight = c.app.flight
	var spread: float = float(int(c.get("next_id") if "next_id" in c else 0)%5-2)*SKEIN_CROSS_SPREAD
	var heading: float = float(flight.heading)+deg_to_rad(SKEIN_CROSS_DEGREES+spread)
	var direction := Vector3(sin(heading),-SKEIN_DESCENT,-cos(heading)).normalized()
	return direction*lerpf(Tune.CONTACT_MIN_SPEED,Tune.CONTACT_MAX_SPEED,0.5)

static func _in_skein(c: Node, enemy: Dictionary) -> bool:
	if not ("skein_ids" in c): return false
	var ids = c.skein_ids
	return ids is Array and ids.has(int(enemy.get("id",-1)))

static func _skein_basis(leader: Dictionary) -> Basis:
	var course: Vector3 = leader.get("course",Vector3.FORWARD)
	var flat := Vector3(course.x,0.0,course.z)
	if flat.length()<0.01: flat = Vector3.FORWARD
	flat = flat.normalized()
	var right: Vector3 = flat.cross(Vector3.UP)
	right = right.normalized() if right.length()>0.001 else Vector3.RIGHT
	return Basis(right,Vector3.UP,-flat)

## The point bird, promoting the closest follower if it has been shot down.
static func _leader(c: Node, enemy: Dictionary) -> Dictionary:
	if not _in_skein(c,enemy): return {}
	var best: Dictionary = {}
	var best_rank: int = 1<<30
	for other: Dictionary in c.enemies:
		if float(other.get("health",0.0))<=0.0 or not _in_skein(c,other): continue
		var rank: int = int(other.get("rank",0))
		if rank==0: return other
		if rank<best_rank: best_rank = rank; best = other
	if not best.is_empty():
		# The leader died: the next bird up takes the point without the whole
		# formation jumping, by carrying its old slot as the anchor offset.
		best.lead_offset = formation_slot(best_rank)
		best.rank = 0
		best.lead_clock = 0.0
		return best
	return {}

static func _rotate_lead(c: Node, leader: Dictionary, dt: float) -> void:
	var clock: float = float(leader.get("lead_clock",0.0))+dt
	if clock<Tune.SKEIN_LEAD_ROTATE:
		leader.lead_clock = clock
		return
	leader.lead_clock = 0.0
	var follower: Dictionary = {}
	var best_rank: int = 1<<30
	for other: Dictionary in c.enemies:
		if float(other.get("health",0.0))<=0.0 or not _in_skein(c,other): continue
		var rank: int = int(other.get("rank",0))
		if rank>0 and rank<best_rank: best_rank = rank; follower = other
	if follower.is_empty(): return
	# The tired point bird drops into the follower's slot and the follower takes
	# the point. lead_offset keeps the anchor where it was, so nobody else in
	# the V sees the hand-over at all.
	follower.lead_offset = formation_slot(best_rank)
	follower.rank = 0
	follower.lead_clock = 0.0
	leader.rank = best_rank
	leader.lead_offset = Vector3.ZERO

static func _formation_steer(c: Node, enemy: Dictionary, velocity: Vector3, dt: float) -> Vector3:
	if not _in_skein(c,enemy): return velocity
	var leader: Dictionary = _leader(c,enemy)
	if leader.is_empty(): return velocity
	if int(leader.get("id",-1))==int(enemy.get("id",-2)):
		_rotate_lead(c,enemy,dt)
		return velocity
	var basis := _skein_basis(leader)
	var anchor: Vector3 = Vector3(leader.position)-basis*Vector3(leader.get("lead_offset",Vector3.ZERO))
	var slot: Vector3 = anchor+basis*formation_slot(int(enemy.get("rank",0)))
	var command: Vector3 = velocity+(slot-enemy.position)*FORMATION_GAIN
	var speed: float = command.length()
	if speed>0.01: command = command.normalized()*clampf(speed,FORMATION_SPEED_MIN,FORMATION_SPEED_MAX)
	return velocity.lerp(command,1.0-exp(-dt*FORMATION_RESPONSE))

# =======================================================================
# reaction - posture only, see REACTION_DISPLACEMENT_METRES
# =======================================================================
static func _scatter_allowed(c: Node, enemy: Dictionary) -> bool:
	return _in_skein(c,enemy)

static func _reaction(c: Node, enemy: Dictionary, dt: float, to_plane: Vector3, distance: float) -> Dictionary:
	var state: String = str(enemy.get("reaction_state","calm"))
	var clock: float = float(enemy.get("reaction_clock",0.0))
	var closure: float = 0.0
	if distance>0.5:
		closure = (Vector3(c.app.flight.velocity)-Vector3(enemy.get("velocity",Vector3.ZERO))).dot(-to_plane/distance)
	var closing: bool = closure>ALERT_CLOSURE and distance<ALERT_DISTANCE
	if not closing:
		clock = maxf(0.0,clock-dt*1.5)
		if clock<=0.0: state = "calm"
	else:
		clock += dt
		if state=="calm": state = "alert"
		if state=="alert" and clock>=REACTION_LAG and distance<BREAK_DISTANCE:
			state = "scatter" if _scatter_allowed(c,enemy) else "break"
			clock = 0.0
	enemy.reaction_state = state
	enemy.reaction_clock = clock
	var flap: float = 1.0
	var roll: float = 0.0
	if state=="alert": flap = ALERT_FLAP_SCALE
	elif state=="break" or state=="scatter":
		flap = SCATTER_FLAP_SCALE if state=="scatter" else BREAK_FLAP_SCALE
		var amount: float = SCATTER_ROLL if state=="scatter" else BREAK_ROLL
		# A roll the bird holds, keyed off its own id, so twelve birds in a
		# skein do not all heel over the same way. Attitude only: the velocity
		# above is untouched, so the round the player already led still hits.
		roll = amount*signf(sin(float(int(enemy.get("id",0))*2.399)))
	return {"flap":flap,"roll":roll,"state":state}

## Offered to target_intent.retain_degrees: while a bird is rolling away the
## lock cone may widen, never narrow. Nothing in this package requires it.
static func retain_bonus_degrees(c: Node, enemy: Dictionary) -> float:
	if enemy.is_empty(): return 0.0
	var state: String = str(enemy.get("reaction_state","calm"))
	return BREAK_RETAIN_BONUS_DEGREES if (state=="break" or state=="scatter") else 0.0

# =======================================================================
# death
# =======================================================================
## Called once, the frame the bird's health reaches zero. The old path skipped
## the physics block entirely: the corpse kept flying forward at 30% speed with
## no gravity while shrinking to 14% of its size. Nothing here touches scale.
static func kill(c: Node, enemy: Dictionary) -> void:
	if bool(enemy.get("falling_started",false)): return
	enemy.falling_started = true
	enemy.health = 0.0
	enemy.dying = maxf(0.0,float(enemy.get("dying",0.0)))
	enemy.fall_clock = 0.0
	var node: Node3D = enemy.get("node")
	if node!=null and is_instance_valid(node):
		_ensure(c,enemy,node)
		enemy.fall_euler = node.rotation
		Model.set_lod(node,2)
		enemy.lod = 2
		enemy.geometry = _collect(node)
		enemy.wing_geometry = _wing_geometry(enemy,node)
		enemy.damage_shown = -1.0
	# Deterministic tumble, so a replay of the same sortie kills the same way
	# and nothing here perturbs the CombatDirector's spawn rng.
	var seed_value: float = float(enemy.get("phase",0.0))+float(int(enemy.get("id",0)))*0.618
	enemy.spin = Vector3(sin(seed_value*3.1)*4.0,cos(seed_value*5.7)*3.0,sin(seed_value*9.3+1.7)*6.0)
	var falling = c.falling if "falling" in c else null
	if falling is Array:
		for i in range(c.enemies.size()-1,-1,-1):
			if int(c.enemies[i].get("id",-1))==int(enemy.get("id",-2)):
				c.enemies.remove_at(i); break
		falling.append(enemy)
		while falling.size()>MAX_FALLING:
			var oldest: Dictionary = falling.pop_front()
			var stale: Node3D = oldest.get("node")
			if stale!=null and is_instance_valid(stale): stale.queue_free()

## Drives every corpse. Safe to call when combat.gd has no `falling` array yet:
## update() also routes a dead contact left in `enemies` through fall_step.
static func update_falling(c: Node, dt: float) -> void:
	var falling = c.falling if "falling" in c else null
	if not (falling is Array): return
	for i in range(falling.size()-1,-1,-1):
		var corpse: Dictionary = falling[i]
		if not fall_step(c,corpse,dt):
			var node: Node3D = corpse.get("node")
			if node!=null and is_instance_valid(node): node.queue_free()
			falling.remove_at(i)

## Drop the whole corpse list, for combat.reset(). Leaving it populated across a
## replay is exactly what test_spectral_run's pool-cleanliness check catches.
static func clear_falling(c: Node) -> void:
	var falling = c.falling if "falling" in c else null
	if not (falling is Array): return
	for corpse: Dictionary in falling:
		var node: Node3D = corpse.get("node")
		if node!=null and is_instance_valid(node): node.queue_free()
	falling.clear()

## One frame of ballistic fall. Returns false when the bird is finished.
static func fall_step(c: Node, enemy: Dictionary, dt: float) -> bool:
	var node: Node3D = enemy.get("node")
	if node==null or not is_instance_valid(node): return false
	if not bool(enemy.get("falling_started",false)): kill(c,enemy)
	enemy.dying = float(enemy.get("dying",0.0))+dt
	enemy.fall_clock = float(enemy.get("fall_clock",0.0))+dt
	var velocity: Vector3 = enemy.get("velocity",Vector3.ZERO)
	velocity += (Vector3.DOWN*FALL_GRAVITY-velocity*velocity.length()*FALL_DRAG)*dt
	enemy.velocity = velocity
	enemy.position += velocity*dt
	node.position = enemy.position
	var euler: Vector3 = Vector3(enemy.get("fall_euler",node.rotation))+Vector3(enemy.get("spin",Vector3.ZERO))*dt
	enemy.fall_euler = euler
	node.rotation = euler
	# The wings fold over a quarter second: the silhouette collapses instead of
	# gliding away on a flat pair of boards.
	var blend: float = 1.0-exp(-dt*FALL_FOLD_RATE)
	var left: Node3D = enemy.get("wing_l")
	var right: Node3D = enemy.get("wing_r")
	if left!=null and is_instance_valid(left):
		left.rotation = Vector3(0.0,lerpf(left.rotation.y,FALL_FOLD_SWEEP,blend),lerpf(left.rotation.z,-FALL_FOLD_ANGLE,blend))
	if right!=null and is_instance_valid(right):
		right.rotation = Vector3(0.0,lerpf(right.rotation.y,-FALL_FOLD_SWEEP,blend),lerpf(right.rotation.z,FALL_FOLD_ANGLE,blend))
	var ground: float = c.app.world.ground_height(enemy.position.x,enemy.position.z)
	if enemy.position.y<=ground+1.0:
		enemy.position.y = ground
		if c.has_method("event"): c.event("impact",enemy.position,1.0)
		return false
	return float(enemy.fall_clock)<FALL_TIMEOUT

# =======================================================================
# retirement, offered to combat.gd
# =======================================================================
## Skein members get a generous leash so the final act cannot delete itself
## mid-pass; everything else keeps the old rule, because combat.gd is reused by
## the unbounded patrol and coast routes where a never-retired enemies array
## leaks nodes across a long session.
static func should_retire(c: Node, enemy: Dictionary, distance: float) -> bool:
	var age: float = float(enemy.get("age",0.0))
	if _in_skein(c,enemy): return age>Tune.SKEIN_DESPAWN_AGE or distance>Tune.SKEIN_DESPAWN_DISTANCE
	var behind: float = Vector3(c.forward()).dot(enemy.position-c.app.flight.position)
	return age>PLAIN_RETIRE_AGE or distance>PLAIN_RETIRE_DISTANCE or behind<-PLAIN_RETIRE_BEHIND

# =======================================================================
# housekeeping
# =======================================================================
static func _collect(node: Node3D) -> Array:
	var out: Array = []
	for geometry: Node in [node.get_node_or_null("Body"),node.get_node_or_null("WingL/Feathers"),node.get_node_or_null("WingR/Feathers")]:
		if geometry is GeometryInstance3D: out.append(geometry)
	if out.is_empty():
		for geometry: Node in node.find_children("*","GeometryInstance3D",true,false): out.append(geometry)
	return out

static func _wing_geometry(enemy: Dictionary, node: Node3D) -> Array:
	var out: Array = []
	for key: String in ["wing_l","wing_r"]:
		var pivot: Node3D = enemy.get(key)
		if pivot==null or not is_instance_valid(pivot): continue
		for child: Node in pivot.get_children():
			if child is GeometryInstance3D: out.append(child)
	if out.is_empty():
		for path: String in ["WingL/Feathers","WingR/Feathers"]:
			var geometry: Node = node.get_node_or_null(path)
			if geometry is GeometryInstance3D: out.append(geometry)
	return out

## Fills in anything combat.gd's contact Dictionary has not supplied. P2 seeds
## most of these as literal keys at spawn; doing it here as well keeps this
## module usable from a bare harness and from either side of that landing.
static func _ensure(c: Node, enemy: Dictionary, node: Node3D) -> void:
	if enemy.has("goose_ready"): return
	enemy.goose_ready = true
	if not enemy.has("flap_phase"): enemy.flap_phase = fposmod(float(enemy.get("phase",0.0)),TAU)
	if not enemy.has("bank"): enemy.bank = 0.0
	if not enemy.has("rank"): enemy.rank = 0
	if not enemy.has("spin"): enemy.spin = Vector3.ZERO
	if not enemy.has("reaction_state"): enemy.reaction_state = "calm"
	if not enemy.has("reaction_clock"): enemy.reaction_clock = 0.0
	if not enemy.has("prev_velocity"): enemy.prev_velocity = enemy.get("course",Vector3.ZERO)
	if not enemy.has("lead_offset"): enemy.lead_offset = Vector3.ZERO
	if not enemy.has("lead_clock"): enemy.lead_clock = 0.0
	if not enemy.has("falling_started"): enemy.falling_started = false
	enemy.lat_accel = float(enemy.get("lat_accel",0.0))
	enemy.lod = int(enemy.get("lod",Model.current_lod(node)))
	enemy.lod_clock = float(enemy.get("lod_clock",0.0))
	enemy.damage_shown = float(enemy.get("damage_shown",-1.0))
	# The contact's scale is read ONCE, here, before anything writes a basis:
	# Basis(x,y,z) is unit length and would otherwise silently reset the bird
	# to 1:1 the first time it banked.
	if not enemy.has("model_scale"): enemy.model_scale = maxf(node.scale.x,0.0001)
	if enemy.get("wing_l")==null: enemy.wing_l = node.get_node_or_null("WingL")
	if enemy.get("wing_r")==null: enemy.wing_r = node.get_node_or_null("WingR")
	var geometry = enemy.get("geometry")
	if not (geometry is Array) or (geometry as Array).is_empty(): enemy.geometry = _collect(node)
	enemy.wing_geometry = _wing_geometry(enemy,node)
