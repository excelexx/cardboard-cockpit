extends Control
class_name CockpitHUD

signal action(name: String)
signal select_aircraft(index: int)

var app: Node
var font := SystemFont.new()
var mono := SystemFont.new()
var hot := ""
var zones: Dictionary = {}
var fade := GradientTexture2D.new()
const INK := Color(0.045,0.08,0.10,0.93)
const WHITE := Color(0.91,0.94,0.94)
const MUTED := Color(0.56,0.65,0.69)
const AMBER := Color(0.96,0.70,0.37)
const GREEN := Color(0.49,0.84,0.71)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue"])
	mono.font_names = PackedStringArray(["Menlo", "Courier"])
	var gradient := Gradient.new()
	gradient.set_color(0,Color(0.025,0.05,0.07,0.95))
	gradient.set_color(1,Color(0.025,0.05,0.07,0.0))
	fade.gradient = gradient
	fade.width = 512
	fade.height = 2
	fade.fill_from = Vector2.ZERO
	fade.fill_to = Vector2.RIGHT
	mouse_filter = Control.MOUSE_FILTER_PASS

func _process(_dt: float) -> void:
	queue_redraw()

func text(at: Vector2, value: String, size: int = 20, color: Color = WHITE, technical: bool = false) -> void:
	draw_string(mono if technical else font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func paragraph(at: Vector2, value: String, width: float, size: int, color: Color) -> void:
	var current := ""
	var row := 0
	for word: String in value.split(" "):
		var candidate: String = word if current.is_empty() else current + " " + word
		if not current.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			text(at + Vector2(0, row * (size + 5)), current, size, color)
			row += 1
			current = word
		else:
			current = candidate
	text(at + Vector2(0, row * (size + 5)), current, size, color)

func line(a: Vector2, b: Vector2, color: Color = Color(0.4,0.55,0.6,0.3), width: float = 1.0) -> void:
	draw_line(a,b,color,width,true)

func panel(rect: Rect2, color: Color = INK) -> void:
	draw_style_box(style(color,Color(0.50,0.64,0.69,0.20)),rect)

func style(bg: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	return s

func button(id: String, rect: Rect2, label: String, primary: bool = false) -> void:
	zones[id] = rect
	var hover: bool = hot == id
	draw_style_box(style(AMBER.lightened(0.12) if primary and hover else AMBER if primary else Color(0.16,0.23,0.27,0.97) if hover else INK, AMBER if primary else Color(0.45,0.57,0.62,0.35)),rect)
	var size: int = 20
	var width: float = font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	text(rect.position+Vector2((rect.size.x-width)*0.5,rect.size.y*0.5+7),label,size,INK if primary else WHITE)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hot = ""
		for id: String in zones:
			if (zones[id] as Rect2).has_point(event.position):
				hot = id
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hot != "" else Control.CURSOR_ARROW
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for id: String in zones:
			if (zones[id] as Rect2).has_point(event.position):
				if id.begins_with("plane_"):
					select_aircraft.emit(int(id.trim_prefix("plane_")))
				else:
					action.emit(id)
				accept_event()
				break

func _draw() -> void:
	if not is_instance_valid(app):
		return
	zones.clear()
	# UI is composed at 1600×1000 and scaled by Godot with the window.
	if app.mode == "hangar" or app.mode == "briefing":
		draw_hangar()
	else:
		draw_flight()
	if app.mode == "briefing":
		draw_briefing()
	elif app.mode == "paused":
		draw_pause()
	elif app.mode == "results":
		draw_results()
	if app.help_visible:
		draw_help()
	if app.calibration_visible:
		draw_calibration()
	if app.credits_visible:
		draw_credits()

func masthead() -> void:
	text(Vector2(58,57),"C / C",28,AMBER)
	line(Vector2(144,29),Vector2(144,64))
	text(Vector2(169,48),"CARDBOARD COCKPIT",17)
	text(Vector2(170,67),"FLIGHT EXPERIENCE",11,MUTED,true)
	text(Vector2(1192,48),"NATIVE CLIENT  /  LOCAL FLIGHT",12,MUTED,true)
	draw_circle(Vector2(1524,44),4,GREEN)
	line(Vector2(58,88),Vector2(1542,88))

func draw_hangar() -> void:
	# The dark editorial panel leaves the aircraft unobstructed on the right.
	draw_texture_rect(fade,Rect2(0,89,800,655),false)
	draw_rect(Rect2(0,0,1600,89),Color(0.035,0.055,0.07,0.86))
	masthead()
	var p: Dictionary = app.profile()
	text(Vector2(60,153),"01  /  THE HANGAR",13,AMBER,true)
	text(Vector2(60,220),"A cardboard dream.",41)
	text(Vector2(60,270),"A real flight.",41)
	text(Vector2(62,313),"Choose your aircraft. Find your horizon.",18,MUTED)
	line(Vector2(62,354),Vector2(392,354))
	text(Vector2(62,393),str(p.maker),13,MUTED,true)
	text(Vector2(60,443),str(p.name),32)
	text(Vector2(62,472),str(p.type),12,AMBER,true)
	var lines: PackedStringArray = str(p.description).split("\n")
	for i: int in lines.size():
		text(Vector2(62,510+i*25),lines[i],15,MUTED)
	text(Vector2(62,600),"WINGSPAN",11,MUTED,true)
	text(Vector2(229,600),"LENGTH",11,MUTED,true)
	text(Vector2(380,600),"ENGINES",11,MUTED,true)
	text(Vector2(60,635),"%.1f m" % p.span,24)
	text(Vector2(228,635),"%.1f m" % p.length,24)
	text(Vector2(382,635),str(p.engines),24)
	text(Vector2(62,693),"EXTERIOR MODEL  /  FLIGHTGEAR COMMUNITY",10,MUTED,true)
	text(Vector2(1060,698),"DRAG TO ORBIT   ·   SCROLL TO ZOOM",11,MUTED,true)
	draw_rect(Rect2(0,735,1600,265),Color(0.025,0.045,0.06,0.98))
	line(Vector2(58,735),Vector2(1542,735))
	text(Vector2(59,770),"YOUR FLEET",12,MUTED,true)
	text(Vector2(1380,770),"05 AIRCRAFT",12,MUTED,true)
	for i: int in 5:
		var rect := Rect2(58+i*300,790,284,104)
		var selected: bool = i == app.selected
		zones["plane_%d" % i] = rect
		panel(rect,Color(0.17,0.22,0.25) if selected else Color(0.07,0.105,0.13))
		if selected:
			draw_rect(Rect2(rect.position,Vector2(3,104)),AMBER)
		text(rect.position+Vector2(19,24),"0%d" % (i+1),10,AMBER if selected else MUTED,true)
		text(rect.position+Vector2(18,59),str(AircraftCatalog.PLANES[i].short),27,WHITE if selected else MUTED)
		text(rect.position+Vector2(18,84),str(AircraftCatalog.PLANES[i].label),10,MUTED,true)
	text(Vector2(60,954),"KEYBOARD + MOUSE READY",12,GREEN,true)
	text(Vector2(353,954),"MOUNTAIN VALLEY  /  GOLDEN HOUR",12,MUTED,true)
	button("help",Rect2(1018,924,200,48),"Controls  /  F1")
	button("brief",Rect2(1240,920,302,56),"PREPARE FLIGHT   →",true)

func draw_briefing() -> void:
	zones.clear()
	draw_rect(Rect2(0,0,1600,1000),Color(0.015,0.03,0.045,0.78))
	panel(Rect2(350,170,900,660))
	text(Vector2(406,225),"02  /  FLIGHT BRIEFING",13,AMBER,true)
	text(Vector2(404,280),"The valley is yours.",40)
	text(Vector2(406,324),"ALPINE DEPARTURE   →   FIVE CHECKPOINTS   →   NORTH FIELD",13,MUTED,true)
	line(Vector2(406,349),Vector2(1194,349))
	var items: Array[String] = ["01   DEPART     Hold W for power. At %d kt, hold ↑ to lift off." % int(float(app.profile().rotation_speed)*1.94384),"02   EXPLORE    Follow the glowing rings through the valley.","03   ARRIVE      After ring 5, lower gear and follow the approach."]
	for i: int in 3:
		text(Vector2(406,402+i*55),items[i],18,WHITE)
	text(Vector2(406,595),"↑ / ↓ pitch    ← / → bank    A / D rudder    W / S power",16,MUTED,true)
	text(Vector2(406,626),"V camera    G gear    SPACE brakes    R reset    ESC pause",16,MUTED,true)
	text(Vector2(406,676),"First time? Press H in flight for a training copilot. Take over anytime.",17,GREEN)
	button("hangar",Rect2(406,725,205,54),"Back to hangar")
	button("fly",Rect2(883,725,311,54),"CLEARED FOR TAKEOFF  →",true)

func draw_flight() -> void:
	var f: FlightDynamics = app.flight
	panel(Rect2(28,24,1544,76),Color(0.03,0.06,0.08,0.82))
	text(Vector2(51,59),"C / C",24,AMBER)
	text(Vector2(151,52),str(app.profile().name),15)
	text(Vector2(151,76),app.phase_label(),11,GREEN,true)
	text(Vector2(598,53),"ALPINE  →  NORTH FIELD",14,WHITE,true)
	text(Vector2(599,78),"CHECKPOINTS  %d / 5" % app.ring_index,12,MUTED,true)
	text(Vector2(1130,53),"%02d:%02d" % [int(f.elapsed)/60,int(f.elapsed)%60],21,WHITE,true)
	text(Vector2(1280,51),"COPILOT" if app.copilot else "MANUAL FLIGHT",13,AMBER if app.copilot else GREEN,true)
	text(Vector2(1280,76),"%s   ·   %d FPS" % ["COCKPIT" if app.cockpit else "CHASE",Engine.get_frames_per_second()],11,MUTED,true)
	# Central heading ribbon and horizon flight director.
	panel(Rect2(581,120,438,44),Color(0.03,0.06,0.08,0.5))
	for offset: int in range(-2,3):
		text(Vector2(607+(offset+2)*84,149),"%03d" % int(fposmod(f.get_heading_degrees()+offset*15,360)),14,AMBER if offset==0 else MUTED,true)
	draw_colored_polygon(PackedVector2Array([Vector2(793,169),Vector2(807,169),Vector2(800,176)]),AMBER)
	var center := Vector2(800,435)
	line(center+Vector2(-65,0),center+Vector2(-22,0),Color(1,1,1,0.85),2)
	line(center+Vector2(22,0),center+Vector2(65,0),Color(1,1,1,0.85),2)
	line(center+Vector2(-22,0),center+Vector2(0,8),Color(1,1,1,0.85),2)
	line(center+Vector2(0,8),center+Vector2(22,0),Color(1,1,1,0.85),2)
	draw_circle(center,3,AMBER)
	if f.airborne:
		for degree: int in [-20,-10,0,10,20]:
			var offset_y: float = (rad_to_deg(f.pitch)-degree)*6.0
			if absf(offset_y)<150:
				var a := Vector2(-100,offset_y).rotated(f.roll)
				var b := Vector2(100,offset_y).rotated(f.roll)
				line(center+a,center+b,Color(0.8,0.93,0.97,0.35),1)
				text(center+b+Vector2(9,5),str(degree),11,MUTED,true)
	var target: Vector3 = app.target_position()
	var distance: float = f.position.distance_to(target)
	panel(Rect2(28,122,346,98),Color(0.03,0.06,0.08,0.78))
	text(Vector2(49,151),"NEXT  /  " + ("CHECKPOINT %02d" % (app.ring_index+1) if app.ring_index<5 else "RUNWAY 36"),11,AMBER,true)
	text(Vector2(48,184),"%.1f km" % (distance/1000.0),27)
	text(Vector2(207,182),"%d FT MSL" % int(target.y*3.28084),12,MUTED,true)
	text(Vector2(49,207),"H  TRAINING COPILOT / TAKE OVER",10,GREEN if app.copilot else MUTED,true)
	if app.spectator:
		panel(Rect2(1218,122,354,183),Color(0.03,0.06,0.08,0.85))
		text(Vector2(1240,154),"THE CARDBOARD CONNECTION",12,AMBER,true)
		text(Vector2(1240,187),app.vision.status,11,GREEN,true)
		text(Vector2(1240,219),"A webcam sees cardboard controls",16)
		text(Vector2(1240,244),"and turns movement into flight.",16)
		text(Vector2(1240,278),"C  CAMERA SETUP    ·    TAB  HIDE",10,MUTED,true)
	# Lower cockpit-style instrument strip.
	panel(Rect2(28,831,1544,140),Color(0.025,0.05,0.065,0.92))
	var labels: Array[String] = ["AIRSPEED", "ALTITUDE MSL", "VERTICAL SPEED", "ENGINE POWER", "HEADING", "LANDING GEAR"]
	var values: Array[String] = ["%03d" % int(f.speed*1.94384),"%05d" % int(f.position.y*3.28084),"%+05d" % int(f.vertical_speed*196.85),"%03d" % int(f.throttle*100),"%03d°" % int(f.get_heading_degrees()),"DOWN" if f.gear else "UP"]
	var units: Array[String] = ["KNOTS", "FEET", "FT / MIN", "PERCENT", "MAGNETIC", "G TO TOGGLE"]
	for i: int in 6:
		var x: float = 54+i*254
		text(Vector2(x,860),labels[i],11,MUTED,true)
		text(Vector2(x-1,911),values[i],36,GREEN if i==5 and f.gear else WHITE,true)
		text(Vector2(x,944),units[i],10,MUTED,true)
		if i<5:
			line(Vector2(x+228,855),Vector2(x+228,947))
	line(Vector2(815,956),Vector2(1025,956),MUTED,3)
	line(Vector2(815,956),Vector2(815+210*f.throttle,956),AMBER,3)
	var prompt: String = app.flight_prompt()
	var tw: float = font.get_string_size(prompt,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
	panel(Rect2(800-tw*0.5-24,751,tw+48,49),Color(0.04,0.085,0.11,0.86))
	text(Vector2(800-tw*0.5,782),prompt,20,AMBER if f.stall_time>1 else WHITE)
	text(Vector2(36,993),"W/S POWER   ARROWS PITCH / BANK   A/D RUDDER   V CAMERA   G GEAR   H COPILOT   F1 HELP   ESC PAUSE",10,MUTED,true)
	if app.toast_time>0:
		var w: float = font.get_string_size(app.toast,HORIZONTAL_ALIGNMENT_LEFT,-1,24).x
		panel(Rect2(800-w/2-28,247,w+56,60))
		text(Vector2(800-w/2,286),app.toast,24,GREEN)

func draw_pause() -> void:
	zones.clear()
	draw_rect(Rect2(0,0,1600,1000),Color(0.015,0.03,0.045,0.76))
	panel(Rect2(540,235,520,535))
	text(Vector2(598,300),"FLIGHT PAUSED",13,AMBER,true)
	text(Vector2(596,355),"Take a moment.",35)
	button("resume",Rect2(598,401,404,58),"RESUME FLIGHT",true)
	button("restart",Rect2(598,478,404,52),"Restart from runway")
	button("hangar",Rect2(598,545,404,52),"Choose another aircraft")
	button("help",Rect2(598,612,192,50),"Controls")
	button("mute",Rect2(810,612,192,50),"Sound: OFF" if app.audio.muted else "Sound: ON")
	text(Vector2(598,719),"Q  QUALITY: %s" % ("HIGH" if app.high_quality else "BALANCED"),12,MUTED,true)

func draw_results() -> void:
	zones.clear()
	draw_rect(Rect2(0,0,1600,1000),Color(0.015,0.03,0.045,0.79))
	panel(Rect2(370,200,860,605))
	var success: bool = app.mission_success
	text(Vector2(428,254),"FLIGHT DEBRIEF",13,AMBER,true)
	text(Vector2(426,319),"Welcome to North Field." if success else "Every flight teaches you.",36)
	paragraph(Vector2(428,355),app.result_reason,742,17,GREEN if success else MUTED)
	line(Vector2(428,397),Vector2(1170,397))
	var f: FlightDynamics = app.flight
	var names: Array[String] = ["FLIGHT TIME", "CHECKPOINTS", "SMOOTHNESS"]
	var values: Array[String] = ["%02d:%02d" % [int(f.elapsed)/60,int(f.elapsed)%60],"%d / 5" % app.ring_index,"%d%%" % f.get_smoothness()]
	for i: int in 3:
		text(Vector2(428+i*263,438),names[i],11,MUTED,true)
		text(Vector2(427+i*263,486),values[i],36,WHITE,true)
	text(Vector2(428,560),"CAPTAIN" if success and f.get_smoothness()>80 else "CADET PILOT" if success else "PILOT IN TRAINING",24,AMBER)
	text(Vector2(428,597),"%s  ·  %s" % [str(app.profile().short), "Training copilot used" if app.used_copilot else "Manual flight"],16,MUTED)
	button("restart",Rect2(428,674,349,62),"FLY AGAIN  →",true)
	button("hangar",Rect2(800,674,370,62),"NEXT PILOT / HANGAR")

func draw_help() -> void:
	zones.clear()
	draw_rect(Rect2(0,0,1600,1000),Color(0.015,0.03,0.045,0.90))
	panel(Rect2(315,105,970,785))
	text(Vector2(370,166),"YOUR FLIGHT CONTROLS",14,AMBER,true)
	text(Vector2(368,222),"A little input goes a long way.",35)
	var rows: Array[Array] = [["W / S", "Increase / decrease engine power"],["↑ / ↓", "Nose up / nose down"],["← / →", "Bank left / right"],["A / D", "Rudder and runway steering"],["RIGHT MOUSE", "Hold and drag to look around"],["B", "Toggle mouse yoke (move cursor to steer)"],["G  /  SPACE", "Landing gear / wheel brakes"],["V  /  H", "Cockpit or chase view / training copilot"],["R  /  M", "Reset aircraft / mute sound"],["TAB  /  C", "Spectator panel / camera setup"],["ESC  /  Q", "Pause / change render quality"]]
	for i: int in rows.size():
		text(Vector2(373,272+i*41),str(rows[i][0]),15,WHITE,true)
		text(Vector2(657,272+i*41),str(rows[i][1]),17,MUTED)
	button("help",Rect2(943,802,283,52),"GOT IT  /  F1",true)
	button("credits",Rect2(373,802,283,52),"Credits & sources")

func draw_credits() -> void:
	zones.clear()
	draw_rect(Rect2(0,0,1600,1000),Color(0.015,0.03,0.045,0.97))
	panel(Rect2(295,125,1010,750))
	text(Vector2(353,185),"BUILT WITH THE COMMUNITY",13,AMBER,true)
	text(Vector2(350,239),"Aircraft, landscapes, and open tools.",32)
	var lines: Array[String] = ["AIRCRAFT  /  FLIGHTGEAR COMMUNITY", "A380: Ampere K., Innis Cunningham, F. Dalvi, S. Hamilton and contributors.", "F-35B: Petar Jedvaj, Detlef Faber, F-GTUX, Stuart Cassie, Gary Brown and contributors.", "B-2 Spirit: Markus Zojer.", "737-300: Innis Cunningham, Heiko Schulz, Emmanuel Baranger and contributors.", "747: Jim Wilson and FlightGear 747 contributors.", "Aircraft licensed under GPL v2 / v3; source and complete notices included in the project.", "", "LANDSCAPE  /  POLY HAVEN", "CC0 photographic terrain materials and Kloppenheim 06 sky.", "", "ENGINE  /  GODOT", "Godot 4.7.2, Copyright Juan Linietsky, Ariel Manzur and contributors. MIT license.", "Full asset and engine notices are bundled with this application."]
	for i: int in lines.size():
		text(Vector2(354,289+i*32),lines[i],15,AMBER if i in [0,8,11] else MUTED)
	button("credits",Rect2(953,783,293,52),"BACK",true)

func draw_calibration() -> void:
	zones.clear()
	draw_rect(Rect2(0,0,1600,1000),Color(0.015,0.03,0.045,0.94))
	panel(Rect2(330,150,940,700))
	text(Vector2(386,210),"OPTIONAL  /  CARDBOARD CONTROLS",13,AMBER,true)
	text(Vector2(384,268),"Connect your cardboard cockpit.",34)
	text(Vector2(386,315),"Keyboard and mouse are ready now. Vision needs the separate tracker.",18,MUTED)
	var lines: Array[String] = ["1. Print marker 7 for your yoke and marker 23 for the throttle.","2. Place the webcam in front so both markers stay visible.","3. Run: ./tools/tracker.sh --camera 0 --calibrate", "4. Capture the seven poses with Space in the tracker preview.","5. Enable vision below, then return to flight."]
	for i: int in lines.size():
		text(Vector2(386,382+i*45),lines[i],18,WHITE)
	text(Vector2(386,605),"ROLL %+.2f   PITCH %+.2f   POWER %03d%%" % [app.vision.yoke.x,app.vision.yoke.y,int(app.vision.throttle*100)],15,WHITE,true)
	text(Vector2(386,639),"YOKE: %s    THROTTLE: %s" % ["TRACKED" if app.vision.tracking else "LOST", "TRACKED" if app.vision.throttle_confidence>0.4 else "HOLDING / LOST"],13,MUTED,true)
	text(Vector2(386,673),app.vision.status,13,GREEN if app.vision.connected else AMBER,true)
	text(Vector2(386,701),"Keyboard steering or power changes give you control.",15,MUTED)
	button("vision",Rect2(386,727,401,57),"VISION: ON" if app.vision.enabled else "ENABLE VISION",true)
	button("calibration",Rect2(810,727,402,57),"BACK TO FLIGHT" if app.mode == "flight" else "BACK")
