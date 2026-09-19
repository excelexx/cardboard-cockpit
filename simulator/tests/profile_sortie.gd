extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.set_physics_process(false)
	app.set_process_input(false)
	app.set_process_unhandled_input(false)
	app.set_process_unhandled_key_input(false)
	app.audio.muted=true
	app.capture_file="profiling"
	app.diagnostic_input_lock=true
	app.vision.enabled=false
	var start: int=Time.get_ticks_usec()
	app.on_action("demo")
	print("PREPARATION_MS ",(Time.get_ticks_usec()-start)/1000.0)
	var samples: Array[float]=[]
	var stage: int=app.combat.wave
	var rendered: bool="--render" in OS.get_cmdline_user_args()
	var render_samples: Array[float]=[]
	var render_start: int=Time.get_ticks_usec()
	for frame in range(15000):
		start=Time.get_ticks_usec()
		app._physics_process(1.0/60.0)
		if frame%6==0: app._process(1.0/60.0)
		var ms: float=(Time.get_ticks_usec()-start)/1000.0
		samples.append(ms)
		if app.combat.wave!=stage:
			stage=app.combat.wave
			print("UPGRADE_CPU_MS stage=",stage," ms=",ms)
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
	if not render_samples.is_empty():
		render_samples.sort()
		print("ACCELERATED_RENDER_INTERVAL_MS p50=",render_samples[int(render_samples.size()*0.5)]," p95=",render_samples[int(render_samples.size()*0.95)]," p99=",render_samples[int(render_samples.size()*0.99)]," max=",render_samples[-1])
	quit(0 if app.mission_success else 1)
