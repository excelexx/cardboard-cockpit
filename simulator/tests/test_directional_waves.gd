extends "res://tests/test_endless_waves.gd"
func run()->void:
	setup()
	app.flight.airborne=true;app.flight.position=Vector3(0,500,0);app.flight.pitch=.25
	app.mission.tick(6);app.mission.tick(1.99)
	check(app.combat.next_id==0,"No goose before eight airborne seconds")
	app.mission.tick(.01)
	var last_spawn: float=app.mission.clock
	var count: int=app.combat.next_id
	check(count==1,"First arrival is one goose")
	for step in range(1000):
		app.flight.heading+=.01
		app.flight.position+=app.flight.forward()*30
		app.mission.tick(.1)
		if app.combat.next_id>count:
			check(app.combat.next_id==count+1,"Only one goose spawns at a time")
			check(app.mission.clock-last_spawn>=7.999,"Spawns stay eight seconds apart across wave boundaries")
			check(app.mission.wave_size>=2 and app.mission.wave_size<=3,"Waves contain two or three geese")
			var bird: Dictionary=app.combat.enemies.back()
			check(is_equal_approx(bird.position.y,app.flight.position.y),"Spawn matches current aircraft altitude")
			check(app.flight.forward().dot((bird.position-app.flight.position).normalized())>.8,"Spawn remains ahead of the aircraft")
			last_spawn=app.mission.clock;count=app.combat.next_id
	check(count>=9,"Arrivals continue at the requested cadence")
	app.landing_started=true;app.mission.tick(100)
	check(app.combat.next_id==count,"Landing stops arrivals")
	await finish()
