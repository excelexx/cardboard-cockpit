extends "res://tests/test_endless_waves.gd"
## The 12/20 introduction now hands off to 32/40 and unlimited later waves.
func run() -> void:
	setup();start_first_wave()
	check(app.mission.wave_number==1 and app.mission.wave_ids.size()==12,"First wave contains twelve distinct birds")
	kill_birds(12)
	check(app.mission.phase=="wave_break" and app.mission.wave_down()==12 and app.mission.skein_down==12,"Full first clear earns an honest reward beat")
	check(app.mission.last_wave_cleared and not app.mission.skein_final,"A cleared introduction is not a sortie ending")
	app.mission.tick(3.8)
	check(app.mission.wave_number==1,"The short reward beat remains visible")
	app.mission.tick(.21);fill_wave()
	check(app.mission.wave_number==2 and app.mission.wave_size==20 and app.mission.skein_total()==32,"Second wave adds twenty to the actual-arrival count")
	kill_birds(20)
	check(app.mission.skein_down==32 and not app.mission.skein_final,"Thirty-two actual kills do not end play")
	next_wave()
	check(app.mission.wave_number==3 and app.mission.wave_size==32 and app.mission.skein_total()==64,"Third wave continues with thirty-two fresh geese")
	var missing: Dictionary=app.combat.enemies.pop_back();missing.node.queue_free()
	app.combat.enemies[0].retiring=true
	app.mission._tally_skein(app.combat)
	check(app.mission.wave_down()==0 and app.mission.skein_down==32,"Missing and retiring geese are not credited as kills")
	# A real fatal event can precede corpse removal between mission samples.
	var downed: Dictionary=app.combat.enemies.pop_back();downed.node.queue_free();app.combat.kills+=1
	app.mission.tick(.01)
	check(app.mission.wave_down()==1 and app.mission.skein_down==33,"Actual combat kill counter recovers a removed corpse")
	app.mission.tick(Mission.WAVE_SECONDS+.01)
	check(not app.mission.last_wave_cleared and app.mission.skein_down==33,"Wave expiry does not invent kills or claim a clear")
	next_wave()
	check(app.mission.wave_number==4 and app.mission.wave_size==40 and app.mission.skein_total()==104,"Fourth wave grows to the forty-contact cap")
	check(app.combat.enemies.size()==40 and app.mission.wave_down()==0,"Retired previous-wave contacts do not accumulate")
	app.landing_started=true
	var before: int=app.combat.next_id
	app.mission.tick(100.0)
	check(app.mission.skein_final and not app.combat.engagement_enabled and app.combat.next_id==before,"Explicit landing flag also stops waves immediately")
	check(app.landing_calls==0 and app.result_calls==0,"Intro flow never auto-lands or auto-completes")
	await finish()
