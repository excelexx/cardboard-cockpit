extends "res://tests/test_endless_waves.gd"
## Smaller 6/8/10/12 flocks continue indefinitely until the pilot lands.
func run() -> void:
	setup();start_first_wave()
	check(app.mission.wave_number==1 and app.mission.wave_ids.size()==6,"First wave contains six distinct birds")
	kill_birds(6)
	check(app.mission.phase=="wave_break" and app.mission.wave_down()==6 and app.mission.skein_down==6,"Full first clear earns an honest reward beat")
	check(app.mission.last_wave_cleared and not app.mission.skein_final,"A cleared introduction is not a sortie ending")
	app.mission.tick(2.8)
	check(app.mission.wave_number==1,"The short reward beat remains visible")
	app.mission.tick(.21);fill_wave()
	check(app.mission.wave_number==2 and app.mission.wave_size==8 and app.mission.skein_total()==14,"Second wave adds eight to the actual-arrival count")
	kill_birds(8)
	check(app.mission.skein_down==14 and not app.mission.skein_final,"Fourteen actual kills do not end play")
	next_wave()
	check(app.mission.wave_number==3 and app.mission.wave_size==10 and app.mission.skein_total()==24,"Third wave continues with ten fresh geese")
	var missing: Dictionary=app.combat.enemies.pop_back();missing.node.queue_free()
	app.combat.enemies[0].retiring=true
	app.mission._tally_skein(app.combat)
	check(app.mission.wave_down()==0 and app.mission.skein_down==14,"Missing and retiring geese are not credited as kills")
	# A real fatal event can precede corpse removal between mission samples.
	var downed: Dictionary=app.combat.enemies.pop_back();downed.node.queue_free();app.combat.kills+=1
	app.mission.tick(.01)
	check(app.mission.wave_down()==1 and app.mission.skein_down==15,"Actual combat kill counter recovers a removed corpse")
	app.mission.tick(Mission.WAVE_SECONDS+.01)
	check(not app.mission.last_wave_cleared and app.mission.skein_down==15,"Wave expiry does not invent kills or claim a clear")
	next_wave()
	check(app.mission.wave_number==4 and app.mission.wave_size==12 and app.mission.skein_total()==36,"Fourth wave grows to the twelve-contact cap")
	check(app.combat.enemies.size()==12 and app.mission.wave_down()==0,"Retired previous-wave contacts do not accumulate")
	app.landing_started=true
	var before: int=app.combat.next_id
	app.mission.tick(100.0)
	check(app.mission.skein_final and not app.combat.engagement_enabled and app.combat.next_id==before,"Explicit landing flag also stops waves immediately")
	check(app.landing_calls==0 and app.result_calls==0,"Intro flow never auto-lands or auto-completes")
	await finish()
