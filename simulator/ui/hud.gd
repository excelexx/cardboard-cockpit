extends Control
class_name CockpitHUD
const Tune = preload("res://data/balance.gd")
signal action(name: String)
var app: Node
var font := SystemFont.new()
var mono := SystemFont.new()
var title_art: Texture2D
var zones: Dictionary = {}
var hot := ""
var clock := 0.0
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
func _process(dt: float) -> void:
	clock += dt; queue_redraw()
func text(at: Vector2, value: String, size: int = 18, color: Color = WHITE, technical: bool = false) -> void:
	if not app.text_hud and app.mode=="flight" and not app.overlay_visible() and not app.tutorial.active:return
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
	if app.mode=="title": draw_title()
	else: draw_flight()
	if app.mode=="paused": draw_pause()
	if app.mode=="results": draw_results()
	if app.toast_time>0 and app.mode=="flight":text(Vector2(510,170),app.toast,17,CYAN,true)
	if app.mode=="flight" and app.mission.phase=="aftermath":button("land",Rect2(590,790,420,58),"LAND AT SFO  /  BADGE B",true)
	if app.landing_transition>0:
		draw_rect(Rect2(0,0,1600,1000),Color(0.01,.02,.03,clampf(app.landing_transition/1.2,0,1)))
		text(Vector2(580,480),"RETURNING TO SFO FINAL",24,WHITE)
	if app.tutorial.active and app.mode in ["flight","rollout"] and not app.overlay_visible():draw_tutorial()
	if app.help_visible: draw_help()
	if app.calibration_visible: draw_camera_setup()
	if app.credits_visible: draw_credits()
func draw_title() -> void:
	if title_art!=null: draw_texture_rect(title_art,Rect2(0,0,1600,1000),false)
	else: draw_rect(Rect2(0,0,1600,1000),Color(0.025,0.045,0.07))
	# Draw a simple transparent scrim; retain the generated art as the focal point.
	draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(960,0),Vector2(960,1000),Vector2(0,1000)]),PackedColorArray([Color(0.012,0.025,0.038,0.90),Color(0.012,0.025,0.038,0),Color(0.012,0.025,0.038,0),Color(0.012,0.025,0.038,0.90)]))
	text(Vector2(72,100),"GOOSE PROTOCOL",16,CYAN,true)
	text(Vector2(66,283),"SPECTRE",86,WHITE)
	text(Vector2(72,335),"X—26",34,MUTED,true)
	line(Vector2(74,373),Vector2(478,373),Color(0.4,0.72,0.77,0.4))
	text(Vector2(74,421),"Clear the flock. Enjoy the flight.",26,WHITE)
	text(Vector2(74,468),"One city. Two switches. One very large goose.",18,MUTED)
	button("fly",Rect2(74,571,394,69),"PLAY   →",true)
	text(Vector2(500,615),"SAN FRANCISCO  /  2:30 MAX",14,CYAN,true)
	button("guided",Rect2(74,659,187,48),"Watch demo")
	button("approach",Rect2(279,659,189,48),"Landing practice")
	button("camera",Rect2(74,737,187,43),"Cardboard setup")
	button("help",Rect2(279,737,189,43),"Flight controls")
	text(Vector2(74,846),"ENTER  PLAY    •    F1  CONTROLS",12,CYAN,true)
	text(Vector2(74,892),"SPACE  PRIMARY TOGGLE  /  T  SALVO TOGGLE",11,MUTED,true)
	text(Vector2(74,915),app.badge.status,11,GREEN if app.badge.connected else MUTED,true)
	button("credits",Rect2(74,927,140,34),"Credits")
func draw_flight() -> void:
	if app.paper_test or (app.cockpit and not app.combat.active):
		draw_clear_flight()
		return
	if app.paper_test:
		text(Vector2(460,150),"YOKE LIVE  /  ROTATE TO BANK  /  TILT TO PITCH" if app.vision.tracking else "HOLD MARKER 7 STEADY TO CENTER  /  FLIGHT HELD",16,CYAN,true)
	var f: FlightDynamics = app.flight
	var c: CombatDirector = app.combat
	text(Vector2(42,49),"SPECTRE / X–26",14,WHITE,true)
	text(Vector2(42,75),app.mission.label() if app.mission.active else "FCS NOMINAL" if c.hull>65 else "AIRFRAME CAUTION",12,CYAN if c.hull>65 else AMBER,true)
	text(Vector2(1376,49),"%02d:%02d" % [int(app.mission.clock)/60,int(app.mission.clock)%60] if app.mission.active else "%02d:%02d" % [maxi(0,int(ceil(c.duration-c.elapsed)))/60,maxi(0,int(ceil(c.duration-c.elapsed)))%60] if app.flight_kind=="combat" else ("SFO 28R" if app.route_id=="sf" else "RWY 36"),19,WHITE,true)
	text(Vector2(1376,73),"FCS / GUIDED" if app.copilot else "CARDBOARD" if app.vision.tracking else "FCS / MANUAL",10,CYAN,true)
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
	if app.mission.active and app.mission.phase in ["opening","combat","return"]:
		var waypoint: Vector3 = app.mission.route_target()
		if not app.camera.is_position_behind(waypoint):
			var nav: Vector2 = app.camera.unproject_position(waypoint)
			nav = nav.clamp(Vector2(160,135),Vector2(1440,730))
			draw_polyline(PackedVector2Array([nav+Vector2(0,-10),nav+Vector2(10,0),nav+Vector2(0,10),nav+Vector2(-10,0),nav+Vector2(0,-10)]),Color(.4,.7,1),2,true)
			text(nav+Vector2(16,3),"NAV %02d" % (app.mission.route_index+1),11,Color(.5,.75,1),true)
	var nose: Vector2 = app.camera.unproject_position(f.position+c.forward()*2000)
	var ring_edge: Vector3 = c.forward().rotated(app.camera.global_basis.x,deg_to_rad(c.intent.acquire_degrees(c)))
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
		text(nose+Vector2(-50,ring_radius+22),"TRACK",11,MUTED,true)
		if not tracking: text(nose+Vector2(-62,ring_radius+40),"",10,MUTED,true)
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
		text(Vector2(716,146),"+%d" % c.last_reward,32,Color(1,.80,.36,c.reward_flash),true)
		if c.combo>=3: text(Vector2(716,174),"%d IN A ROW" % c.combo,14,Color(.65,1,.83,c.reward_flash),true)
	if c.incoming_distance<2200:
		var bearing: float = c.incoming_bearing
		var position := Vector2(800+sin(bearing)*650,470-cos(bearing)*300)
		var direction := Vector2(sin(bearing),-cos(bearing))
		var side := direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([position+direction*9,position-direction*5+side*6,position-direction*5-side*6]),DANGER)
		text(Vector2(635,125),"MISSILE INBOUND  /  Z FLARES",12,DANGER,true)
	if c.hit_flash>0:
		line(Vector2(20,270),Vector2(20,660),Color(1,0.25,0.15,c.hit_flash*1.7),4)
		line(Vector2(1580,270),Vector2(1580,660),Color(1,0.25,0.15,c.hit_flash*1.7),4)
	draw_scope(Vector2(1450,830),c)
	var primary_color: Color=CYAN if app.primary_latched or c.beam_active else MUTED
	var salvo_color: Color=CYAN if app.salvo_latched else MUTED
	text(Vector2(45,907),"PRIMARY  "+("LIVE" if app.primary_latched or c.beam_active else "SAFE"),12,primary_color,true)
	text(Vector2(235,907),"QUAD SALVO  "+("LIVE" if app.salvo_latched else "SAFE"),12,salvo_color,true)
	if not c.primary_used and app.mission.clock<25:text(Vector2(45,933),"SPACE / YOKE SWITCH 1",11,WHITE,true)
	if not c.salvo_used and app.mission.clock<25:text(Vector2(235,933),"T / YOKE SWITCH 2",11,WHITE,true)
	if c.boss_id>=0 and not c.boss_defeated:
		for enemy: Dictionary in c.enemies:
			if enemy.id!=c.boss_id:continue
			var title: String="UNKNOWN" if enemy.age<4 or app.mission.phase=="anticipation" else "THE FINAL HONK"
			text(Vector2(690,118),title,15,CYAN,true)
			var fraction: float=clampf(enemy.health/enemy.max_health,0,1)
			for segment in range(4):
				var left: float=665+segment*70
				line(Vector2(left,131),Vector2(left+62*clampf(fraction*4-segment,0,1),131),CYAN,2)
			break
	if f.airborne:
		text(Vector2(44,550),"AIRBRAKE" if f.airbrake>.1 else "ACCEL" if f.power_input>.1 else "CRUISE",12,AMBER if f.airbrake>.1 else CYAN,true)
		text(Vector2(44,571),"W / S  SPEED",10,MUTED,true)
	if f.afterburner: text(Vector2(575,972),"AFTERBURNER",13,AMBER,true)
	else: text(Vector2(575,972),"POWER %03d%%" % int(f.throttle*100),13,MUTED,true)
	if f.gear or f.flaps>0: text(Vector2(42,967),"GEAR %s / FLAPS %d" % ["DOWN" if f.gear else "UP",f.flaps],12,AMBER,true)
	if c.message_time>0: text(Vector2(610,215),c.message,14,AMBER,true)
	if (app.flight_kind=="approach" or (app.mission.active and app.mission.phase in ["return","approach"])) and f.airborne:
		var guidance: Dictionary = app.approach_data()
		var cross := Vector2(800,730)
		line(cross-Vector2(90,0),cross+Vector2(90,0),Color(0.5,0.75,0.73,0.4))
		line(cross-Vector2(0,35),cross+Vector2(0,35),Color(0.5,0.75,0.73,0.4))
		draw_circle(cross+Vector2(guidance.localizer*80,-guidance.glideslope*30),3,CYAN)
		text(Vector2(717,760),"SFO 28R / APPROACH" if app.route_id=="sf" else "RWY 36 / APPROACH",11,CYAN,true)
	if app.mission.active and app.mode in ["flight","rollout"]:
		var instruction: String = app.mission.instruction()
		if app.copilot and not app.mission.cinematic and app.mission.phase!="combat": instruction = "FLIGHT ASSIST ON  /  ENJOY THE RIDE — STEERING IS OPTIONAL"
		var width: float = mono.get_string_size(instruction,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
		text(Vector2(800-width/2,595),instruction,15,CYAN,true)
	elif app.mode=="rollout": text(Vector2(630,739),"TOUCHDOWN / HOLD SPACE TO BRAKE",13,GREEN,true)
	if app.eject_hold>0: text(Vector2(663,730),"EJECT  %03d%%" % int(app.eject_hold/.9*100),15,AMBER,true)
	if app.mode=="ejected": text(Vector2(660,730),"EJECTION CONFIRMED",16,CYAN,true)
	if app.camera_rig.missile_link:
		panel(Rect2(43,606,336,198),.92)
		draw_texture_rect(app.camera_rig.pip_texture,Rect2(49,633,324,164),false)
		text(Vector2(56,625),"MISSILE LINK / X TO CLOSE",10,CYAN,true)
	if not app.audio.radio.caption.is_empty():
		var caption: String = app.audio.radio.caption
		var width: float = font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
		text(Vector2(800-width/2,620),app.audio.radio.speaker,9,CYAN,true)
		text(Vector2(800-width/2,644),caption,17,WHITE)
	if app.vision.tracking or app.developer_mode: draw_control_feedback()
	if app.developer_mode: text(Vector2(610,960),"%d FPS / %.1f M/S / %s" % [Engine.get_frames_per_second(),f.speed,"HIGH" if app.high_quality else "BALANCED"],11,MUTED,true)
func draw_clear_flight() -> void:
	var f: FlightDynamics=app.flight
	var c: CombatDirector=app.combat
	text(Vector2(52,64),"%d KNOTS" % int(f.speed*1.94384),24,WHITE,true)
	text(Vector2(1280,64),"%d FT" % int(f.position.y*3.28084),24,WHITE,true)
	text(Vector2(740,64),"%03d°" % int(f.get_heading_degrees()),23,CYAN,true)
	var instruction: String=""
	if app.paper_test:
		instruction="ROTATE TO BANK  ·  TILT TOP TOWARD YOU TO CLIMB" if app.vision.tracking else "SHOW MARKER 7 AND HOLD STILL — FLIGHT HELD"
	elif app.mission.active: instruction=app.mission.instruction()
	var width: float=font.get_string_size(instruction,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
	text(Vector2(800-width/2,122),instruction,19,CYAN)
	if app.mission.active:
		var target: Vector3=app.mission.route_target()
		if not app.camera.is_position_behind(target):
			var nav: Vector2=app.camera.unproject_position(target).clamp(Vector2(170,160),Vector2(1430,550))
			draw_polyline(PackedVector2Array([nav+Vector2(0,-9),nav+Vector2(9,0),nav+Vector2(0,9),nav+Vector2(-9,0),nav+Vector2(0,-9)]),CYAN,2,true)
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
			text(Vector2(1090,951),"SPACE  FIRE    T  MISSILE",17,MUTED)
			text(Vector2(680,170),"MISSILE LOCK" if c.lock_progress>=1 else "",20,GREEN)
	if c.incoming_distance<2200: text(Vector2(610,210),"MISSILE INBOUND — Z FLARES",20,DANGER)
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
	for shot: Dictionary in c.shots:
		if shot.kind!="hostile_missile": continue
		var delta: Vector3 = shot.position-app.flight.position
		var point: Vector2 = (Vector2(delta.x,delta.z).rotated(-app.flight.heading)*0.025).limit_length(73)
		draw_circle(center+point,2,DANGER)
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
	button("quality",Rect2(589,548,422,47),"Fidelity: High" if app.high_quality else "Fidelity: Balanced")
	button("restart",Rect2(589,613,200,47),"Restart sortie")
	button("title",Rect2(811,613,200,47),"Return to deck")
	text(Vector2(589,714),"ESC  RESUME",11,MUTED,true)
func draw_results() -> void:
	zones.clear(); dim(); panel(Rect2(380,228,840,547),.95)
	var c: CombatDirector = app.combat
	text(Vector2(432,291),"SPECTRE / SORTIE RECORD",13,CYAN,true)
	text(Vector2(430,347),app.result_headline,35,WHITE)
	text(Vector2(433,390),app.result_reason,17,MUTED)
	line(Vector2(433,420),Vector2(1167,420),Color(0.3,0.5,0.56,0.4))
	var labels: Array[String] = ["GEESE CLEARED","BEST STREAK","SCORE"]
	var values: Array[String] = [str(c.kills),"×%d" % c.best_combo,str(c.score)]
	for i in range(3):
		text(Vector2(433+i*255,466),labels[i],11,MUTED,true)
		text(Vector2(431+i*255,516),values[i],36,WHITE,true)
	text(Vector2(433,575),app.result_advice,14,MUTED)
	button("fly",Rect2(433,642,350,62),"PLAY AGAIN",true)
	button("title",Rect2(816,642,350,62),"FLIGHT DECK")
func draw_help() -> void:
	zones.clear(); dim(); panel(Rect2(365,136,870,738),.97)
	text(Vector2(419,196),"FLIGHT CONTROLS",13,CYAN,true)
	text(Vector2(417,244),"Precision starts with small inputs.",30,WHITE)
	var rows: Array[Array] = [["ARROWS / A D","Pitch and roll / rudder"],["W S / SHIFT","Accelerate / airbrake / hold afterburner"],["SPACE / LEFT MOUSE","Toggle minigun + continuous energy cannon"],["T / RIGHT MOUSE","Toggle repeated four-missile salvos"],["Q","Quick barrel roll"],["V / X","Cockpit or chase / missile datalink"],["ALT + MOUSE","Look around without steering"],["G / F","Landing gear / flap detent"],["B / J","Mouse flight / close-range aim assistance"],["H / HOLD E","Flight assist / eject"],["C / ESC / M","Cardboard setup / pause / mute"]]
	for i in range(rows.size()):
		text(Vector2(421,293+i*40),rows[i][0],13,WHITE,true)
		text(Vector2(707,293+i*40),rows[i][1],16,MUTED)
	button("help",Rect2(909,787,269,48),"RETURN TO FLIGHT",true)
	text(Vector2(421,817),"R REPLAY / F8 TEXT / F9 TELEMETRY",10,MUTED,true)
func draw_camera_setup() -> void:
	zones.clear(); dim(); panel(Rect2(370,175,860,650),.97)
	text(Vector2(421,236),"CARDBOARD / LOCAL INPUT",13,CYAN,true)
	text(Vector2(419,291),"Your cockpit. Your aircraft.",32,WHITE)
	var lines: Array[String] = ["1. Start tools/tracker.sh --camera 0 --calibrate.","2. Capture the seven poses in the tracker preview.","3. Enable tracking below, then centre the yoke.","Yoke switches: primary 31/32, salvo 41/42. Flip ON or OFF.","Badge B: deploy flaps + assisted landing at SFO."]
	for i in range(lines.size()): text(Vector2(423,345+i*42),lines[i],17,MUTED if i>2 else WHITE)
	text(Vector2(423,586),app.vision.status,13,CYAN if app.vision.tracking else AMBER,true)
	text(Vector2(423,626),"ROLL %+.2f / PITCH %+.2f / POWER %03d%%" % [app.vision.yoke.x,app.vision.yoke.y,int(app.vision.throttle*100)],15,WHITE,true)
	button("vision",Rect2(423,708,364,59),"TRACKING ENABLED" if app.vision.enabled else "ENABLE TRACKING",true)
	button("camera",Rect2(814,708,363,59),"RETURN")
func draw_credits() -> void:
	zones.clear(); dim(); panel(Rect2(355,170,890,660),.97)
	text(Vector2(409,233),"BUILT WITH OPEN TOOLS",13,CYAN,true)
	var lines: Array[String] = ["SPECTRE X-26 is a fictional, game-tuned airframe.","Base aircraft: FlightGear F-35B community; GPL source included.","Canada goose: Poly by Google; CC BY 3.0.","Missile: Jarlan Perez; CC BY 3.0.","Effects and voices: Kenney; CC0.","Music: MintoDog; CC0. Goose recordings: British Library; CC BY-SA.","Environment materials: Poly Haven; CC0.","Title art: image generation. Runtime systems: original project code.","Godot 4.7.2 / MIT. Complete notices are bundled with the app."]
	for i in range(lines.size()): text(Vector2(410,293+i*43),lines[i],17,WHITE if i==0 else MUTED)
	button("credits",Rect2(905,733,283,51),"BACK",true)

func draw_tutorial() -> void:
	panel(Rect2(275,755,1050,140),.84)
	var lesson: Dictionary=app.tutorial.lesson()
	text(Vector2(300,788),lesson.title,15,CYAN,true)
	for i in range(lesson.lines.size()):text(Vector2(300,820+i*27),str(lesson.lines[i]),17,WHITE)
