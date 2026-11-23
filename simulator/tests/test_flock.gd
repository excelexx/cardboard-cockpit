extends SceneTree
## P6 acceptance: the flock is affordable, the birds fly and beat like birds,
## they bank into their turns, they die ballistically, and none of it makes a
## goose harder to shoot.
##
##   Godot --headless --path simulator --script tests/test_flock.gd
const Model = preload("res://systems/goose_model.gd")
const Tune = preload("res://data/balance.gd")

## The exact surface systems/goose_flight.gd touches on the CombatDirector.
## Standing it up here keeps the acceptance run independent of whichever half
## of P2's skein API has landed, and documents the contract P2 has to satisfy.
class Flock extends Node:
	var app: Node
	var enemies: Array[Dictionary] = []
	var falling: Array[Dictionary] = []
	var skein_ids: Array[int] = []
	var engagement_enabled := true
	var next_id := 0
	var events := 0
	func forward() -> Vector3: return app.flight.forward().normalized()
	func event(_kind: String, _at: Vector3 = Vector3.ZERO, _weight: float = 1.0) -> void: events += 1

var app: Node3D
var checks := 0
var failures: Array[String] = []
var notes: Array[String] = []

func _initialize(): call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error("FLOCK FAIL: "+label)

func triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += int(index.size()/3) if index.size()>0 else int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()/3)
	return total

func bird_triangles(root: Node3D) -> int:
	var total := 0
	for node: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false): total += triangles(node.mesh)
	return total

func contact(id: int, at: Vector3, course: Vector3, rank: int = 0) -> Dictionary:
	var node: Node3D = Model.create()
	node.scale = Vector3.ONE*Tune.CONTACT_MODEL_SCALE
	node.position = at
	app.combat.add_child(node)
	return {"id":id,"node":node,"position":at,"health":Tune.CONTACT_HEALTH,"max_health":Tune.CONTACT_HEALTH,
		"kind":"normal","size_factor":1.0,"hit_radius":Tune.CONTACT_HIT_RADIUS,"velocity":course,"course":course,
		"right":Vector3.ZERO,"age":0.0,"phase":float(id)*0.91,"fade":1.0,"retiring":false,"rank":rank,
		"hit_flash":0.0,"dying":-1.0,"near_passed":false}

## Circular concentration of the flock's wingbeat phases: 0 is twelve unrelated
## clocks, 1 is perfect lockstep.
func concentration(group: Flock) -> float:
	var x := 0.0; var y := 0.0
	for bird: Dictionary in group.enemies:
		x += cos(float(bird.get("flap_phase",0.0))); y += sin(float(bird.get("flap_phase",0.0)))
	return Vector2(x,y).length()/maxf(float(group.enemies.size()),1.0)

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	app.start_flight("combat"); app.flight.position.y = 900

	# ---------------------------------------------------------------- (a)
	Model.prewarm()
	var first := Time.get_ticks_usec()
	var alpha: Node3D = Model.create()
	var second := Time.get_ticks_usec()
	var beta: Node3D = Model.create()
	var third := Time.get_ticks_usec()
	var warm_cost := float(third-second)/1000.0
	notes.append("prewarm(all three LODs) %.2f ms" % Model.build_milliseconds())
	notes.append("create() warm %.4f ms (first-after-prewarm %.4f ms)" % [warm_cost,float(second-first)/1000.0])
	check(warm_cost<0.5,"A warm GooseModel.create() costs under 0.5 ms")
	var body_a: MeshInstance3D = alpha.get_node("Body")
	var body_b: MeshInstance3D = beta.get_node("Body")
	var wing_a: MeshInstance3D = alpha.get_node("WingL/Feathers")
	var wing_b: MeshInstance3D = beta.get_node("WingR/Feathers")
	check(body_a.material_override==body_b.material_override and wing_a.material_override==wing_b.material_override,
		"Two birds share one body material and one wing material, so the flock batches")
	check(body_a.material_override!=wing_a.material_override,"Body and wing keep their own shared material, two in total")
	check(body_a.mesh==body_b.mesh and wing_a.mesh==alpha.get_node("WingL/Feathers").mesh,
		"Meshes are shared instances, not per-bird rebuilds")

	# ---------------------------------------------------------------- (b)
	var lod_tris: Array[int] = []
	for level in range(3):
		var bird: Node3D = Model.create(level)
		lod_tris.append(bird_triangles(bird))
		var cost := Time.get_ticks_usec()
		for i in range(50): Model.create(level).queue_free()
		notes.append("LOD%d %d tris/bird, create() %.4f ms" % [level,lod_tris[level],float(Time.get_ticks_usec()-cost)/50000.0])
		bird.queue_free()
	check(triangles(Model._body_lod[2])<400 and lod_tris[2]<400,"An LOD2 mesh stays under 400 triangles")
	check(triangles(Model._body_lod[1])<1400 and lod_tris[1]<1400,"An LOD1 mesh stays under 1400 triangles")
	check(lod_tris[0]>4000 and lod_tris[0]<9000,"LOD0 keeps the hero bird's detail")
	notes.append("12-bird skein peak %d triangles (4 x LOD0 + 8 x LOD1)" % (4*lod_tris[0]+8*lod_tris[1]))

	# LOD ladder and hysteresis
	check(Model.lod_for_distance(600.0,0)==1 and Model.lod_for_distance(450.0,1)==1 and Model.lod_for_distance(410.0,1)==0,
		"LOD1 takes over past 500 m and does not hand back until 420 m")
	check(Model.lod_for_distance(1300.0,1)==2 and Model.lod_for_distance(1100.0,2)==2 and Model.lod_for_distance(1000.0,2)==1,
		"LOD2 takes over past 1200 m with the same hysteresis")
	Model.set_lod(alpha,1)
	check(alpha.get_node("Body").cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"A demoted bird stops casting shadows")
	Model.set_lod(alpha,0)
	check(alpha.get_node("Body").cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"The hero bird casts a shadow again")
	alpha.queue_free(); beta.queue_free()

	# ---------------------------------------------------------------- (c)
	var flock := Flock.new(); flock.app = app
	var queue: Array[int] = []
	for rank in range(Tune.SKEIN_SIZE): queue.append(rank)
	var frames := 0
	var worst_frame := 0.0
	var worst_batch := 0
	while not queue.is_empty():
		var started := Time.get_ticks_usec()
		var made := 0
		while made<Tune.SKEIN_SPAWN_PER_FRAME and not queue.is_empty():
			var rank: int = queue.pop_front()
			var slot: Vector3 = GooseFlight.formation_slot(rank)
			flock.enemies.append(contact(rank,app.flight.position+app.flight.forward()*1500+Vector3.UP*140+slot,GooseFlight.skein_course(flock),rank))
			flock.skein_ids.append(rank)
			made += 1
		worst_batch = maxi(worst_batch,made)
		worst_frame = maxf(worst_frame,float(Time.get_ticks_usec()-started)/1000.0)
		frames += 1
	notes.append("spawn_skein(%d) drained over %d frames, worst frame %.3f ms" % [Tune.SKEIN_SIZE,frames,worst_frame])
	check(frames>=6 and worst_batch<=2,"A twelve-bird skein spawns across at least six frames, never more than two a frame")

	# ---------------------------------------------------------------- (d)
	var symmetric := true
	var arm_ordered := true
	var angles: Array[float] = []
	for rank in range(1,Tune.SKEIN_SIZE):
		var slot: Vector3 = GooseFlight.formation_slot(rank)
		angles.append(rad_to_deg(atan2(absf(slot.x),slot.z))*2.0)
		if rank%2==0:
			var mirror: Vector3 = GooseFlight.formation_slot(rank-1)
			if absf(slot.x+mirror.x)>0.001 or absf(slot.z-mirror.z)>0.001: symmetric = false
		if rank>2:
			var ahead: Vector3 = GooseFlight.formation_slot(rank-2)
			if slot.z<=ahead.z or absf(slot.x)<=absf(ahead.x): arm_ordered = false
	var widest := 0.0
	for a in angles: widest = maxf(widest,absf(a-Tune.SKEIN_V_DEGREES))
	check(symmetric,"The two arms of the V mirror each other exactly about the leader")
	check(arm_ordered,"Each rank sits further back and further out than the one ahead of it on its arm")
	check(widest<5.0,"Every slot sits on a %.0f degree V within 5 degrees (worst %.1f)" % [Tune.SKEIN_V_DEGREES,widest])
	check(GooseFlight.formation_slot(0)==Vector3.ZERO,"Rank zero is the point bird")

	# A control flock with no V: same birds, same clocks, never locked.
	var loose := Flock.new(); loose.app = app
	for rank in range(Tune.SKEIN_SIZE):
		loose.enemies.append(contact(500+rank,app.flight.position+Vector3(float(rank)*60.0,0,-700),GooseFlight.skein_course(flock)))

	# ------------------------------------------- the point bird tires and drops back
	var lead_before: int = -1
	for bird: Dictionary in flock.enemies:
		if int(bird.rank)==0: lead_before = int(bird.id)
	var anchor_before := Vector3.ZERO
	var anchor_after := Vector3.ZERO
	var swapped: int = -1
	for i in range(int(Tune.SKEIN_LEAD_ROTATE*90.0)):
		if i==int(Tune.SKEIN_LEAD_ROTATE*60.0)-30:
			for bird: Dictionary in flock.enemies: anchor_before += Vector3(bird.position)
			anchor_before /= float(flock.enemies.size())
		for bird: Dictionary in flock.enemies:
			bird.age = float(bird.age)+1.0/60.0
			GooseFlight.update(flock,bird,1.0/60.0)
		for bird: Dictionary in loose.enemies:
			bird.age = float(bird.age)+1.0/60.0
			GooseFlight.update(loose,bird,1.0/60.0)
	for bird: Dictionary in flock.enemies:
		anchor_after += Vector3(bird.position)
		if int(bird.rank)==0: swapped = int(bird.id)
	anchor_after /= float(flock.enemies.size())
	var drift: float = (anchor_after-anchor_before).length()-GooseFlight.skein_course(flock).length()*(Tune.SKEIN_LEAD_ROTATE*0.5+0.5)
	notes.append("lead rotation: id %d -> id %d, centroid drift beyond cruise %.1f m" % [lead_before,swapped,drift])
	check(swapped!=lead_before and swapped>=0,"The point bird tires and hands the lead to the bird behind it")
	check(absf(drift)<45.0,"The hand-over does not jolt the whole V: the formation anchor stays put")
	check(concentration(loose)<0.45,"Twelve birds with no formation keep twelve unrelated clocks (R=%.2f)" % concentration(loose))
	check(concentration(flock)>0.60 and concentration(flock)>concentration(loose)+0.3,
		"Birds holding a V slot settle onto the leader's beat (R=%.2f against %.2f unformed)" % [concentration(flock),concentration(loose)])
	notes.append("wingbeat phase concentration: %.2f in the V, %.2f with no formation" % [concentration(flock),concentration(loose)])

	# ---------------------------------------------------------------- (h)
	var course: Vector3 = GooseFlight.skein_course(flock)
	var alignment: float = absf(course.normalized().dot(app.flight.forward().normalized()))
	notes.append("skein_course %.1f m/s, %.1f deg off the player's nose" % [course.length(),rad_to_deg(course.angle_to(app.flight.forward()))])
	check(course.length()>=Tune.CONTACT_MIN_SPEED and course.length()<=Tune.CONTACT_MAX_SPEED,"The skein cruises at goose speed, not at the jet's")
	check(alignment<0.9,"The skein crosses the route instead of flying down the player's vector")

	# ---------------------------------------------------------------- (f)
	app.flight.velocity = Vector3.ZERO
	var turner: Dictionary = contact(900,app.flight.position+Vector3(0,0,-140),app.flight.forward()*20.0)
	var solo := Flock.new(); solo.app = app
	solo.enemies.append(turner)
	for i in range(360):
		turner.course = turner.course.rotated(Vector3.UP,0.4/60.0)
		GooseFlight.update(solo,turner,1.0/60.0)
		app.flight.position = turner.position+Vector3(0,0,140)
	var bank_degrees: float = absf(rad_to_deg(float(turner.bank)))
	notes.append("20 m/s bird in a 0.4 rad/s turn banks %.1f deg" % bank_degrees)
	check(bank_degrees>30.0 and bank_degrees<45.0,"A 20 m/s bird holding 0.4 rad/s banks between 30 and 45 degrees")
	check(absf(turner.node.scale.x-Tune.CONTACT_MODEL_SCALE)<0.001,"Banking does not silently reset the contact's model scale")
	check(turner.node.transform.basis.y.normalized().dot(Vector3.UP)<0.9,"The wings are not pinned level by look_at(..., Vector3.UP)")

	# ---------------------------------------------------------------- (g)
	var beater: Dictionary = contact(901,app.flight.position+Vector3(0,0,-300),app.flight.forward()*20.0)
	solo.enemies.append(beater)
	beater.gliding = false; beater.glide_timer = 9999.0
	GooseFlight.update(solo,beater,1.0/240.0)
	beater.gliding = false; beater.glide_timer = 9999.0
	var travelled := 0.0
	var previous: float = float(beater.get("flap_phase",0.0))
	for i in range(240):
		GooseFlight.update(solo,beater,1.0/240.0)
		travelled += fposmod(float(beater.flap_phase)-previous,TAU)
		previous = float(beater.flap_phase)
	notes.append("wingbeat %.2f Hz at 20 m/s cruise" % (travelled/TAU))
	check(travelled/TAU>3.0 and travelled/TAU<4.0,"The wingbeat runs at 3-4 Hz, not the old 0.67 Hz")
	var frozen: float = float(beater.flap_phase)
	for i in range(60): GooseFlight.update(solo,beater,0.0)
	check(is_equal_approx(frozen,float(beater.flap_phase)),"The beat rides a per-bird accumulator, so a zero timestep does not advance it")
	var other: Dictionary = contact(902,app.flight.position+Vector3(40,0,-300),app.flight.forward()*20.0)
	solo.enemies.append(other)
	GooseFlight.update(solo,other,1.0/240.0)
	check(absf(float(other.flap_phase)-float(beater.flap_phase))>0.05,"Two birds do not beat in lockstep off one global clock")
	var rising := 0
	for i in range(1000):
		if GooseFlight.stroke(float(i+1)/1000.0)>GooseFlight.stroke(float(i)/1000.0): rising += 1
	check(absf(float(rising)/1000.0-0.38)<0.01,"The downstroke occupies 38%% of the cycle (measured %.3f)" % (float(rising)/1000.0))
	var amplitude: float = absf(float((beater.wing_l as Node3D).rotation.z))
	check(GooseFlight.FLAP_AMPLITUDE>0.45,"Stroke amplitude is about 32 degrees, not the old 13.8")
	check(amplitude<=GooseFlight.FLAP_AMPLITUDE+0.001,"The wing never exceeds the commanded amplitude (%.3f rad)" % amplitude)

	# -------------------------------------------- reaction is cosmetic only
	var calm: Dictionary = contact(910,app.flight.position+Vector3(0,0,-260),app.flight.forward()*20.0)
	var scared: Dictionary = contact(911,app.flight.position+Vector3(0,0,-260),app.flight.forward()*20.0)
	scared.phase = calm.phase
	var quiet := Flock.new(); quiet.app = app; quiet.enemies.append(calm)
	var charged := Flock.new(); charged.app = app; charged.enemies.append(scared)
	var keep: Vector3 = app.flight.position
	for i in range(300):
		app.flight.velocity = Vector3.ZERO
		GooseFlight.update(quiet,calm,1.0/60.0)
		app.flight.velocity = app.flight.forward()*320.0
		GooseFlight.update(charged,scared,1.0/60.0)
		app.flight.position = keep
	notes.append("reaction states: calm bird %s, charged bird %s" % [calm.reaction_state,scared.reaction_state])
	check(scared.reaction_state!="calm","A goose does notice a jet closing on it")
	check(calm.position.distance_to(scared.position)<0.0005,"The startled reaction never moves the bird: same track, same lead, same burst")
	check(GooseFlight.REACTION_DISPLACEMENT_METRES==0.0,"The reaction's positional budget is zero by construction")

	# ---------------------------------------------------------------- (e)
	var corpses := Flock.new(); corpses.app = app
	var victims: Array[Dictionary] = []
	for i in range(10):
		var bird: Dictionary = contact(1000+i,app.flight.position+Vector3(float(i)*30.0,0,-400),app.flight.forward()*20.0)
		corpses.enemies.append(bird); victims.append(bird)
		GooseFlight.update(corpses,bird,1.0/60.0)
	var spawn_scale: Vector3 = victims[0].node.scale
	var cap := 0
	for bird in victims:
		bird.health = 0.0
		GooseFlight.kill(corpses,bird)
		cap = maxi(cap,corpses.falling.size())
	check(cap<=6,"The falling list is capped at six corpses (peak %d)" % cap)
	check(corpses.enemies.size()==0,"A dead bird leaves `enemies`, so target_intent never scans a corpse")
	var tracked: Dictionary = corpses.falling.back()
	check(Model.current_lod(tracked.node)>=1,"A corpse is demoted off the hero LOD the moment it dies")
	var heights: Array[float] = []
	var elapsed := 0.0
	var landed := false
	for i in range(600):
		GooseFlight.update_falling(corpses,1.0/60.0)
		elapsed += 1.0/60.0
		if elapsed>0.3 and not landed: heights.append(float(tracked.position.y))
		if corpses.falling.is_empty(): landed = true; break
	var monotonic := true
	for i in range(1,heights.size()):
		if heights[i]>heights[i-1]+0.0001: monotonic = false
	notes.append("fall: %d frames to the ground, %.1f m/s at impact, %.1f m fallen" % [heights.size(),float(tracked.velocity.length()),heights[0]-heights[heights.size()-1] if heights.size()>1 else 0.0])
	check(monotonic and heights.size()>5,"A killed bird falls: y decreases every frame after 0.3 s")
	check(landed and corpses.falling.is_empty(),"Every corpse is released at ground contact, none are left resident")
	check(tracked.node==null or not is_instance_valid(tracked.node) or tracked.node.scale.is_equal_approx(spawn_scale),
		"The corpse keeps its spawn scale: no shrinking to 14% in mid-air")
	check(float(tracked.velocity.length())>25.0 and float(tracked.velocity.length())<50.0,
		"Terminal velocity lands near 38 m/s, not an unbounded free fall")
	GooseFlight.clear_falling(corpses)
	check(corpses.falling.is_empty(),"clear_falling drains the corpse list for combat.reset()")

	# ------------------------------------- the real contact dictionary still works
	app.start_flight("combat"); app.flight.position.y = 900
	app.combat.spawn_clock = 999; app.combat.spawn_contact()
	var live: Dictionary = app.combat.enemies[0]
	live.course = app.flight.forward()*20.0
	var before: Vector3 = live.position
	for i in range(120): GooseFlight.update(app.combat,live,1.0/60.0)
	check(live.position.distance_to(before)>10.0 and live.has("bank") and live.has("flap_phase"),
		"GooseFlight drives a contact built by the live combat.spawn_contact()")
	check(is_instance_valid(live.node) and absf(live.node.scale.x-Tune.CONTACT_MODEL_SCALE)<0.01,
		"CONTACT_MODEL_SCALE survives a full update pass")
	check(Tune.CONTACT_MODEL_SCALE>=3.0 and float(live.hit_radius)>=22.0,"Model scale and hit radius are untouched by this package")

	for note in notes: print("FLOCK NOTE  ",note)
	print("FLOCK: ",checks," checks / ",failures.size()," failures")
	for failure in failures: printerr(failure)
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
