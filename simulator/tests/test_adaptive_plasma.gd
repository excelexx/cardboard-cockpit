extends SceneTree
const Tune=preload("res://data/balance.gd")
var app: Node
var checks:=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fresh() -> void:
	app.start_flight("combat");app.flight.spawn_airborne(Vector3(0,3000,0),180);app.apply_aircraft_pose();app.combat.spawn_clock=999;app.fire_guard=0
func bird(offset: Vector3,health: float=100) -> Dictionary:
	app.combat.spawn_contact();var enemy: Dictionary=app.combat.enemies.back()
	enemy.position=app.flight.position+offset;enemy.node.position=enemy.position;enemy.course=Vector3(0,0,-5);enemy.right=Vector3.ZERO;enemy.fade=1;enemy.health=health;enemy.max_health=health
	return enemy
func run() -> void:
	app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","alpine");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	fresh();var a: Dictionary=bird(Vector3(-30,0,-500));var b: Dictionary=bird(Vector3(30,0,-500))
	check(app.aircraft.find_child("CG26",true,false)==null and app.aircraft.find_child("GatlingRotor",true,false)==null,"No live minigun remains")
	check(not app.combat.has_method("fire_gun") and not app.combat.has_method("fire_missile"),"The pilot has no minigun or conscious missile firing API")
	app.combat.fire_primary();app.combat.update_beam(.1)
	check(app.combat.beam_target_ids[0]!=app.combat.beam_target_ids[1] and app.combat.beam_target_ids.has(a.id) and app.combat.beam_target_ids.has(b.id),"Two visible geese receive separate plasma beams")
	app.combat.visuals.draw_plasma()
	for index in range(2):
		var bloom=app.combat.visuals.plasma_impact_blooms[index]
		check(bloom.visible and bloom.global_position.is_equal_approx(app.combat.beam_ends[index]),"A plasma impact bloom stays attached to its actual hit point")
	check(is_equal_approx(a.health,90) and is_equal_approx(b.health,90),"Split beams damage both real targets")
	app.combat.hurt_enemy(a,1000,"beam",a.position);app.combat.update_beam(.1)
	check(app.combat.beam_target_ids[0]==b.id and app.combat.beam_target_ids[1]==b.id and is_equal_approx(b.health,70),"A lone remaining goose receives both cannons at doubled combined damage")
	app.combat.gun_firing_time=0;app.combat.update_beam(.1)
	check(not app.combat.beam_active and app.combat.beam_target_ids==[-1,-1],"Releasing primary stops both beams and clears target assignments")
	fresh();a=bird(Vector3(0,0,-450),400);b=bird(Vector3(60,0,-550))
	app.combat.fire_primary();app.combat.update_beam(.1)
	check(app.combat.beam_target_ids==[int(a.id),int(a.id)] and is_equal_approx(a.health,380) and b.health==100,"Both cannons focus a tougher central target")
	fresh();a=bird(Vector3(-30,0,-500));b=bird(Vector3(30,0,-500));var behind: Dictionary=bird(Vector3(0,0,400))
	app.combat.fire_primary();app.combat.update_beam(0)
	var stable: Array=app.combat.beam_target_ids.duplicate()
	for i in range(20):a.position.x+=.005;app.combat.update_beam(0)
	check(app.combat.beam_target_ids==stable,"Small target movements do not cause beam assignment flicker")
	check(not app.combat.beam_target_ids.has(behind.id),"Beams never target geese behind the aircraft")
	app.combat.aim_strength=0;app.combat.assist=false;app.combat.update_beam(.1)
	check(a.health==100 and b.health==100,"Zero aim assistance preserves forward manual rays rather than hidden auto-target damage")
	fresh()
	for i in range(12):bird(Vector3((i-3.5)*30,0,-700-i*35))
	app.combat.fire_primary();app.combat.update_beam(0)
	app.combat.update_swarm_missiles()
	check(app.combat.swarm_active and app.combat.launch_queue.size()==4,"A large visible flock automatically schedules four missiles")
	var ids: Array=[]
	for request: Dictionary in app.combat.launch_queue:ids.append(request.target)
	check(ids[0]!=ids[1] and not app.combat.beam_target_ids.has(ids[0]) and not app.combat.beam_target_ids.has(ids[1]),"The missile burst selects distinct targets that plasma is not already handling")
	app.combat.update_swarm_missiles();check(app.combat.launch_queue.size()==4,"Repeated render calls cannot bypass the one-second pair cadence")
	app.combat.update_launches(.06)
	check(app.combat.missiles_fired==4,"All four automatic missiles launch together")
	for i in range(54):app.combat.tick(1.0/60)
	check(app.combat.missiles_fired==4,"No extra pair launches before one second")
	for i in range(12):app.combat.tick(1.0/60)
	check(app.combat.missiles_fired==8,"A sustained swarm receives the next burst after one second")
	var reserved: Dictionary={};var duplicates:=false
	for shot: Dictionary in app.combat.shots:
		if shot.kind=="missile":
			if reserved.has(shot.target):duplicates=true
			reserved[shot.target]=true
	check(not duplicates,"Automatic launches do not waste multiple in-flight missiles on the same goose")
	for i in range(3,app.combat.enemies.size()):app.combat.enemies[i].health=0
	var launched: int=app.combat.missiles_fired
	app.combat.missile_cooldown=0;app.combat.update_swarm_missiles();app.combat.update_launches(.1)
	check(not app.combat.swarm_active and app.combat.missiles_fired==launched and app.combat.launch_queue.is_empty(),"Automatic support stops once only a few geese remain")
	fresh()
	for i in range(8):bird(Vector3((i-2.5)*35,0,-800))
	app.combat.update_swarm_missiles()
	check(not app.combat.beam_active and app.combat.launch_queue.size()==4,"Swarm support does not require the pilot to hold the plasma trigger")
	app.combat.engagement_enabled=false;app.combat.update_launches(.2)
	check(app.combat.missiles_fired==0,"Leaving combat cancels pending autonomous launches")
	fresh()
	var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_T;app._input(key)
	var mouse:=InputEventMouseButton.new();mouse.pressed=true;mouse.button_index=MOUSE_BUTTON_RIGHT;app._input(mouse)
	check(app.combat.launch_queue.is_empty() and app.combat.missiles_fired==0,"T and right mouse are no longer missile controls")
	app.queue_free();await process_frame
	print("ADAPTIVE PLASMA: ",checks," checks / ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
