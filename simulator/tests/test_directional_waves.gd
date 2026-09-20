extends "res://tests/test_endless_waves.gd"
var observed_gaps: Array[float]=[]
func verify_wave(check_sightline:bool)->void:
	var previous:=0.0
	for i in range(app.combat.enemies.size()):
		var bird:Dictionary=app.combat.enemies[i]
		var distance:float=app.flight.position.distance_to(bird.position)
		check(bird.position.y>=396.23,"All geese spawn at or above 1,300 feet")
		if i>0:
			var gap:float=distance-previous;observed_gaps.append(gap)
			check(gap>=400.0,"Each goose is at least 400 metres farther from the plane")
		if check_sightline:check((-app.camera.global_basis.z).angle_to((bird.position-app.camera.global_position).normalized())<deg_to_rad(5),"Randomized positions remain near the sightline")
		previous=distance
func run()->void:
	setup();seed(20260920)
	app.flight.airborne=true;app.flight.position=Vector3(0,200,0);app.flight.pitch=0
	app.mission.tick(5.5);app.mission.tick(2)
	check(app.combat.next_id==2,"Wave still spawns when the player is below 1,300 feet")
	verify_wave(false)
	app.flight.position=Vector3(0,1000,0)
	app.camera=Camera3D.new();app.add_child(app.camera)
	app.camera.position=app.flight.position;app.camera.look_at(app.flight.position+Vector3(.4,.12,-1))
	var last_spawn:float=app.mission.clock
	var count:int=app.combat.next_id
	for step in range(700):
		app.mission.tick(.1)
		if app.combat.next_id>count:
			var added:int=app.combat.next_id-count
			check(added>=2 and added<=3,"Whole waves contain two or three geese")
			check(app.mission.clock-last_spawn>=7.499 and app.mission.clock-last_spawn<7.8,"Wave interval is 7.5 seconds")
			verify_wave(true)
			last_spawn=app.mission.clock;count=app.combat.next_id
	observed_gaps.sort()
	check(observed_gaps[-1]-observed_gaps[0]>25,"Goose gaps vary between waves instead of repeating fixed positions")
	app.camera.look_at(app.flight.position+Vector3(.2,-.8,-1))
	app.mission._open_skein(app.combat,app.mission.wave_number+1);app.mission.next_spawn_at=app.mission.clock
	app.mission._drive_skein(app.combat,0);verify_wave(false)
	count=app.combat.next_id;app.landing_started=true;app.mission.tick(100)
	check(app.combat.next_id==count,"Landing stops wave arrivals")
	await finish()
