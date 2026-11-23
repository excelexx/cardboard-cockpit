extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","coast"); root.add_child(app)
	await process_frame
	app.set_process(false)
	app.set_physics_process(false)
	app.set_process_input(false)
	app.set_process_unhandled_input(false)
	app.set_process_unhandled_key_input(false)
	app.audio.muted=true
	app.capture_file="profiling"
	app.vision.enabled=false
	var start: int=Time.get_ticks_usec()
	app.on_action("guided")
	print("PREPARATION_MS ",(Time.get_ticks_usec()-start)/1000.0)
	var samples: Array[float]=[]
	var stage: int=app.mission.route_index
	var rendered: bool="--render" in OS.get_cmdline_user_args()
	var render_samples: Array[float]=[]
	var render_start: int=Time.get_ticks_usec()
	for frame in range(15000):
		start=Time.get_ticks_usec()
		app._physics_process(1.0/60.0)
		if frame%6==0: app._process(1.0/60.0)
		var ms: float=(Time.get_ticks_usec()-start)/1000.0
		samples.append(ms)
		if app.mission.route_index!=stage:
			stage=app.mission.route_index
			print("CHECKPOINT_CPU_MS index=",stage," ms=",ms)
		if rendered and frame%6==0:
			await process_frame
			var interval: float=(Time.get_ticks_usec()-render_start)/1000.0
			if frame>120:
				render_samples.append(interval)
				if interval>60: print("RENDER_HITCH ms=",interval," frame=",frame," stage=",stage," position=",app.flight.position)
			render_start=Time.get_ticks_usec()
		elif frame%600==0: await process_frame
		if app.mode=="results": break
	samples.sort()
	print("SORTIE_CPU_MS p50=",samples[int(samples.size()*0.5)]," p95=",samples[int(samples.size()*0.95)]," p99=",samples[int(samples.size()*0.99)]," max=",samples[-1]," success=",app.mission_success)
	print("SORTIE_END mode=",app.mode," copilot=",app.copilot," elapsed=",app.flight.elapsed," position=",app.flight.position," reason=",app.result_reason)
	# Ordnance through a full scripted showcase. GUN_MAGAZINE and MISSILE_STORES
	# are both -1 (unlimited, booth safety), so `remaining` is the report the
	# lead asked for and the gate is that it never reads zero.
	var rounds_left: Variant=app.combat.ammo
	var missiles_left: Variant=app.combat.missiles
	print("SORTIE_STORES rounds_fired=",app.combat.rounds_fired," rounds_hit=",app.combat.rounds_hit,
		" rounds_remaining=",("unlimited" if int(rounds_left)<0 else rounds_left),
		" missiles_fired=",app.combat.missiles_fired," missiles_remaining=",("unlimited" if int(missiles_left)<0 else missiles_left),
		" kills=",app.combat.kills," score=",app.combat.score)
	print("SORTIE_FLOCK total=",app.combat.skein_total," down=",app.combat.skein_down," remaining=",app.combat.skein_remaining()," cleared=",app.combat.skein_cleared)
	if not render_samples.is_empty():
		render_samples.sort()
		print("ACCELERATED_RENDER_INTERVAL_MS p50=",render_samples[int(render_samples.size()*0.5)]," p95=",render_samples[int(render_samples.size()*0.95)]," p99=",render_samples[int(render_samples.size()*0.99)]," max=",render_samples[-1])
	# The flock is the heaviest moment in the game and it only exists on the
	# scripted SF showcase, so the ordnance report and the spawn cost the lead
	# asked for are measured there, on top of the coast profile above.
	var demo=load("res://scenes/main.tscn").instantiate()
	demo.set_meta("route_override","sf"); root.add_child(demo)
	await process_frame
	demo.set_process(false); demo.set_physics_process(false); demo.set_process_input(false)
	demo.set_process_unhandled_input(false); demo.set_process_unhandled_key_input(false)
	demo.audio.muted=true; demo.capture_file="profiling"; demo.vision.enabled=false
	demo.on_action("guided")
	var show_samples: Array[float]=[]
	var flock_samples: Array[float]=[]
	var flock_open: float=-1.0
	var lowest_rounds: int=1<<30
	for frame in range(60*160):
		var t0: int=Time.get_ticks_usec()
		demo._physics_process(1.0/60.0)
		if frame%6==0: demo._process(1.0/60.0)
		var ms: float=(Time.get_ticks_usec()-t0)/1000.0
		show_samples.append(ms)
		if demo.mission.phase=="skein":
			if flock_open<0.0: flock_open=demo.mission.clock
			flock_samples.append(ms)
		if int(demo.combat.ammo)>=0 and not (demo.mission.phase in ["approach","rollout"]):
			lowest_rounds=mini(lowest_rounds,int(demo.combat.ammo))
		if frame%600==0: await process_frame
		if demo.mode=="results": break
	show_samples.sort(); flock_samples.sort()
	print("SHOWCASE_CPU_MS p50=",show_samples[int(show_samples.size()*0.5)]," p95=",show_samples[int(show_samples.size()*0.95)]," p99=",show_samples[int(show_samples.size()*0.99)]," max=",show_samples[-1])
	if not flock_samples.is_empty():
		print("SHOWCASE_FLOCK_CPU_MS frames=",flock_samples.size()," p50=",flock_samples[int(flock_samples.size()*0.5)]," p99=",flock_samples[int(flock_samples.size()*0.99)]," max=",flock_samples[-1])
	print("SHOWCASE_FLOCK opened=",flock_open," total=",demo.mission.skein_total()," down=",demo.mission.skein_down," cleared=",demo.mission.skein_success," combat_total=",demo.combat.skein_total," combat_down=",demo.combat.skein_down," combat_cleared=",demo.combat.skein_cleared)
	print("SHOWCASE_STORES rounds_fired=",demo.combat.rounds_fired," rounds_hit=",demo.combat.rounds_hit,
		" rounds_remaining=",("unlimited" if int(demo.combat.ammo)<0 else demo.combat.ammo),
		" lowest_rounds_before_landing=",("unlimited" if lowest_rounds==(1<<30) else lowest_rounds),
		" missiles_fired=",demo.combat.missiles_fired," missiles_remaining=",("unlimited" if int(demo.combat.missiles)<0 else demo.combat.missiles),
		" kills=",demo.combat.kills)
	print("SHOWCASE_END mode=",demo.mode," clock=",demo.mission.clock," success=",demo.mission_success," code=",demo.result_code)
	var showcase_ok: bool=demo.mission_success
	demo.queue_free(); await process_frame
	quit(0 if (app.mission_success and showcase_ok) else 1)
