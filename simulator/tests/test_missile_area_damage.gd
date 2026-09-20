extends SceneTree
var app:Node
var failures:Array[String]=[]
var checks:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func bird(at:Vector3)->Dictionary:
	app.combat.spawn_contact();var e:Dictionary=app.combat.enemies.back();e.position=at;e.node.position=at;e.health=100;e.max_health=100;e.fade=1;e.retiring=false;return e
func run()->void:
	app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","alpine");root.add_child(app);app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	app.start_flight("combat");app.flight.spawn_airborne(Vector3(0,3000,0),180);app.combat.spawn_clock=999
	var at:=Vector3(0,3000,-500)
	var direct:=bird(at);var near:=bird(at+Vector3(45,0,0));var edge:=bird(at+Vector3(115,0,0));var outside:=bird(at+Vector3(121,0,0))
	app.combat.spawn_shot(at,Vector3(0,0,-180),"missile",direct.id,180);var shot:Dictionary=app.combat.shots.back()
	var hull:float=app.combat.hull
	app.combat.detonate_missile(shot,direct.id)
	check(direct.health==0 and near.health==0 and app.combat.kills==2,"A missile clears its direct target and nearby geese with real area damage")
	check(edge.health>0 and edge.health<100,"Blast damage falls off toward its edge")
	check(outside.health==100,"Targets beyond the120m blast radius are unaffected")
	check(app.combat.hull==hull,"Friendly area damage does not punish the pilot")
	var before:float=edge.health;var score:int=app.combat.score
	app.combat.detonate_missile(shot,direct.id)
	check(edge.health==before and app.combat.score==score and app.combat.kills==2,"The same missile cannot detonate or score twice")
	app.combat.spawn_shot(at,Vector3(0,0,-180),"missile",edge.id,180);app.combat.detonate_missile(app.combat.shots.back())
	check(app.combat.kills==3 and outside.health==100,"Overlapping blasts finish survivors without recounting dead geese")
	app.start_flight("combat");app.flight.spawn_airborne(Vector3(0,3000,0),180);app.combat.spawn_clock=999
	var dead:=bird(Vector3(0,3000,-600));var assigned:=bird(Vector3(40,3000,-700));var free:=bird(Vector3(-45,3000,-750))
	app.combat.spawn_shot(Vector3(0,3000,0),Vector3(0,0,-180),"missile",dead.id,180);shot=app.combat.shots.back()
	app.combat.spawn_shot(Vector3(2,3000,0),Vector3(0,0,-180),"missile",assigned.id,180)
	dead.health=0;app.combat._retarget_missile(shot)
	check(shot.target==free.id,"A missile whose target died switches to an unassigned living goose")
	check(app.combat.visuals.has_method("missile_blast"),"Area damage has a dedicated world-space blast effect")
	app.queue_free();await process_frame
	print("MISSILE AREA DAMAGE: ",checks," checks / ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
