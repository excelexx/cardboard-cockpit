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
var title_art: Texture2D
var plasma_art: Texture2D
const INK := Color(0.045,0.08,0.10,0.93)
const WHITE := Color(0.91,0.94,0.94)
const MUTED := Color(0.56,0.65,0.69)
const AMBER := Color(0.96,0.70,0.37)
const GREEN := Color(0.49,0.84,0.71)

func _ready() -> void:
	if ResourceLoader.exists("res://assets/art/plasma-cannon.png"): plasma_art = load("res://assets/art/plasma-cannon.png")
	if ResourceLoader.exists("res://assets/art/goose-title.png"): title_art = load("res://assets/art/goose-title.png")
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
					action.emit("views" if id=="views_header" else id)
				accept_event()
				break

func _draw() -> void:
	if not is_instance_valid(app):
		return
	zones.clear()
	if app.mode=="title":
		draw_title()
		if app.help_visible: draw_help()
		if app.calibration_visible: draw_calibration()
		if app.credits_visible: draw_credits()
		return
	# UI is composed at 1600×1000 and scaled by Godot with the window.
	if app.mode == "hangar" or app.mode == "briefing":
		draw_hangar()
	elif app.flight_kind=="campaign":
		draw_campaign()
	elif app.flight_kind=="combat":
		draw_combat()
	elif not app.cockpit:
		draw_exterior_flight()
	else:
		draw_flight()
	if app.mode in ["flight","rollout"] and not app.overlay_visible(): draw_radio_caption()
	if app.mode == "briefing":
		draw_briefing()
	elif app.mode == "paused":
		draw_pause()
	elif app.mode == "results":
		draw_results()
	if app.camera_menu_open and app.mode not in ["hangar","briefing"]:
		draw_camera_picker()
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
	text(Vector2(62,667),"TOP %d KT  /  ROLL %d°/s" % [int(float(p.max_speed)*1.94384),int(rad_to_deg(float(p.roll_rate)))],12,AMBER,true)
	text(Vector2(62,693),"EXTERIOR MODEL  /  FLIGHTGEAR COMMUNITY",10,MUTED,true)
	text(Vector2(965,698),"REAL SCALE  ·  10 m GRID  ·  SCROLL TO ZOOM",11,MUTED,true)
	draw_rect(Rect2(0,735,1600,265),Color(0.025,0.045,0.06,0.98))
	line(Vector2(58,735),Vector2(1542,735))
	text(Vector2(59,770),"YOUR FLEET",12,MUTED,true)
	text(Vector2(1380,770),"06 AIRCRAFT",12,MUTED,true)
	for i: int in AircraftCatalog.PLANES.size():
		var rect := Rect2(58+i*250,790,234,104)
		var selected: bool = i == app.selected
		zones["plane_%d" % i] = rect
		panel(rect,Color(0.17,0.22,0.25) if selected else Color(0.07,0.105,0.13))
		if selected:
			draw_rect(Rect2(rect.position,Vector2(3,104)),AMBER)
		text(rect.position+Vector2(19,24),"0%d" % (i+1),10,AMBER if selected else MUTED,true)
		text(rect.position+Vector2(18,59),str(AircraftCatalog.PLANES[i].short),27,WHITE if selected else MUTED)
		text(rect.position+Vector2(18,84),str(AircraftCatalog.PLANES[i].label),10,MUTED,true)
	text(Vector2(60,954),"KEYBOARD + MOUSE READY",12,GREEN,true)
	text(Vector2(353,954),"MOUNTAIN VALLEY  /  " + app.world.get_condition_name().to_upper(),12,MUTED,true)
	button("help",Rect2(1018,924,200,48),"Controls  /  F1")
	button("brief",Rect2(1240,920,302,56),"PREPARE FLIGHT   →",true)

func draw_briefing() -> void:
	zones.clear()
	draw_rect(Rect2(0,0,1600,1000),Color(0.015,0.03,0.045,0.84))
	panel(Rect2(300,116,1000,772))
	text(Vector2(355,171),"02  /  FLIGHT BRIEFING",13,AMBER,true)
	text(Vector2(353,225),"Choose your next horizon.",38)
	text(Vector2(355,263),str(app.profile().name)+"  /  "+str(app.profile().type),13,MUTED,true)
	var kinds: Array[String] = ["valley","approach","free","campaign"]
	var titles: Array[String] = ["Valley mission","Landing practice","Free flight","Goose Protocol"]
	for i: int in kinds.size():
		button("kind_"+kinds[i],Rect2(355+i*228,295,217,53),titles[i],app.flight_kind==kinds[i])
	var details: Dictionary = {
		"campaign":["3 MINUTES / SIX UPGRADES / WATERLOO GEESE","Start with a worn gatling. Finish with the Millennium Falcon and plasma.","Aim at geese to fire. Each level has exactly one weapon."],
		"combat":["F-35 INTERCEPTION / THREE WAVES / DEFEND THE VALLEY","Cannon, lock-on missiles and flares. Sky Shield selects the F-35.","SPACE fires · T launches a locked missile · SHIFT rolls · Hold E ejects."],
		"valley":["ALPINE DEPARTURE  →  FIVE CHECKPOINTS  →  NORTH FIELD","Take off, follow five glowing rings, then fly the final approach.","Lower gear, set flaps, touch down and brake to a full stop."],
		"approach":["NORTH FIELD  /  RUNWAY 36  /  STRAIGHT-IN APPROACH","Begin airborne with gear down and approach flaps set.","Follow the guidance diamonds. Flare gently, then hold SPACE to brake."],
		"free":["TWO AIRPORTS  /  MOUNTAINS  /  YOUR OWN ROUTE","Depart Alpine and explore the valley without checkpoints.","Land at either airport and brake to a stop to complete your flight."]}
	var lines: Array = details.get(app.flight_kind,details.valley)
	text(Vector2(355,393),str(lines[0]),12,AMBER,true)
	text(Vector2(355,435),str(lines[1]),18)
	text(Vector2(355,465),str(lines[2]),18,MUTED)
	line(Vector2(355,493),Vector2(1245,493))
	text(Vector2(355,527),"SKY CONDITIONS",11,MUTED,true)
	var skies: Array[String] = ["golden","clear","overcast"]
	var sky_names: Array[String] = ["Golden hour","Clear midday","High overcast"]
	for i: int in 3:
		button("weather_"+skies[i],Rect2(355+i*305,547,280,46),sky_names[i],app.conditions==skies[i])
	if app.flight_kind=="campaign":
		button("showcase",Rect2(355,611,440,49),"3-MIN SHOWCASE: ON" if app.showcase_mode else "CLEAR-TO-PROGRESS CAMPAIGN",app.showcase_mode)
		button("developer",Rect2(813,611,431,49),"DEV MODE: ON" if app.developer_mode else "DEV MODE: OFF",app.developer_mode)
	else:
		text(Vector2(355,626),"%s  ·  %s km visibility  ·  calm winds" % [app.world.get_conditions().time_of_day,app.world.get_conditions().visibility_km],13,MUTED,true)
	text(Vector2(355,681),"W/S power   Arrows pitch/bank   G gear   F flaps   SPACE brakes",14,WHITE,true)
	text(Vector2(355,716),"V cycles seven views. 1–7 select a view. H enables the training copilot.",17,GREEN)
	button("hangar",Rect2(355,775,250,57),"Back to hangar")
	button("fly",Rect2(926,775,319,57),"BEGIN APPROACH  →" if app.flight_kind=="approach" else "CLEARED FOR TAKEOFF  →",true)

func draw_flight() -> void:
	var f: FlightDynamics = app.flight
	panel(Rect2(28,24,1544,76),Color(0.03,0.06,0.08,0.82))
	text(Vector2(51,59),"C / C",24,AMBER)
	text(Vector2(151,52),str(app.profile().name),15)
	text(Vector2(151,76),app.phase_label(),11,GREEN,true)
	text(Vector2(598,53),app.flight_kind_label(),14,WHITE,true)
	text(Vector2(599,78),("CHECKPOINTS  %d / 5" % app.ring_index if app.flight_kind=="valley" else app.world.get_condition_name().to_upper()),12,MUTED,true)
	text(Vector2(1130,53),"%02d:%02d" % [int(f.elapsed)/60,int(f.elapsed)%60],21,WHITE,true)
	text(Vector2(1280,51),"COPILOT" if app.copilot else "MANUAL FLIGHT",13,AMBER if app.copilot else GREEN,true)
	text(Vector2(1130,78),"%d FPS" % Engine.get_frames_per_second(),11,MUTED,true)
	var camera_button := Rect2(1268,60,282,30)
	zones["views_header"] = camera_button
	if hot=="views_header" or app.camera_menu_open:
		panel(camera_button,Color(0.18,0.25,0.28,0.96))
	text(Vector2(1280,80),"VIEW: %s   ▾   V" % app.camera_view_label().to_upper(),12,AMBER,true)
	# Central heading ribbon and horizon flight director.
	panel(Rect2(581,120,438,44),Color(0.03,0.06,0.08,0.5))
	for offset: int in range(-2,3):
		text(Vector2(607+(offset+2)*84,149),"%03d" % int(fposmod(f.get_heading_degrees()+offset*15,360)),14,AMBER if offset==0 else MUTED,true)
	draw_colored_polygon(PackedVector2Array([Vector2(793,169),Vector2(807,169),Vector2(800,176)]),AMBER)
	if app.camera_view in ["cockpit","chase","tail"]:
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
	text(Vector2(49,151),"NEXT  /  " + ("CHECKPOINT %02d" % (app.ring_index+1) if app.ring_index<5 and app.flight_kind=="valley" else "NORTH FIELD / RWY 36"),11,AMBER,true)
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
	if app.ring_index>=5 and app.flight_kind!="free" and f.airborne and app.camera_view in ["cockpit","chase","tail"]:
		draw_approach()
	if not app.cockpit or app.expanded_hud:
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
	var prompt_y: float = 751 if not app.cockpit or app.expanded_hud else 323
	panel(Rect2(800-tw*0.5-24,prompt_y,tw+48,49),Color(0.04,0.085,0.11,0.86))
	text(Vector2(800-tw*0.5,prompt_y+31),prompt,20,AMBER if f.stall_time>1 else WHITE)
	text(Vector2(36,993),"W/S POWER   ARROWS PITCH / BANK   A/D RUDDER   V / SHIFT+V VIEWS   1–7 SELECT   G GEAR   F FLAPS   H COPILOT   F2 INSTRUMENTS   F1 HELP   ESC PAUSE",10,MUTED,true)
	if app.toast_time>0:
		var w: float = font.get_string_size(app.toast,HORIZONTAL_ALIGNMENT_LEFT,-1,24).x
		panel(Rect2(800-w/2-28,247,w+56,60))
		text(Vector2(800-w/2,286),app.toast,24,GREEN)

func draw_camera_picker() -> void:
	panel(Rect2(1256,108,316,422),Color(0.025,0.045,0.06,0.98))
	text(Vector2(1276,141),"CAMERA VIEWS",12,AMBER,true)
	zones["views"] = Rect2(1521,117,37,31)
	text(Vector2(1533,141),"×",23,MUTED)
	var ids: Array[String] = ["cockpit","chase","tail","top","left","right","front"]
	var names: Array[String] = ["Cockpit","Chase","Tail","Top down","Left side","Right side","Nose"]
	for i: int in ids.size():
		var rect := Rect2(1272,158+i*44,284,38)
		var selected: bool = app.camera_view==ids[i]
		button("view_"+ids[i],rect,names[i],selected)
		text(rect.position+Vector2(15,25),str(i+1),12,INK if selected else MUTED,true)
	text(Vector2(1276,491),"V  NEXT   SHIFT+V  PREVIOUS",10,MUTED,true)
	text(Vector2(1276,512),"ESC CLOSES THIS MENU",10,MUTED,true)

func draw_approach() -> void:
	var guidance: Dictionary = app.approach_data()
	var center := Vector2(800,435)
	var magenta := Color(0.92,0.48,0.9,0.92)
	line(center+Vector2(-130,120),center+Vector2(130,120),Color(0.72,0.83,0.85,0.55))
	line(center+Vector2(180,-100),center+Vector2(180,100),Color(0.72,0.83,0.85,0.55))
	for i: int in [-2,-1,0,1,2]:
		draw_circle(center+Vector2(i*60,120),2,WHITE)
		draw_circle(center+Vector2(180,i*45),2,WHITE)
	var loc := center+Vector2(float(guidance.localizer)*120,120)
	var glide := center+Vector2(180,-float(guidance.glideslope)*90)
	for point: Vector2 in [loc,glide]:
		draw_colored_polygon(PackedVector2Array([point+Vector2(0,-7),point+Vector2(7,0),point+Vector2(0,7),point+Vector2(-7,0)]),magenta)
	text(center+Vector2(-124,146),"LOC",10,magenta,true)
	text(center+Vector2(194,-88),"GS",10,magenta,true)
	text(center+Vector2(-50,146),"3° APPROACH",10,MUTED,true)

func draw_pause() -> void:
	zones.clear()
	draw_rect(Rect2(0,0,1600,1000),Color(0.015,0.03,0.045,0.76))
	panel(Rect2(540,235,520,535))
	text(Vector2(598,300),"FLIGHT PAUSED",13,AMBER,true)
	text(Vector2(596,355),"Take a moment.",35)
	button("resume",Rect2(598,401,404,58),"RESUME FLIGHT",true)
	button("restart",Rect2(598,478,404,52),"Restart flight")
	button("hangar",Rect2(598,545,404,52),"Choose another aircraft")
	button("help",Rect2(598,612,192,50),"Controls")
	button("mute",Rect2(810,612,192,50),"Sound: OFF" if app.audio.muted else "Sound: ON")
	button("views_header",Rect2(810,686,192,46),"Camera views")
	text(Vector2(598,719),"Q  QUALITY: %s" % ("HIGH" if app.high_quality else "BALANCED"),12,MUTED,true)

func draw_results() -> void:
	if app.flight_kind in ["combat","campaign"]:
		draw_combat_results()
		return
	zones.clear()
	draw_rect(Rect2(0,0,1600,1000),Color(0.015,0.03,0.045,0.79))
	panel(Rect2(370,200,860,605))
	var success: bool = app.mission_success
	text(Vector2(428,254),"FLIGHT DEBRIEF",13,AMBER,true)
	text(Vector2(426,319),("Welcome back, captain." if app.flight_kind=="free" else "Welcome to North Field.") if success else "Every flight teaches you.",36)
	paragraph(Vector2(428,355),app.result_reason,742,17,GREEN if success else MUTED)
	line(Vector2(428,397),Vector2(1170,397))
	var f: FlightDynamics = app.flight
	var names: Array[String] = ["FLIGHT TIME", "LANDING SCORE", "TOUCHDOWN"]
	var values: Array[String] = ["%02d:%02d" % [int(f.elapsed)/60,int(f.elapsed)%60],"%d / 100" % f.landing_score() if f.contact=="landed" else "—","%d FPM" % int(absf(f.touchdown_sink)*196.85)]
	for i: int in 3:
		text(Vector2(428+i*263,438),names[i],11,MUTED,true)
		text(Vector2(427+i*263,486),values[i],36,WHITE,true)
	text(Vector2(428,560),"CAPTAIN" if success and f.landing_score()>80 else "CADET PILOT" if success else "PILOT IN TRAINING",24,AMBER)
	text(Vector2(428,597),"%s  ·  %s" % [str(app.profile().short), "Training copilot used" if app.used_copilot else "Manual flight"],16,MUTED)
	button("restart",Rect2(428,674,349,62),"FLY AGAIN  →",true)
	button("hangar",Rect2(800,674,370,62),"NEXT PILOT / HANGAR")

func draw_help() -> void:
	zones.clear()
	draw_rect(Rect2(0,0,1600,1000),Color(0.015,0.03,0.045,0.90))
	panel(Rect2(315,105,970,785))
	text(Vector2(370,166),"YOUR FLIGHT CONTROLS",14,AMBER,true)
	text(Vector2(368,222),"A little input goes a long way.",35)
	var rows: Array[Array] = [["W / S", "Increase / decrease engine power"],["↑ / ↓", "Nose up / nose down"],["← / →", "Bank left / right"],["A / D", "Rudder and runway steering"],["RIGHT MOUSE", "Hold and drag to look around"],["B", "Toggle mouse yoke (move cursor to steer)"],["G  /  SPACE", "Landing gear / wheel brakes"],["F  /  F2", "Flaps UP / 15 / 30 · show instrument overlay"],["V / SHIFT+V", "Next / previous camera view"],["1–7", "Select a camera directly during flight"],["H", "Training copilot on/off"],["R  /  M", "Reset aircraft / mute sound"],["TAB  /  C", "Spectator panel / camera setup"],["ESC  /  Q", "Pause / change render quality"]]
	if app.flight_kind=="combat":
		rows = [["ARROWS / W / S","Bank and pitch / increase or reduce power"],["SPACE / LEFT CLICK","Fire the cannon (watch the heat bar)"],["T","Launch a missile after the target locks"],["Z","Deploy defensive flares"],["SHIFT","Perform a full F-35 barrel roll"],["HOLD E","Eject from the F-35 (hold one second)"],["J","Toggle cardboard combat assistance"],["CARDBOARD AIM","Hold a drone in the reticle to fire"],["PULL YOKE BACK","Launch a locked missile; re-center to re-arm"],["FULL YOKE BANK","Barrel roll; re-center to re-arm"],["V / H / R","Camera / training copilot / restart"]]
	if app.flight_kind=="campaign" or app.mode=="title":
		rows = [["ARROWS","Bank and pitch to aim at a goose"],["W / S","Increase / decrease power"],["SPACE / LEFT CLICK","Fire this level's single weapon"],["CARDBOARD YOKE","Aim to lock and fire automatically"],["H","Guided demo / take over manually"],["V","Switch cockpit / chase camera"],["C","Connect and inspect cardboard controls"],["F9","Enable / disable developer mode"],["1–6 / N","Developer: choose level / next upgrade"],["R","Restart the complete demo"],["ESC / M","Pause / mute all audio"]]
	for i: int in rows.size():
		text(Vector2(373,268+i*35),str(rows[i][0]),15,WHITE,true)
		text(Vector2(657,268+i*35),str(rows[i][1]),17,MUTED)
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
	text(Vector2(354,754),"Demo: Poly by Google · Kenney · MintoDog · British Library / Lawrence Shove",13,WHITE)
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

func draw_combat() -> void:
	var c: CombatDirector = app.combat
	var f: FlightDynamics = app.flight
	panel(Rect2(28,24,1544,78),Color(0.025,0.045,0.06,0.9))
	text(Vector2(48,57),"SKY SHIELD",24,AMBER,true)
	text(Vector2(49,82),"F-35 / DRONE INTERCEPTION",11,MUTED,true)
	text(Vector2(423,59),"WAVE %d / 3" % c.wave,22,WHITE,true)
	text(Vector2(682,59),"HULL %03d" % int(c.hull),22,GREEN if c.hull>35 else Color(1,0.3,0.15),true)
	text(Vector2(962,59),"DEFENSE %03d" % int(c.base_health),22,WHITE,true)
	text(Vector2(1295,59),"%05d PTS" % c.score,22,AMBER,true)
	var center := Vector2(800,440)
	var locked: bool = c.lock_progress>=1
	var aim_color: Color = GREEN if locked else AMBER
	draw_arc(center,34,-PI/2,-PI/2+maxf(0.01,c.lock_progress)*TAU,48,aim_color,2.5,true)
	line(center+Vector2(-58,0),center+Vector2(-16,0),WHITE,2)
	line(center+Vector2(16,0),center+Vector2(58,0),WHITE,2)
	line(center+Vector2(0,-58),center+Vector2(0,-16),WHITE,2)
	line(center+Vector2(0,16),center+Vector2(0,58),WHITE,2)
	text(Vector2(688,516),"TARGET LOCKED" if locked else "ACQUIRING" if c.target_id>=0 else "SCAN FOR TARGETS",15,aim_color,true)
	for enemy: Dictionary in c.enemies:
		var pos: Vector3 = enemy.position
		if app.camera.is_position_behind(pos): continue
		var point: Vector2 = app.camera.unproject_position(pos)
		point.x = clampf(point.x,45,1555)
		point.y = clampf(point.y,125,770)
		var chosen: bool = enemy.id==c.target_id
		var color: Color = GREEN if chosen and locked else AMBER if chosen else Color(1,0.4,0.27)
		draw_rect(Rect2(point-Vector2(23,23),Vector2(46,46)),color,false,2)
		text(point+Vector2(30,0),"DRONE %02d" % (enemy.id+1),11,color,true)
		text(point+Vector2(30,18),"%.1f KM" % (pos.distance_to(f.position)/1000),11,color,true)
		line(point+Vector2(-23,31),point+Vector2(-23+46*enemy.health/100,31),color,3)
	panel(Rect2(1295,130,270,270),Color(0.025,0.05,0.07,0.87))
	text(Vector2(1315,157),"TACTICAL / 4 KM",12,MUTED,true)
	var radar := Vector2(1430,275)
	draw_arc(radar,98,0,TAU,64,Color(0.4,0.7,0.65,0.4),1,true)
	line(radar-Vector2(98,0),radar+Vector2(98,0),Color(0.4,0.7,0.65,0.25))
	line(radar-Vector2(0,98),radar+Vector2(0,98),Color(0.4,0.7,0.65,0.25))
	draw_colored_polygon(PackedVector2Array([radar+Vector2(0,-7),radar+Vector2(-5,5),radar+Vector2(5,5)]),GREEN)
	for enemy: Dictionary in c.enemies:
		var offset: Vector3 = enemy.position-f.position
		var flat := Vector2(offset.x,offset.z).rotated(f.heading)*0.024
		flat = flat.limit_length(95)
		draw_circle(radar+flat,4,GREEN if enemy.id==c.target_id else Color(1,0.4,0.25))
	panel(Rect2(28,810,1544,164),Color(0.025,0.045,0.06,0.95))
	var names: Array[String] = ["CANNON", "MISSILES", "FLARES", "SPEED / KT", "ALT / FT", "ASSIST"]
	var values: Array[String] = [str(c.ammo),str(c.missiles),str(c.flares),str(int(f.speed*1.94384)),str(int(f.position.y*3.28084)),"ON" if c.assist else "OFF"]
	for i: int in names.size():
		var x: float = 54+i*254
		text(Vector2(x,844),names[i],12,MUTED,true)
		text(Vector2(x,890),values[i],32,WHITE,true)
		if i<5: line(Vector2(x+223,835),Vector2(x+223,909))
	text(Vector2(54,946),"SPACE / CLICK fire   T missile   Z flares   SHIFT roll   Hold E eject   J assist   H copilot",15,AMBER,true)
	line(Vector2(54,906),Vector2(249,906),MUTED,3)
	line(Vector2(54,906),Vector2(54+195*c.gun_heat,906),Color(1,0.35,0.15),4)
	if c.message_time>0:
		panel(Rect2(350,163,820,59))
		text(Vector2(376,202),c.message,18,GREEN)
	if app.vision.enabled:
		panel(Rect2(28,130,515,100))
		text(Vector2(47,161),"CARDBOARD ASSIST  /  " + ("ON" if c.assist else "OFF"),13,GREEN,true)
		text(Vector2(47,187),"Aim to fire · Pull back for a locked missile",16)
		text(Vector2(47,213),"Full bank for a roll · Re-center to re-arm",16,MUTED)
	if c.eject_hold>0:
		text(Vector2(630,680),"HOLD E TO EJECT  %d%%" % int(c.eject_hold*100),20,AMBER,true)
	if app.mode=="ejected":
		panel(Rect2(490,640,620,74))
		text(Vector2(519,687),"PILOT SAFE · PARACHUTE DEPLOYED",23,GREEN,true)
	if c.hit_flash>0:
		draw_rect(Rect2(0,0,1600,1000),Color(1,0.12,0.02,c.hit_flash*0.25))

func draw_combat_results() -> void:
	zones.clear()
	draw_rect(Rect2(0,0,1600,1000),Color(0.015,0.03,0.045,0.86))
	panel(Rect2(340,175,920,640))
	var c: CombatDirector = app.combat
	text(Vector2(398,237),"GOOSE PROTOCOL / DEMO DEBRIEF" if app.flight_kind=="campaign" else "SKY SHIELD / MISSION DEBRIEF",14,AMBER,true)
	text(Vector2(395,306),"DEMO COMPLETE" if app.flight_kind=="campaign" and app.mission_success else "VALLEY SECURED" if app.mission_success else "SORTIE COMPLETE",38,GREEN if app.mission_success else WHITE,true)
	paragraph(Vector2(399,354),app.result_reason,800,19,MUTED)
	line(Vector2(399,405),Vector2(1199,405))
	text(Vector2(399,455),"INTERCEPTIONS",12,MUTED,true)
	text(Vector2(699,455),"MISSION SCORE",12,MUTED,true)
	text(Vector2(999,455),"TIME",12,MUTED,true)
	text(Vector2(399,511),str(c.kills),40,WHITE,true)
	text(Vector2(699,511),"%05d" % c.score,40,AMBER,true)
	text(Vector2(999,511),"%02d:%02d" % [int(c.elapsed)/60,int(c.elapsed)%60],32,WHITE,true)
	text(Vector2(399,591),"Training copilot used" if app.used_copilot else "Manual sortie",18,MUTED)
	text(Vector2(399,628),"SIX AIRCRAFT. SIX WEAPONS. ONE CARDBOARD COCKPIT." if app.flight_kind=="campaign" else "F-35 INTERCEPTOR · CANNON / GUIDED MISSILES / FLARES",14,GREEN,true)
	button("restart",Rect2(399,697,380,61),"FLY AGAIN",true)
	button("hangar",Rect2(819,697,380,61),"BACK TO HANGAR")

func draw_title() -> void:
	if title_art!=null:
		draw_texture_rect(title_art,Rect2(0,0,1600,1000),false)
	else:
		draw_rect(Rect2(0,0,1600,1000),Color(0.025,0.05,0.09,0.95))
	draw_texture_rect(fade,Rect2(0,0,1050,1000),false)
	text(Vector2(80,110),"C / C     CARDBOARD COCKPIT",17,AMBER,true)
	text(Vector2(77,294),"GOOSE",88,WHITE)
	text(Vector2(77,384),"PROTOCOL",88,WHITE)
	text(Vector2(82,451),"Waterloo's airspace has a goose problem.",24,WHITE)
	text(Vector2(82,495),"You have cardboard. They have numbers.",22,MUTED)
	text(Vector2(82,568),"6 AIRCRAFT   /   6 WEAPONS   /   3 MINUTES",17,AMBER,true)
	button("demo",Rect2(80,644,470,80),"START THE 3-MINUTE DEMO  →",true)
	button("brief_campaign",Rect2(80,746,227,54),"Demo setup")
	button("hangar",Rect2(324,746,226,54),"Aircraft hangar")
	text(Vector2(82,858),"AIM TO FIRE  ·  CARDBOARD OR KEYBOARD",14,GREEN,true)
	text(Vector2(82,891),"ENTER launch  ·  C cardboard setup  ·  F1 controls",15,MUTED)
	text(Vector2(82,936),"A tiny trainer. A massive finale. A very bad day for geese.",16,WHITE)

func draw_campaign() -> void:
	var c: GooseCampaign = app.combat
	var spec: Dictionary = c.stage()
	var f: FlightDynamics = app.flight
	var green := Color(0.35,0.96,0.65)
	var accent: Color = spec.color
	panel(Rect2(24,20,1552,84),Color(0.015,0.032,0.045,0.93))
	text(Vector2(44,51),"GOOSE / PROTOCOL",18,WHITE,true)
	text(Vector2(44,81),"L%02d  %s" % [c.wave,spec.name],12,accent,true)
	text(Vector2(450,52),str(spec.aircraft),17,WHITE,true)
	text(Vector2(450,82),app.camera_view_label().to_upper()+"  /  "+("CARDBOARD" if app.vision.tracking else "GUIDED PILOT" if app.copilot else "MANUAL"),11,green,true)
	var remaining: int = maxi(0,int(ceil(180-c.elapsed)))
	text(Vector2(994,56),"%02d:%02d" % [remaining/60,remaining%60] if c.showcase else "CAMPAIGN",28,WHITE,true)
	text(Vector2(994,83),"SHOWCASE / TRAINING SHIELD" if c.showcase else "CLEAR FLOCK TO ADVANCE",9,MUTED,true)
	text(Vector2(1310,54),"%05d" % c.score,28,accent,true)
	text(Vector2(1460,51),"HULL",10,MUTED,true)
	text(Vector2(1460,81),"%03d" % int(c.hull),24,green if c.hull>35 else Color(1,0.3,0.2),true)
	for i in range(6):
		var x: float = 25+i*259
		draw_rect(Rect2(x,108,253,3),accent if i<c.wave else Color(0.16,0.25,0.28))
		if i==c.wave-1 and c.showcase: draw_rect(Rect2(x,108,253*c.stage_clock/30,3),green)
	# Primary flight references sit on the edges; the firing solution stays clear.
	panel(Rect2(535,126,530,51),Color(0.02,0.04,0.055,0.67))
	var heading: float = f.get_heading_degrees()
	for step in range(-3,4):
		var x: float = 798+step*73
		text(Vector2(x-17,153),"%03d" % int(fposmod(heading+step*10,360)),12,green if step==0 else MUTED,true)
		line(Vector2(x,159),Vector2(x,166),green if step==0 else MUTED)
	draw_colored_polygon(PackedVector2Array([Vector2(795,174),Vector2(805,174),Vector2(800,182)]),green)
	if not app.cockpit:
		flight_tape(Rect2(24,151,163,341),f.speed*1.94384,10.0,"IAS","KNOTS",green)
		flight_tape(Rect2(1413,151,163,341),f.position.y*3.28084,100.0,"ALT","FEET MSL",green)
		text(Vector2(1428,528),"V/S %+05d" % int(f.vertical_speed*196.85),13,green,true)
		text(Vector2(1428,552),"PITCH %+.1f°" % rad_to_deg(f.pitch),12,MUTED,true)
		text(Vector2(40,528),"POWER %03d%%" % int(f.throttle*100),13,green,true)
		text(Vector2(40,552),"BANK %+.1f°" % rad_to_deg(f.roll),12,MUTED,true)
	var center: Vector2 = app.camera.unproject_position(f.position+c.forward()*1500)
	var locked: bool = c.lock_progress>=1
	var aim_color: Color = green if locked else Color(0.72,0.9,0.83)
	line(center+Vector2(-40,0),center+Vector2(-10,0),aim_color,1.5)
	line(center+Vector2(10,0),center+Vector2(40,0),aim_color,1.5)
	line(center+Vector2(0,-29),center+Vector2(0,-9),aim_color,1.5)
	draw_arc(center,18,0,TAU,40,aim_color,1,true)
	draw_circle(center,1.6,aim_color)
	text(center+Vector2(-47,49),"LOCK" if locked else "ACQUIRE" if c.target_id>=0 else "SCAN",12,aim_color,true)
	var selected: Dictionary = c.target()
	for enemy: Dictionary in c.enemies:
		if app.camera.is_position_behind(enemy.position): continue
		var point: Vector2 = app.camera.unproject_position(enemy.position)
		if point.x<10 or point.x>1590 or point.y<125 or point.y>815: continue
		if enemy.id==c.target_id:
			target_brackets(point,26,green if locked else accent)
			text(point+Vector2(34,-9),"GOOSE %02d" % (enemy.id+1),11,WHITE,true)
			text(point+Vector2(34,11),"%.2f KM" % (f.position.distance_to(enemy.position)/1000),11,green,true)
			var fraction: float = float(enemy.health)/float(enemy.get("max_health",100))
			line(point+Vector2(-26,33),point+Vector2(26,33),MUTED,2)
			line(point+Vector2(-26,33),point+Vector2(-26+52*fraction,33),green,2)
			if c.wave not in [2,4,6]:
				var velocity: Vector3 = enemy.get("velocity",Vector3.ZERO)
				var lead: Vector3 = enemy.position+velocity*minf(f.position.distance_to(enemy.position)/1150,1.5)
				var pip: Vector2 = app.camera.unproject_position(lead)
				draw_polyline(PackedVector2Array([pip+Vector2(0,-5),pip+Vector2(5,0),pip+Vector2(0,5),pip+Vector2(-5,0),pip+Vector2(0,-5)]),green,1,true)
		else:
			line(point+Vector2(-5,-17),point+Vector2(0,-12),Color(1,0.61,0.38,0.7),1)
			line(point+Vector2(0,-12),point+Vector2(5,-17),Color(1,0.61,0.38,0.7),1)
	draw_tactical_scope(Rect2(24,682,296,292),c,green)
	panel(Rect2(1280,713,296,261),Color(0.02,0.042,0.055,0.91))
	text(Vector2(1301,744),"FLIGHT CONTROLS",12,WHITE,true)
	control_bar(Vector2(1301,780),"ROLL",app.control.x,green)
	control_bar(Vector2(1301,827),"PITCH",app.control.y,green)
	control_bar(Vector2(1301,874),"YAW",app.control.z,green)
	text(Vector2(1301,936),"GEAR "+("DOWN" if f.gear else "UP"),12,green,true)
	text(Vector2(1440,936),"FLAPS "+str(f.flaps),11,MUTED,true)
	panel(Rect2(340,837,920,137),Color(0.018,0.038,0.052,0.95))
	if c.wave==6 and plasma_art!=null:
		draw_texture_rect(plasma_art,Rect2(347,850,108,91),false)
	else:
		weapon_glyph(Vector2(386,895),c.wave,accent)
	text(Vector2(456,864),"WEAPON %02d / 06" % c.wave,10,MUTED,true)
	text(Vector2(455,896),str(spec.weapon),22,WHITE,true)
	var fire_mode: String = "CONTINUOUS BEAM" if c.wave==6 else "GUIDED / LOCK REQUIRED" if c.wave in [2,4] else "FORWARD FIRE / LEAD TARGET"
	text(Vector2(456,921),fire_mode,10,accent,true)
	text(Vector2(913,864),"ENERGY" if c.wave==6 else "ROUNDS",10,MUTED,true)
	text(Vector2(912,900),str(c.ammo),28,green,true)
	text(Vector2(1055,864),"NEXT UPGRADE",10,MUTED,true)
	text(Vector2(1055,900),"%02d SEC" % maxi(0,int(ceil(30-c.stage_clock))),24,WHITE,true)
	line(Vector2(456,944),Vector2(790,944),Color(0.2,0.29,0.31),4)
	line(Vector2(456,944),Vector2(456+334*c.gun_heat,944),Color(1,0.36,0.2) if c.gun_heat>.8 else accent,4)
	text(Vector2(814,949),"COOLING" if c.beam_overheated else "HEAT",10,MUTED,true)
	text(Vector2(932,950),"J  ASSIST: LOW" if c.assist else "J  ASSIST: OFF",11,green,true)
	if c.transition_time>0:
		panel(Rect2(375,209,850,100),Color(0.02,0.045,0.065,0.94))
		text(Vector2(402,239),"AIRFRAME UPGRADE / LEVEL %d" % c.wave,11,accent,true)
		text(Vector2(400,276),str(spec.aircraft),27,WHITE,true)
	if c.developer:
		text(Vector2(534,815),"DEV  /  1–6 SELECT STAGE  /  N NEXT  /  F9 EXIT",12,AMBER,true)
	if c.hit_flash>0: draw_rect(Rect2(0,0,1600,1000),Color(1,0.12,0.02,c.hit_flash*0.22))

func flight_tape(rect: Rect2, value: float, step: float, label: String, unit: String, color: Color) -> void:
	panel(rect,Color(0.02,0.04,0.052,0.68))
	text(rect.position+Vector2(16,26),label,11,MUTED,true)
	text(rect.position+Vector2(16,65),"%03d" % int(value),29,WHITE,true)
	text(rect.position+Vector2(16,85),unit,9,MUTED,true)
	var center_y: float = rect.position.y+211
	var base: float = floorf(value/step)*step
	for index in range(-4,5):
		var tick: float = base+index*step
		var y: float = center_y-(tick-value)/step*29
		if y<rect.position.y+110 or y>rect.end.y-14 or tick<0: continue
		line(Vector2(rect.end.x-29,y),Vector2(rect.end.x-12,y),color,1)
		text(Vector2(rect.position.x+21,y+4),str(int(tick)),11,color,true)
	draw_colored_polygon(PackedVector2Array([Vector2(rect.end.x-3,center_y),Vector2(rect.end.x-13,center_y-5),Vector2(rect.end.x-13,center_y+5)]),WHITE)

func target_brackets(point: Vector2, radius: float, color: Color) -> void:
	for x in [-1,1]:
		for y in [-1,1]:
			var corner := point+Vector2(x*radius,y*radius)
			line(corner,corner-Vector2(x*10,0),color,1.6)
			line(corner,corner-Vector2(0,y*10),color,1.6)

func control_bar(at: Vector2, label: String, value: float, color: Color) -> void:
	text(at,label,10,MUTED,true)
	text(at+Vector2(193,0),"%+03d" % int(value*100),10,color,true)
	var center: Vector2 = at+Vector2(126,14)
	line(center-Vector2(126,0),center+Vector2(126,0),Color(0.18,0.29,0.29),5)
	var end := center+Vector2(clampf(value,-1,1)*126,0)
	line(center,end,color,5)
	line(center-Vector2(0,6),center+Vector2(0,6),WHITE,1)

func draw_tactical_scope(rect: Rect2, c: CombatDirector, color: Color) -> void:
	panel(rect,Color(0.018,0.04,0.052,0.91))
	text(rect.position+Vector2(18,27),"TACTICAL / 3 KM",11,WHITE,true)
	text(rect.position+Vector2(181,27),"%02d GEESE" % c.enemies.size(),11,AMBER,true)
	var center := rect.position+Vector2(rect.size.x/2,153)
	for radius in [48.0,96.0]: draw_arc(center,radius,0,TAU,64,Color(0.22,0.6,0.43,0.35),1,true)
	line(center-Vector2(96,0),center+Vector2(96,0),Color(0.22,0.6,0.43,0.25))
	line(center-Vector2(0,96),center+Vector2(0,96),Color(0.22,0.6,0.43,0.25))
	for enemy: Dictionary in c.enemies:
		var delta: Vector3 = enemy.position-app.flight.position
		var point: Vector2 = Vector2(delta.x,delta.z).rotated(-app.flight.heading)*0.032
		point = point.limit_length(94)
		draw_circle(center+point,3.5,color if enemy.id==c.target_id else Color(1,0.52,0.32))
	for shot: Dictionary in c.shots:
		if shot.kind!="hostile": continue
		var delta: Vector3 = shot.position-app.flight.position
		var point: Vector2 = Vector2(delta.x,delta.z).rotated(-app.flight.heading)*0.032
		if point.length()<96: draw_circle(center+point,2,Color(1,0.22,0.15))
	draw_colored_polygon(PackedVector2Array([center+Vector2(0,-7),center+Vector2(-4,5),center+Vector2(4,5)]),color)
	text(rect.position+Vector2(18,rect.size.y-18),"H  PILOT: "+("GUIDED" if app.copilot else "MANUAL"),10,color,true)

func weapon_glyph(at: Vector2, stage: int, color: Color) -> void:
	if stage in [2,4]:
		for i in range(3 if stage==4 else 1):
			var x: float = at.x+(i-1)*15 if stage==4 else at.x
			draw_polyline(PackedVector2Array([Vector2(x,at.y-33),Vector2(x+4,at.y-22),Vector2(x+4,at.y+16),Vector2(x+11,at.y+28),Vector2(x,at.y+22),Vector2(x-11,at.y+28),Vector2(x-4,at.y+16),Vector2(x-4,at.y-22),Vector2(x,at.y-33)]),color,1.5,true)
	elif stage==6:
		for side in [-1,1]:
			line(at+Vector2(side*13,29),at+Vector2(side*13,-30),color,5)
			line(at+Vector2(side*13,29),at+Vector2(side*13,-30),WHITE,1.5)
		line(at+Vector2(-23,29),at+Vector2(23,29),MUTED,4)
	elif stage==5:
		draw_arc(at,25,0,TAU,32,color,2,true)
		draw_arc(at,13,0,TAU,32,WHITE,1.5,true)
		line(at-Vector2(0,34),at+Vector2(0,34),color,2)
	else:
		for i in range(5 if stage==1 else 3):
			line(at+Vector2(-22+i*10,25),at+Vector2(-22+i*10,-26),color,2.5 if stage==1 else 5)
		line(at+Vector2(-30,10),at+Vector2(29,10),MUTED,5)

func draw_radio_caption() -> void:
	if app.audio.radio.caption.is_empty(): return
	panel(Rect2(390,742,840,67),Color(0.015,0.035,0.05,0.94))
	text(Vector2(414,766),app.audio.radio.speaker+" / RADIO",10,GREEN,true)
	text(Vector2(414,795),app.audio.radio.caption,18,WHITE)

func draw_exterior_flight() -> void:
	var f: FlightDynamics = app.flight
	var green := Color(0.35,0.96,0.65)
	panel(Rect2(24,20,1552,84),Color(0.015,0.032,0.045,0.93))
	text(Vector2(44,52),str(app.profile().name),22,WHITE,true)
	text(Vector2(44,82),app.phase_label(),12,green,true)
	text(Vector2(860,55),"HDG %03d°" % int(f.get_heading_degrees()),23,WHITE,true)
	text(Vector2(1190,54),app.camera_view_label().to_upper(),19,AMBER,true)
	text(Vector2(1420,54),"%02d:%02d" % [int(f.elapsed)/60,int(f.elapsed)%60],22,WHITE,true)
	flight_tape(Rect2(24,151,163,341),f.speed*1.94384,10,"IAS","KNOTS",green)
	flight_tape(Rect2(1413,151,163,341),f.position.y*3.28084,100,"ALT","FEET MSL",green)
	text(Vector2(1428,530),"V/S %+05d" % int(f.vertical_speed*196.85),13,green,true)
	text(Vector2(40,530),"POWER %03d%%" % int(f.throttle*100),13,green,true)
	var center := Vector2(800,435)
	for side in [-1,1]: line(center+Vector2(side*20,0),center+Vector2(side*60,0),green,1.5)
	line(center+Vector2(-20,0),center+Vector2(0,8),green,1.5)
	line(center+Vector2(20,0),center+Vector2(0,8),green,1.5)
	panel(Rect2(24,682,296,292),Color(0.018,0.04,0.052,0.91))
	text(Vector2(42,710),"NAVIGATION / 5 KM",11,WHITE,true)
	var radar := Vector2(172,835)
	for radius in [48.0,96.0]: draw_arc(radar,radius,0,TAU,64,Color(0.22,0.6,0.43,0.35),1,true)
	line(radar-Vector2(96,0),radar+Vector2(96,0),MUTED)
	line(radar-Vector2(0,96),radar+Vector2(0,96),MUTED)
	for target: Vector3 in [Vector3.ZERO,Vector3(0,0,-15000),app.target_position()]:
		var delta: Vector3 = target-f.position
		var point := Vector2(delta.x,delta.z).rotated(-f.heading)*0.019
		point = point.limit_length(94)
		draw_rect(Rect2(radar+point-Vector2(3,3),Vector2(6,6)),AMBER,false,1.5)
	draw_colored_polygon(PackedVector2Array([radar+Vector2(0,-7),radar+Vector2(-4,5),radar+Vector2(4,5)]),green)
	text(Vector2(42,953),"NEXT %.1f KM" % (f.position.distance_to(app.target_position())/1000),12,green,true)
	panel(Rect2(1280,713,296,261),Color(0.02,0.042,0.055,0.91))
	text(Vector2(1301,744),"FLIGHT CONTROLS",12,WHITE,true)
	control_bar(Vector2(1301,780),"ROLL",app.control.x,green)
	control_bar(Vector2(1301,827),"PITCH",app.control.y,green)
	control_bar(Vector2(1301,874),"YAW",app.control.z,green)
	text(Vector2(1301,936),"GEAR "+("DOWN" if f.gear else "UP"),12,green,true)
	text(Vector2(1440,936),"FLAPS "+str(f.flaps),11,MUTED,true)
	panel(Rect2(340,837,920,137),Color(0.018,0.038,0.052,0.95))
	text(Vector2(365,865),"FLIGHT DIRECTOR",11,MUTED,true)
	paragraph(Vector2(365,900),app.flight_prompt(),840,18,WHITE)
	text(Vector2(365,950),"W/S POWER · ARROWS PITCH/BANK · SPACE BRAKES · V VIEW · F1 CONTROLS",11,green,true)
	if app.toast_time>0:
		panel(Rect2(380,224,840,58))
		text(Vector2(401,262),app.toast,19,green)
