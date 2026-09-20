extends SceneTree

var app: Node
var sequence_number := 0

func _initialize() -> void:
	call_deferred("run")

func triggers(gun: bool) -> void:
	sequence_number += 1
	var packet := {"version": 1, "sequence": sequence_number, "timestamp": 1, "tracking": false,
		"yoke": {"roll": 0, "pitch": 0, "confidence": 1},
		"throttle": {"value": .5, "confidence": 0},
		"weapons": {"gun": gun}}
	assert(app.vision._accept_packet(JSON.stringify(packet).to_utf8_buffer(), Time.get_ticks_msec()))

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override", "alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.test_mode = true
	app.audio.muted = true; app.start_flight("combat", true)
	app.vision.enabled = true; app.vision.tracking = true; app.copilot = false
	triggers(true)
	app.fire_guard = .3
	app._physics_process(.01)
	assert(app.combat.rounds_fired == 0, "Startup guard applies to tag fire")
	app.fire_guard = 0
	app._physics_process(.01)
	assert(app.combat.rounds_fired > 0, "Visible ID 04 fires the actual gun")
	var rounds: int = app.combat.rounds_fired
	app._physics_process(.001)
	assert(app.combat.rounds_fired == rounds, "Gun tag respects the firing cooldown")
	triggers(false)
	app.combat.gun_cooldown = 0
	app._physics_process(.01)
	assert(app.combat.rounds_fired == rounds, "Covering gun stops only gun")
	triggers(true)
	app.combat.gun_cooldown = 0
	app._physics_process(.01)
	assert(app.combat.rounds_fired > rounds, "Exposing the gun resumes fire")
	rounds = app.combat.rounds_fired
	triggers(false)
	app.combat.gun_cooldown = 0
	# A locked target used to trigger automatic yoke gunfire. Keep that exact
	# condition present and verify covered tags prevail, including demo assist.
	app.combat.spawn_contact()
	var enemy: Dictionary = app.combat.enemies.back()
	enemy.position = app.flight.position + app.flight.forward()*1000
	app.combat.target_id = enemy.id; app.combat.lock_progress = 1
	app.combat.assist = true
	app._physics_process(.001)
	assert(app.combat.lock_progress == 1, "Regression fixture must retain target lock")
	assert(app.combat.rounds_fired == rounds, "Target lock must not bypass covered gun tag")
	app.vision.tracking = false; app.vision.yoke_enabled = false; app.copilot = true; app.demo_auto_fire = true
	app._physics_process(.001)
	assert(app.combat.rounds_fired == rounds, "Demo auto fire cannot bypass camera triggers")
	triggers(true)
	app.vision.yoke_enabled = false
	app.mode = "paused"; app._physics_process(.01)
	assert(app.combat.rounds_fired == rounds, "Paused flight does not fire")
	app.mode = "flight"; app.demo_auto_fire = false; app.copilot = false
	app.vision.connected = true
	app.vision._expire_weapons(app.vision.last_received+150)
	app._physics_process(.01)
	assert(app.combat.rounds_fired == rounds, "Stale connection stops actual weapons")
	app.vision.enabled = false; app.test_mode = false; app.fire_guard = 0
	rounds = app.combat.rounds_fired
	for code in [KEY_T, KEY_X]:
		var key := InputEventKey.new(); key.pressed = true; key.keycode = code
		app._input(key)
	var right_click := InputEventMouseButton.new(); right_click.pressed = true; right_click.button_index = MOUSE_BUTTON_RIGHT
	app._input(right_click)
	assert(app.combat.rounds_fired == rounds and app.combat.shots.all(func(shot): return shot.kind == "cannon"), "Removed controls cannot launch projectiles")
	print("WEAPON TAG GAME: PASS")
	app.queue_free(); await process_frame; quit()
