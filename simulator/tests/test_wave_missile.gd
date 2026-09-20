extends "res://tests/test_adaptive_plasma.gd"
func wave(number:int,size:int)->void:
	fresh();app.combat.managed_mission=true
	app.mission.cinematic=true;app.mission.phase="skein";app.mission.wave_number=number;app.mission.wave_size=size;app.mission.skein_pending=0;app.mission.wave_ids.clear()
	for i in range(size):
		var enemy: Dictionary=bird(Vector3([100.0,-90.0,90.0][i],0,-2200-i*400))
		app.mission.wave_ids.append(int(enemy.id))
func run()->void:
	app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","alpine");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	wave(1,2);app.combat.update_swarm_missiles();app.combat.update_launches(.1)
	check(app.combat.missiles_fired==0 and app.combat.launch_queue.is_empty(),"Two-goose waves do not launch a missile")
	wave(2,3);app.combat.update_swarm_missiles()
	check(app.combat.launch_queue.size()==1,"Three-goose wave automatically queues one missile")
	var reserved:int=app.combat.launch_queue[0].target
	for i in range(10):app.combat.update_swarm_missiles()
	check(app.combat.launch_queue.size()==1,"Repeated frames cannot queue duplicate missiles for one wave")
	app.combat.update_launches(.06)
	check(app.combat.missiles_fired==1 and app.combat.shots.size()==1,"Exactly one missile launches without holding fire")
	app.combat.fire_primary();app.combat.update_beam(0)
	check(not app.combat.beam_target_ids.has(reserved),"Plasma leaves the reserved goose for the automatic missile")
	app.combat.gun_firing_time=0
	for i in range(540):app.combat.tick(1.0/60)
	check(app.combat.kills==1,"Automatic missile destroys exactly one goose within the wave interval")
	check(app.combat.enemies.size()==2 and app.combat.enemies.all(func(e:Dictionary)->bool:return e.health==100),"Other two geese remain unharmed for the pilot")
	check(app.combat.missiles_fired==1 and app.combat.launch_queue.is_empty(),"No second missile is launched during the same wave")
	print("WAVE MISSILE kills=",app.combat.kills," fired=",app.combat.missiles_fired)
	wave(4,3);app.combat.wave_missile_number=2;app.combat.update_swarm_missiles()
	check(app.combat.launch_queue.size()==1,"A new three-goose wave gets its own missile")
	app.combat.active=false;app.combat.engagement_enabled=false;app.combat.update_launches(.1)
	check(app.combat.launch_queue.is_empty() and app.combat.missiles_fired==0,"Landing cancels a pending automatic launch")
	wave(5,3);app.combat.update_swarm_missiles();app.combat.update_launches(.06)
	app.mission.wave_number=6;app.combat.update_shots(.016)
	check(app.combat.shots.is_empty(),"An old wave missile cannot attack the next wave")
	wave(6,3)
	for enemy:Dictionary in app.combat.enemies:enemy.position=app.flight.position+Vector3(0,0,-500)
	var target:Dictionary=app.combat.enemies[0]
	app.combat.detonate_missile({"wave_missile":true,"position":target.position,"life":1.0},int(target.id))
	check(app.combat.kills==1 and app.combat.enemies[1].health==100 and app.combat.enemies[2].health==100,"Wave missile cannot kill or damage neighbours through splash")
	wave(8,3)
	for i in range(540):app.combat.fire_primary();app.combat.tick(1.0/60)
	check(app.combat.kills==3 and app.combat.missiles_fired==1,"Continuous plasma clears the other two while one missile handles its reserved goose")
	app.queue_free();await process_frame
	print("WAVE MISSILE: ",checks," checks / ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
