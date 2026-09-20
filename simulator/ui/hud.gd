extends Control
class_name CockpitHUD
const Tune = preload("res://data/balance.gd")
signal action(name: String)
signal sensitivity_changed(axis: String, value: float)
var app: Node
var font := SystemFont.new()
var mono := SystemFont.new()
var title_art: Texture2D
var zones: Dictionary = {}
var hot := ""
var clock := 0.0
var sensitivity_sliders: Dictionary = {}
const SETTING_AXES := ["pitch","bank","yaw","pitch_agility","bank_agility","yaw_agility","auto_aim"]
const GAMEPLAY_SETTINGS = preload("res://systems/gameplay_settings.gd")
const WHITE := Color(0.91,0.95,0.97)
const MUTED := Color(0.70,0.82,0.85)
const CYAN := Color(0.33,0.86,0.87)
const GREEN := Color(0.45,0.94,0.71)
const AMBER := Color(1.0,0.65,0.30)
const DANGER := Color(1.0,0.30,0.19)
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font.font_names = PackedStringArray(["Avenir Next","Helvetica Neue"])
	font.font_weight = 600
	mono.font_names = PackedStringArray(["Menlo","Courier"])
	if ResourceLoader.exists("res://assets/art/spectre-title.png"): title_art = load("res://assets/art/spectre-title.png")
	mouse_filter = Control.MOUSE_FILTER_PASS
	for axis: String in SETTING_AXES:
		var slider := HSlider.new()
		slider.name = axis.capitalize()+"Sensitivity"
		slider.min_value = VisionClient.MIN_SENSITIVITY
		slider.max_value = VisionClient.MAX_SENSITIVITY
		if axis.ends_with("_agility"): slider.min_value = GAMEPLAY_SETTINGS.MIN_AGILITY; slider.max_value = GAMEPLAY_SETTINGS.MAX_AGILITY
		elif axis=="auto_aim": slider.min_value = 0; slider.max_value = GAMEPLAY_SETTINGS.MAX_AUTO_AIM
		slider.step = .05
		slider.scrollable = false
		slider.tooltip_text = {"pitch":"Pitch sensitivity: nose up / down", "bank":"Bank sensitivity: wings left / right", "yaw":"Yaw sensitivity: nose left / right", "pitch_agility":"Speed of pitching up and down", "bank_agility":"Speed of banking and banked turns", "yaw_agility":"Speed of swivelling the nose left and right", "auto_aim":"Target acquisition and aim tracking strength. Zero turns assistance off."}[axis]
		var track := StyleBoxFlat.new()
		track.bg_color = Color(.14,.24,.28)
		track.content_margin_top = 4; track.content_margin_bottom = 4
		track.set_corner_radius_all(4)
		slider.add_theme_stylebox_override("slider",track)
		var fill := track.duplicate() as StyleBoxFlat
		fill.bg_color = CYAN
		slider.add_theme_stylebox_override("grabber_area",fill)
		slider.add_theme_stylebox_override("grabber_area_highlight",fill)
		slider.value_changed.connect(_on_sensitivity_slider.bind(axis))
		slider.visible = false
		add_child(slider); sensitivity_sliders[axis] = slider
func _process(dt: float) -> void:
	clock += dt; update_sensitivity_sliders(); queue_redraw()

func settings_rect() -> Rect2:
	var extent := Vector2(minf(1040,size.x-64),780)
	return Rect2((size-extent)/2,extent)

func setting_value(axis: String) -> float:
	return app.gameplay_settings.get(axis) if axis.ends_with("_agility") or axis=="auto_aim" else app.vision.get(axis+"_sensitivity")

func setting_slider_rect(axis: String) -> Rect2:
	var card := settings_rect()
	var width := (card.size.x-112)/2
	if axis=="auto_aim": return Rect2(card.position+Vector2(36,581),Vector2(card.size.x-72,34))
	var agility := axis.ends_with("_agility")
	var index: int = ["pitch","bank","yaw"].find(axis.trim_suffix("_agility"))
	return Rect2(card.position+Vector2(36+(width+40 if agility else 0),221+110*index),Vector2(width,34))

func update_sensitivity_sliders() -> void:
	if not is_instance_valid(app): return
	var shown: bool = app.settings_visible
	for axis: String in sensitivity_sliders:
		var slider: HSlider = sensitivity_sliders[axis]
		slider.visible = shown
		if not shown:
			if slider.has_focus(): slider.release_focus()
			continue
		var rect := setting_slider_rect(axis)
		slider.position = rect.position
		slider.size = rect.size
		slider.set_value_no_signal(setting_value(axis))

func _on_sensitivity_slider(value: float, axis: String) -> void:
	sensitivity_changed.emit(axis,value)
func text(at: Vector2, value: String, size: int = 18, color: Color = WHITE, technical: bool = false) -> void:
	draw_string(mono if technical else font,at+Vector2(0,1),value,HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(size,12),Color(0.005,0.015,0.025,color.a*.85))
	draw_string(mono if technical else font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(size,12),color)
func line(a: Vector2,b: Vector2,color: Color=MUTED,width: float=1) -> void:
	draw_line(a,b,Color(0.005,0.015,0.025,color.a*0.48),width+1.8,true)
	draw_line(a,b,color,width,true)
func panel(rect: Rect2, alpha: float = 0.88) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015,0.029,0.042,alpha)
	style.border_color = Color(0.3,0.52,0.6,0.22)
	style.set_border_width_all(1); style.set_corner_radius_all(6)
	draw_style_box(style,rect)
func button(id: String,rect: Rect2,label: String,primary: bool = false) -> void:
	zones[id] = rect
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12,0.65,0.70,0.96) if primary else Color(0.06,0.11,0.15,0.96)
	if hot==id: style.bg_color = style.bg_color.lightened(0.13)
	style.border_color = CYAN if hot==id else Color(0.3,0.53,0.6,0.34)
	style.set_border_width_all(1); style.set_corner_radius_all(4)
	draw_style_box(style,rect)
	var width: float = font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
	text(rect.position+Vector2((rect.size.x-width)/2,rect.size.y/2+7),label,19,Color(0.02,0.06,0.08) if primary else WHITE)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hot = ""
		for id: String in zones:
			if (zones[id] as Rect2).has_point(event.position): hot = id
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if not hot.is_empty() else CURSOR_ARROW
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for id: String in zones:
			if (zones[id] as Rect2).has_point(event.position): action.emit(id); accept_event(); break
func _draw() -> void:
	if not is_instance_valid(app): return
	zones.clear()
	if app.mode=="tutorial":
		draw_control_tutorial()
		return
	if app.yoke_recovery_visible() and not app.overlay_visible():
		draw_flight()
		draw_yoke_recovery()
		return
	if app.mode=="title": draw_title()
	else: draw_flight()
	if app.mode=="paused": draw_pause()
	if app.mode=="results": draw_results()
	if app.help_visible: draw_help()
	if app.calibration_visible: draw_camera_setup()
	if app.credits_visible: draw_credits()
	if app.settings_visible: draw_settings()

func centered_text(at: Vector2, value: String, font_size: int = 18, color: Color = WHITE) -> void:
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	text(at-Vector2(width/2,0),value,font_size,color)

func tutorial_lines(value: String, width: float, font_size: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var current := ""
	for word: String in value.split(" "):
		var candidate := word if current.is_empty() else current+" "+word
		if not current.is_empty() and font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width:
			lines.append(current); current = word
		else: current = candidate
	if not current.is_empty(): lines.append(current)
	return lines

func tutorial_arrow(from: Vector2, to: Vector2, color: Color = CYAN) -> void:
	line(from,to,color,7)
	var direction := (to-from).normalized()
	var side := direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([to,to-direction*23+side*14,to-direction*23-side*14]),color)

func draw_tutorial_cue(rect: Rect2, key: String, group: String) -> void:
	var center := rect.get_center()
	var color := GREEN if app.tutorial.passed else CYAN
	if group == "throttle":
		# A labelled rail diagram, independent of how the phone is mounted.
		var left := center+Vector2(-88,35)
		var right := center+Vector2(88,35)
		line(left,right,MUTED,5)
		for point: Vector2 in [left,right]: draw_circle(point,7,MUTED)
		var handle := left.lerp(right,clampf(app.vision.throttle,0,1))
		line(handle-Vector2(0,8),handle-Vector2(0,43),WHITE,9)
		line(handle+Vector2(-15,-43),handle+Vector2(15,-43),WHITE,9)
		var toward_full := key == "full"
		tutorial_arrow(Vector2(left.x if toward_full else right.x,center.y-45),Vector2(right.x if toward_full else left.x,center.y-45),color)
		centered_text(left+Vector2(0,36),"0%",20)
		centered_text(right+Vector2(0,36),"100%",20)
		centered_text(center+Vector2(0,-80),"TOWARD FULL" if toward_full else "TOWARD IDLE",18,color)
	elif group == "yoke":
		if key in ["left","right"]:
			var points := PackedVector2Array()
			var direction := -1.0 if key == "left" else 1.0
			for i in range(25):
				var angle := -PI/2+direction*float(i)/24*PI*.65
				points.append(center+Vector2(cos(angle),sin(angle))*81)
			draw_polyline(points,color,7,true)
			tutorial_arrow(points[points.size()-3],points[-1],color)
			centered_text(center+Vector2(0,113),"TURN LEFT" if key=="left" else "TURN RIGHT",18,color)
		elif key in ["yaw_left","yaw_right"]:
			var direction := -1.0 if key=="yaw_left" else 1.0
			tutorial_arrow(center+Vector2(-direction*74,-65),center+Vector2(direction*74,-65),color)
			centered_text(center+Vector2(0,113),"SWIVEL LEFT" if key=="yaw_left" else "SWIVEL RIGHT",18,color)
		elif key in ["up","down"]:
			var direction := -1.0 if key == "up" else 1.0
			tutorial_arrow(center+Vector2(80,-direction*62),center+Vector2(80,direction*62),color)
			centered_text(center+Vector2(0,113),"PITCH UP" if key=="up" else "PITCH DOWN",18,color)
		else:
			line(center+Vector2(-85,0),center+Vector2(85,0),Color(CYAN,.4),1)
			centered_text(center+Vector2(0,113),"YOKE BASICS" if key=="yoke_info" else "HOLD LEVEL",18,color)
		# Simple yoke silhouette with two grips and a centre stem.
		var rotation := -.23 if key=="left" else .23 if key=="right" else 0.0
		var shape := PackedVector2Array()
		for point: Vector2 in [Vector2(-48,-26),Vector2(-48,8),Vector2(0,30),Vector2(48,8),Vector2(48,-26)]:
			shape.append(center+point.rotated(rotation))
		draw_polyline(shape,WHITE,9,true)
		line(center+Vector2(0,30).rotated(rotation),center+Vector2(0,62).rotated(rotation),WHITE,9)
	elif group == "weapons":
		var covering := key.begins_with("cover")
		var lifting := key == "show"
		var tag := "GUN"
		if key == "grip":
			draw_circle(center+Vector2(-42,0),28,GREEN)
			draw_circle(center+Vector2(42,0),28,Color(.28,.58,1))
			centered_text(center+Vector2(-42,7),"M",23,Color(.02,.06,.08))
			centered_text(center+Vector2(42,7),"R",23,Color(.02,.06,.08))
			centered_text(center+Vector2(0,88),"MIDDLE / RING",17,color)
		else:
			draw_rect(Rect2(center+Vector2(-43,-20),Vector2(86,75)),WHITE,false,4)
			centered_text(center+Vector2(0,28),tag,30)
			tutorial_arrow(center+Vector2(0,-92 if covering else -32),center+Vector2(0,-32 if covering else -92),color)
			centered_text(center+Vector2(0,105),"COVER TAG" if covering else "LIFT FINGER" if lifting else "SHOW TAG",18,color)
	else:
		line(center+Vector2(-50,0),center+Vector2(-12,38),GREEN,9)
		line(center+Vector2(-12,38),center+Vector2(65,-45),GREEN,9)
		centered_text(center+Vector2(0,98),"READY",20,GREEN)

func draw_control_tutorial() -> void:
	var lesson = app.tutorial
	var v: VisionClient = app.vision
	var done: bool = lesson.complete()
	var current: Array = lesson.step()
	var group: String = lesson.focus()
	var preview: Texture2D = app.vision_preview.texture
	draw_rect(Rect2(Vector2.ZERO,size),Color(.012,.025,.038))
	if preview != null:
		# Fixed aspect-fill background. Marker position never changes scale or centre.
		# Preview pixels arrive mirrored; text and movement arrows stay readable.
		var scale_factor := maxf(size.x/preview.get_width(),size.y/preview.get_height())
		var extent := preview.get_size()*scale_factor
		draw_texture_rect(preview,Rect2((size-extent)/2,extent),false)
	draw_rect(Rect2(Vector2.ZERO,size),Color(0,.01,.02,.12))
	panel(Rect2(24,20,400,34),.7)
	text(Vector2(38,43),"LIVE CAMERA / MIRRORED" if preview!=null else "WAITING FOR YOUR LIVE CAMERA",15,CYAN if preview!=null else MUTED,true)
	var labels := ["1  CALIBRATE","2  THROTTLE","3  YOKE","4  GUN"]
	var groups := ["calibrate","throttle","yoke","weapons"]
	var ends := [0,3,4,7]
	for i in range(4):
		var rect := Rect2(size.x/2-415+i*210,76,200,40)
		var checked: bool = not lesson.calibrating and lesson.index >= ends[i]
		panel(rect,.82)
		var selected: bool = i==0 if lesson.calibrating else group==groups[i]
		centered_text(rect.position+Vector2(100,27),("✓ " if checked else "")+labels[i],16,GREEN if checked else CYAN if selected else MUTED)
	var card_width := minf(size.x-96,1180)
	var text_width := card_width-320
	var title_lines := tutorial_lines("Ready for takeoff" if done else str(current[2]),text_width,34)
	var instruction_lines := tutorial_lines("Centre the yoke, set 0% throttle and cover the gun tag." if done else str(current[3]),text_width,23)
	var hint_lines := tutorial_lines("Hold steady for one second. Your flight starts automatically." if done else str(current[4]),text_width,20)
	var body_height := maxf(210,title_lines.size()*42+instruction_lines.size()*31+hint_lines.size()*27+32)
	var card := Rect2(Vector2((size.x-card_width)/2,size.y*.5-(body_height+165)/2),Vector2(card_width,body_height+165))
	panel(card,.45)
	draw_tutorial_cue(Rect2(card.position+Vector2(24,15),Vector2(228,body_height-42)),"ready" if done else str(current[0]),group)
	var at := card.position+Vector2(286,49)
	for value: String in title_lines:
		text(at,value,34); at.y += 42
	at.y += 7
	for value: String in instruction_lines:
		text(at,value,23); at.y += 31
	at.y += 10
	for value: String in hint_lines:
		text(at,value,20,MUTED); at.y += 27
	var meter_y := card.position.y+body_height+48
	line(Vector2(card.position.x+28,meter_y-33),Vector2(card.end.x-28,meter_y-33),Color(MUTED,.25))
	if lesson.calibrating:
		centered_text(Vector2(size.x/2,meter_y),"HOLD UPRIGHT  /  %.1f s" % (3.0*(1.0-lesson.progress())),24,CYAN)
	elif group == "throttle":
		text(Vector2(card.position.x+30,meter_y),"THROTTLE  %3d%%" % roundi(v.throttle*100),20,CYAN,true)
		var bar := Rect2(card.position.x+290,meter_y-16,card_width-324,16)
		draw_rect(bar,Color(.08,.15,.18)); draw_rect(Rect2(bar.position,Vector2(bar.size.x*v.throttle,16)),CYAN)
	elif group == "yoke":
		centered_text(Vector2(size.x/2,meter_y),"BANK %+.0f%%     PITCH %+.0f%%     YAW %+.0f%%" % [v.steering().x*100,v.steering().y*100,v.steering().z*100],20,CYAN)
	else:
		centered_text(Vector2(size.x/2,meter_y),"GUN: "+("ON" if v.gun_trigger else "OFF"),20,GREEN if v.gun_trigger else MUTED)
	var status: String = lesson.status if preview!=null else "Waiting for your live camera — keep the tracker connected."
	centered_text(Vector2(size.x/2,meter_y+46),status,21,GREEN if lesson.passed or lesson.can_start else WHITE)
	var progress_rect := Rect2(card.position.x+30,card.end.y-28,card_width-60,5)
	draw_rect(progress_rect,Color(.08,.15,.18))
	draw_rect(Rect2(progress_rect.position,Vector2(progress_rect.size.x*(clampf(float(lesson.ready_ms)/lesson.READY_HOLD_MS,0,1) if done else lesson.progress()),5)),GREEN if lesson.passed or done else CYAN)
	button("title",Rect2(32,size.y-84,245,52),"Back to main menu")
	if done:
		centered_text(Vector2(size.x/2,size.y-51),"Flight starts automatically when ready",19,MUTED)
	else:
		panel(Rect2(size.x/2-150,size.y-78,300,40),.72)
		centered_text(Vector2(size.x/2,size.y-51),"YOKE CALIBRATION" if lesson.calibrating else "YOKE OVERVIEW" if current[0]=="yoke_info" else "CHECK %02d / %02d" % [lesson.index+1,lesson.STEPS.size()],16,MUTED)
		button("tutorial_retry",Rect2(size.x-232,size.y-84,200,52),"Retry this step")

func draw_yoke_recovery() -> void:
	# Flight stays rendered and paused behind this small translucent overlay.
	zones.clear()
	var width := minf(1020,size.x-96)
	var card := Rect2((size.x-width)/2,size.y*.24,width,190)
	panel(card,.45)
	centered_text(Vector2(size.x/2,card.position.y+34),"FLIGHT PAUSED / YOKE OUT OF VIEW",16,CYAN)
	centered_text(Vector2(size.x/2,card.position.y+79),"Bring your yoke back into view",32)
	centered_text(Vector2(size.x/2,card.position.y+116),"Keep the whole yoke tag and its white border visible.",22,MUTED)
	var returning: bool = app.vision.tracking
	centered_text(Vector2(size.x/2,card.position.y+157),"Yoke found — hold steady to resume..." if returning else "Your flight will resume from this position.",20,GREEN if returning else WHITE)
	var camera_rect := Rect2(32,size.y-304,384,216)
	panel(camera_rect,.45)
	var preview: Texture2D = app.vision_preview.texture
	if preview != null:
		# Fit the complete frame in the helper inset, including its outer edges.
		var scale_factor := minf(camera_rect.size.x/preview.get_width(),camera_rect.size.y/preview.get_height())
		var extent := preview.get_size()*scale_factor
		draw_texture_rect(preview,Rect2(camera_rect.position+(camera_rect.size-extent)/2,extent),false)
	else:
		centered_text(camera_rect.get_center(),"Waiting for your camera...",19,MUTED)
	panel(Rect2(camera_rect.position,Vector2(camera_rect.size.x,32)),.45)
	text(camera_rect.position+Vector2(12,23),"YOKE CAMERA / MIRRORED",14,CYAN,true)
	button("keyboard",Rect2(size.x-312,size.y-84,280,52),"USE KEYBOARD")

func draw_title() -> void:
	if title_art!=null: draw_texture_rect(title_art,Rect2(0,0,1600,1000),false)
	else: draw_rect(Rect2(0,0,1600,1000),Color(0.025,0.045,0.07))
	# Draw a simple transparent scrim; retain the generated art as the focal point.
	draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(960,0),Vector2(960,1000),Vector2(0,1000)]),PackedColorArray([Color(0.012,0.025,0.038,0.90),Color(0.012,0.025,0.038,0),Color(0.012,0.025,0.038,0),Color(0.012,0.025,0.038,0.90)]))
	text(Vector2(72,100),"SHORT FLIGHT DEMO",16,CYAN,true)
	text(Vector2(66,283),"SPECTRE",86,WHITE)
	text(Vector2(72,335),"X—26",34,MUTED,true)
	line(Vector2(74,373),Vector2(478,373),Color(0.4,0.72,0.77,0.4))
	text(Vector2(74,421),"Sixteen geese. A flight to remember.",26,WHITE)
	text(Vector2(74,468),"Take off through the rings. Climb and cruise. Clear sixteen geese. Follow the rings to land.",18,MUTED)
	button("fly",Rect2(74,571,394,69),"PLAY / CHECK CONTROLS   →",true)
	button("route",Rect2(490,582,260,48),"ROUTE: "+("SAN FRANCISCO" if app.route_id=="sf" else "AZURE COAST" if app.route_id=="coast" else "ALPINE VALLEY"))
	button("keyboard_play",Rect2(490,659,260,48),"Keyboard / mouse")
	button("guided",Rect2(74,659,187,48),"Watch demo")
	button("approach",Rect2(279,659,189,48),"Landing practice")
	button("camera",Rect2(74,737,187,43),"Cardboard setup")
	button("help",Rect2(279,737,189,43),"Flight controls")
	button("settings",Rect2(490,737,260,43),"Settings")
	text(Vector2(74,846),"ENTER  PLAY    •    F1  CONTROLS",12,CYAN,true)
	text(Vector2(74,892),"CANNON  /  UNLIMITED AMMUNITION",11,MUTED,true)
	button("credits",Rect2(74,927,140,34),"Credits")
func draw_flight() -> void:
	if app.paper_test or app.cockpit:
		draw_clear_flight()
		return
	if app.paper_test:
		text(Vector2(460,150),"YOKE LIVE  /  ROTATE TO BANK  /  TILT TO PITCH" if app.vision.tracking else "HOLD MARKER 7 STEADY TO CENTER  /  FLIGHT HELD",16,CYAN,true)
	var f: FlightDynamics = app.flight
	var c: CombatDirector = app.combat
	text(Vector2(42,49),"SPECTRE / X–26",14,WHITE,true)
	text(Vector2(42,75),app.mission.label() if app.mission.active else "FCS NOMINAL" if c.hull>65 else "AIRFRAME CAUTION",12,CYAN if c.hull>65 else AMBER,true)
	text(Vector2(1376,49),"%02d:%02d" % [int(app.mission.clock)/60,int(app.mission.clock)%60] if app.mission.active else "%02d:%02d" % [maxi(0,int(ceil(c.duration-c.elapsed)))/60,maxi(0,int(ceil(c.duration-c.elapsed)))%60] if app.flight_kind=="combat" else ("SFO 28R" if app.route_id=="sf" else "RWY 36"),19,WHITE,true)
	text(Vector2(1376,73),"FLIGHT ASSIST" if app.copilot else "CARDBOARD" if app.vision.tracking else "LEVEL ASSIST",10,CYAN,true)
	var heading: float = fposmod(f.get_heading_degrees()+(298 if app.route_id=="sf" else 0),360)
	for index in range(-3,4):
		var x: float = 800+index*65
		text(Vector2(x-14,64),"%03d" % int(fposmod(heading+index*10,360)),11,CYAN if index==0 else MUTED,true)
		line(Vector2(x,74),Vector2(x,81),CYAN if index==0 else Color(0.4,0.6,0.66,0.3))
	draw_colored_polygon(PackedVector2Array([Vector2(795,88),Vector2(805,88),Vector2(800,94)]),CYAN)
	if not app.cockpit:
		text(Vector2(43,410),"IAS",10,MUTED,true)
		text(Vector2(41,445),str(int(f.speed*1.94384)),29,WHITE,true)
		text(Vector2(44,470),"KNOTS",9,MUTED,true)
		text(Vector2(1430,410),"ALT",10,MUTED,true)
		text(Vector2(1428,445),str(int(f.position.y*3.28084)),27,WHITE,true)
		text(Vector2(1431,470),"FEET MSL",9,MUTED,true)
		for i in range(-3,4):
			line(Vector2(126,439+i*22),Vector2(133 if i%2 else 140,439+i*22),Color(0.45,0.7,0.72,0.38))
			line(Vector2(1370,439+i*22),Vector2(1384 if i%2 else 1390,439+i*22),Color(0.45,0.7,0.72,0.38))
		text(Vector2(44,518),"%.1f G" % f.g_load,12,CYAN,true)
		text(Vector2(1430,518),"%+d" % int(f.vertical_speed*196.85),12,CYAN,true)
	var nose: Vector2 = app.camera.unproject_position(f.position+c.forward()*2000)
	var ring_edge: Vector3 = c.forward().rotated(app.camera.global_basis.x,deg_to_rad(c.acquire_angle()))
	var ring_radius: float = clampf(nose.distance_to(app.camera.unproject_position(f.position+ring_edge*1200)),38,115)
	var tracking: bool = c.target_id>=0 and c.assist
	var sight_color: Color = GREEN if tracking and c.lock_progress>=1 else AMBER if tracking else WHITE
	for i in range(4):
		var angle: float = i*PI/2
		draw_arc(nose,ring_radius,angle+.12,angle+PI/2-.12,20,Color(.48,.78,.82,.35),1,true)
		var direction := Vector2(cos(angle),sin(angle))
		line(nose+direction*(ring_radius-4),nose+direction*(ring_radius+4),Color(.55,.83,.85,.6),1)
	draw_circle(nose,2,Color(.65,.85,.87,.6))
	var center: Vector2 = app.camera.unproject_position(c.reticle_point())
	line(center+Vector2(-16,0),center+Vector2(-6,0),sight_color,1.8)
	line(center+Vector2(6,0),center+Vector2(16,0),sight_color,1.8)
	line(center+Vector2(0,-16),center+Vector2(0,-6),sight_color,1.8)
	line(center+Vector2(0,6),center+Vector2(0,12),sight_color,1.8)
	draw_circle(center,1.3,sight_color)
	if c.active and c.engagement_enabled:
		text(nose+Vector2(-50,ring_radius+22),"AUTO-AIM / %.1f°" % c.acquire_angle(),11,MUTED,true)
		if not tracking: text(nose+Vector2(-62,ring_radius+40),"ALIGN TO ACQUIRE",10,MUTED,true)
	for enemy: Dictionary in c.enemies:
		if app.camera.is_position_behind(enemy.position): continue
		var point: Vector2 = app.camera.unproject_position(enemy.position)
		if point.x<25 or point.x>1575 or point.y<115 or point.y>810: continue
		if enemy.id==c.target_id:
			var radius: float = clampf(12000/maxf(f.position.distance_to(enemy.position),1),22,40)
			var track_color: Color = GREEN if c.lock_progress>=1 else AMBER
			brackets(point,radius,track_color)
			text(point+Vector2(radius+10,-15),"TRK %02d" % (enemy.id+1),12,WHITE,true)
			text(point+Vector2(radius+10,2),"RNG %d M" % int(f.position.distance_to(enemy.position)),11,CYAN,true)
			text(point+Vector2(radius+10,20),"LOCK" if c.lock_progress>=1 else "ACQUIRING",11,track_color,true)
			line(point+Vector2(radius+10,29),point+Vector2(radius+62,29),Color(.4,.6,.6,.35),3)
			line(point+Vector2(radius+10,29),point+Vector2(radius+10+52*clampf(enemy.health/enemy.max_health,0,1),29),WHITE,2)
			line(point+Vector2(-radius,radius+7),point+Vector2(-radius+radius*2*c.lock_progress,radius+7),track_color,2)
			var distance: float = f.position.distance_to(enemy.position)
			var pip: Vector2 = app.camera.unproject_position(f.position+c.assisted_direction()*distance)
			if pip.distance_to(center)>7:
				line(center,pip,Color(.4,.85,.9,.35),1)
				draw_polyline(PackedVector2Array([pip+Vector2(0,-4),pip+Vector2(4,0),pip+Vector2(0,4),pip+Vector2(-4,0),pip+Vector2(0,-4)]),CYAN,1,true)
		else:
			line(point+Vector2(-4,-12),point+Vector2(0,-8),Color(0.91,0.7,0.48,0.5))
			line(point+Vector2(0,-8),point+Vector2(4,-12),Color(0.91,0.7,0.48,0.5))
	if c.hit_confirm>0:
		for side in [-1,1]: line(center+Vector2(side*12,side*12),center+Vector2(side*19,side*19),Color(1,0.84,0.4,c.hit_confirm),2)
	if c.reward_flash>0:
		text(Vector2(716,286 if app.mission.active else 146),"+%d" % c.last_reward,32,Color(1,.80,.36,c.reward_flash),true)
		if c.combo>=3: text(Vector2(716,314 if app.mission.active else 174),"%d IN A ROW" % c.combo,14,Color(.65,1,.83,c.reward_flash),true)
	if c.hit_flash>0:
		line(Vector2(20,270),Vector2(20,660),Color(1,0.25,0.15,c.hit_flash*1.7),4)
		line(Vector2(1580,270),Vector2(1580,660),Color(1,0.25,0.15,c.hit_flash*1.7),4)
	draw_scope(Vector2(1450,830),c)
	text(Vector2(47,860),"SPACE / LMB",18,WHITE,true)
	text(Vector2(47,886),"GATLING",14,CYAN,true)
	text(Vector2(47,927),"∞",36,WHITE)
	text(Vector2(98,920),"INFINITE",11,MUTED,true)
	text(Vector2(250,860),"STREAK",18,WHITE,true)
	text(Vector2(250,886),"KEEP IT GOING",14,CYAN,true)
	text(Vector2(250,927),"×%d" % c.combo,36,WHITE)
	if f.airborne:
		text(Vector2(44,550),"AIRBRAKE" if f.airbrake>.1 else "ACCEL" if f.power_input>.1 else "CRUISE",12,AMBER if f.airbrake>.1 else CYAN,true)
		text(Vector2(44,571),"W / S  SPEED",10,MUTED,true)
	if f.afterburner: text(Vector2(575,972),"AFTERBURNER",13,AMBER,true)
	else: text(Vector2(575,972),"POWER %03d%%" % int(f.throttle*100),13,MUTED,true)
	if f.gear or f.flaps>0: text(Vector2(42,967),"GEAR %s / FLAPS %d" % ["DOWN" if f.gear else "UP",f.flaps],12,AMBER,true)
	if c.message_time>0 and not app.mission.active: text(Vector2(610,215),c.message,14,AMBER,true)
	if (app.flight_kind=="approach" or (app.mission.active and app.mission.phase in ["return","approach"])) and f.airborne:
		var guidance: Dictionary = app.approach_data()
		var cross := Vector2(800,730)
		line(cross-Vector2(90,0),cross+Vector2(90,0),Color(0.5,0.75,0.73,0.4))
		line(cross-Vector2(0,35),cross+Vector2(0,35),Color(0.5,0.75,0.73,0.4))
		draw_circle(cross+Vector2(guidance.localizer*80,-guidance.glideslope*30),3,CYAN)
		text(Vector2(717,760),"DEMO AIRFIELD / APPROACH" if app.mission.active else "SFO 28R / APPROACH" if app.route_id=="sf" else "RWY 36 / APPROACH",11,CYAN,true)
	if app.mission.active and app.mode in ["flight","rollout"]: draw_demo_guidance()
	elif app.mode=="rollout": text(Vector2(630,739),"TOUCHDOWN / HOLD SPACE TO BRAKE",13,GREEN,true)
	if app.eject_hold>0: text(Vector2(663,730),"EJECT  %03d%%" % int(app.eject_hold/.9*100),15,AMBER,true)
	if app.mode=="ejected": text(Vector2(660,730),"EJECTION CONFIRMED",16,CYAN,true)
func draw_demo_guidance() -> void:
	var m = app.mission
	var card := Rect2(size.x/2-410,158,820,98)
	panel(card,.45)
	centered_text(Vector2(size.x/2,card.position.y+27),"%s    ·    TARGETS %d / %d" % [m.label(),mini(app.combat.kills,m.TARGET_COUNT),m.TARGET_COUNT],16,CYAN)
	centered_text(Vector2(size.x/2,card.position.y+62),m.instruction(),22,WHITE)
	if m.phase in ["takeoff","return","approach"]:
		var f = app.flight
		centered_text(Vector2(size.x/2,card.position.y+86),"THROTTLE %d%%   ·   GEAR %s   ·   FLAPS %d / 2" % [int(f.throttle*100),"DOWN" if f.gear else "UP",f.flaps],14,MUTED)
	if m.phase not in ["takeoff","combat","return","approach"] or m.route_index>=m.points.size(): return
	var target: Vector3 = m.route_target()
	var delta: Vector3 = target-app.flight.position
	var behind: bool = app.camera.is_position_behind(target)
	var nav: Vector2 = app.camera.unproject_position(target) if not behind else Vector2(120 if app.flight.forward().cross(delta).y>0 else size.x-120,size.y*.45)
	var edge: Vector2 = nav.clamp(Vector2(130,290),Vector2(size.x-130,size.y-230))
	if behind or edge.distance_to(nav)>10:
		var direction := (nav-size/2).normalized()
		if behind: direction = Vector2(-1 if nav.x<size.x/2 else 1,0)
		var side := Vector2(-direction.y,direction.x)
		draw_colored_polygon(PackedVector2Array([edge+direction*16,edge-direction*10+side*10,edge-direction*10-side*10]),AMBER)
		centered_text(edge+Vector2(0,36),"NEXT RING",15,AMBER)
	else:
		centered_text(nav+Vector2(0,30),"NEXT RING · %d M" % int(delta.length()),14,AMBER)

func flight_heading() -> float:
	return fposmod(app.flight.get_heading_degrees()+(298.0 if app.route_id=="sf" else 0.0),360.0)

func draw_clear_flight() -> void:
	if not app.text_hud: return
	var f: FlightDynamics=app.flight
	var c: CombatDirector=app.combat
	text(Vector2(52,64),"%d KNOTS" % int(f.speed*1.94384),24,WHITE,true)
	text(Vector2(1280,64),"%d FT" % int(f.position.y*3.28084),24,WHITE,true)
	text(Vector2(740,64),"%03d°" % int(flight_heading()),23,CYAN,true)
	var instruction: String=""
	if app.mission.active: instruction=""
	elif app.paper_test:
		instruction="ROTATE TO BANK  ·  TILT TOP TOWARD YOU TO CLIMB" if app.vision.tracking else "SHOW MARKER 7 AND HOLD STILL — FLIGHT HELD"
	elif app.mission.active: instruction=app.mission.instruction()
	var width: float=font.get_string_size(instruction,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
	text(Vector2(800-width/2,122),instruction,19,CYAN)
	if app.mission.active: draw_demo_guidance()
	var center: Vector2=app.camera.unproject_position(c.reticle_point())
	line(center-Vector2(16,0),center-Vector2(5,0),WHITE)
	line(center+Vector2(5,0),center+Vector2(16,0),WHITE)
	if c.active and c.engagement_enabled:
		for enemy: Dictionary in c.enemies:
			if enemy.id!=c.target_id or app.camera.is_position_behind(enemy.position): continue
			var at: Vector2=app.camera.unproject_position(enemy.position)
			brackets(at,24,GREEN if c.lock_progress>=1 else AMBER)
			text(at+Vector2(34,0),"%d M" % int(f.position.distance_to(enemy.position)),16,WHITE,true)
	if app.paper_test:
		text(Vector2(52,920),"BANK  %+.0f%%     PITCH  %+.0f%%" % [app.control.x*100,app.control.y*100],21,WHITE,true)
		text(Vector2(52,957),"R  RESET FLIGHT   ·   SPACE IN CAMERA WINDOW  RECENTER",15,MUTED)
	else:
		text(Vector2(52,951),"POWER %d%%  ·  GEAR %s" % [int(f.throttle*100),"DOWN" if f.gear else "UP"],17,MUTED)
		if c.active and c.engagement_enabled:
			text(Vector2(1090,951),"GUN TAG / UNCOVER TO FIRE" if app.vision.enabled else "SPACE / LEFT MOUSE  FIRE",17,MUTED)
			text(Vector2(680,290 if app.mission.active else 170),"TARGET TRACKED" if c.lock_progress>=1 else "",20,GREEN)
	if f.stall_time>.6: text(Vector2(660,250),"STALL — LOWER NOSE",20,AMBER)
	if not app.audio.radio.caption.is_empty():
		var caption: String=app.audio.radio.caption
		var caption_width: float=font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
		text(Vector2(800-caption_width/2,880),caption,18,WHITE)

func draw_scope(center: Vector2,c: CombatDirector) -> void:
	draw_circle(center,79,Color(0.015,0.035,0.045,0.50))
	for radius in [38.0,76.0]: draw_arc(center,radius,0,TAU,64,Color(0.34,0.65,0.63,0.35),1,true)
	line(center-Vector2(76,0),center+Vector2(76,0),Color(0.3,0.55,0.55,0.23))
	line(center-Vector2(0,76),center+Vector2(0,76),Color(0.3,0.55,0.55,0.23))
	for enemy: Dictionary in c.enemies:
		var delta: Vector3 = enemy.position-app.flight.position
		var point: Vector2 = (Vector2(delta.x,delta.z).rotated(-app.flight.heading)*0.025).limit_length(73)
		draw_circle(center+point,2.5,GREEN if enemy.id==c.target_id else AMBER)
	draw_colored_polygon(PackedVector2Array([center+Vector2(0,-6),center+Vector2(-3,4),center+Vector2(3,4)]),WHITE)
	text(center+Vector2(-55,-91),"CONTACTS %02d" % c.enemies.size(),10,MUTED,true)
	text(center+Vector2(-29,96),"3 KM",9,MUTED,true)
func brackets(point: Vector2,radius: float,color: Color) -> void:
	for x in [-1,1]:
		for y in [-1,1]:
			var corner := point+Vector2(x*radius,y*radius)
			line(corner,corner-Vector2(x*7,0),color,1.5)
			line(corner,corner-Vector2(0,y*7),color,1.5)
func draw_control_feedback() -> void:
	for i in range(3):
		var at := Vector2(650+i*120,930)
		var value: float = app.control[i]
		text(at,["ROLL","PITCH","YAW"][i],9,MUTED,true)
		line(at+Vector2(0,11),at+Vector2(90,11),Color(0.2,0.4,0.4,0.4),2)
		line(at+Vector2(45,11),at+Vector2(45+value*45,11),GREEN,2)
func dim() -> void: draw_rect(Rect2(0,0,1600,1000),Color(0.008,0.018,0.027,0.76))
func draw_pause() -> void:
	zones.clear(); dim(); panel(Rect2(540,247,520,505),.95)
	text(Vector2(589,310),"FLIGHT PAUSED",13,CYAN,true)
	text(Vector2(587,360),"You have the controls.",29,WHITE)
	button("resume",Rect2(589,405,422,59),"RESUME FLIGHT",true)
	button("help",Rect2(589,483,200,47),"Controls")
	button("mute",Rect2(811,483,200,47),"Audio off" if app.audio.muted else "Audio on")
	button("settings",Rect2(589,548,200,47),"Settings")
	button("quality",Rect2(811,548,200,47),"High quality" if app.high_quality else "Balanced quality")
	button("restart",Rect2(589,613,200,47),"Restart sortie")
	button("title",Rect2(811,613,200,47),"Return to deck")
	text(Vector2(589,714),"ESC  RESUME",11,MUTED,true)
func draw_results() -> void:
	zones.clear(); dim(); panel(Rect2(380,228,840,547),.95)
	var c: CombatDirector = app.combat
	text(Vector2(432,291),"SPECTRE / SORTIE RECORD",13,CYAN,true)
	text(Vector2(430,347),"AIRCRAFT SECURED" if app.mission_success and app.flight.contact=="landed" else "RETURN VECTOR" if app.mission_success else "SORTIE ENDED",35,WHITE)
	text(Vector2(433,390),app.result_reason,17,MUTED)
	line(Vector2(433,420),Vector2(1167,420),Color(0.3,0.5,0.56,0.4))
	var labels: Array[String] = ["TARGETS CLEARED","BEST STREAK","SCORE"]
	var values: Array[String] = ["%d / %d" % [c.kills,app.mission.TARGET_COUNT] if app.mission.active else str(c.kills),"×%d" % c.best_combo,str(c.score)]
	for i in range(3):
		text(Vector2(433+i*255,466),labels[i],11,MUTED,true)
		text(Vector2(431+i*255,516),values[i],36,WHITE,true)
	text(Vector2(433,575),"NEW PERSONAL BEST!" if app.record_broken else "TAKEOFF  /  INTERCEPT  /  LANDING COMPLETE" if app.mission.active and app.mission_success else "Guided pilot used" if app.used_copilot else "Manual sortie",14,MUTED)
	button("fly",Rect2(433,642,350,62),"PLAY AGAIN",true)
	button("title",Rect2(816,642,350,62),"FLIGHT DECK")
func draw_help() -> void:
	zones.clear(); dim(); panel(Rect2(365,136,870,738),.97)
	text(Vector2(419,196),"FLIGHT CONTROLS",13,CYAN,true)
	text(Vector2(417,244),"Precision starts with small inputs.",30,WHITE)
	var rows: Array[Array] = [["ARROWS / A D","Pitch and roll / rudder"],["W S / SHIFT","Accelerate / airbrake / hold afterburner"],["SPACE / LEFT MOUSE","Hold for Gatling fire; unlimited ammunition"],["Z / Q","Countermeasures / barrel roll"],["V","Cockpit or chase view"],["ALT + MOUSE","Look around without steering"],["G / F","Landing gear / flap detent"],["B / J","Mouse flight / close-range aim assistance"],["H / HOLD E","Flight assist / eject"],["C / ESC / M","Cardboard setup / pause / mute"]]
	for i in range(rows.size()):
		text(Vector2(421,293+i*40),rows[i][0],13,WHITE,true)
		text(Vector2(707,293+i*40),rows[i][1],16,MUTED)
	button("help",Rect2(909,787,269,48),"RETURN TO FLIGHT",true)
	text(Vector2(421,817),"R RESTART / F9 TELEMETRY",10,MUTED,true)
func draw_settings() -> void:
	zones.clear(); dim()
	var card := settings_rect()
	panel(card,.94)
	text(card.position+Vector2(36,42),"SETTINGS / SAVED AUTOMATICALLY",13,CYAN,true)
	text(card.position+Vector2(36,86),"Flight & aiming",32)
	text(card.position+Vector2(36,120),"Changes apply immediately. Move the yoke to check its response.",18,MUTED)
	var column_width := (card.size.x-112)/2
	text(card.position+Vector2(36,158),"SENSITIVITY / INPUT AMOUNT",13,CYAN,true)
	text(card.position+Vector2(76+column_width,158),"AGILITY / MOVEMENT SPEED",13,CYAN,true)
	var labels := {"pitch":"Pitch / up & down", "bank":"Bank / wing tilt", "yaw":"Yaw / nose left & right"}
	for axis: String in SETTING_AXES:
		var rect := setting_slider_rect(axis)
		var label: String = "Auto-aim / target tracking" if axis=="auto_aim" else labels[axis.trim_suffix("_agility")]
		text(rect.position+Vector2(0,-15),label,21)
		text(rect.position+Vector2(rect.size.x-84,-15),"%.2f×" % setting_value(axis),22,CYAN,true)
		var low: String = "Off" if axis=="auto_aim" else "0.50×" if axis.ends_with("_agility") else "0.25×"
		text(rect.position+Vector2(0,53),low,14,MUTED)
		text(rect.position+Vector2(rect.size.x-48,53),"3.00×",14,MUTED)
	var v = app.vision
	var output: Vector3 = v.steering()
	var readout := "Live input:  PITCH %+.0f%%   BANK %+.0f%%   YAW %+.0f%%" % [output.y*100,output.x*100,output.z*100]
	text(card.position+Vector2(36,516),readout if v.tracking else "Show the yoke to see live input here.",16,CYAN if v.tracking else MUTED,true)
	var sync_label := "Settings saved · tracker disconnected"
	if v.tracker_settings.synced(v.sensitivity_values()): sync_label = "Settings applied to the game and camera tracker"
	elif v.connected: sync_label = "Applying camera settings…"
	text(card.position+Vector2(36,663),sync_label,16,MUTED)
	button("sensitivity_reset",Rect2(card.position+Vector2(36,704),Vector2(240,52)),"Reset to defaults")
	button("settings",Rect2(card.position+Vector2(card.size.x-236,704),Vector2(200,52)),"Done",true)

func draw_camera_setup() -> void:
	zones.clear(); dim(); panel(Rect2(370,175,860,650),.97)
	text(Vector2(421,236),"CARDBOARD / LOCAL INPUT",13,CYAN,true)
	text(Vector2(419,291),"Your cockpit. Your aircraft.",32,WHITE)
	var lines: Array[String] = ["1. Start tools/tracker.sh --camera 0 --paper-test.","2. Hold the yoke steady and show all three throttle tags.","3. Enable tracking below, then centre the yoke.","Throttle alone: use --throttle-only; arrows steer, W/S takes over.","Keep all three throttle tags flat and visible to the camera.","Gun tag: uncover to fire, cover to stop."]
	for i in range(lines.size()): text(Vector2(423,345+i*42),lines[i],17,MUTED if i>2 else WHITE)
	text(Vector2(423,586),app.vision.status,13,CYAN if app.vision.tracking else AMBER,true)
	text(Vector2(423,626),"ROLL %+.2f / PITCH %+.2f / POWER %03d%%" % [app.vision.steering().x,app.vision.steering().y,int(app.vision.throttle*100)],15,WHITE,true)
	text(Vector2(423,666),"GUN: %s" % ("FIRE" if app.vision.gun_trigger else "OFF"),15,WHITE,true)
	button("vision",Rect2(423,708,364,59),"TRACKING ENABLED" if app.vision.enabled else "ENABLE TRACKING",true)
	button("camera",Rect2(814,708,363,59),"RETURN")
func draw_credits() -> void:
	zones.clear(); dim(); panel(Rect2(355,170,890,660),.97)
	text(Vector2(409,233),"BUILT WITH OPEN TOOLS",13,CYAN,true)
	var lines: Array[String] = ["SPECTRE X-26 is a fictional, game-tuned airframe.","Base aircraft: FlightGear F-35B community; GPL source included.","Canada goose: Poly by Google; CC BY 3.0.","Effects and voices: Kenney; CC0.","Music: MintoDog; CC0. Goose recordings: British Library; CC BY-SA.","Environment materials: Poly Haven; CC0.","Title art: image generation. Runtime systems: original project code.","Godot 4.7.2 / MIT. Complete notices are bundled with the app."]
	for i in range(lines.size()): text(Vector2(410,293+i*43),lines[i],17,WHITE if i==0 else MUTED)
	button("credits",Rect2(905,733,283,51),"BACK",true)
