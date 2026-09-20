extends SceneTree
var app: Node3D
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if not value: failures.append(label); push_error("BALLISTICS FAIL: "+label)
func run():
	app = load("res://scenes/main.tscn").instantiate(); app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	app.start_flight("combat")
	app.cockpit = false
	check(app.fighter_fx.plasma_models.size()==2 and app.fighter_fx.plasma_muzzles.size()==2,"Both mounted plasma emitters have physical muzzle anchors")
	app.combat.fire_primary();app.combat.update_beam(.016);app.fighter_fx.update_plasma(.016)
	check(app.combat.beam_active and app.combat.beam_ends.size()==2,"Primary immediately activates two forward plasma beams")
	var left: Vector3=app.fighter_fx.plasma_muzzle_position(Vector3.ZERO,0)
	var right: Vector3=app.fighter_fx.plasma_muzzle_position(Vector3.ZERO,1)
	check(left.distance_to(right)>1,"Plasma originates from two distinct mounted emitters")
	app.combat.gun_firing_time=0;app.combat.update_beam(.1)
	check(not app.combat.beam_active and app.combat.rounds_fired==0,"Release stops plasma without leaving bullet fire")
	app.start_flight("combat")
	var start:=Vector3(0,500,-3500)
	app.combat.spawn_shot(start,Vector3(0,0,-180),"missile",-1,135)
	var shot: Dictionary=app.combat.shots.back()
	app.combat.update_shots(.05)
	check(shot.velocity.length()<190,"Missile separates before its motor accelerates")
	for i in range(30):app.combat.update_shots(1.0/60)
	check(shot.velocity.length()>200,"Missile motor accelerates after its ignition delay")
	app.start_flight("combat");app.combat.spawn_contact()
	var enemy: Dictionary=app.combat.enemies[0]
	enemy.position=start+Vector3(0,0,-50);enemy.health=100
	app.combat.spawn_shot(start,Vector3(0,0,-5000),"missile",-1,135)
	app.combat.update_shots(1.0/60)
	check(app.combat.kills==1,"Swept missile collision detects a target crossed between frames")
	app.start_flight("combat")
	app.combat.spawn_shot(Vector3(0,5,-3500),Vector3(0,-600,-100),"missile",-1,135)
	app.combat.update_shots(.03)
	check(app.combat.shots.is_empty() and app.combat.visuals.active_blast_count()==1,"Missiles hit terrain and produce an impact")
	app.start_flight("combat");app.combat.spawn_clock=999;app.fire_guard=0
	var press:=InputEventKey.new();press.keycode=KEY_SPACE;press.physical_keycode=KEY_SPACE;press.pressed=true
	Input.parse_input_event(press);Input.flush_buffered_events()
	for i in range(240):app._physics_process(1.0/60)
	press=press.duplicate();press.pressed=false;Input.parse_input_event(press);Input.flush_buffered_events()
	check(app.combat.primary_used and app.combat.beam_active and app.combat.rounds_fired==0,"Holding Space sustains only the dual plasma weapon")
	for i in range(30):app._physics_process(1.0/60)
	check(app.combat.gun_firing_time<=0 and not app.combat.beam_active,"Releasing Space stops both beams after the short release tail")
	app.start_flight("combat"); app.combat.spawn_contact(); enemy = app.combat.enemies[0]
	enemy.position = app.flight.position+Vector3(35,0,-500); app.combat.target_id = enemy.id
	var initial: Vector3 = app.combat.assisted_direction()
	app.combat.update_aim(1.0/60)
	check(initial.angle_to(app.combat.assisted_direction())<deg_to_rad(6),"Magnetic aim moves smoothly instead of snapping instantly")
	for i in range(24): app.combat.update_aim(1.0/120)
	check(app.combat.assisted_direction().angle_to((enemy.position-app.flight.position).normalized())<deg_to_rad(3),"Magnetic aim settles quickly onto a visible target")
	var samples: Array[Vector2] = [Vector2(2400,-4800),Vector2(-4400,-8100),Vector2(960,-6500),Vector2(130,-13800)]
	for at in samples:
		var cached: float = app.world.ground_height(at.x,at.y)
		var columns: int = app.world._height_columns; app.world._height_columns = 0
		var direct: float = app.world.ground_height(at.x,at.y); app.world._height_columns = columns
		check(absf(cached-direct)<.001,"Cached collision terrain matches the rendered heightfield")
	for path in ["res://assets/environment/alpine-fir.png","res://assets/environment/alpine-fir-b.png","res://assets/environment/alpine-granite.png","res://assets/fighter/spectre-satin.png"]:
		var texture: Texture2D = load(path)
		check(texture.get_image().has_mipmaps(),"Runtime 3D texture includes filtered distance levels: "+path)
	print("BALLISTICS: ",checks," checks / ",failures.size()," failures")
	app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
