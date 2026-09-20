extends Control
class_name CockpitHUD
## Flight HUD and menus, drawn in a 1600 x 1000 design space.
##
## One colour means one thing: GREEN is the player's aircraft and anything
## ready, RED is the enemy or danger, AMBER asks for attention, WHITE is the
## number being read. Every glyph carries a dark outline so it holds up over
## bright sky, water and city; nothing in flight is smaller than 14 px.
const Tune = preload("res://data/balance.gd")
signal action(name: String)
signal sensitivity_changed(axis: String,value: float)
var sensitivity_sliders: Dictionary={}
const SETTING_AXES:=["pitch","bank","yaw","pitch_agility","bank_agility","yaw_agility","auto_aim"]
const GAMEPLAY_SETTINGS=preload("res://systems/gameplay_settings.gd")
var app: Node
var display: Font
var display_bold: Font
var mono: FontVariation
var body: Font
var title_art: Texture2D
var zones: Dictionary = {}
var hot := ""
var clock := 0.0
const WHITE := Color(0.957,0.969,0.953)
const SOFT := Color(0.663,0.722,0.678)
const GREEN := Color(0.553,1.0,0.690)
const AMBER := Color(1.0,0.710,0.278)
const RED := Color(1.0,0.294,0.243)
const GLASS := Color(0.043,0.067,0.063)
const HAIRLINE := Color(0.169,0.227,0.192)
# Older call sites still use these names.
const MUTED := SOFT
const CYAN := GREEN
const DANGER := RED
const GAME_TITLE := "WILD GOOSE CHASE"
## Sentinel from fpm_screen_point() when the flight path is behind the camera.
const OFFSCREEN := Vector2(-9999,-9999)
## Half the gap between the on-speed chevrons, wide open and fully shut.
const INDEXER_OPEN := 20.0
const INDEXER_SHUT := 6.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display = load("res://assets/fonts/SairaCondensed-SemiBold.ttf")
	display_bold = load("res://assets/fonts/SairaCondensed-Bold.ttf")
	body = load("res://assets/fonts/IBMPlexMono-Regular.ttf")
	mono = FontVariation.new()
	mono.base_font = load("res://assets/fonts/IBMPlexMono-Medium.ttf")
	mono.spacing_glyph = 2
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
		slider.tooltip_text = {"pitch":"Pitch sensitivity: nose up / down", "bank":"Bank sensitivity: wings left / right", "yaw":"Yaw sensitivity: nose left / right", "pitch_agility":"Speed of pitching up and down", "bank_agility":"Speed of banking and banked turns", "yaw_agility":"Speed of swivelling the nose left and right", "auto_aim":"Gun aiming assistance. Zero shoots straight ahead."}[axis]
		var track := StyleBoxFlat.new()
		track.bg_color = GLASS.lightened(.12)
		track.content_margin_top = 4; track.content_margin_bottom = 4
		track.set_corner_radius_all(4)
		slider.add_theme_stylebox_override("slider",track)
		var fill := track.duplicate() as StyleBoxFlat
		fill.bg_color = GREEN
		slider.add_theme_stylebox_override("grabber_area",fill)
		slider.add_theme_stylebox_override("grabber_area_highlight",fill)
		slider.value_changed.connect(_on_sensitivity_slider.bind(axis))
		slider.visible = false
		add_child(slider); sensitivity_sliders[axis] = slider
func _process(dt: float) -> void:
	clock += dt; update_sensitivity_sliders(); queue_redraw()

func settings_rect() -> Rect2:
	var extent := Vector2(minf(1040,size.x-64),850)
	return Rect2((size-extent)/2,extent)

func setting_value(axis: String) -> float:
	return app.gameplay_settings.get(axis) if axis.ends_with("_agility") or axis=="auto_aim" else app.vision.get(axis+"_sensitivity")

func setting_slider_rect(axis: String) -> Rect2:
	var card := settings_rect()
	var width := (card.size.x-112)/2
	if axis=="auto_aim": return Rect2(card.position+Vector2(36,575),Vector2(card.size.x-72,34))
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

# --- primitives -------------------------------------------------------------
func hidden_in_flight() -> bool:
	return not app.text_hud and app.mode=="flight" and not app.overlay_visible() and not app.tutorial.active
func put(face: Font,at: Vector2,value: String,size: int,color: Color,align: int=HORIZONTAL_ALIGNMENT_LEFT,width: float=-1) -> void:
	if value.is_empty(): return
	draw_string_outline(face,at,value,align,width,size,maxi(3,size/9),Color(0,0,0,0.62*color.a))
	draw_string(face,at,value,align,width,size,color)
## Labels and states (technical: caps, tracked mono) or sentences.
func text(at: Vector2, value: String, size: int = 18, color: Color = WHITE, technical: bool = false) -> void:
	if hidden_in_flight(): return
	put(mono if technical else body,at,value,maxi(size,14),color)
## Big numerals and titles.
func big(at: Vector2,value: String,size: int,color: Color=WHITE,align: int=HORIZONTAL_ALIGNMENT_LEFT,width: float=-1,bold: bool=false) -> void:
	if hidden_in_flight(): return
	put(display_bold if bold else display,at,value,size,color,align,width)
func centered(y: float,value: String,size: int,color: Color,face: Font=null) -> void:
	if hidden_in_flight(): return
	put(face if face!=null else mono,Vector2(0,y),value,size,color,HORIZONTAL_ALIGNMENT_CENTER,1600)
func line(a: Vector2,b: Vector2,color: Color=GREEN,width: float=2) -> void:
	draw_line(a,b,Color(0,0,0,0.5*color.a),width+2.5,true)
	draw_line(a,b,color,width,true)
func ring(center: Vector2,radius: float,from: float,to: float,color: Color,width: float=2) -> void:
	draw_arc(center,radius,from,to,48,Color(0,0,0,0.5*color.a),width+2.5,true)
	draw_arc(center,radius,from,to,48,color,width,true)
func panel(rect: Rect2, alpha: float = 0.78,edge: Color=HAIRLINE) -> void:
	draw_rect(rect,Color(GLASS.r,GLASS.g,GLASS.b,alpha))
	draw_rect(rect,edge,false,1)
func bar(rect: Rect2,fraction: float,color: Color) -> void:
	draw_rect(rect,Color(GLASS.r,GLASS.g,GLASS.b,0.62))
	draw_rect(Rect2(rect.position,Vector2(rect.size.x*clampf(fraction,0,1),rect.size.y)),color)
	draw_rect(rect,Color(color.r,color.g,color.b,0.9),false,1)
func keycap(at: Vector2,label: String,size: int=18) -> float:
	var width: float = mono.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x+18
	draw_rect(Rect2(at+Vector2(0,-size-3),Vector2(width,size+10)),WHITE)
	draw_string(mono,at+Vector2(9,1),label,HORIZONTAL_ALIGNMENT_LEFT,-1,size,GLASS)
	return width
## Alert banner: TITLE in the alert colour, then plain words and "[KEY]" caps.
func banner(y: float,title: String,parts: Array,color: Color) -> void:
	if hidden_in_flight(): return
	var title_width: float = display_bold.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,32).x
	var width: float = title_width+40
	for part: String in parts:
		var word: String = part.trim_prefix("[").trim_suffix("]")
		width += (mono if part.begins_with("[") else body).get_string_size(word,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x+(30 if part.begins_with("[") else 12)
	if not parts.is_empty(): width += 14
	var left: float = 800-width/2
	panel(Rect2(left,y-36,width,52),0.78,color)
	draw_string(display_bold,Vector2(left+20,y),title,HORIZONTAL_ALIGNMENT_LEFT,-1,32,color)
	var x: float = left+20+title_width+14
	for part: String in parts:
		if part.begins_with("["):
			x += keycap(Vector2(x,y-3),part.trim_prefix("[").trim_suffix("]"))+12
		else:
			draw_string(body,Vector2(x,y-3),part,HORIZONTAL_ALIGNMENT_LEFT,-1,18,WHITE)
			x += body.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x+12
## "TITLE|words|[KEY]|words" from mission and tutorial code becomes a banner.
func instruction_banner(y: float,instruction: String,color: Color) -> void:
	if instruction.is_empty(): return
	var pieces: PackedStringArray = instruction.split("|")
	var parts: Array = []
	for i in range(1,pieces.size()): parts.append(pieces[i])
	banner(y,pieces[0],parts,color)
func button(id: String,rect: Rect2,label: String,primary: bool = false,hint: String="") -> void:
	zones[id] = rect
	var over: bool = hot==id
	if primary:
		draw_rect(rect,GREEN.lightened(0.18) if over else GREEN)
	else:
		draw_rect(rect,Color(GLASS.r,GLASS.g,GLASS.b,0.86 if over else 0.62))
		draw_rect(rect,GREEN if over else Color(0.231,0.290,0.255),false,1)
	var size: int = clampi(int(rect.size.y*0.52),20,40)
	var face: Font = display_bold if primary else display
	var baseline: float = rect.position.y+rect.size.y/2+size*0.36
	draw_string(face,Vector2(rect.position.x+24,baseline),label,HORIZONTAL_ALIGNMENT_LEFT,-1,size,GLASS if primary else WHITE)
	if not hint.is_empty():
		draw_string(mono,Vector2(rect.position.x,baseline-3),hint,HORIZONTAL_ALIGNMENT_RIGHT,rect.size.x-22,15,GLASS if primary else GREEN)
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
	if app.mode=="control_setup":draw_control_setup();return
	if app.mode=="title": draw_title()
	else: draw_flight()
	if app.camera_previews and app.vision.enabled and app.mode in ["flight","rollout"] and not app.settings_visible and not app.calibration_visible:draw_camera_previews()
	if app.mode=="paused":
		draw_pause()
		if app.camera_previews and app.vision.enabled and not app.settings_visible and not app.calibration_visible:draw_camera_previews()
	if app.mode=="results": draw_results()
	if app.toast_time>0 and app.mode=="flight": centered(176,app.toast.to_upper(),18,GREEN)
	if app.mode=="flight" and app.mission.phase=="aftermath": button("land",Rect2(590,790,420,62),"LAND AT SFO",true,"B")
	if app.landing_transition>0:
		draw_rect(Rect2(0,0,1600,1000),Color(0.01,.02,.03,clampf(app.landing_transition/1.2,0,1)))
		centered(496,"HEADING BACK TO SFO",40,WHITE,display_bold)
	if app.flight_kind=="training" and app.mode in ["flight","rollout"] and not app.overlay_visible():draw_training_coach()
	if app.tutorial.active and app.mode in ["flight","rollout"] and not app.overlay_visible():draw_tutorial()
	if app.help_visible: draw_help()
	if app.calibration_visible: draw_camera_setup()
	if app.credits_visible: draw_credits()
	if app.yoke_recovery_visible() and not app.overlay_visible():draw_yoke_recovery()
	if app.settings_visible:draw_settings()

# --- title ------------------------------------------------------------------
func draw_title() -> void:
	if title_art!=null: draw_texture_rect(title_art,Rect2(0,0,1600,1000),false)
	else: draw_rect(Rect2(0,0,1600,1000),Color(0.025,0.045,0.07))
	draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(1000,0),Vector2(1000,1000),Vector2(0,1000)]),PackedColorArray([Color(0.02,0.035,0.035,0.92),Color(0.02,0.035,0.035,0),Color(0.02,0.035,0.035,0),Color(0.02,0.035,0.035,0.92)]))
	text(Vector2(96,150),"CARDBOARD COCKPIT",18,GREEN,true)
	big(Vector2(92,268),"WILD GOOSE",124,WHITE,HORIZONTAL_ALIGNMENT_LEFT,-1,true)
	big(Vector2(92,376),"CHASE",124,WHITE,HORIZONTAL_ALIGNMENT_LEFT,-1,true)
	text(Vector2(96,436),"Shoot down the geese. Clear the big skein.",20,WHITE)
	text(Vector2(96,466),"Two flocks: 12, then 20. Land at SFO.",20,WHITE)
	button("fly",Rect2(96,520,420,72),"PLAY",true,"ENTER · START")
	button("training",Rect2(96,604,420,52),"TUTORIAL",false,"TAKE OFF · SHOOT · LAND")
	button("guided",Rect2(96,666,205,52),"WATCH DEMO")
	button("approach",Rect2(311,666,205,52),"LANDING PRACTICE")
	button("camera",Rect2(96,728,420,52),"SET UP CARDBOARD")
	button("settings",Rect2(96,790,205,48),"SETTINGS")
	button("help",Rect2(311,790,205,48),"CONTROLS")
	button("credits",Rect2(1390,922,154,44),"CREDITS")
	button("next_pilot",Rect2(96,852,420,48),"NEXT PILOT",false,"SPECTRE-%02d" % app.pilot_number)
	status_dot(Vector2(96,930),"YOKE READY" if app.vision.tracking else "YOKE NOT FOUND",app.vision.tracking)
	status_dot(Vector2(330,930),"BADGE CONNECTED" if app.badge.connected else "BADGE NOT FOUND",app.badge.connected)
func status_dot(at: Vector2,label: String,ok: bool) -> void:
	if ok: draw_circle(at+Vector2(5,-6),5,GREEN)
	else: draw_arc(at+Vector2(5,-6),4.5,0,TAU,24,AMBER,2,true)
	put(mono,at+Vector2(20,0),label,15,WHITE if ok else AMBER)

# --- pure readout helpers ---------------------------------------------------
## Everything here is a plain function of state so tests/test_hud_readouts.gd can
## drive it without a viewport; _draw() never runs under --headless.
## Read a float that a sibling package may not have landed yet.
static func read_number(from: Object,field: String,fallback: float) -> float:
	if from==null: return fallback
	var found: Variant = from.get(field)
	return float(found) if found!=null else fallback
## (birds down, birds in the skein) for the objective. Reads the same fields
## scenes/main.gd reads for the cockpit display, so the two never disagree:
## skein_total plus skein_remaining(), or skein_down. Until the combat package
## publishes either, this falls back to the kill count against the designed
## skein size so the objective still reads.
static func skein_tally(c: CombatDirector) -> Vector2:
	if c==null: return Vector2.ZERO
	if is_instance_valid(c.app) and c.app.mission.cinematic:
		return Vector2(c.app.mission.skein_down,c.app.mission.skein_total())
	var total: float = read_number(c,"skein_total",float(Tune.SKEIN_SIZE))
	if total<=0.0: return Vector2.ZERO
	var down: float = -1.0
	if c.has_method("skein_remaining"): down = total-float(c.call("skein_remaining"))
	else: down = read_number(c,"skein_down",-1.0)
	if down<0.0: down = float(c.kills)
	return Vector2(clampf(down,0.0,total),total)
## 0 with nothing down, 1 with the skein cleared, and never a divide by zero.
static func objective_fraction(c: CombatDirector) -> float:
	var tally: Vector2 = skein_tally(c)
	return 0.0 if tally.y<=0.0 else clampf(tally.x/tally.y,0.0,1.0)
## Calibrated airspeed in knots: what an airspeed indicator reads. Equal to the
## true speed at sea level and lower than it everywhere above.
static func cas_knots(f: FlightDynamics) -> float:
	if f==null: return 0.0
	return f.speed*sqrt(pow(maxf(1.0-2.2557e-5*maxf(f.position.y,0.0),0.0),4.256))*1.94384
## Where the aircraft is actually going, in HUD space. OFFSCREEN when that point
## is behind the camera, because unproject_position() mirrors it if it is.
static func fpm_screen_point(f: FlightDynamics,camera: Camera3D) -> Vector2:
	if f==null or camera==null or not camera.is_inside_tree(): return OFFSCREEN
	var path: Vector3 = f.velocity
	if path.length()<1.0: return OFFSCREEN
	var ahead: Vector3 = f.position+path.normalized()*1000.0
	if camera.is_position_behind(ahead): return OFFSCREEN
	return camera.unproject_position(ahead)
## On-speed indexer: half the gap between the two chevrons beside the marker,
## closing as the wing works toward its drawn limit.
## The ids the combat director counts as this skein, empty until it publishes
## them. HOOK: CombatDirector.skein_ids.
static func skein_ids(c: CombatDirector) -> Array:
	if c==null: return []
	if is_instance_valid(c.app) and c.app.mission.cinematic:return c.app.mission.skein_ids
	var found: Variant = c.get("skein_ids")
	return found if found is Array else []
static func aoa_bracket_gap(f: FlightDynamics) -> float:
	var share: float = clampf(read_number(f,"aoa",0.0)/FlightDynamics.ALPHA_MAX,0.0,1.0)
	return lerpf(INDEXER_OPEN,INDEXER_SHUT,share)

# --- flight -----------------------------------------------------------------
func mission_line() -> String:
	if not app.mission.active: return ""
	if app.flight_kind=="training":return app.mission.label()
	if app.mission.cinematic:
		return {"opening":"Take off and follow the coast","combat":"Shoot down the geese","gather":"A skein is inbound","skein":"Clear the skein","aftermath":"Land at SFO","approach":"Landing at SFO","rollout":"Stop on the runway"}.get(app.mission.phase,"")
	return {"takeoff":"Take off","combat":"Shoot down the geese","return":"Fly back to the airport","approach":"Land the jet","rollout":"Stop on the runway"}.get(app.mission.phase,"")
func clock_text() -> String:
	var c: CombatDirector = app.combat
	if app.mission.active:
		var shown: int = maxi(0,int(ceil(Tune.DEMO_LIMIT-app.mission.clock))) if app.mission.cinematic else int(app.mission.clock)
		return "%d:%02d" % [shown/60,shown%60]
	if app.flight_kind=="combat":
		var remaining: int = maxi(0,int(ceil(c.duration-c.elapsed)))
		return "%d:%02d" % [remaining/60,remaining%60]
	return ""
func draw_flight() -> void:
	if app.paper_test or (app.cockpit and not app.combat.active):
		draw_clear_flight()
		return
	var f: FlightDynamics = app.flight
	var c: CombatDirector = app.combat
	var show: bool = not hidden_in_flight()
	# Top left: what to do. Top right: time.
	var objective: String = mission_line()
	if not objective.is_empty():
		text(Vector2(56,58),"MISSION",18,GREEN,true)
		text(Vector2(56,86),objective,20,WHITE)
	if c.hull<=65: text(Vector2(56,116),"DAMAGED",18,AMBER,true)
	var time_left: String = clock_text()
	if show and not time_left.is_empty():
		put(mono,Vector2(1244,58),"TIME LEFT" if app.mission.cinematic or not app.mission.active else "TIME",18,GREEN,HORIZONTAL_ALIGNMENT_RIGHT,300)
		put(display,Vector2(1244,106),time_left,52,WHITE,HORIZONTAL_ALIGNMENT_RIGHT,300)
	if show: put(mono,Vector2(1244,132),"AUTO-FLY" if app.copilot else "CARDBOARD YOKE" if app.vision.tracking else "",15,GREEN,HORIZONTAL_ALIGNMENT_RIGHT,300)
	# Heading tape.
	var heading: float = fposmod(f.get_heading_degrees()+(298 if app.route_id=="sf" else 0),360)
	if show:
		for index in [-3,-2,-1,1,2,3]:
			put(mono,Vector2(770+index*74,62),"%03d" % int(fposmod(heading+index*10,360)),16,Color(GREEN.r,GREEN.g,GREEN.b,0.9-absf(index)*0.14),HORIZONTAL_ALIGNMENT_CENTER,60)
		panel(Rect2(762,30,76,44),0.6,GREEN)
		put(display,Vector2(762,65),"%03d" % int(heading),34,WHITE,HORIZONTAL_ALIGNMENT_CENTER,76)
	# Speed and altitude sit on the lower borders: numbers beside the aircraft read
	# as clutter on top of it. The cockpit shows them on its own displays instead.
	if show and not app.cockpit:
		put(mono,Vector2(56,726),"SPEED",18,GREEN)
		put(display,Vector2(56,806),str(int(cas_knots(f))),84,WHITE)
		put(mono,Vector2(56,832),"KNOTS",18,GREEN)
		var g: float = read_number(f,"g_load",1.0)
		put(mono,Vector2(56,864),"G %+.1f" % g,20,RED if absf(g)>=FlightDynamics.G_LIMIT-0.2 else AMBER if absf(g)>=5.0 else GREEN)
		put(mono,Vector2(196,864),"AFTERBURNER" if f.afterburner else "AIRBRAKE" if f.airbrake>.1 else "POWER %d%%" % int(f.throttle*100),18,AMBER if f.afterburner or f.airbrake>.1 else GREEN)
		bar(Rect2(340,854,180,8),1.0 if f.afterburner else f.throttle,AMBER if f.afterburner else GREEN)
		put(mono,Vector2(1244,726),"ALTITUDE",18,GREEN,HORIZONTAL_ALIGNMENT_RIGHT,300)
		put(display,Vector2(1244,806),thousands(int(f.position.y*3.28084)),84,WHITE,HORIZONTAL_ALIGNMENT_RIGHT,300)
		put(mono,Vector2(1244,832),"FEET",18,GREEN,HORIZONTAL_ALIGNMENT_RIGHT,300)
		put(mono,Vector2(1244,864),"CLIMB %+d" % (int(f.vertical_speed*1.9685)*100),18,GREEN,HORIZONTAL_ALIGNMENT_RIGHT,300)
	if show and (f.gear or f.flaps>0): put(mono,Vector2(1244,894),"GEAR %s · FLAPS %d" % ["DOWN" if f.gear else "UP",f.flaps],18,AMBER,HORIZONTAL_ALIGNMENT_RIGHT,300)
	# Next waypoint.
	if app.mission.active and app.mission.phase in ["opening","combat","return"]:
		var waypoint: Vector3 = app.mission.route_target()
		if not app.camera.is_position_behind(waypoint):
			var nav: Vector2 = app.camera.unproject_position(waypoint).clamp(Vector2(160,150),Vector2(1440,730))
			diamond(nav,12,GREEN,2)
			text(nav+Vector2(20,6),"GO HERE",16,GREEN,true)
	draw_sight(f,c)
	if c.hit_confirm>0:
		var center: Vector2 = app.camera.unproject_position(c.reticle_point())
		for sx in [-1,1]:
			for sy in [-1,1]: line(center+Vector2(sx*14,sy*14),center+Vector2(sx*24,sy*24),Color(1,1,1,c.hit_confirm),3)
	if c.reward_flash>0:
		big(Vector2(0,250),"+%d" % c.last_reward,56,Color(GREEN.r,GREEN.g,GREEN.b,c.reward_flash),HORIZONTAL_ALIGNMENT_CENTER,1600,true)
		if c.combo>=3: centered(282,"%d IN A ROW" % c.combo,20,Color(WHITE.r,WHITE.g,WHITE.b,c.reward_flash))
	if c.hit_flash>0: draw_rect(Rect2(0,0,1600,1000),Color(RED.r,RED.g,RED.b,clampf(c.hit_flash*0.9,0,1)),false,14)
	if not app.cockpit: draw_scope(Vector2(1450,306),c)   # the cockpit's own display carries the radar
	draw_weapons(c)
	draw_objective(c)
	draw_alerts(f,c)
	if (app.flight_kind=="approach" or (app.mission.active and app.mission.phase in ["return","approach"])) and f.airborne:
		var guidance: Dictionary = app.approach_data()
		var cross := Vector2(800,700)
		line(cross-Vector2(90,0),cross+Vector2(90,0),Color(GREEN.r,GREEN.g,GREEN.b,0.5),2)
		line(cross-Vector2(0,40),cross+Vector2(0,40),Color(GREEN.r,GREEN.g,GREEN.b,0.5),2)
		diamond(cross+Vector2(guidance.localizer*80,-guidance.glideslope*34),7,WHITE,3)
	if show and not app.audio.radio.caption.is_empty():
		put(mono,Vector2(0,626),app.audio.radio.speaker,15,GREEN,HORIZONTAL_ALIGNMENT_CENTER,1600)
		put(body,Vector2(0,654),app.audio.radio.caption,20,WHITE,HORIZONTAL_ALIGNMENT_CENTER,1600)
	if app.vision.tracking or app.developer_mode: draw_control_feedback()
	if app.developer_mode: text(Vector2(620,990),"%d FPS · %.0f M/S · %s" % [Engine.get_frames_per_second(),f.speed,"HIGH" if app.high_quality else "BALANCED"],14,SOFT,true)
func thousands(value: int) -> String:
	var digits: String = str(absi(value))
	var out := ""
	for i in range(digits.length()):
		if i>0 and (digits.length()-i)%3==0: out += ","
		out += digits[i]
	return ("-" if value<0 else "")+out
## The flight-path marker, dimmer and thinner than the gunsight so the gunsight
## stays dominant: the circle is where the jet is going, the chevrons beside it
## close up as the wing works - sit them on the runway numbers to land.
func draw_flight_path(f: FlightDynamics) -> void:
	var at: Vector2 = fpm_screen_point(f,app.camera)
	if at==OFFSCREEN: return
	at = at.clamp(Vector2(140,170),Vector2(1460,690))
	var faint := Color(GREEN.r,GREEN.g,GREEN.b,0.45)
	ring(at,10,0,TAU,faint,1.5)
	for stub: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP]: line(at+stub*10,at+stub*18,faint,1.5)
	var gap: float = aoa_bracket_gap(f)
	for side in [-1.0,1.0]:
		var tip: Vector2 = at+Vector2(-22,side*gap)
		line(tip,tip+Vector2(-9,side*6),faint,1.5)
func draw_sight(f: FlightDynamics,c: CombatDirector) -> void:
	draw_flight_path(f)
	var nose: Vector2 = app.camera.unproject_position(f.position+c.forward()*2000)
	var ring_edge: Vector3 = c.forward().rotated(app.camera.global_basis.x,deg_to_rad(c.acquire_angle()))
	var ring_radius: float = clampf(nose.distance_to(app.camera.unproject_position(f.position+ring_edge*1200)),38,115)
	var tracking: bool = c.target_id>=0 and c.assist
	var locked: bool = tracking and c.lock_progress>=1
	# Where the nose points: a quiet ring. Where the guns point: the cross.
	for i in range(4): ring(nose,ring_radius,i*PI/2+.2,i*PI/2+PI/2-.2,Color(GREEN.r,GREEN.g,GREEN.b,0.55),2)
	var center: Vector2 = app.camera.unproject_position(c.reticle_point())
	var sight: Color = RED if locked else AMBER if tracking else GREEN
	ring(center,14,0,TAU,sight,2)
	for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]: line(center+direction*20,center+direction*34,sight,2)
	draw_circle(center,2.5,sight)
	for enemy: Dictionary in c.enemies:
		if app.camera.is_position_behind(enemy.position): continue
		var point: Vector2 = app.camera.unproject_position(enemy.position)
		if point.x<25 or point.x>1575 or point.y<115 or point.y>810: continue
		if enemy.id==c.target_id:
			var distance: float = f.position.distance_to(enemy.position)
			var radius: float = clampf(14000/maxf(distance,1),28,54)
			var tone: Color = RED if c.lock_progress>=1 else AMBER
			brackets(point,radius,tone)
			if c.lock_progress>=1: diamond(point,radius*0.45,RED,3)
			else: ring(point,radius*0.62,-PI/2,-PI/2+TAU*c.lock_progress,AMBER,3)
			big(point+Vector2(radius+16,-6),"LOCKED" if c.lock_progress>=1 else "LOCKING",30,tone,HORIZONTAL_ALIGNMENT_LEFT,-1,true)
			text(point+Vector2(radius+16,20),"%d m" % int(distance),20,WHITE)
			var pip: Vector2 = app.camera.unproject_position(f.position+c.assisted_direction()*distance)
			if pip.distance_to(center)>9: line(center,pip,Color(tone.r,tone.g,tone.b,0.55),2)
		else:
			diamond(point,8,Color(RED.r,RED.g,RED.b,0.9),2)
func draw_weapons(_c: CombatDirector) -> void:
	if hidden_in_flight(): return
	var gun_on: bool = app.gun_requested() or _c.gun_firing_time>0
	put(mono,Vector2(56,900),"PRIMARY",20,GREEN)
	var chip := Rect2(204,873,64 if gun_on else 72,36)
	if gun_on:
		draw_rect(chip,GREEN)
		draw_string(display_bold,chip.position+Vector2(13,28),"ON",HORIZONTAL_ALIGNMENT_LEFT,-1,30,GLASS)
	else:
		draw_rect(chip,Color(GLASS.r,GLASS.g,GLASS.b,0.62));draw_rect(chip,Color(GREEN.r,GREEN.g,GREEN.b,0.7),false,1)
		draw_string(display_bold,chip.position+Vector2(13,28),"OFF",HORIZONTAL_ALIGNMENT_LEFT,-1,30,SOFT)
	put(body,Vector2(292,898),"MINIGUN + PLASMA / SHOW TAG OR HOLD SPACE",16,WHITE)
	put(mono,Vector2(56,943),"MISSILE",20,GREEN)
	put(mono,Vector2(204,943),"READY" if _c.missile_cooldown<=0 else "%.1fs" % _c.missile_cooldown,18,GREEN if _c.missile_cooldown<=0 else SOFT)
	put(body,Vector2(330,941),"T / right mouse · one every 3 seconds",16,WHITE)
## How much of the skein is down, in the span the old health bar used to hold:
## one pip per bird, amber as it goes down. No named individual, no health bar.
func draw_objective(c: CombatDirector) -> void:
	if hidden_in_flight() or not c.active or not c.engagement_enabled: return
	if app.flight_kind=="training":
		put(mono,Vector2(540,118),"TRAINING TARGETS  %d / %d" % [c.kills,app.mission.TARGET_COUNT],20,GREEN);bar(Rect2(540,132,520,12),float(c.kills)/app.mission.TARGET_COUNT,GREEN);return
	var tally: Vector2 = skein_tally(c)
	var wave_title: String="FLOCKS"
	if app.mission.cinematic and app.mission.has_method("wave_down"):
		if app.mission.wave_number<=0:return
		tally=Vector2(app.mission.wave_down(),app.mission.wave_size)
		wave_title="WAVE %d / 2" % app.mission.wave_number
	if tally.y<=0.0: return
	put(mono,Vector2(540,118),"GEESE %d / %d" % [int(tally.x),int(tally.y)],20,AMBER)
	put(mono,Vector2(540,118),wave_title,20,AMBER,HORIZONTAL_ALIGNMENT_RIGHT,520)
	var pips: int = clampi(int(tally.y),1,26)
	var width: float = (526.0-float(pips-1)*4.0)/float(pips)
	draw_rect(Rect2(536,124,534,22),Color(GLASS.r,GLASS.g,GLASS.b,0.66))
	for index in range(pips):
		var slot := Rect2(540.0+float(index)*(width+4.0),128,width,14)
		if index<int(tally.x): draw_rect(slot,AMBER)
		else: draw_rect(slot,Color(AMBER.r,AMBER.g,AMBER.b,0.18)); draw_rect(slot,Color(AMBER.r,AMBER.g,AMBER.b,0.35),false,1)
func draw_alerts(f: FlightDynamics,c: CombatDirector) -> void:
	var y := 800.0
	if f.stall_time>.6: banner(y,"NOSE TOO HIGH",["Ease off, add power"],RED); y -= 62
	if app.eject_hold>0:
		banner(y,"EJECTING",["Keep holding","[E]"],RED)
		bar(Rect2(640,y+22,320,8),app.eject_hold/.9,RED); y -= 72
	if app.mode=="ejected": banner(y,"EJECTED",["You are out of the jet"],AMBER); y -= 62
	if c.message_time>0: banner(y,c.message.to_upper(),[],AMBER); y -= 62
	if app.mission.active and app.flight_kind!="training" and app.mode in ["flight","rollout"]:
		var instruction: String = app.mission.instruction()
		if app.copilot and not app.mission.cinematic and app.mission.phase!="combat": instruction = "AUTO-FLY ON|Steer any time"
		instruction_banner(y,instruction,GREEN if instruction.begins_with("AUTO-FLY") else AMBER)
	elif app.mode=="rollout": banner(y,"LANDED",["Hold","[SPACE]","to brake"],AMBER)
func draw_clear_flight() -> void:
	var f: FlightDynamics=app.flight
	var c: CombatDirector=app.combat
	var show: bool = not hidden_in_flight()
	big(Vector2(56,84),"%d" % int(f.speed*1.94384),56,WHITE)
	text(Vector2(56,110),"KNOTS",16,GREEN,true)
	if show:
		put(display,Vector2(1244,84),thousands(int(f.position.y*3.28084)),56,WHITE,HORIZONTAL_ALIGNMENT_RIGHT,300)
		put(mono,Vector2(1244,110),"FEET",16,GREEN,HORIZONTAL_ALIGNMENT_RIGHT,300)
		put(display,Vector2(0,76),"%03d" % int(f.get_heading_degrees()),40,WHITE,HORIZONTAL_ALIGNMENT_CENTER,1600)
	if app.paper_test:
		if app.vision.tracking: banner(170,"YOKE READY",["Turn to bank, tilt to climb"],GREEN)
		else: banner(170,"CAN'T SEE THE YOKE",["Show tag 7 and hold still"],AMBER)
	elif app.mission.active: instruction_banner(170,app.mission.instruction(),AMBER)
	if app.mission.active:
		var target: Vector3=app.mission.route_target()
		if not app.camera.is_position_behind(target):
			diamond(app.camera.unproject_position(target).clamp(Vector2(170,160),Vector2(1430,550)),11,GREEN,2)
	var center: Vector2=app.camera.unproject_position(c.reticle_point())
	line(center-Vector2(22,0),center-Vector2(7,0),GREEN);line(center+Vector2(7,0),center+Vector2(22,0),GREEN)
	if c.active and c.engagement_enabled:
		for enemy: Dictionary in c.enemies:
			if enemy.id!=c.target_id or app.camera.is_position_behind(enemy.position): continue
			var at: Vector2=app.camera.unproject_position(enemy.position)
			brackets(at,28,RED if c.lock_progress>=1 else AMBER)
			text(at+Vector2(40,6),"%d m" % int(f.position.distance_to(enemy.position)),18,WHITE)
	if app.paper_test:
		text(Vector2(56,920),"BANK %+.0f%%   PITCH %+.0f%%" % [app.control.x*100,app.control.y*100],20,WHITE,true)
		text(Vector2(56,952),"R resets the flight. SPACE in the camera window re-centers.",16,SOFT)
	else:
		text(Vector2(56,952),"POWER %d%% · GEAR %s" % [int(f.throttle*100),"DOWN" if f.gear else "UP"],18,GREEN,true)
	if f.stall_time>.6: banner(312,"NOSE TOO HIGH",["Ease off, add power"],RED)
	if show and not app.audio.radio.caption.is_empty():
		put(body,Vector2(0,884),app.audio.radio.caption,20,WHITE,HORIZONTAL_ALIGNMENT_CENTER,1600)
func draw_scope(center: Vector2,c: CombatDirector) -> void:
	if hidden_in_flight(): return
	draw_circle(center,92,Color(GLASS.r,GLASS.g,GLASS.b,0.74))
	draw_arc(center,92,0,TAU,72,GREEN,2,true)
	for radius in [30.0,61.0]: draw_arc(center,radius,0,TAU,64,Color(GREEN.r,GREEN.g,GREEN.b,0.4),1,true)
	draw_line(center-Vector2(92,0),center+Vector2(92,0),Color(GREEN.r,GREEN.g,GREEN.b,0.28),1)
	draw_line(center-Vector2(0,92),center+Vector2(0,92),Color(GREEN.r,GREEN.g,GREEN.b,0.28),1)
	for enemy: Dictionary in c.enemies:
		var delta: Vector3 = enemy.position-app.flight.position
		var point: Vector2 = center+(Vector2(delta.x,delta.z).rotated(-app.flight.heading)*0.030).limit_length(86)
		if enemy.id==c.target_id or skein_ids(c).has(enemy.id): draw_colored_polygon(PackedVector2Array([point+Vector2(0,-7),point+Vector2(7,0),point+Vector2(0,7),point+Vector2(-7,0)]),RED)
		else: draw_circle(point,4,RED)
	draw_colored_polygon(PackedVector2Array([center+Vector2(0,-9),center+Vector2(-7,8),center+Vector2(7,8)]),GREEN)
	put(mono,center+Vector2(-100,-104),"RADAR 3 KM",15,GREEN,HORIZONTAL_ALIGNMENT_CENTER,200)
func brackets(point: Vector2,radius: float,color: Color) -> void:
	var arm: float = radius*0.45
	for x in [-1,1]:
		for y in [-1,1]:
			var corner := point+Vector2(x*radius,y*radius)
			line(corner,corner-Vector2(x*arm,0),color,3)
			line(corner,corner-Vector2(0,y*arm),color,3)
func diamond(at: Vector2,radius: float,color: Color,width: float=2) -> void:
	var points := PackedVector2Array([at+Vector2(0,-radius),at+Vector2(radius,0),at+Vector2(0,radius),at+Vector2(-radius,0),at+Vector2(0,-radius)])
	draw_polyline(points,Color(0,0,0,0.5*color.a),width+2.5,true)
	draw_polyline(points,color,width,true)
func draw_control_feedback() -> void:
	if hidden_in_flight(): return
	for i in range(3):
		var at := Vector2(620+i*130,950)
		var value: float = app.control[i]
		put(mono,at,["ROLL","PITCH","YAW"][i],14,GREEN)
		draw_rect(Rect2(at+Vector2(0,8),Vector2(100,6)),Color(GLASS.r,GLASS.g,GLASS.b,0.62))
		draw_rect(Rect2(at+Vector2(50+minf(value,0)*50,8),Vector2(absf(value)*50,6)),GREEN)

# --- overlays ---------------------------------------------------------------
func dim() -> void: draw_rect(Rect2(0,0,1600,1000),Color(0.02,0.035,0.035,0.80))
func draw_yoke_recovery() -> void:
	zones.clear();dim();panel(Rect2(180,125,1240,740),.95)
	put(mono,Vector2(220,177),"FLIGHT HELD / YOKE TRACKING",17,AMBER)
	put(display_bold,Vector2(216,243),"BRING THE YOKE BACK INTO VIEW",48,WHITE)
	put(body,Vector2(220,288),"Hold the yoke visible and steady to resume. Your flight stays here while tracking returns.",19,SOFT)
	camera_card(Rect2(220,324,558,340),"LAPTOP / YOKE + GUN",app.yoke_preview,app.vision.tracking)
	camera_card(Rect2(802,324,578,340),"PHONE / THROTTLE",app.throttle_preview,app.vision.throttle_confidence>.4)
	put(body,Vector2(220,713),"Keep the yoke pattern uncovered. Cover the gun tag to stop shooting.",18,SOFT)
	button("keyboard",Rect2(220,757,330,62),"USE KEYBOARD",true)
	put(mono,Vector2(580,796),"ARROWS STEER / W S POWER / HOLD SPACE TO FIRE",16,GREEN)
func draw_pause() -> void:
	zones.clear();dim();panel(Rect2(500,185,600,635),.94)
	put(mono,Vector2(546,236),"FLIGHT PAUSED",17,GREEN)
	put(display_bold,Vector2(542,324),"YOU HAVE THE CONTROLS",49,WHITE)
	button("resume",Rect2(546,364,508,68),"RESUME FLIGHT",true,"ESC · HOME")
	button("help",Rect2(546,456,242,54),"CONTROLS")
	button("mute",Rect2(812,456,242,54),"AUDIO",false,"OFF" if app.audio.muted else "ON")
	button("settings",Rect2(546,532,242,54),"SETTINGS")
	button("quality",Rect2(812,532,242,54),"GRAPHICS",false,"HIGH" if app.high_quality else "BALANCED")
	button("restart",Rect2(546,608,242,54),"RESTART SORTIE")
	button("title",Rect2(812,608,242,54),"RETURN TO DECK")
	put(mono,Vector2(546,718),"BADGE  A GEAR  ·  B LAND  ·  LEFT VIEW",15,SOFT)
	put(mono,Vector2(546,749),"HOME RESUME  ·  HOLD DOWN TACTICAL",15,SOFT)
	status_dot(Vector2(546,791),"BADGE LINKED" if app.badge.connected else "BADGE OFFLINE",app.badge.connected)
func draw_results() -> void:
	zones.clear(); dim()
	var c: CombatDirector = app.combat
	put(mono,Vector2(300,250),app.result_reason.to_upper(),18,GREEN if app.mission_success else AMBER)
	put(display_bold,Vector2(296,346),app.result_headline.to_upper(),104,WHITE)
	put(mono,Vector2(300,420),"SCORE",18,GREEN)
	put(display,Vector2(296,556),thousands(c.score),148,WHITE)
	draw_line(Vector2(300,600),Vector2(1300,600),HAIRLINE,1)
	var labels: Array[String] = ["GEESE DOWN","BEST STREAK","TIME"]
	var values: Array[String] = [str(c.kills),str(c.best_combo),"%d:%02d" % [int(app.mission.clock)/60,int(app.mission.clock)%60]]
	for i in range(3):
		put(display,Vector2(300+i*280,672),values[i],56,WHITE)
		put(mono,Vector2(300+i*280,702),labels[i],16,SOFT)
	put(body,Vector2(300,752),app.result_advice,18,SOFT)
	button("fly",Rect2(300,790,300,68),"PLAY AGAIN",true,"START")
	button("title",Rect2(612,790,260,68),"MAIN MENU")
	button("next_pilot",Rect2(884,790,300,68),"NEXT PILOT")
func draw_help() -> void:
	zones.clear(); dim(); panel(Rect2(330,110,940,790),.9)
	put(display_bold,Vector2(384,196),"CONTROLS",64,WHITE)
	var rows: Array[Array] = [["ARROWS","Climb, dive and bank"],["A  D","Rudder: slide left and right"],["W  S","Faster, slower"],["SHIFT","Hold for afterburner"],["SPACE / CLICK","Hold minigun + plasma; release to stop"],["T / RIGHT CLICK","Slow guided missiles"],["GUN TAG ID 4","Show to fire; cover to stop"],["Z","Flares"],["Q","Barrel roll"],["V","Cockpit or chase view"],["G  F","Landing gear, flaps"],["H","Auto-fly on / off"],["HOLD E","Eject"],["C  M  ESC","Set up cardboard, mute, pause"]]
	for i in range(rows.size()):
		put(mono,Vector2(388,252+i*40),rows[i][0],18,GREEN)
		put(body,Vector2(610,252+i*40),rows[i][1],18,WHITE)
	button("help",Rect2(990,824,240,52),"BACK",true)
func draw_settings() -> void:
	zones.clear();dim();var card:=settings_rect();panel(card,.95)
	put(mono,card.position+Vector2(36,39),"SETTINGS / SAVED AUTOMATICALLY",16,GREEN)
	put(display_bold,card.position+Vector2(33,93),"FLIGHT & AIMING",52,WHITE)
	put(body,card.position+Vector2(36,126),"Input sensitivity and aircraft response are adjusted independently.",17,SOFT)
	var width: float=(card.size.x-112)/2
	put(mono,card.position+Vector2(36,163),"SENSITIVITY / INPUT AMOUNT",16,GREEN)
	put(mono,card.position+Vector2(76+width,163),"AGILITY / MOVEMENT SPEED",16,GREEN)
	var labels: Dictionary={"pitch":"Pitch / up & down","bank":"Bank / wing tilt","yaw":"Yaw / nose left & right"}
	for axis: String in SETTING_AXES:
		var rect:=setting_slider_rect(axis)
		put(body,rect.position+Vector2(0,-15),"Aim assistance" if axis=="auto_aim" else labels[axis.trim_suffix("_agility")],18,WHITE)
		put(mono,rect.position+Vector2(rect.size.x-85,-15),"%.2f×" % setting_value(axis),19,GREEN)
		put(mono,rect.position+Vector2(0,53),"OFF" if axis=="auto_aim" else "0.50×" if axis.ends_with("_agility") else "0.25×",14,SOFT)
		put(mono,rect.position+Vector2(rect.size.x-52,53),"3.00×",14,SOFT)
	var v=app.vision;var input: Vector3=v.steering()
	put(mono,card.position+Vector2(36,518),"PITCH %+.0f%%   BANK %+.0f%%   YAW %+.0f%%" % [input.y*100,input.x*100,input.z*100] if v.tracking else "SHOW THE YOKE TO CHECK LIVE INPUT",16,GREEN if v.tracking else SOFT)
	button("camera_previews",Rect2(card.position+Vector2(36,650),Vector2(280,46)),"CAMERA PREVIEWS",false,"ON" if app.camera_previews else "OFF")
	button("badge_prompts",Rect2(card.position+Vector2(336,650),Vector2(255,46)),"BADGE HINTS",false,"ON" if app.badge_prompts else "OFF")
	put(mono,card.position+Vector2(614,679),"BADGE LINKED" if app.badge.connected else "BADGE OFFLINE",15,GREEN if app.badge.connected else SOFT)
	var sync: String="Saved · camera tracker offline"
	if v.tracker_settings.synced(v.sensitivity_values()):sync="Applied to the game and both camera controls"
	elif v.connected:sync="Applying camera settings…"
	put(body,card.position+Vector2(36,732),sync,16,SOFT)
	button("sensitivity_reset",Rect2(card.position+Vector2(36,763),Vector2(280,52)),"RESET DEFAULTS")
	button("settings",Rect2(card.position+Vector2(card.size.x-236,763),Vector2(200,52)),"DONE",true,"HOME")

func camera_card(rect: Rect2,title: String,preview,tracking: bool) -> void:
	panel(rect,.88,GREEN if preview.texture!=null and tracking else HAIRLINE)
	put(mono,rect.position+Vector2(12,21),title,14,GREEN)
	var picture:=Rect2(rect.position+Vector2(6,31),rect.size-Vector2(12,60))
	if preview.texture!=null:
		var extent: Vector2=preview.texture.get_size();var ratio: float=minf(picture.size.x/extent.x,picture.size.y/extent.y);extent*=ratio
		draw_texture_rect(preview.texture,Rect2(picture.position+(picture.size-extent)/2,extent),false)
	else:
		put(body,picture.position+Vector2(10,picture.size.y/2),"Waiting for camera",16,SOFT)
	put(mono,rect.position+Vector2(12,rect.size.y-10),"TRACKING" if tracking and preview.texture!=null else "LIVE / TAG NOT FOUND" if preview.texture!=null else "DISCONNECTED",13,GREEN if tracking and preview.texture!=null else AMBER)
func draw_camera_previews() -> void:
	if app.mode=="paused":
		camera_card(Rect2(56,340,360,248),"LAPTOP / YOKE + GUN",app.yoke_preview,app.vision.tracking)
		camera_card(Rect2(1184,340,360,248),"PHONE / THROTTLE",app.throttle_preview,app.vision.throttle_confidence>.4)
		return
	camera_card(Rect2(56,162,258,196),"LAPTOP / YOKE + GUN",app.yoke_preview,app.vision.tracking)
	camera_card(Rect2(328,162,258,196),"PHONE / THROTTLE",app.throttle_preview,app.vision.throttle_confidence>.4)
func draw_camera_setup() -> void:
	zones.clear();dim();panel(Rect2(180,90,1240,820),.95)
	put(display_bold,Vector2(218,166),"TWO-CAMERA COCKPIT",56,WHITE)
	put(body,Vector2(220,201),"Laptop: yoke and gun. Phone: throttle. Both previews stay independent.",18,SOFT)
	camera_card(Rect2(220,234,558,362),"LAPTOP / YOKE + GUN",app.yoke_preview,app.vision.tracking)
	camera_card(Rect2(802,234,578,362),"PHONE / THROTTLE",app.throttle_preview,app.vision.throttle_confidence>.4)
	put(body,Vector2(220,640),"Keep the yoke tag visible; show the throttle handle and both end tags to the phone.",18,WHITE)
	put(mono,Vector2(220,675),"GUN %s  /  SHOW ID 4 OR HOLD SPACE / LEFT MOUSE" % ("ON" if app.gun_requested() else "OFF"),16,GREEN)
	put(body,Vector2(220,706),"Badge: A gear · B landing assist · HOME back/pause · hold DOWN for tactical view.",16,SOFT)
	var calibration=app.vision.yoke_calibration
	var neutral_status: String="READY TO CALIBRATE / HOLD THE YOKE UPRIGHT"
	if calibration.active:
		neutral_status="NEUTRAL CAPTURED" if calibration.state=="complete" else "HOLD STILL / %.1f SECONDS LEFT" % maxf(0,3-calibration.elapsed) if calibration.state=="holding" else "SHOW THE YOKE AND HOLD IT UPRIGHT"
	put(mono,Vector2(220,739),neutral_status,16,GREEN if calibration.state=="complete" else AMBER)
	button("vision",Rect2(220,764,350,62),"TRACKING ON" if app.vision.enabled else "ENABLE TRACKING",true)
	button("calibrate_yoke",Rect2(590,764,350,62),"CALIBRATE NEUTRAL")
	button("camera",Rect2(1090,764,290,62),"BACK")
func draw_credits() -> void:
	zones.clear(); dim(); panel(Rect2(330,150,940,700),.9)
	put(display_bold,Vector2(384,236),"CREDITS",64,WHITE)
	var lines: Array[String] = ["The SPECTRE is a made-up jet, tuned for fun.","Jet model: FlightGear F-35B community, GPL (source included).","Goose: Poly by Google, CC BY 3.0.","Sound effects and voices: Kenney, CC0.","Music: MintoDog, CC0. Goose calls: British Library, CC BY-SA.","Ground and sky: USGS, FlightGear, Poly Haven.","Fonts: Saira Condensed and IBM Plex Mono, SIL OFL.","Title art: image generation.","Engine: Godot, MIT. Full notices ship with the game."]
	for i in range(lines.size()): put(body,Vector2(388,296+i*40),lines[i],18,WHITE if i==0 else SOFT)
	button("credits",Rect2(990,770,240,52),"BACK",true)
func draw_tutorial() -> void:
	var lesson: Dictionary=app.tutorial.lesson()
	panel(Rect2(300,748,1000,64+lesson.lines.size()*30),.82,GREEN)
	put(display_bold,Vector2(328,790),str(lesson.title).to_upper(),30,GREEN)
	for i in range(lesson.lines.size()): put(body,Vector2(328,824+i*30),str(lesson.lines[i]),19,WHITE)

func draw_training_coach() -> void:
	if app.combat.incoming_distance<2200 or app.flight.stall_time>.6 or app.eject_hold>0:return
	panel(Rect2(330,720,940,134),.87)
	put(display_bold,Vector2(354,756),app.mission.label(),27,GREEN)
	put(body,Vector2(354,791),app.mission.instruction(),18,WHITE)
	put(mono,Vector2(354,831),app.mission.badge_hint(),14,SOFT)

func centered_text(at: Vector2, value: String, font_size: int = 18, color: Color = WHITE) -> void:
	var width := body.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	put(body,at-Vector2(width/2,0),value,font_size,color)

func tutorial_lines(value: String, width: float, font_size: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var current := ""
	for word: String in value.split(" "):
		var candidate := word if current.is_empty() else current+" "+word
		if not current.is_empty() and body.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width:
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
	var color := GREEN if app.controls_lesson.passed else CYAN
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


func draw_control_setup() -> void:
	zones.clear()
	var lesson=app.controls_lesson
	var v: VisionClient=app.vision
	var done: bool=lesson.complete()
	var step: Array=lesson.step()
	var group: String=lesson.focus()
	draw_rect(Rect2(0,0,1600,1000),GLASS)
	put(display_bold,Vector2(64,73),"SET UP YOUR CARDBOARD COCKPIT",46,WHITE)
	put(mono,Vector2(1132,62),"LIVE CAMERA CHECKS",16,GREEN)
	var labels: Array[String]=["01 / CALIBRATE","02 / THROTTLE","03 / YOKE","04 / GUN"]
	var groups: Array[String]=["calibrate","throttle","yoke","weapons"]
	for i in range(4):
		var selected: bool=i==0 if lesson.calibrating else group==groups[i] or done and i==3
		var rect:=Rect2(64+i*374,101,350,43)
		panel(rect,.9,GREEN if selected else HAIRLINE)
		put(mono,rect.position+Vector2(14,28),labels[i],17,GREEN if selected else SOFT)
	camera_card(Rect2(64,164,724,300),"LAPTOP / YOKE + GUN",app.yoke_preview,v.tracking)
	camera_card(Rect2(812,164,724,300),"PHONE / THROTTLE",app.throttle_preview,v.throttle_confidence>.4)
	panel(Rect2(64,486,1472,342),.95)
	draw_tutorial_cue(Rect2(90,517,226,190),"ready" if done else str(step[0]),"ready" if done else group)
	var at:=Vector2(360,537)
	var heading: String="CONTROLS CHECKED" if done else str(step[2]).to_upper()
	put(display_bold,at,heading,37,WHITE);at.y+=43
	var instruction: String="Centre the yoke, set 0% throttle and cover the gun tag." if done else str(step[3])
	for value: String in tutorial_lines(instruction,1120,20):
		put(body,at,value,20,WHITE);at.y+=29
	at.y+=10
	var hint: String=("Hold steady for one second to resume your flight." if app.setup_next_action.is_empty() else "Hold steady for one second to start your flight.") if done else str(step[4])
	for value: String in tutorial_lines(hint,1120,17):
		put(body,at,value,17,SOFT);at.y+=26
	var values: String="THROTTLE %3d%%   BANK %+.0f%%   PITCH %+.0f%%   YAW %+.0f%%   GUN %s" % [roundi(v.throttle*100),v.steering().x*100,v.steering().y*100,v.steering().z*100,"ON" if v.gun_trigger else "OFF"]
	put(mono,Vector2(360,720),values,17,GREEN)
	var status: String=lesson.status
	if not app.control_setup_picture():status="Waiting for both live cameras." if done else "Waiting for the phone camera." if group=="throttle" else "Waiting for the laptop camera."
	put(body,Vector2(360,760),status,18,GREEN if lesson.passed or lesson.can_start else AMBER)
	var progress: float=clampf(float(lesson.ready_ms)/lesson.READY_HOLD_MS,0,1) if done else lesson.progress()
	draw_rect(Rect2(90,803,1418,5),HAIRLINE);draw_rect(Rect2(90,803,1418*progress,5),GREEN)
	if not v.connected:put(body,Vector2(64,868),"Start Launch Two-Camera Cockpit with your phone connected, then return here.",17,AMBER)
	else:put(body,Vector2(64,868),"Checks advance when the camera sees the action. Flight stays paused while you test.",17,SOFT)
	button("setup_cancel",Rect2(64,901,288,56),"BACK",false,"ESC / HOME")
	button("setup_keyboard",Rect2(370,901,300,56),"USE KEYBOARD")
	button("setup_retry",Rect2(1236,901,300,56),"RETRY THIS STEP",true)
