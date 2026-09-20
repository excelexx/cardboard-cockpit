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
func _process(dt: float) -> void:
	clock += dt; queue_redraw()

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
	if app.mode=="title": draw_title()
	else: draw_flight()
	if app.mode=="paused": draw_pause()
	if app.mode=="results": draw_results()
	if app.toast_time>0 and app.mode=="flight": centered(176,app.toast.to_upper(),18,GREEN)
	if app.mode=="flight" and app.mission.phase=="aftermath": button("land",Rect2(590,790,420,62),"LAND AT SFO",true,"B")
	if app.landing_transition>0:
		draw_rect(Rect2(0,0,1600,1000),Color(0.01,.02,.03,clampf(app.landing_transition/1.2,0,1)))
		centered(496,"HEADING BACK TO SFO",40,WHITE,display_bold)
	if app.tutorial.active and app.mode in ["flight","rollout"] and not app.overlay_visible():draw_tutorial()
	if app.help_visible: draw_help()
	if app.calibration_visible: draw_camera_setup()
	if app.credits_visible: draw_credits()

# --- title ------------------------------------------------------------------
func draw_title() -> void:
	if title_art!=null: draw_texture_rect(title_art,Rect2(0,0,1600,1000),false)
	else: draw_rect(Rect2(0,0,1600,1000),Color(0.025,0.045,0.07))
	draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(1000,0),Vector2(1000,1000),Vector2(0,1000)]),PackedColorArray([Color(0.02,0.035,0.035,0.92),Color(0.02,0.035,0.035,0),Color(0.02,0.035,0.035,0),Color(0.02,0.035,0.035,0.92)]))
	text(Vector2(96,150),"CARDBOARD COCKPIT",18,GREEN,true)
	big(Vector2(92,268),"WILD GOOSE",124,WHITE,HORIZONTAL_ALIGNMENT_LEFT,-1,true)
	big(Vector2(92,376),"CHASE",124,WHITE,HORIZONTAL_ALIGNMENT_LEFT,-1,true)
	text(Vector2(96,436),"Shoot down the geese. Clear the big skein.",20,WHITE)
	text(Vector2(96,466),"Land at SFO. You have 2:30.",20,WHITE)
	button("fly",Rect2(96,520,420,72),"PLAY",true,"ENTER · START")
	button("guided",Rect2(96,604,420,52),"WATCH DEMO")
	button("approach",Rect2(96,666,420,52),"LANDING PRACTICE")
	button("camera",Rect2(96,728,420,52),"SET UP CARDBOARD")
	button("help",Rect2(96,790,205,48),"CONTROLS")
	button("credits",Rect2(311,790,205,48),"CREDITS")
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
	var found: Variant = c.get("skein_ids")
	return found if found is Array else []
static func aoa_bracket_gap(f: FlightDynamics) -> float:
	var share: float = clampf(read_number(f,"aoa",0.0)/FlightDynamics.ALPHA_MAX,0.0,1.0)
	return lerpf(INDEXER_OPEN,INDEXER_SHUT,share)

# --- flight -----------------------------------------------------------------
func mission_line() -> String:
	if not app.mission.active: return ""
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
	if app.camera_rig.missile_link:
		panel(Rect2(43,430,336,198),.92,GREEN)
		draw_texture_rect(app.camera_rig.pip_texture,Rect2(49,459,324,164),false)
		text(Vector2(56,452),"MISSILE CAMERA · X TO CLOSE",14,GREEN,true)
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
	var ring_edge: Vector3 = c.forward().rotated(app.camera.global_basis.x,deg_to_rad(c.intent.acquire_degrees(c)))
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
func draw_weapons(c: CombatDirector) -> void:
	if hidden_in_flight(): return
	var gun_on: bool = app.primary_latched or c.beam_active
	var rows: Array = [["GUN",gun_on,"Switch 1 · SPACE",c.primary_used],["MISSILES",app.salvo_latched,"Switch 2 · T",c.salvo_used]]
	for i in range(2):
		var y: float = 900+i*46
		put(mono,Vector2(56,y),rows[i][0],20,GREEN)
		var on: bool = rows[i][1]
		var chip := Rect2(204,y-27,64 if on else 72,36)
		if on:
			draw_rect(chip,GREEN)
			draw_string(display_bold,chip.position+Vector2(13,28),"ON",HORIZONTAL_ALIGNMENT_LEFT,-1,30,GLASS)
		else:
			draw_rect(chip,Color(GLASS.r,GLASS.g,GLASS.b,0.62));draw_rect(chip,Color(GREEN.r,GREEN.g,GREEN.b,0.7),false,1)
			draw_string(display_bold,chip.position+Vector2(13,28),"OFF",HORIZONTAL_ALIGNMENT_LEFT,-1,30,SOFT)
		if not rows[i][3] and app.mission.clock<25: put(body,Vector2(292,y-2),rows[i][2],16,WHITE)
## How much of the skein is down, in the span the old health bar used to hold:
## one pip per bird, amber as it goes down. No named individual, no health bar.
func draw_objective(c: CombatDirector) -> void:
	if hidden_in_flight() or not c.active or not c.engagement_enabled: return
	var tally: Vector2 = skein_tally(c)
	if tally.y<=0.0: return
	put(mono,Vector2(540,118),"GEESE %d / %d" % [int(tally.x),int(tally.y)],20,AMBER)
	put(mono,Vector2(540,118),"SKEIN",20,AMBER,HORIZONTAL_ALIGNMENT_RIGHT,520)
	var pips: int = clampi(int(tally.y),1,26)
	var width: float = (526.0-float(pips-1)*4.0)/float(pips)
	draw_rect(Rect2(536,124,534,22),Color(GLASS.r,GLASS.g,GLASS.b,0.66))
	for index in range(pips):
		var slot := Rect2(540.0+float(index)*(width+4.0),128,width,14)
		if index<int(tally.x): draw_rect(slot,AMBER)
		else: draw_rect(slot,Color(AMBER.r,AMBER.g,AMBER.b,0.18)); draw_rect(slot,Color(AMBER.r,AMBER.g,AMBER.b,0.35),false,1)
func draw_alerts(f: FlightDynamics,c: CombatDirector) -> void:
	var y := 800.0
	if c.incoming_distance<2200:
		var bearing: float = c.incoming_bearing
		var position := Vector2(800+sin(bearing)*650,470-cos(bearing)*300)
		var direction := Vector2(sin(bearing),-cos(bearing))
		var side := direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([position+direction*16,position-direction*9+side*11,position-direction*9-side*11]),RED)
		banner(y,"MISSILE!",["Press","[Z]","for flares"],RED); y -= 62
	if f.stall_time>.6: banner(y,"NOSE TOO HIGH",["Ease off, add power"],RED); y -= 62
	if app.eject_hold>0:
		banner(y,"EJECTING",["Keep holding","[E]"],RED)
		bar(Rect2(640,y+22,320,8),app.eject_hold/.9,RED); y -= 72
	if app.mode=="ejected": banner(y,"EJECTED",["You are out of the jet"],AMBER); y -= 62
	if c.message_time>0: banner(y,c.message.to_upper(),[],AMBER); y -= 62
	if app.mission.active and app.mode in ["flight","rollout"]:
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
	if c.incoming_distance<2200: banner(250,"MISSILE!",["Press","[Z]","for flares"],RED)
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
	for shot: Dictionary in c.shots:
		if shot.kind!="hostile_missile": continue
		var delta: Vector3 = shot.position-app.flight.position
		draw_circle(center+(Vector2(delta.x,delta.z).rotated(-app.flight.heading)*0.030).limit_length(86),3,AMBER)
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
func draw_pause() -> void:
	zones.clear(); dim()
	put(display_bold,Vector2(580,300),"PAUSED",104,WHITE)
	put(body,Vector2(584,340),"The jet waits for you.",18,SOFT)
	button("resume",Rect2(580,380,440,68),"RESUME",true,"ESC · HOME")
	button("restart",Rect2(580,460,440,52),"RESTART")
	button("help",Rect2(580,522,440,52),"CONTROLS")
	button("mute",Rect2(580,584,440,52),"SOUND",false,"OFF" if app.audio.muted else "ON")
	button("quality",Rect2(580,646,440,52),"GRAPHICS",false,"HIGH" if app.high_quality else "BALANCED")
	button("title",Rect2(580,708,440,52),"MAIN MENU")
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
	var rows: Array[Array] = [["ARROWS","Climb, dive and bank"],["A  D","Rudder: slide left and right"],["W  S","Faster, slower"],["SHIFT","Hold for afterburner"],["SPACE","Gun on / off (yoke switch 1)"],["T","Missiles on / off (yoke switch 2)"],["Z","Flares"],["Q","Barrel roll"],["V","Cockpit or chase view"],["X","Missile camera"],["G  F","Landing gear, flaps"],["H","Auto-fly on / off"],["HOLD E","Eject"],["C  M  ESC","Set up cardboard, mute, pause"]]
	for i in range(rows.size()):
		put(mono,Vector2(388,252+i*40),rows[i][0],18,GREEN)
		put(body,Vector2(610,252+i*40),rows[i][1],18,WHITE)
	button("help",Rect2(990,824,240,52),"BACK",true)
func draw_camera_setup() -> void:
	zones.clear(); dim(); panel(Rect2(330,150,940,700),.9)
	put(display_bold,Vector2(384,236),"SET UP CARDBOARD",64,WHITE)
	var lines: Array[String] = ["1. Run  tools/tracker.sh --camera 0 --check  and fix any FAIL line.","2. Run  tools/tracker.sh --camera 0 --calibrate  and hold the seven poses.","3. Turn tracking on below, then hold the yoke level.","","Yoke switch 1 is the gun. Switch 2 is missiles.","Badge button B lands the jet at SFO."]
	for i in range(lines.size()): put(body,Vector2(388,300+i*38),lines[i],18,WHITE if i<3 else SOFT)
	put(mono,Vector2(388,570),str(app.vision.status).to_upper(),18,GREEN if app.vision.tracking else AMBER)
	put(mono,Vector2(388,610),"ROLL %+.2f · PITCH %+.2f · POWER %d%%" % [app.vision.yoke.x,app.vision.yoke.y,int(app.vision.throttle*100)],18,WHITE)
	button("vision",Rect2(388,730,400,62),"TRACKING ON" if app.vision.enabled else "TURN TRACKING ON",true)
	button("camera",Rect2(800,730,240,62),"BACK")
func draw_credits() -> void:
	zones.clear(); dim(); panel(Rect2(330,150,940,700),.9)
	put(display_bold,Vector2(384,236),"CREDITS",64,WHITE)
	var lines: Array[String] = ["The SPECTRE is a made-up jet, tuned for fun.","Jet model: FlightGear F-35B community, GPL (source included).","Goose: Poly by Google, CC BY 3.0.","Missile: Jarlan Perez, CC BY 3.0.","Sound effects and voices: Kenney, CC0.","Music: MintoDog, CC0. Goose calls: British Library, CC BY-SA.","Ground and sky: USGS, FlightGear, Poly Haven.","Fonts: Saira Condensed and IBM Plex Mono, SIL OFL.","Title art: image generation.","Engine: Godot, MIT. Full notices ship with the game."]
	for i in range(lines.size()): put(body,Vector2(388,296+i*40),lines[i],18,WHITE if i==0 else SOFT)
	button("credits",Rect2(990,770,240,52),"BACK",true)
func draw_tutorial() -> void:
	var lesson: Dictionary=app.tutorial.lesson()
	panel(Rect2(300,748,1000,64+lesson.lines.size()*30),.82,GREEN)
	put(display_bold,Vector2(328,790),str(lesson.title).to_upper(),30,GREEN)
	for i in range(lesson.lines.size()): put(body,Vector2(328,824+i*30),str(lesson.lines[i]),19,WHITE)
