extends "res://tests/test_endless_waves.gd"
func run()->void:
	setup()
	for heading: float in [0.0,PI*.5,PI,-PI*.5]:
		app.flight.airborne=true;app.flight.heading=heading;app.flight.pitch=.25;app.flight.position=Vector3(0,500,0)
		app.mission.reset(true);app.flight.airborne=true
		app.mission.tick(4);app.mission.tick(2)
		check(app.mission.wave_ids.size()>=1 and app.mission.wave_ids.size()<=4,"Each stream begins with one to four birds")
		while app.mission.skein_pending>0:
			var before: int=app.combat.next_id
			var gap: float=app.mission.stream_gap-app.mission.stream_distance
			check(app.mission.stream_gap>=200 and app.mission.stream_gap<=500,"Next swarm spacing is randomly bounded between 200 and 500 metres")
			app.flight.position+=app.flight.forward()*(gap-.2);app.mission.tick(.01)
			check(app.combat.next_id==before,"Birds do not bunch up before the next sampled gap")
			app.flight.position+=app.flight.forward()*.3;app.mission.tick(.01)
			var spawned: int=app.combat.next_id-before
			check(spawned>=1 and spawned<=4,"The next sampled distance produces one to four birds")
			for bird: Dictionary in app.combat.enemies:
				if bird.id>=before:check(app.flight.forward().dot((bird.position-app.flight.position).normalized())>.8,"New birds are ahead of the current heading and pitch")
		check(app.mission.skein_total()==6 and app.combat.enemies.size()<=12,"Arrival counts stay honest and bounded")
	app.flight.heading+=PI
	var kills: int=app.combat.kills;app.mission.tick(Mission.EMPTY_VIEW_SECONDS+.01)
	check(app.mission.phase=="wave_break","Leaving the whole stream behind schedules another encounter")
	app.flight.position+=app.flight.forward()*(app.mission.stream_gap+1)
	app.mission.tick(.01)
	check(app.mission._flock_ahead(app.combat) and app.combat.kills==kills,"Replacement stream starts ahead without inventing kills")
	app.landing_started=true;var before: int=app.combat.next_id;app.mission.tick(100)
	check(app.combat.next_id==before,"Landing stops all arrivals")
	await finish()
