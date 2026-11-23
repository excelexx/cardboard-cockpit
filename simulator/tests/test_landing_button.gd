extends SceneTree
func _initialize() -> void:call_deferred("run")
func packet(n: int,mask: int) -> PackedByteArray:
	return JSON.stringify({"version":1,"session":"landing-test","sequence":n,"mask":mask,"connected":true,"phase_supported":true}).to_utf8_buffer()
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	app.on_action("fly");app.flight.spawn_airborne(Vector3(15000,400,-13000),300)
	app.combat.score=700;app.combat.kills=4;app.primary_latched=true;app.salvo_latched=true
	assert(app.badge.open_inputs(0))
	var sender:=PacketPeerUDP.new();sender.connect_to_host("127.0.0.1",app.badge.receiver.get_local_port())
	sender.put_packet(packet(1,0));sender.put_packet(packet(2,2))
	await create_timer(.05).timeout
	app._physics_process(.016)
	assert(app.landing_started and app.mission.phase=="approach","Physical B starts landing")
	assert(app.flight.gear and app.flight.flaps==2 and app.copilot,"One press deploys gear/flaps and guidance")
	assert(not app.primary_latched and not app.salvo_latched and not app.combat.active,"Landing safes weapons")
	assert(app.combat.score==700 and app.combat.kills==4,"Landing preserves the sortie score")
	var at: Vector3=app.flight.position;app.begin_landing()
	assert(app.flight.position==at,"Repeated landing request does not reset approach")
	# Record the attitude the airframe is DRAWN at on the frame the mains arrive: the
	# flare must put the nose up, and it must do it without a harder arrival.
	var touchdown_attitude:=-99.0
	for i in range(60*40):
		app._physics_process(1.0/60)
		if touchdown_attitude<-90.0 and app.flight.contact=="landed":
			touchdown_attitude=rad_to_deg(app.flight.pose_pitch() if app.flight.has_method("pose_pitch") else app.flight.pitch)
		if app.mode=="results":break
	assert(app.flight.contact=="landed" and app.flight.speed==0 and app.mode=="results","Assisted approach lands and brakes to a stop")
	assert(touchdown_attitude>6.0,"The jet touches down nose-high, not on its nosewheel: "+str(touchdown_attitude))
	assert(absf(app.flight.touchdown_sink)<3.0,"Flare keeps the arrival soft: "+str(app.flight.touchdown_sink))
	print("TOUCHDOWN ATTITUDE: %.1f deg nose-up, sink %.2f m/s, speed %.0f m/s" % [touchdown_attitude,app.flight.touchdown_sink,app.flight.touchdown_speed])
	app.on_action("fly");assert(not app.landing_started,"Replay clears landing state")
	sender.close();app.queue_free();await process_frame;print("BADGE LANDING: PASS");quit()
