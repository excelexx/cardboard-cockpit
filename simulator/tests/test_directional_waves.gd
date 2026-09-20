extends "res://tests/test_endless_waves.gd"
func run()->void:
	setup()
	app.flight.airborne=true;app.flight.position=Vector3(0,200,0);app.flight.pitch=0
	app.mission.tick(8);app.mission.tick(2)
	check(app.combat.next_id==2,"Wave still spawns when the player is below 1,300 feet")
	for bird: Dictionary in app.combat.enemies:check(is_equal_approx(bird.position.y,396.24),"Low-altitude player gets geese at 1,300 feet")
	app.flight.position=Vector3(0,1000,0)
	app.camera=Camera3D.new();app.add_child(app.camera)
	app.camera.position=app.flight.position
	app.camera.look_at(app.flight.position+Vector3(.4,.12,-1))
	app.mission.tick(.01)
	var last_spawn: float=app.mission.clock
	var count: int=app.combat.next_id
	check(count==2,"First wave spawns two geese together")
	for step in range(700):
		app.mission.tick(.1)
		if app.combat.next_id>count:
			var added: int=app.combat.next_id-count
			check(added>=2 and added<=3,"Entire waves spawn together with two or three geese")
			check(app.mission.clock-last_spawn>=9.999 and app.mission.clock-last_spawn<10.3,"New waves arrive every ten seconds")
			for i in range(app.combat.enemies.size()):
				var bird: Dictionary=app.combat.enemies[i]
				check(bird.position.y>=396.23,"All geese spawn at or above 1,300 feet")
				var reference: Vector3=app.combat.spawn_sight_point(2200+i*400)
				var delta: Vector3=bird.position-reference
				check(absf(delta.dot(-app.camera.global_basis.z))<.01,"Goose depth is 2.2 km plus 400 m per bird")
				check(delta.length()<=120.01,"Goose is close to the sightline with a small lateral offset")
			last_spawn=app.mission.clock;count=app.combat.next_id
	check(count>=15,"Ten-second waves continue")
	app.landing_started=true;app.mission.tick(100)
	check(app.combat.next_id==count,"Landing stops wave arrivals")
	await finish()
