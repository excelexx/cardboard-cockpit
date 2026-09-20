extends SceneTree
var failures: Array[String]=[]
func check(ok: bool, message: String="Regression check failed") -> void:
	if not ok:failures.append(message);push_error(message)
class ScriptedBadge extends BadgeLink:
	var next_press:=0
	func poll() -> void:
		connected=true;pressed=next_press;mask=next_press;released=0;next_press=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	app.on_action("keyboard_play");app.flight.spawn_airborne(Vector3(15000,400,-13000),300)
	app.combat.score=700;app.combat.kills=4;app.combat.fire_gun()
	app.badge.close();app.badge=ScriptedBadge.new();app.badge.next_press=1<<1
	app._physics_process(.016)
	check(app.landing_started and app.mission.phase=="approach","Synthetic badge B starts landing")
	check(app.flight.gear and app.flight.flaps==2 and app.copilot,"One press deploys gear/flaps and guidance")
	check(not app.combat.active and app.combat.gun_firing_time<=0,"Landing safes weapons")
	check(app.combat.score==700 and app.combat.kills==4,"Landing preserves the sortie score")
	var at: Vector3=app.flight.position;app.begin_landing()
	check(app.flight.position==at,"Repeated landing request does not reset approach")
	for i in range(60*40):
		app._physics_process(1.0/60)
		if app.mode=="results":break
	check(app.flight.contact=="landed" and app.flight.speed==0 and app.mode=="results","Assisted approach lands and brakes to a stop")
	app.on_action("keyboard_play");check(not app.landing_started,"Replay clears landing state")
	app.queue_free();await process_frame;print("BADGE LANDING: PASS");quit(0 if failures.is_empty() else 1)
