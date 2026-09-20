extends SceneTree

# Screenshot the real 2D HUD with synthetic fixtures, without opening a camera
# or loading the 3D world. Keep artifacts in ignored build/.
class ReviewApp extends Node:
	var mode := "tutorial"
	var tutorial = preload("res://systems/control_tutorial.gd").new()
	var vision = preload("res://systems/vision_client.gd").new()
	var vision_preview := {"texture": null}
	var route_id := "sf"
	var help_visible := false
	var calibration_visible := false
	var settings_visible := false
	var credits_visible := false
	func yoke_recovery_visible() -> bool: return false
	func overlay_visible() -> bool: return false

func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 800)
	var app := ReviewApp.new(); root.add_child(app)
	var hud = load("res://ui/hud.gd").new(); hud.app = app; root.add_child(hud)
	var directory := ProjectSettings.globalize_path("res://../build")
	for item: Array in [[0,"calibration"],[0,"throttle"],[1,"throttle-full"],[3,"yoke-overview"],[4,"grip"],[5,"weapons"],[6,"lift-gun"],[7,"ready"],[-1,"title"],[0,"waiting"]]:
		app.mode = "title" if item[0] == -1 else "tutorial"
		app.tutorial.index = maxi(0,item[0])
		app.tutorial.calibrating = item[1]=="calibration"
		app.tutorial.calibration_progress = .5
		app.tutorial.status = "All controls checked. Flight starts automatically." if item[1]=="ready" else "Follow the instruction above."
		if app.tutorial.calibrating: app.tutorial.status = "Hold still — 1.5 seconds remaining."
		app.tutorial.can_start = item[1]=="ready"
		app.vision.throttle = .05; app.vision.yoke = Vector2(0,.5)
		app.vision.gun_trigger = item[1]=="weapons"
		var source: String = "ready" if item[1]=="ready" else "weapons" if item[0] in range(4,7) else "yoke" if item[0] in range(3,4) else "throttle"
		if app.tutorial.calibrating: source = "yoke"
		var frame := Image.load_from_file(directory.path_join("tutorial-fixture-"+source+".png"))
		app.vision_preview.texture = null if item[1]=="waiting" else ImageTexture.create_from_image(frame)
		hud.queue_redraw()
		await process_frame; await RenderingServer.frame_post_draw
		var destination := directory.path_join("tutorial-review-"+item[1]+".png")
		root.get_texture().get_image().save_png(destination)
		if item[1]=="ready": assert(not hud.zones.has("tutorial_start"))
		elif item[1]=="title": assert(hud.zones.has("fly") and hud.zones.has("keyboard_play"))
		else: assert(hud.zones.has("tutorial_retry") and not hud.zones.has("tutorial_start"))
		print("TUTORIAL UI: "+destination)
	quit()
