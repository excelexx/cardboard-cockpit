extends SceneTree
## Mission-only fixtures: no main scene, renderer, devices, keyboard or real flight.
const Mission = preload("res://systems/demo_mission.gd")
const Flight = preload("res://systems/flight_dynamics.gd")

class FakeRadio extends RefCounted:
	func say(_line: String, _priority: int = 0) -> void: pass
class FakeAudio extends RefCounted:
	var radio := FakeRadio.new()
class FakeWorld extends Node:
	func ground_height(_x: float, _z: float) -> float: return 0.0
	func update_showcase(_position: Vector3, _act: int, _intensity: float, _dt: float) -> void: pass
class FakeCombat extends CombatDirector:
	func _ready() -> void: pass
	func event(_kind: String, _at: Vector3 = Vector3.ZERO, _weight: float = 1.0) -> void: pass
	func announce(text: String) -> void: message = text
	func spawn_contact(kind: String = "normal") -> void:
		var node := Node3D.new();add_child(node)
		enemies.append({"id":next_id,"node":node,"position":Vector3.ZERO,"health":100.0,
			"kind":kind,"course":Vector3.FORWARD*19,"velocity":Vector3.FORWARD*19,
			"retiring":false,"age":0.0,"fade":1.0})
		next_id += 1
class Harness extends Node:
	var cockpit := false
	var route_id := "sf"
	var flight := Flight.new()
	var combat: FakeCombat
	var mission: DemoMission
	var audio := FakeAudio.new()
	var world := FakeWorld.new()
	var demo_auto_fire := false
	var copilot := false
	var landing_started := false
	var landing_calls := 0
	var result_calls := 0
	func begin_landing() -> void: landing_calls += 1
	func finish_sortie(_success: bool, _reason: String) -> void: result_calls += 1
	func approach_controls() -> Vector3: return Vector3.ZERO

var app: Harness
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message);push_error("ENDLESS WAVES: "+message)
func setup() -> void:
	app=Harness.new();root.add_child(app);app.add_child(app.world)
	app.combat=FakeCombat.new();app.combat.app=app;app.add_child(app.combat)
	app.mission=Mission.new();app.mission.app=app
	app.mission.reset(true)
func fill_wave() -> void:
	for frame in range(24):
		if app.mission.skein_pending==0:break
		app.flight.position+=app.flight.forward()*(app.mission.stream_gap+1)
		app.mission.tick(maxf(.01,app.mission.next_spawn_at-app.mission.clock))
func start_first_wave() -> void:
	app.flight.airborne=true;app.flight.gear=true;app.flight.flaps=1;app.flight.position=Vector3(0,500,-1000)
	app.mission.tick(6.0);app.mission.tick(2.0);fill_wave()
func kill_birds(count: int) -> void:
	var remaining := count
	for enemy in app.combat.enemies:
		if remaining<=0:break
		if enemy.health<=0:continue
		enemy.health=0.0;app.combat.kills+=1;remaining-=1
	app.mission.tick(.01)
func next_wave() -> void:
	app.flight.position+=app.flight.forward()*maxf(1,app.mission.stream_gap-app.mission.stream_distance+1)
	app.mission.tick(maxf(.01,app.mission.next_spawn_at-app.mission.clock));fill_wave()
func finish() -> void:
	print("ENDLESS WAVES: %d checks / %d failures" % [checks,failures.size()])
	app.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
func run() -> void:
	setup()
	app.mission.tick(70.0)
	check(app.mission.wave_number==0 and app.mission.phase=="opening","Ground wait never starts a clock-triggered combat wave")
	start_first_wave()
	check(app.mission.wave_number==1 and app.mission.wave_size==2,"First proper wave arrives eight seconds after airborne")
	check(app.flight.gear,"Gear-down flight does not block the first wave")
	check(app.mission.skein_total()==2,"Total means actual arrivals, not a predetermined quota")
	app.mission.controls()
	check(app.flight.gear and app.flight.flaps==1,"Assistance preserves pilot gear and flap choices")
	app.demo_auto_fire=true;app.mission.controls();app.demo_auto_fire=false
	check(not app.flight.gear and app.flight.flaps==0,"Only Watch Demo auto-configures gear and flaps")
	var expected_spawned := 0
	var expected_down := 0
	for wave in range(1,41):
		var size: int=app.mission.size_for_wave(wave)
		expected_spawned+=size
		check(app.mission.wave_number==wave and app.mission.wave_size==size,"Wave number advances with two or three geese")
		check(app.mission.skein_total()==expected_spawned,"Cumulative actual arrivals remain exact")
		if wave%4==0:
			kill_birds(size);expected_down+=size
		else:
			kill_birds(1);expected_down+=1
			if app.mission.phase!="wave_break":app.mission.tick(Mission.WAVE_SECONDS+.01)
		check(app.mission.phase=="wave_break" and not app.mission.skein_final,"A clear or timeout always leads to another wave")
		check(app.mission.skein_down==expected_down,"Expired survivors never become kills")
		check(app.mission.skein_ids.size()<=12 and app.mission.wave_ids.size()<=12 and app.mission.skein_alive.size()<=12 and app.mission.skein_killed.size()<=12,"Only current-wave identity history is retained")
		check(app.mission.history.size()<=Mission.HISTORY_LIMIT and app.combat.enemies.size()<=12,"Mission history and live contacts stay bounded")
		if wave<40:next_wave()
		await process_frame
	check(app.mission.clock>600 and app.mission.wave_number==40,"More than ten minutes and thirty waves remain playable")
	check(app.landing_calls==0 and app.result_calls==0,"No deadline or wave quota requests landing or finishes sortie")
	check(app.mission.skein_total()==100 and app.mission.skein_down>32,"Cumulative counts continue beyond the former 32-bird ending")
	check(app.combat.managed_mission and is_inf(app.combat.spawn_clock),"Mission suppresses finite patrol ending and ambient arrivals")
	var before: int=app.combat.next_id
	app.mission.transition("approach")
	app.mission.tick(800.0)
	check(app.combat.next_id==before and app.mission.skein_pending==0 and app.mission.skein_final,"Approach stops future wave spawns")
	check(app.mission.phase=="approach" and not app.combat.engagement_enabled,"Landing remains under the parent controller")
	var visuals: Node3D = load("res://systems/combat_visuals.gd").new()
	visuals.combat=app.combat;app.add_child(visuals)
	var expired := Node3D.new()
	visuals.rings.append({"node":expired,"id":-1});expired.free()
	visuals.tick(0.0)
	check(visuals.rings.is_empty(),"Endless visual tracking prunes freed contact handles")
	await finish()
