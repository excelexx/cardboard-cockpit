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
signal audio_changed(channel: String,value: float)
const AUDIO_CHANNELS := ["music","engine","effects","voice"]
var audio_sliders: Dictionary={}
var settings_page := "flight"
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
		slider.tooltip_text = {"pitch":"Pitch sensitivity: nose up / down", "bank":"Bank sensitivity: wings left / right", "yaw":"Yaw sensitivity: nose left / right", "pitch_agility":"Speed of pitching up and down", "bank_agility":"Speed of banking and banked turns", "yaw_agility":"Speed of swivelling the nose left and right", "auto_aim":"Plasma aiming assistance. Zero aims straight ahead."}[axis]
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
	for channel: String in AUDIO_CHANNELS:
		var slider:=HSlider.new();slider.name=channel.capitalize()+"Volume"
		slider.min_value=0;slider.max_value=4 if channel=="music" else 2;slider.step=.01;slider.scrollable=false
		slider.tooltip_text={"music":"Free Bird music volume","engine":"Engine, wind and wheel volume","effects":"Weapons, geese and other effects","voice":"Radio and instructor voice volume"}[channel]
		var track:=StyleBoxFlat.new();track.bg_color=GLASS.lightened(.12);track.content_margin_top=4;track.content_margin_bottom=4;track.set_corner_radius_all(4)
		slider.add_theme_stylebox_override("slider",track)
		var fill:=track.duplicate() as StyleBoxFlat;fill.bg_color=GREEN
		slider.add_theme_stylebox_override("grabber_area",fill);slider.add_theme_stylebox_override("grabber_area_highlight",fill)
		slider.value_changed.connect(_on_audio_slider.bind(channel));slider.visible=false
		add_child(slider);audio_sliders[channel]=slider

func _process(dt: float) -> void:
	clock += dt;update_sensitivity_sliders();update_audio_sliders();queue_redraw()

func audio_slider_rect(channel: String) -> Rect2:
	var card:=settings_rect()
	return Rect2(card.position+Vector2(36,221+110*AUDIO_CHANNELS.find(channel)),Vector2(card.size.x-72,34))

func update_audio_sliders() -> void:
	if not is_instance_valid(app):return
	for channel: String in audio_sliders:
		var slider: HSlider=audio_sliders[channel]
		slider.visible=app.settings_visible and settings_page=="audio"
		if not slider.visible:
			if slider.has_focus():slider.release_focus()
			continue
		var rect:=audio_slider_rect(channel);slider.position=rect.position;slider.size=rect.size
		slider.set_value_no_signal(app.audio_settings.get(channel))

func _on_audio_slider(value: float,channel: String) -> void:
	audio_changed.emit(channel,value)

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
	var shown: bool = app.settings_visible and settings_page=="flight"
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
	if app.toast_time>0 and app.mode=="flight": put(mono,Vector2(56,176),app.toast.to_upper(),18,GREEN)
	if app.landing_transition>0:
		draw_rect(Rect2(0,0,1600,1000),Color(0.01,.02,.03,clampf(app.landing_transition/1.2,0,1)))
		put(display_bold,Vector2(56,176),"YOUR LANDING APPROACH",32,WHITE)
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
	text(Vector2(96,436),"Fly and shoot Geese Gods in this cardboard cockpit simulator.",20,WHITE)
	button("fly",Rect2(96,520,420,72),"PLAY",true,"ENTER · START")
	button("guided",Rect2(96,604,420,52),"WATCH DEMO")
	button("camera",Rect2(96,672,420,52),"SET UP CARDBOARD")
	button("settings",Rect2(96,742,205,48),"SETTINGS")
	button("help",Rect2(311,742,205,48),"CONTROLS")
	button("credits",Rect2(1390,922,154,44),"CREDITS")
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
	if app.landing_started:return "Your approach · B / badge B landing mode"
	if not app.flight.airborne:return "Take off · increase power and pull up"
	return "Endless judge demo · land whenever you like"
func clock_text() -> String:
	if not app.landing_started and app.mode!="rollout" and app.mission.phase not in ["approach","rollout"]:return ""
	var elapsed: int=maxi(0,int(app.mission.clock if app.mission.active else app.flight.elapsed))
	return "%d:%02d" % [elapsed/60,elapsed%60]
func draw_flight() -> void:
	if app.paper_test:
		draw_clear_flight()
		return
	var f: FlightDynamics = app.flight
	var c: CombatDirector = app.combat
	var show: bool = not hidden_in_flight()
	var time_left: String = clock_text()
	if show and not time_left.is_empty():
		put(mono,Vector2(1244,58),"ELAPSED",18,GREEN,HORIZONTAL_ALIGNMENT_RIGHT,300)
		put(display,Vector2(1244,106),time_left,52,WHITE,HORIZONTAL_ALIGNMENT_RIGHT,300)
	if show: put(mono,Vector2(1244,132),"AUTO-FLY" if app.copilot else "CARDBOARD YOKE" if app.vision.tracking else "",15,GREEN,HORIZONTAL_ALIGNMENT_RIGHT,300)
	if show:draw_heading_compass(f);draw_attitude_altitude(f)
	# A compact lower-left instrument row leaves the aiming area clear.
	if show:draw_pilot_readouts(f)
	draw_sight(f,c)
	if c.hit_confirm>0:
		var center: Vector2 = app.camera.unproject_position(c.reticle_point())
		for sx in [-1,1]:
			for sy in [-1,1]: line(center+Vector2(sx*14,sy*14),center+Vector2(sx*24,sy*24),Color(1,1,1,c.hit_confirm),3)
	if c.hit_flash>0: draw_rect(Rect2(0,0,1600,1000),Color(RED.r,RED.g,RED.b,clampf(c.hit_flash*0.9,0,1)),false,14)
	if not app.cockpit: draw_scope(Vector2(1450,306),c)   # the cockpit's own display carries the radar
	draw_objective(c)
	draw_alerts(f,c)
	if (app.flight_kind=="approach" or (app.mission.active and app.mission.phase in ["return","approach"])) and f.airborne:
		var guidance: Dictionary = app.approach_data()
		var cross := Vector2(1390,680)
		line(cross-Vector2(90,0),cross+Vector2(90,0),Color(GREEN.r,GREEN.g,GREEN.b,0.5),2)
		line(cross-Vector2(0,40),cross+Vector2(0,40),Color(GREEN.r,GREEN.g,GREEN.b,0.5),2)
		diamond(cross+Vector2(guidance.localizer*80,-guidance.glideslope*34),7,WHITE,3)
	if show and not app.audio.radio.caption.is_empty():
		put(mono,Vector2(56,810),app.audio.radio.speaker,15,GREEN)
		put(body,Vector2(56,838),app.audio.radio.caption,18,WHITE)
	if app.developer_mode: text(Vector2(620,990),"%d FPS · %.0f M/S · %s" % [Engine.get_frames_per_second(),f.speed,"HIGH" if app.high_quality else "BALANCED"],14,SOFT,true)
func draw_heading_compass(f: FlightDynamics) -> void:
	var heading: float=fposmod(f.get_heading_degrees()+(298 if app.route_id=="sf" else 0),360)
	var nearest: int=int(floor(heading/5))*5
	for offset in range(-7,9):
		var degree: int=nearest+offset*5
		var x: float=800+(degree-heading)*7.5
		if x<535 or x>1065:continue
		var normalized: int=posmod(degree,360)
		var major: bool=normalized%10==0
		line(Vector2(x,87),Vector2(x,73 if major else 80),GREEN,1.5)
		if major and absf(x-800)>58:
			var label: String=["N","E","S","W"][normalized/90] if normalized%90==0 else "%03d" % normalized
			put(mono,Vector2(x-25,61),label,15,GREEN,HORIZONTAL_ALIGNMENT_CENTER,50)
	put(display,Vector2(749,65),"%03d°" % int(heading),32,WHITE,HORIZONTAL_ALIGNMENT_CENTER,102)
	draw_colored_polygon(PackedVector2Array([Vector2(800,82),Vector2(793,96),Vector2(807,96)]),GREEN)

func draw_attitude_altitude(f: FlightDynamics) -> void:
	# Keep the aiming area empty; show only three pitch marks at the right edge.
	var center := Vector2(1390,480)
	var pitch: float=rad_to_deg(f.pitch)
	var nearest: int=int(round(pitch/10.0))*10
	for offset in range(-1,2):
		var degrees: int=nearest+offset*10
		var y: float=center.y+(pitch-degrees)*3.0
		line(Vector2(center.x-28,y),Vector2(center.x+28,y),GREEN,1.5)
		put(mono,Vector2(center.x+38,y+5),str(degrees),12,GREEN)
	put(mono,center+Vector2(-38,80),"ALTITUDE",14,GREEN)
	put(display,center+Vector2(-42,118),thousands(int(f.position.y*3.28084)),32,WHITE)
	put(mono,center+Vector2(-38,142),"FEET",13,SOFT)

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
func draw_sight(_f: FlightDynamics,c: CombatDirector) -> void:
	var tracking: bool = c.target_id>=0 and c.assist
	var locked: bool = tracking and c.lock_progress>=1
	# Where the nose points: a quiet ring. Where the guns point: the cross.
	var center: Vector2 = app.camera.unproject_position(c.reticle_point())
	var sight: Color = RED if locked else AMBER if tracking else GREEN
	for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]: line(center+direction*20,center+direction*34,sight,2)
	draw_circle(center,2.5,sight)
	# Red circles identify geese and show remaining health.
	for enemy: Dictionary in c.enemies:
		if not c.active:break
		if enemy.health<=0 or app.camera.is_position_behind(enemy.position):continue
		var point: Vector2=app.camera.unproject_position(enemy.position)
		if point.x<25 or point.x>1575 or point.y<115 or point.y>810:continue
		var distance: float=_f.position.distance_to(enemy.position)
		var radius: float=clampf(22000.0/maxf(distance,1.0),18,70)
		var health: float=clampf(float(enemy.health)/maxf(float(enemy.max_health),1),0,1)
		ring(point,radius+7,-PI/2,TAU-PI/2,Color(0.1,0.1,0.1,0.7),4)
		ring(point,radius+7,-PI/2,-PI/2+TAU*health,RED,4)
func plasma_status(active: bool, ids: Variant) -> String:
	if not active:return "OFF"
	if ids is Array and ids.size()>=2:
		if int(ids[0])>=0 and int(ids[1])>=0:return "FOCUS" if ids[0]==ids[1] else "SPLIT"
		if int(ids[0])>=0 or int(ids[1])>=0:return "FOCUS"
	return "FIRING"
func draw_weapons(c: CombatDirector) -> void:
	if hidden_in_flight(): return
	var status: String=plasma_status(c.beam_active,c.get("beam_target_ids"))
	put(mono,Vector2(56,900),"DUAL PLASMA",18,GREEN)
	var chip := Rect2(204,873,110,36)
	draw_rect(chip,GREEN if c.beam_active else Color(GLASS.r,GLASS.g,GLASS.b,.62))
	if not c.beam_active:draw_rect(chip,Color(GREEN.r,GREEN.g,GREEN.b,.7),false,1)
	put(mono,chip.position+Vector2(10,26),status,19,GLASS if c.beam_active else SOFT)
	put(body,Vector2(334,898),"SHOW ID 4 / HOLD SPACE OR LEFT MOUSE",16,WHITE)
	var swarm: bool=bool(c.get("swarm_active"))
	put(mono,Vector2(56,943),"AUTO MISSILES",18,GREEN)
	put(mono,Vector2(240,943),("READY" if c.missile_cooldown<=0 else "%.1fs" % c.missile_cooldown) if swarm else "STANDBY",17,GREEN if swarm else SOFT)
	put(body,Vector2(370,941),"ONE GOOSE PER THREE-GOOSE WAVE" if swarm else "AUTOMATIC ON THREE-GOOSE WAVES",15,WHITE)
## Compact wave and kill count. No progress bar or per-goose pips.
func draw_objective(c: CombatDirector) -> void:
	if hidden_in_flight() or not c.active or not c.engagement_enabled: return
	var tally: Vector2 = skein_tally(c)
	var wave_title: String="FLOCKS"
	if app.mission.cinematic and app.mission.has_method("wave_down"):
		if app.mission.wave_number<=0:return
		tally=Vector2(app.mission.wave_down(),app.mission.wave_size)
		wave_title="WAVE %d" % app.mission.wave_number
	if tally.y<=0.0: return
	put(mono,Vector2(540,118),"%s  ·  %d/%d" % [wave_title,int(tally.x),int(tally.y)],20,AMBER,HORIZONTAL_ALIGNMENT_CENTER,520)

func draw_alerts(f: FlightDynamics,c: CombatDirector) -> void:
	var y := 220.0
	if f.stall_time>.6:
		put(mono,Vector2(56,y),"NOSE TOO HIGH · EASE OFF, ADD POWER",17,RED); y+=28
	if app.eject_hold>0:
		put(mono,Vector2(56,y),"EJECTING · KEEP HOLDING E",17,RED); y+=28
	if app.mode=="ejected":
		put(mono,Vector2(56,y),"EJECTED",17,AMBER); y+=28
	if c.message_time>0:put(mono,Vector2(56,y),c.message.to_upper(),17,AMBER)

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
	camera_card(Rect2(220,324,558,340),"LAPTOP / YOKE + ID 4",app.yoke_preview,app.vision.tracking)
	camera_card(Rect2(802,324,578,340),"PHONE / THROTTLE",app.throttle_preview,app.vision.throttle_confidence>.4)
	put(body,Vector2(220,713),"Keep the yoke pattern uncovered. Cover the plasma gun tag to stop firing.",18,SOFT)
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
	button("restart",Rect2(546,608,242,54),"RESTART DEMO")
	button("title",Rect2(812,608,242,54),"RETURN TO DECK")
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
	var rows: Array[Array] = [["ARROWS","Climb, dive and bank"],[",  .","Rudder left / right"],["W  S","Faster, slower"],["SHIFT","Hold for afterburner"],["SPACE / CLICK","Hold dual plasma; release to stop"],["AUTO MISSILES","Two every five seconds in large flocks"],["GUN TAG ID 4","Show for plasma; cover to stop"],["Z","Flares"],["Q","Barrel roll"],["V","Cockpit or chase view"],["A / G  ·  F","Gear + flaps together / flaps only"],["B / BADGE B","Land now; steer your own approach"],["H","Auto-fly on / off"],["HOLD E","Eject"],["C  M  ESC","Set up cardboard, mute, pause"]]
	for i in range(rows.size()):
		put(mono,Vector2(388,250+i*37),rows[i][0],18,GREEN)
		put(body,Vector2(610,250+i*37),rows[i][1],18,WHITE)
	button("help",Rect2(990,824,240,52),"BACK",true)
func draw_settings() -> void:
	zones.clear();dim();var card:=settings_rect();panel(card,.95)
	button("settings_flight",Rect2(card.position+Vector2(card.size.x-364,52),Vector2(150,44)),"FLIGHT",settings_page=="flight")
	button("settings_audio",Rect2(card.position+Vector2(card.size.x-200,52),Vector2(164,44)),"AUDIO",settings_page=="audio")
	if settings_page=="audio":draw_audio_settings(card);return
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
		put(mono,rect.position+Vector2(rect.size.x-52,53),"%.2f×" % sensitivity_sliders[axis].max_value,14,SOFT)
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

func draw_audio_settings(card: Rect2) -> void:
	put(mono,card.position+Vector2(36,39),"SETTINGS / SAVED AUTOMATICALLY",16,GREEN)
	put(display_bold,card.position+Vector2(33,93),"AUDIO",52,WHITE)
	put(body,card.position+Vector2(36,126),"Balance Free Bird, the aircraft, effects and voices.",17,SOFT)
	var labels: Dictionary={"music":"FREE BIRD / MUSIC","engine":"ENGINE / WIND","effects":"WEAPONS / EFFECTS","voice":"RADIO / INSTRUCTOR"}
	for channel: String in AUDIO_CHANNELS:
		var rect:=audio_slider_rect(channel)
		put(body,rect.position+Vector2(0,-15),labels[channel],18,WHITE)
		put(mono,rect.position+Vector2(rect.size.x-90,-15),"%d%%" % roundi(float(app.audio_settings.get(channel))*100),19,GREEN)
		put(mono,rect.position+Vector2(0,53),"SILENT",14,SOFT)
		put(mono,rect.position+Vector2(rect.size.x-60,53),"200%" if channel=="music" else "100%",14,SOFT)
	button("mute",Rect2(card.position+Vector2(36,650),Vector2(270,46)),"UNMUTE ALL" if app.audio.muted else "MUTE ALL",false,"M")
	put(body,card.position+Vector2(36,732),"Defaults: Free Bird 200% · other sounds 50%.",16,SOFT)
	button("audio_reset",Rect2(card.position+Vector2(36,763),Vector2(280,52)),"RESET AUDIO")
	button("settings",Rect2(card.position+Vector2(card.size.x-236,763),Vector2(200,52)),"DONE",true,"HOME")

func camera_card(rect: Rect2,title: String,preview,tracking: bool,compact: bool = false) -> void:
	if compact:
		if preview.texture!=null:
			var image_size: Vector2=preview.texture.get_size()
			image_size*=minf(rect.size.x/image_size.x,rect.size.y/image_size.y)
			draw_texture_rect(preview.texture,Rect2(rect.position+(rect.size-image_size)/2,image_size),false)
		else:put(body,rect.position+Vector2(8,rect.size.y*.5),"Waiting for camera",14,SOFT)
		put(mono,rect.position+Vector2(7,17),title,11,WHITE)
		return
	panel(rect,.88,GREEN if preview.texture!=null and tracking else HAIRLINE)
	put(mono,rect.position+Vector2(7 if compact else 12,17 if compact else 21),title,12 if compact else 14,GREEN)
	var picture:=Rect2(rect.position+Vector2(3,23),rect.size-Vector2(6,42)) if compact else Rect2(rect.position+Vector2(6,31),rect.size-Vector2(12,60))
	if preview.texture!=null:
		var extent: Vector2=preview.texture.get_size();var ratio: float=minf(picture.size.x/extent.x,picture.size.y/extent.y);extent*=ratio
		draw_texture_rect(preview.texture,Rect2(picture.position+(picture.size-extent)/2,extent),false)
	else:
		put(body,picture.position+Vector2(10,picture.size.y/2),"Waiting for camera",16,SOFT)
	put(mono,rect.position+Vector2(7 if compact else 12,rect.size.y-(6 if compact else 10)),"TRACKING" if tracking and preview.texture!=null else "LIVE / TAG NOT FOUND" if preview.texture!=null else "DISCONNECTED",13,GREEN if tracking and preview.texture!=null else AMBER)
func draw_pilot_readouts(f: FlightDynamics) -> void:
	var top: float=882
	put(mono,Vector2(50,top+25),"SPEED",14,GREEN)
	put(display,Vector2(50,top+69),"%d" % int(cas_knots(f)),44,WHITE)
	put(mono,Vector2(142,top+65),"KTS",14,SOFT)
	put(mono,Vector2(330,top+25),"POWER",14,GREEN)
	put(display,Vector2(330,top+69),"%d%%" % roundi(f.throttle*100),38,WHITE)
	put(mono,Vector2(50,top+103),"PITCH %+.1f°" % rad_to_deg(f.pitch),15,GREEN)
	put(mono,Vector2(220,top+103),"YAW %+.1f°" % rad_to_deg(wrapf(f.heading,-PI,PI)),15,GREEN)
	put(mono,Vector2(390,top+103),"BANK %+.1f°" % rad_to_deg(f.roll),15,GREEN)

func draw_camera_previews() -> void:
	camera_card(Rect2(992,831,300,169),"LAPTOP / YOKE + ID 4",app.yoke_preview,app.vision.tracking,true)
	camera_card(Rect2(1300,831,300,169),"PHONE / THROTTLE",app.throttle_preview,app.vision.throttle_confidence>.4,true)
func draw_camera_setup() -> void:
	zones.clear();dim();panel(Rect2(180,90,1240,820),.95)
	put(display_bold,Vector2(218,166),"TWO-CAMERA COCKPIT",56,WHITE)
	put(body,Vector2(220,201),"Laptop: yoke and plasma gun tag. Phone: throttle. Both previews stay independent.",18,SOFT)
	camera_card(Rect2(220,234,558,362),"LAPTOP / YOKE + ID 4",app.yoke_preview,app.vision.tracking)
	camera_card(Rect2(802,234,578,362),"PHONE / THROTTLE",app.throttle_preview,app.vision.throttle_confidence>.4)
	put(body,Vector2(220,640),"Keep the yoke tag visible; show the throttle handle and both end tags to the phone.",18,WHITE)
	put(mono,Vector2(220,675),"PLASMA %s  /  SHOW ID 4 OR HOLD SPACE / LEFT MOUSE" % ("ON" if app.gun_requested() else "OFF"),16,GREEN)
	put(body,Vector2(220,706),"Badge: A gear + flaps · B landing mode · HOME pause · hold DOWN tactical.",16,SOFT)
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
	var lines: Array[String] = ["The SPECTRE is a made-up jet, tuned for fun.","Jet model: FlightGear F-35B community, GPL (source included).","Goose: Poly by Google, CC BY 3.0.","Sound effects and voices: Kenney, CC0.","Music: user-provided Free Bird solo. Goose calls: British Library, CC BY-SA.","Ground and sky: USGS, FlightGear, Poly Haven.","Fonts: Saira Condensed and IBM Plex Mono, SIL OFL.","Title art: image generation.","Engine: Godot, MIT. Full notices ship with the game."]
	for i in range(lines.size()): put(body,Vector2(388,296+i*40),lines[i],18,WHITE if i==0 else SOFT)
	button("credits",Rect2(990,770,240,52),"BACK",true)
func context_coach() -> Dictionary:
	var f: FlightDynamics=app.flight
	var state: String="GEAR %s · FLAPS %d · POWER %d%%" % ["DOWN" if f.gear else "UP",f.flaps,roundi(f.throttle*100)]
	if app.mode=="rollout":
		return {"title":"LANDED / STAY ON THE GROUND", "body":"Reduce throttle. Your touchdown stays planted while you slow down.", "status":state+" · BADGE A / G: GEAR + FLAPS"}
	if app.landing_started:
		var configuration: String="Gear + flaps are DOWN. Keep them down for touchdown." if f.gear and f.flaps>0 else "Press F to lower the flaps; gear is already DOWN." if f.gear else "BADGE A / G: put gear + flaps DOWN."
		return {"title":"REDUCE SPEED / THROTTLE BACK", "body":configuration+" Slow toward 120 knots. Steer and pitch your approach.", "status":state+" · B: RESTART APPROACH"}
	if not f.airborne:
		return {"title":"TAKE OFF / INCREASE POWER", "body":"Push the throttle forward. Pull the yoke toward you as speed builds; keyboard W and UP also work.", "status":state+" · AFTER TAKEOFF: BADGE A / G RETRACTS GEAR + FLAPS"}
	if f.gear:
		return {"title":"BADGE A / G: RETRACT GEAR + FLAPS", "body":"You are airborne. Retract the wheels and flaps, then keep flying and shooting.", "status":state+" · B / BADGE B: LAND WHENEVER YOU LIKE"}
	if f.flaps>0:
		return {"title":"PRESS F TO RETRACT THE FLAPS", "body":"Gear is already UP. Bring the remaining flaps up for cruising.", "status":state+" · B / BADGE B: LAND WHENEVER YOU LIKE"}
	var title: String="FLY · SHOOT · KEEP GOING"
	var message: String="Show plasma tag ID 4, or hold SPACE / left mouse. Cover or release to stop. New flocks keep arriving."
	if app.tutorial.active:
		var lesson: Dictionary=app.tutorial.lesson()
		title=str(lesson.title);message=" ".join(lesson.lines)
	return {"title":title, "body":message, "status":state+" · B / BADGE B: LAND NOW"}
func draw_context_coach() -> void:
	var coach: Dictionary=context_coach()
	panel(Rect2(600,772,352,212),.9,GREEN)
	put(display_bold,Vector2(616,802),str(coach.title),18,GREEN)
	var lines: PackedStringArray=tutorial_lines(str(coach.body),320,15)
	for i in range(mini(lines.size(),5)):put(body,Vector2(616,827+i*19),lines[i],15,WHITE)
	var status_lines: PackedStringArray=tutorial_lines(str(coach.status),320,11,mono)
	for i in range(mini(status_lines.size(),3)):put(mono,Vector2(616,947+i*14),status_lines[i],11,SOFT)

func centered_text(at: Vector2, value: String, font_size: int = 18, color: Color = WHITE) -> void:
	var width := body.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	put(body,at-Vector2(width/2,0),value,font_size,color)

func tutorial_lines(value: String, width: float, font_size: int, face: Font = null) -> PackedStringArray:
	var measured_font: Font=body if face==null else face
	var lines := PackedStringArray()
	var current := ""
	for word: String in value.split(" "):
		var candidate := word if current.is_empty() else current+" "+word
		if not current.is_empty() and measured_font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width:
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
		var tag := "ID 4"
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
	if not lesson.calibration_only:
		put(display_bold,Vector2(64,73),"SET UP YOUR CARDBOARD COCKPIT",46,WHITE)
		var labels: Array[String]=["01 / CALIBRATE","02 / THROTTLE","03 / YOKE","04 / PLASMA","05 / BUTTONS"]
		var groups: Array[String]=["calibrate","throttle","yoke","weapons","buttons"]
		for i in range(groups.size()):
			var selected: bool=i==0 if lesson.calibrating else group==groups[i] or done and i==4
			var rect:=Rect2(64+i*298,101,280,43)
			panel(rect,.9,GREEN if selected else HAIRLINE)
			put(mono,rect.position+Vector2(14,28),labels[i],17,GREEN if selected else SOFT)
	var camera_y: float=64.0 if lesson.calibration_only else 164.0
	camera_card(Rect2(64,camera_y,724,480),"LAPTOP / YOKE + ID 4",app.yoke_preview,v.tracking)
	camera_card(Rect2(812,camera_y,724,480),"PHONE / THROTTLE",app.throttle_preview,v.throttle_confidence>.4)
	var info_y: float=camera_y+500.0
	panel(Rect2(64,info_y,1472,132),.95)
	var heading: String="Hold yoke upright for 3 seconds" if lesson.calibrating else "Ready to fly" if done else str(step[2])
	if (lesson.calibrating or done) and roundi(v.throttle*100)>0:heading="Set throttle to 0%"
	put(display_bold,Vector2(90,info_y+46),heading,32,WHITE)
	if lesson.calibrating:bar(Rect2(90,info_y+59,1420,8),clampf(lesson.calibration_progress,0,1),GREEN)
	var values: String="THROTTLE %3d%%   BANK %+.0f%%   PITCH %+.0f%%   YAW %+.0f%%" % [roundi(v.throttle*100),v.steering().x*100,v.steering().y*100,v.steering().z*100]
	put(mono,Vector2(90,info_y+98),values,18,GREEN)
	if not v.connected:put(body,Vector2(64,894),"Start Launch Two-Camera Cockpit with your phone connected, then return here.",15,AMBER)
	button("setup_cancel",Rect2(64,916,288,56),"BACK",false,"ESC / HOME")
	button("setup_keyboard",Rect2(370,916,300,56),"USE KEYBOARD")
	button("setup_retry",Rect2(1236,916,300,56),"RETRY THIS STEP",true)
