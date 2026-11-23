extends SceneTree
var failed:=false
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","sf");root.add_child(app)
	await process_frame;app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	# Optional look at the flock act: --windowed ... -- --visual. Headless runs
	# are untouched by this branch.
	# --flockcam parks a free camera alongside the lead chevron instead of using
	# the cockpit view, so the V and its wander can actually be looked at.
	var flockcam: bool="--flockcam" in OS.get_cmdline_user_args()
	var visual: bool=(flockcam or "--visual" in OS.get_cmdline_user_args()) and DisplayServer.get_name()!="headless"
	if visual:app.capture_file="review"
	var shots: Array[float]=[64.6,66.5,69.0,72.0,76.0,78.5]
	app.on_action("guided")
	var skein_seen:=false;var gun_seen:=false;var max_missiles:=0;var flock:=0;var act_start:=-1.0;var act_end:=-1.0
	for frame in range(60*151):
		app._physics_process(1.0/60.0)
		var m=app.mission
		if m.phase=="skein" and act_start<0:act_start=m.clock
		if m.phase=="skein":act_end=m.clock
		skein_seen=skein_seen or m.skein_total()>0
		flock=maxi(flock,m.skein_total())
		gun_seen=gun_seen or app.combat.rounds_fired>0
		var missiles:=0
		for shot in app.combat.shots:
			if shot.kind=="missile":missiles+=1
		max_missiles=maxi(max_missiles,missiles)
		if visual and not shots.is_empty() and m.clock>=shots[0]:
			var at: float=shots.pop_front()
			app.camera_rig.update(.2);app._process(1.0/60.0)
			if flockcam:_park_beside_flock(app)
			await process_frame
			await RenderingServer.frame_post_draw
			var destination: String=ProjectSettings.globalize_path("res://../build/mission")
			DirAccess.make_dir_recursive_absolute(destination)
			root.get_texture().get_image().save_png(destination+("/chevron-%04.1f.png" if flockcam else "/flock-%04.1f.png") % at)
		if app.mode=="results":break
		if frame%300==0:await process_frame
	print("SPECTRAL RUN time=",app.mission.clock," mode=",app.mode," phase=",app.mission.phase," kills=",app.combat.kills," flock=",flock," down=",app.mission.skein_down," cleared=",app.mission.skein_success," act=",snappedf(act_end-act_start,.01)," gun=",gun_seen," missiles=",app.combat.missiles_fired," simultaneous=",max_missiles," code=",app.result_code," success=",app.mission_success," position=",app.flight.position)
	failed=app.mode!="results" or app.mission.clock>150 or not skein_seen or not gun_seen or max_missiles<4 or app.flight.contact!="landed" or app.flight.speed>0.1
	if flock<Tune_size():failed=true;printerr("The last wave is not a flock of twelve: "+str(flock))
	if not app.mission_success:failed=true;printerr("Auto-flown showcase did not reach a winning debrief: "+str(app.result_code))
	if act_end-act_start<6.0:failed=true;printerr("The flock act is over before it starts: "+str(act_end-act_start))
	# Replay with no shooting must reach an honest timed outcome; it cannot award
	# a cleared flock automatically merely to satisfy the presentation deadline.
	app.on_action("fly")
	for frame in range(60*151):
		app._physics_process(1.0/60)
		if app.mode=="results":break
		if frame%300==0:await process_frame
	print("NO FIRE RUN time=",app.mission.clock," success=",app.mission_success," down=",app.mission.skein_down,"/",app.mission.skein_total()," kills=",app.combat.kills," shots=",app.combat.rounds_fired," code=",app.result_code)
	failed=failed or app.mode!="results" or app.mission.clock>150 or app.mission_success or app.mission.skein_success or app.combat.rounds_fired!=0 or app.flight.contact!="landed" or app.flight.speed>0.1
	app.on_action("guided")
	failed=failed or not app.combat.shots.is_empty() or not app.combat.enemies.is_empty() or app.combat.visuals.sprite_pool.size()!=96
	app.queue_free();await process_frame;quit(1 if failed else 0)
func Tune_size() -> int: return load("res://data/balance.gd").SKEIN_SIZE

## Review only: look at the lead chevron from off its wing, close enough to see
## the V hold its shape and the birds wander inside it.
func _park_beside_flock(app) -> void:
	var centre:=Vector3.ZERO;var heading:=Vector3.ZERO;var count:=0
	var wanted: int=-1
	for enemy: Dictionary in app.combat.enemies:
		if enemy.health<=0 or not app.mission.skein_ids.has(int(enemy.id)):continue
		var chevron: int=int(app.mission.flock_chevron.get(int(enemy.id),0))
		if wanted<0 or chevron<wanted:wanted=chevron
	for enemy: Dictionary in app.combat.enemies:
		if enemy.health<=0 or not app.mission.skein_ids.has(int(enemy.id)):continue
		if int(app.mission.flock_chevron.get(int(enemy.id),0))!=wanted:continue
		centre+=enemy.position;heading+=Vector3(enemy.velocity);count+=1
	if count==0:return
	centre/=float(count);heading/=float(count)
	var flat:=Vector3(heading.x,0,heading.z)
	flat=flat.normalized() if flat.length()>0.5 else Vector3.FORWARD
	var wing: Vector3=flat.cross(Vector3.UP).normalized()
	var camera: Camera3D=app.camera_rig.camera
	camera.global_position=centre-flat*52.0+wing*78.0+Vector3.UP*26.0
	camera.look_at(centre,Vector3.UP)
	camera.fov=42.0
