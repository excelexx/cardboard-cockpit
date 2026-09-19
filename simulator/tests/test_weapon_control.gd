extends SceneTree
var app: Node3D
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run_tests")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("WEAPON FAIL: "+message)
func run_tests() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.set_physics_process(false)
	app.audio.muted = true
	app.on_action("demo")
	app.copilot = false
	var c: GooseCampaign = app.combat
	var enemy: Dictionary = c.enemies[0]
	var angle := deg_to_rad(10)
	enemy.position = app.flight.position+Vector3(sin(angle),0,-cos(angle))*1000
	c.target_id = enemy.id
	c.lock_progress = 1
	c.fire_weapon()
	var fired: Vector3 = c.shots.back().velocity.normalized()
	var desired: Vector3 = (enemy.position-app.flight.position).normalized()
	check(fired.angle_to(c.forward())<=deg_to_rad(2.1), "Gatling aim correction never exceeds two degrees")
	check(fired.angle_to(desired)>deg_to_rad(6), "Poor aim remains a miss instead of snapping onto a goose")
	c.developer = true
	c.skip_to(5)
	c.assist = false
	enemy = c.enemies[0]
	enemy.position = app.flight.position+c.forward()*800
	c.target_id = enemy.id
	c.lock_progress = 1
	var projectile_count: int = c.shots.size()
	c.fire_weapon()
	check(c.shots.size()==projectile_count, "Falcon trigger creates no individual plasma projectiles")
	for i in range(30):
		c.fire_weapon()
		c.tick(1.0/60.0)
	check(c.get("beam_active")==true, "Holding fire sustains a continuous beam")
	for i in range(15): c.tick(1.0/60.0)
	check(c.get("beam_active")==false, "Beam shuts down when its trigger is released")
	print("WEAPON CONTROL: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
