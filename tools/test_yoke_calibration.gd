extends SceneTree

# Actual Python marker detection, two WebSockets, JPEG preview and tutorial state.
var vision = preload("res://systems/vision_client.gd").new()
var preview = preload("res://systems/vision_preview.gd").new()
var lesson = preload("res://systems/control_tutorial.gd").new()
var child := -1
var begun := 0
var saw_progress := false
var saw_reset := false
var seen_picture := false

func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps = 60
	var probe := TCPServer.new()
	if probe.listen(0,"127.0.0.1") != OK:
		finish(false,"Cannot reserve fixture port"); return
	var port := probe.get_local_port(); probe.stop()
	vision.endpoint = "ws://127.0.0.1:%d" % port
	var directory := ProjectSettings.globalize_path("res://..").simplify_path()
	child = OS.create_process(directory.path_join(".venv/bin/python"), PackedStringArray([
		directory.path_join("vision/tests/yoke_recovery_fixture.py"), "--paper-test", "--port", str(port), "--duration", "15"]))
	begun = Time.get_ticks_msec()
	vision.enabled = true; vision.retry_at = begun+400
	vision.yoke_calibration.start(); vision.yoke_calibration.retry_at = begun+400
	if child <= 0: finish(false,"Could not start fixture")

func _process(dt: float) -> bool:
	if child <= 0: return false
	var now := Time.get_ticks_msec()
	vision.poll(dt)
	preview.poll(true,vision.endpoint,lesson.focus())
	lesson.tick(dt,vision,preview.texture!=null,now)
	seen_picture = seen_picture or preview.texture!=null
	if lesson.progress() > .1: saw_progress = true
	if saw_progress and lesson.calibrating and lesson.progress()==0: saw_reset = true
	if not lesson.calibrating:
		finish(saw_progress and saw_reset and seen_picture and lesson.index==0 and vision.yoke.length()<.01 and now-begun>=7000,
			"Live 3-second calibration resets on hidden tag, centres yoke, then opens throttle tutorial")
	elif now-begun>12000: finish(false,"Timed out: "+lesson.status)
	return false

func finish(ok: bool, message: String) -> void:
	vision.enabled = false; preview.stop()
	if child>0 and OS.is_process_running(child): OS.kill(child)
	child = -1
	if ok: print("YOKE CALIBRATION PASS: "+message)
	else: push_error("YOKE CALIBRATION FAIL: "+message)
	quit(0 if ok else 1)
