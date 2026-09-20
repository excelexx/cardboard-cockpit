extends SceneTree

class ReviewApp extends Node:
	var mode := "title"
	var settings_visible := true
	var help_visible := false
	var calibration_visible := false
	var credits_visible := false
	var route_id := "sf"
	var gameplay_settings = preload("res://systems/gameplay_settings.gd").new()
	var vision = preload("res://systems/vision_client.gd").new()
	func yoke_recovery_visible() -> bool: return false
	func overlay_visible() -> bool: return settings_visible
	func change(axis: String, value: float) -> void:
		if axis.ends_with("_agility") or axis=="auto_aim": gameplay_settings.set(axis,value)
		else: vision.set(axis+"_sensitivity",value)

func _initialize() -> void: call_deferred("run")
func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	event.position = point; event.global_position = point
	root.push_input(event,true)

func run() -> void:
	root.size = Vector2i(1280,800)
	var app := ReviewApp.new(); root.add_child(app)
	var hud = load("res://ui/hud.gd").new(); hud.app = app
	hud.sensitivity_changed.connect(app.change); root.add_child(hud)
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/yoke-settings-defaults.png"))
	for axis: String in hud.SETTING_AXES:
		var slider: HSlider = hud.sensitivity_sliders[axis]
		var rect := slider.get_global_rect()
		var start := rect.position+Vector2(rect.size.x*.25,rect.size.y*.5)
		var end := rect.position+Vector2(rect.size.x*.75,rect.size.y*.5)
		mouse(start,true)
		var drag := InputEventMouseMotion.new()
		drag.position = end; drag.global_position = end; drag.relative = end-start; drag.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(drag,true); mouse(end,false)
		assert(slider.value>2 and slider.value<2.7,"Dragging "+axis+" must change its actual slider value")
		assert(is_equal_approx(hud.setting_value(axis),slider.value),"Drag must reach the control setting")
		var value := slider.value
		var key := InputEventKey.new(); key.keycode = KEY_LEFT; key.pressed = true
		root.push_input(key,true)
		assert(is_equal_approx(slider.value,value-.05),"Focused slider must also support arrow keys")
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/yoke-settings-adjusted.png"))
	print("YOKE SETTINGS UI PASS: Seven mouse drags and keyboard adjustments reach their independent control gains")
	quit()
