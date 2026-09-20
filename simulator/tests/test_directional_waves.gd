extends "res://tests/test_endless_waves.gd"
func run()->void:
	setup();start_first_wave()
	for heading: float in [0.0,PI*.5,PI,-PI*.5]:
		app.flight.heading=heading;app.flight.pitch=.25
		app.mission._finish_wave(app.combat,false);next_wave()
		check(app.combat.enemies.size()==app.mission.wave_size and app.combat.enemies.size()<=12,"Every heading receives the expected bounded flock")
		var nearest:=INF
		for i in range(app.combat.enemies.size()):
			var bird: Dictionary=app.combat.enemies[i]
			check(app.flight.forward().dot((bird.position-app.flight.position).normalized())>.7,"Geese spawn ahead of the current heading and pitch")
			for j in range(i):nearest=minf(nearest,Vector3(bird.position).distance_to(app.combat.enemies[j].position))
		check(nearest>50,"Loose flocks keep at least fifty metres between nearby birds")
	app.flight.heading+=PI
	var kills: int=app.combat.kills
	app.mission.tick(Mission.EMPTY_VIEW_SECONDS+.01)
	check(app.mission.phase=="wave_break","Turning away from the whole flock schedules a fresh encounter")
	next_wave()
	check(app.mission._flock_ahead(app.combat) and app.combat.kills==kills,"Fresh geese arrive ahead without crediting missed birds as kills")
	app.landing_started=true;var before: int=app.combat.next_id
	app.mission.tick(100)
	check(app.combat.next_id==before,"Landing still stops all arrivals")
	await finish()
