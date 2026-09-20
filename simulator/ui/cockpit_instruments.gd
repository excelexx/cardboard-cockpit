extends Control
class_name CockpitInstruments

# Purpose-built training flight displays; these are artistic interpretations.
const SFRoute = preload("res://systems/san_francisco_route.gd")
func route_points() -> Array[Vector3]: return SFRoute.POINTS if navigation_kind=="sf" else ROUTE
func display_heading() -> float: return fposmod(heading+(298.0 if navigation_kind=="sf" else 0.0),360.0)
var display_mode: String = "pfd"
var aircraft_name: String = "737"
var engine_count: int = 2
var speed: float = 0.0
var altitude: float = 0.0
var pitch: float = 0.0
var bank: float = 0.0
var heading: float = 0.0
var climb: float = 0.0
var throttle: float = 0.0
var engine: float = 0.0
var gear: bool = true
var flaps: int = 0
var airborne: bool = false
var stall: bool = false
## Calibrated airspeed and the pose numbers, filled by update_flight().
var cas: float = 0.0
var g_load: float = 1.0
var mach: float = 0.0
var position_world := Vector3.ZERO
var elapsed: float = 0.0
var instrument_time: float = 0.0
var navigation_kind: String = "valley"
var navigation_checkpoint: int = 0
var font: Font = ThemeDB.fallback_font
# Panoramic display (fighter): fed by the cockpit each frame.
var numerals: Font = load("res://assets/fonts/SairaCondensed-SemiBold.ttf")
var heavy: Font = load("res://assets/fonts/SairaCondensed-Bold.ttf")
var label_font: Font = load("res://assets/fonts/IBMPlexMono-Medium.ttf")
var tactical: Dictionary = {}
const P_GREEN := Color(0.553,1.0,0.690)
const P_RED := Color(1.0,0.294,0.243)
const P_AMBER := Color(1.0,0.710,0.278)
const P_WHITE := Color(0.957,0.969,0.953)
const P_SOFT := Color(0.42,0.50,0.45)
const P_LINE := Color(0.169,0.227,0.192)
const P_BACK := Color(0.016,0.024,0.022)
const WHITE := Color(0.9, 0.96, 0.98)
const MUTED := Color(0.39, 0.53, 0.62)
const CYAN := Color(0.30, 0.87, 1.0)
const GREEN := Color(0.37, 1.0, 0.62)
const AMBER := Color(1.0, 0.72, 0.28)
const MAGENTA := Color(1.0, 0.39, 0.81)
const BACK := Color(0.012, 0.023, 0.033)
const ROUTE: Array[Vector3] = [Vector3(0,180,-2000),Vector3(-450,420,-4200),Vector3(450,650,-6500),Vector3(150,420,-9000),Vector3(0,200,-11800)]
const NORTH_FIELD_AIM := Vector3(0,3,-14100)

func set_navigation(kind: String, checkpoint: int) -> void:
	var bounded: int = clampi(checkpoint,0,route_points().size())
	if navigation_kind == kind and navigation_checkpoint == bounded:
		return
	navigation_kind = kind
	navigation_checkpoint = bounded
	queue_redraw()
	_refresh_texture()

func navigation_target() -> Vector3:
	if navigation_kind in ["valley","sf"] and navigation_checkpoint < route_points().size():
		return route_points()[navigation_checkpoint]
	return Vector3(0,4,1300) if navigation_kind=="sf" else NORTH_FIELD_AIM

func navigation_target_label() -> String:
	if navigation_kind in ["valley","sf"] and navigation_checkpoint < route_points().size():
		return "CP%02d" % (navigation_checkpoint+1)
	return "SFO / 28R" if navigation_kind=="sf" else "NORTH FIELD"

func update_flight(flight: FlightDynamics, dt: float) -> void:
	speed = flight.speed * 1.94384
	cas = CockpitHUD.cas_knots(flight)
	g_load = CockpitHUD.read_number(flight,"g_load",1.0)
	mach = CockpitHUD.read_number(flight,"mach",0.0)
	altitude = maxf(0.0, flight.position.y * 3.28084)
	pitch = flight.pitch
	bank = flight.roll
	heading = flight.get_heading_degrees()
	climb = flight.vertical_speed * 196.8504
	throttle = flight.throttle
	engine = flight.engine
	gear = flight.gear
	flaps = flight.flaps
	airborne = flight.airborne
	stall = flight.airborne and flight.stall_time > 0.6
	position_world = flight.position
	elapsed = flight.elapsed
	instrument_time += dt
	if instrument_time > 1.0 / 24.0:
		instrument_time = 0.0
		queue_redraw()
		_refresh_texture()

func _refresh_texture() -> void:
	# Keep the flight world smooth; physical instrument LCDs only need 24 Hz.
	if get_parent() is SubViewport:
		get_parent().render_target_update_mode=SubViewport.UPDATE_ONCE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	if display_mode == "dual_flight":
		_panel_transform(Vector2.ZERO,1.0)
		_pfd()
		_panel_transform(Vector2(768,0),1.0)
		_nav()
		draw_set_transform(Vector2.ZERO)
	elif display_mode == "panorama":
		_panorama()
	else:
		_panel_transform(Vector2.ZERO, size.x / 768.0)
		match display_mode:
			"pfd": _pfd()
			"nav": _nav()
			"engine": _engines()
		draw_set_transform(Vector2.ZERO)

func _panel_transform(origin: Vector2, factor: float) -> void:
	draw_set_transform(origin, 0, Vector2.ONE * factor)

func _text(value: String, point: Vector2, font_size: int = 25, color: Color = WHITE) -> void:
	draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _center(value: String, point: Vector2, font_size: int = 25, color: Color = WHITE) -> void:
	var width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, point - Vector2(width * 0.5,0), font_size, color)

func _line(a: Vector2, b: Vector2, color: Color = WHITE, width: float = 2.0) -> void:
	draw_line(a,b,color,width,true)

func _pfd() -> void:
	draw_rect(Rect2(0,0,768,768),BACK)
	_text("MANUAL", Vector2(24,40), 25, GREEN)
	_center("FLIGHT DIRECTOR", Vector2(383,40), 22, GREEN)
	_text("LAND" if gear else "CLEAN", Vector2(620,40), 24, GREEN)
	_line(Vector2(20,58),Vector2(748,58),MUTED)
	# Attitude horizon: polygon clipping holds the moving sky inside its window.
	var aperture := Rect2(125,85,482,425)
	var center := Vector2(366,292)
	var shift := rad_to_deg(pitch) * 6.3
	var horizon := center + Vector2(sin(bank),cos(bank)) * shift
	var right := Vector2(cos(bank), -sin(bank))
	var down := Vector2(sin(bank), cos(bank))
	var sky := PackedVector2Array([horizon-right*1500, horizon+right*1500, horizon+right*1500-down*1500, horizon-right*1500-down*1500])
	var earth := PackedVector2Array([horizon-right*1500, horizon+right*1500, horizon+right*1500+down*1500, horizon-right*1500+down*1500])
	var aperture_poly := PackedVector2Array([aperture.position,Vector2(aperture.end.x,aperture.position.y),aperture.end,Vector2(aperture.position.x,aperture.end.y)])
	for polygon: PackedVector2Array in Geometry2D.intersect_polygons(sky,aperture_poly):
		draw_colored_polygon(polygon,Color(0.075,0.34,0.57))
	for polygon: PackedVector2Array in Geometry2D.intersect_polygons(earth,aperture_poly):
		draw_colored_polygon(polygon,Color(0.40,0.25,0.13))
	# Pitch ladder drawn as clipped segments and labels.
	for angle: int in range(-30,31,5):
		var point: Vector2 = horizon - down * float(angle) * 6.3
		var half: float = 72.0 if angle % 10 == 0 else 35.0
		if angle == 0: half = 245.0
		var a: Vector2 = point-right*half
		var b: Vector2 = point+right*half
		if aperture.has_point(a) and aperture.has_point(b):
			_line(a,b,WHITE,2.7 if angle == 0 else 1.8)
			if angle != 0 and angle % 10 == 0:
				_text(str(absi(angle)),a-Vector2(35,-8),20)
	# Fixed aircraft reference and roll scale.
	_line(center+Vector2(-111,0),center+Vector2(-40,0),AMBER,6)
	_line(center+Vector2(40,0),center+Vector2(111,0),AMBER,6)
	_line(center+Vector2(-40,0),center+Vector2(-40,13),AMBER,6)
	_line(center+Vector2(40,0),center+Vector2(40,13),AMBER,6)
	draw_circle(center,5,AMBER)
	for degrees: int in [-60,-45,-30,-20,-10,0,10,20,30,45,60]:
		var angle: float = deg_to_rad(float(degrees)-90.0)
		var unit := Vector2(cos(angle),sin(angle))
		_line(center+unit*177,center+unit*(194 if degrees%30==0 else 185),WHITE,2)
	var bank_unit := Vector2(sin(-bank),-cos(bank))
	var bank_point: Vector2 = center+bank_unit*170
	draw_colored_polygon(PackedVector2Array([bank_point, bank_point+Vector2(-9,16).rotated(-bank),bank_point+Vector2(9,16).rotated(-bank)]),AMBER)
	# Speed and altitude tapes.
	_tape(Rect2(13,86,107,425),cas,20,50,"IAS",false)
	_tape(Rect2(615,86,136,425),altitude,200,50,"ALT",true)
	_text("KT",Vector2(28,545),21,CYAN)
	_text("FT",Vector2(696,545),21,CYAN)
	_center("%03d°" % roundi(display_heading()),Vector2(369,557),41,CYAN)
	_center("HEADING",Vector2(369,587),17,MUTED)
	# Horizontal heading strip follows the live compass.
	draw_rect(Rect2(120,605,500,71), Color(0.045,0.065,0.085))
	for offset: int in range(-40,41,10):
		var absolute: float = floorf(display_heading()/10.0)*10.0 + offset
		var x: float = 369 + wrapf(absolute-display_heading(),-180,180)*5.5
		if x > 130 and x < 609:
			_line(Vector2(x,607),Vector2(x,620),WHITE)
			_center("%02d" % (roundi(fposmod(absolute,360))/10),Vector2(x,647),21)
	draw_colored_polygon(PackedVector2Array([Vector2(369,605),Vector2(359,592),Vector2(379,592)]),AMBER)
	_line(Vector2(20,692),Vector2(748,692),MUTED)
	_text("VS  %+05d" % (roundi(climb/10.0)*10),Vector2(24,733),29,CYAN)
	_text("FPM",Vector2(242,733),19,MUTED)
	_text("STALL" if stall else ("AIRBORNE" if airborne else "GROUND"),Vector2(531,733),24,AMBER if stall else GREEN)

func _tape(rect: Rect2, value: float, step: float, spacing: float, caption: String, alt: bool) -> void:
	draw_rect(rect,Color(0.045,0.065,0.08))
	var mid: float = rect.position.y+rect.size.y*0.49
	for i: int in range(-6,7):
		var tick: float = (floorf(value/step)+i)*step
		var y: float = mid-(tick-value)/step*spacing
		if y > rect.position.y+30 and y < rect.end.y-10 and tick >= 0:
			_line(Vector2(rect.end.x-14,y),Vector2(rect.end.x-1,y),WHITE,2)
			_text(str(roundi(tick)),Vector2(rect.position.x+6,y+7),21)
	draw_rect(Rect2(rect.position.x-1,mid-24,rect.size.x+2,48),Color(0.008,0.012,0.015))
	draw_rect(Rect2(rect.position.x-1,mid-24,rect.size.x+2,48),WHITE,false,2)
	_center("%05d" % roundi(value) if alt else "%03d" % roundi(value),Vector2(rect.get_center().x,mid+12),37)
	_center(caption,Vector2(rect.get_center().x,rect.position.y+23),18,CYAN)

func _nav() -> void:
	draw_rect(Rect2(0,0,768,768),BACK)
	var map_scale: float = 0.015 if navigation_kind == "free" else 0.039
	_text("MAP",Vector2(24,40),27,GREEN)
	_center("%03d°  TRK" % roundi(display_heading()),Vector2(382,40),29,WHITE)
	_text("12 NM" if navigation_kind == "free" else "4 NM",Vector2(641,40),24,CYAN)
	_line(Vector2(20,58),Vector2(748,58),MUTED)
	var center := Vector2(384,466)
	for radius: float in [110.0,220.0,330.0]:
		draw_arc(center,radius,PI,TAU,72,Color(0.2,0.29,0.32),1.5,true)
	for angle: int in range(-90,91,10):
		var actual: float = float(angle)-90.0
		var unit := Vector2(cos(deg_to_rad(actual)),sin(deg_to_rad(actual)))
		_line(center+unit*330,center+unit*(312 if angle%30==0 else 321),WHITE)
		if angle%30 == 0:
			_center("%03d" % roundi(fposmod(display_heading()+angle,360.0)),center+unit*288+Vector2(0,7),22)
	# Mission context, rather than position, chooses the active waypoint.
	var last := Vector2.ZERO
	if navigation_kind in ["valley","sf"] and navigation_checkpoint < route_points().size():
		for index: int in route_points().size():
			var diff: Vector3 = route_points()[index]-position_world
			var local := Vector2(diff.x,diff.z).rotated(-deg_to_rad(heading))
			var point: Vector2 = center+local*map_scale
			var color: Color = MAGENTA if index == navigation_checkpoint else MUTED
			if index > 0 and Rect2(26,78,716,577).has_point(last) and Rect2(26,78,716,577).has_point(point):
				_line(last,point,MUTED,2)
			if Rect2(36,86,690,550).has_point(point):
				var diamond := PackedVector2Array([point+Vector2(0,-8),point+Vector2(8,0),point+Vector2(0,8),point+Vector2(-8,0),point+Vector2(0,-8)])
				draw_polyline(diamond,color,3 if index == navigation_checkpoint else 2,true)
				_text("CP%02d" % (index+1),point+Vector2(13,-9),20,color)
			last = point
	# Runway centerlines, in world coordinates.
	for runway_z: float in ([0.0] if navigation_kind=="sf" else [0.0,-15000.0]):
		var diff := Vector2(-position_world.x,runway_z-position_world.z).rotated(-deg_to_rad(heading))
		var r: Vector2 = center+diff*map_scale
		if Rect2(40,90,688,550).has_point(r):
			_line(r+Vector2(0,-1600*map_scale).rotated(-deg_to_rad(heading)),r+Vector2(0,1600*map_scale).rotated(-deg_to_rad(heading)),CYAN,6)
			_text("SFO 28R" if navigation_kind=="sf" else "ALPINE" if runway_z == 0.0 else "NORTH FIELD",r+Vector2(13,3),19,CYAN)
	draw_colored_polygon(PackedVector2Array([center+Vector2(0,-22),center+Vector2(10,17),center,center+Vector2(-10,17)]),WHITE)
	_line(center+Vector2(-24,6),center+Vector2(24,6),WHITE,3)
	_text("GS  %03d KT" % roundi(speed),Vector2(24,614),26,GREEN)
	var checkpoint_active: bool = navigation_kind in ["valley","sf"] and navigation_checkpoint < route_points().size()
	_text(("SF BAY TOUR" if navigation_kind=="sf" else "VALLEY TOUR") if checkpoint_active else ("FREE FLIGHT" if navigation_kind == "free" else "RWY 36"),Vector2(477,614),24,CYAN)
	_line(Vector2(20,650),Vector2(748,650),MUTED)
	var target: Vector3 = navigation_target()
	var distance_nm: float = position_world.distance_to(target)/1852.0
	_text(navigation_target_label(),Vector2(24,700),29,MAGENTA if checkpoint_active else CYAN)
	_text("%.1f NM" % distance_nm,Vector2(174 if checkpoint_active else 311,700),29,WHITE)
	if checkpoint_active:
		_text("TARGET %04d FT" % roundi(target.y*3.28084),Vector2(405,700),24,CYAN)
		_text(("ACTIVE LEG %02d  /  SAN FRANCISCO BAY" if navigation_kind=="sf" else "ACTIVE LEG %02d  /  MOUNTAIN DEPARTURE") % (navigation_checkpoint+1),Vector2(24,746),19,MUTED)
	elif navigation_kind == "free":
		_text("AIRPORT REFERENCE  /  NO CHECKPOINTS",Vector2(24,746),19,MUTED)
	else:
		_text("3° APPROACH",Vector2(528,700),23,CYAN)
		_text("SFO  /  RUNWAY 28R FINAL" if navigation_kind=="sf" else "NORTH FIELD  /  RUNWAY 36 FINAL",Vector2(24,746),19,MUTED)

func _engines() -> void:
	draw_rect(Rect2(0,0,768,768),BACK)
	_text(aircraft_name,Vector2(24,40),26,CYAN)
	_text("ENGINE / AIRFRAME",Vector2(397,40),23,GREEN)
	_line(Vector2(20,58),Vector2(748,58),MUTED)
	_center("N1  /  FAN SPEED",Vector2(384,103),22,WHITE)
	for i: int in engine_count:
		var center := Vector2(384.0 + (float(i)-float(engine_count-1)*0.5)*170,211)
		var value: float = 22.0 + engine*77.4
		draw_arc(center,65,deg_to_rad(140),deg_to_rad(400),48,Color(0.14,0.21,0.23),9,true)
		draw_arc(center,65,deg_to_rad(140),deg_to_rad(140+value*2.6),48,GREEN,6,true)
		var angle: float = deg_to_rad(140+value*2.6)
		_line(center,center+Vector2(cos(angle),sin(angle))*54,WHITE,3)
		_center("%.1f" % value,center+Vector2(0,36),38)
		_center("ENG %d" % (i+1),center+Vector2(0,90),21,MUTED)
	_center("EGT",Vector2(384,361),21,MUTED)
	for i: int in engine_count:
		var x: float = 384.0+(float(i)-float(engine_count-1)*0.5)*170
		_center("%03d" % roundi(320+engine*480),Vector2(x,405),31,GREEN)
	_line(Vector2(24,437),Vector2(744,437),MUTED)
	_text("THRUST",Vector2(27,489),24,MUTED)
	_text("%03d %%" % roundi(throttle*100),Vector2(578,489),29,CYAN)
	draw_rect(Rect2(28,510,710,12),Color(0.1,0.16,0.19))
	draw_rect(Rect2(28,510,710*throttle,12),CYAN)
	_text("LANDING GEAR",Vector2(27,585),24,WHITE)
	for i: int in 3:
		draw_circle(Vector2(552+i*72,577),13,GREEN if gear else Color(0.11,0.17,0.2))
	_text("DOWN SELECTED" if gear else "UP SELECTED",Vector2(27,625),23,GREEN if gear else CYAN)
	_line(Vector2(24,650),Vector2(744,650),MUTED)
	_text("FLIGHT TIME",Vector2(27,695),21,MUTED)
	_text("%02d:%02d" % [int(elapsed)/60,int(elapsed)%60],Vector2(564,698),29,CYAN)
	_text("FLAPS",Vector2(27,744),21,MUTED)
	_text(["UP", "15°", "30°"][clampi(flaps,0,2)],Vector2(188,744),23,GREEN)
	_text("NORMAL",Vector2(591,744),23,GREEN)


# --- panoramic display ------------------------------------------------------
func _p(face: Font,at: Vector2,value: String,size_px: int,color: Color,align: int=HORIZONTAL_ALIGNMENT_LEFT,width: float=-1) -> void:
	draw_string(face,at,value,align,width,size_px,color)
func _chip(at: Vector2,on: bool) -> void:
	var rect := Rect2(at,Vector2(108 if on else 124,56))
	if on:
		draw_rect(rect,P_GREEN); _p(heavy,at+Vector2(20,44),"ON",46,P_BACK)
	else:
		draw_rect(rect,P_GREEN*Color(1,1,1,0.6),false,2); _p(heavy,at+Vector2(20,44),"OFF",46,P_SOFT)
func _portal(rect: Rect2,title: String) -> void:
	draw_rect(rect,P_LINE,false,2)
	_p(label_font,rect.position+Vector2(16,32),title,22,P_GREEN)
func _panorama() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),P_BACK)
	# Top strip: aircraft, what to do, time.
	_p(heavy,Vector2(24,44),"SPECTRE",38,P_WHITE)
	_p(label_font,Vector2(0,40),str(tactical.get("objective","")).to_upper(),24,P_GREEN,HORIZONTAL_ALIGNMENT_CENTER,size.x)
	_p(numerals,Vector2(size.x-324,46),str(tactical.get("clock","")),44,P_WHITE,HORIZONTAL_ALIGNMENT_RIGHT,300)
	draw_line(Vector2(0,62),Vector2(size.x,62),P_LINE,2)
	var top := 78.0; var tall: float = size.y-top-16
	# Weapons and airframe.
	var a := Rect2(16,top,380,tall); _portal(a,"WEAPONS")
	_p(label_font,a.position+Vector2(16,104),"PRIMARY",28,P_WHITE); _chip(a.position+Vector2(232,62),bool(tactical.get("gun",false)))
	_p(label_font,a.position+Vector2(16,184),"MISSILE",24,P_WHITE)
	_p(label_font,a.position+Vector2(210,184),"READY" if bool(tactical.get("missile_ready",false)) else "%.1fs" % float(tactical.get("missile_cooldown",0)),20,P_GREEN)
	var lock: float = float(tactical.get("lock",0.0)); var tracking: bool = bool(tactical.get("tracking",false))
	var lock_rect := Rect2(a.position+Vector2(16,226),Vector2(348,78))
	if tracking and lock>=1.0:
		draw_rect(lock_rect,P_RED); _p(heavy,lock_rect.position+Vector2(0,60),"LOCKED",60,P_BACK,HORIZONTAL_ALIGNMENT_CENTER,348)
	elif tracking:
		draw_rect(lock_rect,P_AMBER,false,3); draw_rect(Rect2(lock_rect.position,Vector2(348*lock,78)),P_AMBER*Color(1,1,1,0.35))
		_p(heavy,lock_rect.position+Vector2(0,60),"LOCKING",60,P_AMBER,HORIZONTAL_ALIGNMENT_CENTER,348)
	else:
		draw_rect(lock_rect,P_LINE,false,2); _p(heavy,lock_rect.position+Vector2(0,60),"NO TARGET",60,P_SOFT,HORIZONTAL_ALIGNMENT_CENTER,348)
	_p(label_font,a.position+Vector2(16,360),"GEAR",24,P_SOFT); _p(heavy,a.position+Vector2(16,410),"DOWN" if gear else "UP",48,P_AMBER if gear else P_WHITE)
	_p(label_font,a.position+Vector2(200,360),"FLAPS",24,P_SOFT); _p(heavy,a.position+Vector2(200,410),str(flaps),48,P_AMBER if flaps>0 else P_WHITE)
	if stall: _p(heavy,a.position+Vector2(16,480),"NOSE HIGH",54,P_RED)
	elif bool(tactical.get("damaged",false)): _p(heavy,a.position+Vector2(16,480),"DAMAGED",54,P_AMBER)
	# Horizon.
	var b := Rect2(412,top,440,tall); _attitude(b)
	# Radar.
	var c := Rect2(868,top,410,tall); _portal(c,"RADAR 3 KM")
	var hub: Vector2 = c.position+Vector2(c.size.x/2,c.size.y/2+18); var reach: float = minf(c.size.x,c.size.y)/2-34
	for fraction in [0.33,0.66,1.0]: draw_arc(hub,reach*fraction,0,TAU,72,P_GREEN*Color(1,1,1,0.35 if fraction<1 else 0.9),2,true)
	draw_line(hub-Vector2(reach,0),hub+Vector2(reach,0),P_GREEN*Color(1,1,1,0.25),1); draw_line(hub-Vector2(0,reach),hub+Vector2(0,reach),P_GREEN*Color(1,1,1,0.25),1)
	var waypoint: Vector2 = tactical.get("waypoint",Vector2.ZERO)
	if waypoint!=Vector2.ZERO:
		var w: Vector2 = hub+(waypoint/3000.0*reach).limit_length(reach)
		draw_polyline(PackedVector2Array([w+Vector2(0,-10),w+Vector2(10,0),w+Vector2(0,10),w+Vector2(-10,0),w+Vector2(0,-10)]),P_GREEN,3,true)
	for contact: Vector3 in tactical.get("contacts",[]):
		var at: Vector2 = hub+(Vector2(contact.x,contact.y)/3000.0*reach).limit_length(reach)
		if contact.z>0.5: draw_colored_polygon(PackedVector2Array([at+Vector2(0,-11),at+Vector2(11,0),at+Vector2(0,11),at+Vector2(-11,0)]),P_RED)
		else: draw_circle(at,6,P_RED)
	draw_colored_polygon(PackedVector2Array([hub+Vector2(0,-13),hub+Vector2(-10,11),hub+Vector2(10,11)]),P_GREEN)
	# The objective: one amber pip per bird in the skein. HOOK: scenes/main.gd
	# tactical_state() must publish "skein" as Vector2(birds down, skein size).
	var skein: Vector2 = tactical.get("skein",Vector2(-1,-1))
	if skein.y>0.0:
		_p(label_font,c.position+Vector2(c.size.x-216,32),"GEESE %d / %d" % [int(skein.x),int(skein.y)],22,P_AMBER,HORIZONTAL_ALIGNMENT_RIGHT,200)
		var pips: int = clampi(int(skein.y),1,26)
		var span: float = c.size.x-32.0
		var pip: float = (span-float(pips-1)*3.0)/float(pips)
		for index in range(pips):
			var spot: Vector2 = c.position+Vector2(16.0+float(index)*(pip+3.0),c.size.y-30)
			draw_rect(Rect2(spot,Vector2(pip,12)),P_AMBER if index<int(skein.x) else P_AMBER*Color(1,1,1,0.18))
	# Flight numbers.
	var d := Rect2(1294,top,size.x-1294-16,tall); _portal(d,"FLIGHT")
	_p(label_font,d.position+Vector2(16,92),"SPEED · KNOTS",22,P_SOFT); _p(numerals,d.position+Vector2(12,186),"%d" % int(cas),104,P_WHITE)
	_p(label_font,d.position+Vector2(16,240),"ALTITUDE · FEET",22,P_SOFT); _p(numerals,d.position+Vector2(12,334),_thousands(int(altitude)),104,P_WHITE)
	_p(label_font,d.position+Vector2(16,388),"HEADING",22,P_SOFT); _p(numerals,d.position+Vector2(12,452),"%03d" % int(display_heading()),64,P_WHITE)
	_p(label_font,d.position+Vector2(170,388),"POWER",22,P_SOFT); _p(numerals,d.position+Vector2(166,452),"%d%%" % int(throttle*100),64,P_GREEN)
	_p(numerals,d.position+Vector2(12,500),"G %+.1f" % g_load,40,P_RED if absf(g_load)>=6.8 else P_AMBER if absf(g_load)>=5.0 else P_WHITE)
	_p(numerals,d.position+Vector2(170,500),"M %.2f" % mach,40,P_WHITE)
	draw_rect(Rect2(d.position+Vector2(16,tall-44),Vector2(d.size.x-32,14)),P_GREEN*Color(1,1,1,0.2)); draw_rect(Rect2(d.position+Vector2(16,tall-44),Vector2((d.size.x-32)*clampf(throttle,0,1),14)),P_GREEN)
func _thousands(value: int) -> String:
	var digits: String = str(absi(value)); var out := ""
	for i in range(digits.length()):
		if i>0 and (digits.length()-i)%3==0: out += ","
		out += digits[i]
	return out
func _attitude(rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	var scale_px := 9.0
	var horizon: Vector2 = center+Vector2(sin(bank),cos(bank))*rad_to_deg(pitch)*scale_px
	var right := Vector2(cos(bank),-sin(bank)); var down := Vector2(sin(bank),cos(bank))
	var window := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	var sky := PackedVector2Array([horizon-right*2000,horizon+right*2000,horizon+right*2000-down*2000,horizon-right*2000-down*2000])
	var earth := PackedVector2Array([horizon-right*2000,horizon+right*2000,horizon+right*2000+down*2000,horizon-right*2000+down*2000])
	for polygon: PackedVector2Array in Geometry2D.intersect_polygons(sky,window): draw_colored_polygon(polygon,Color(0.12,0.33,0.52))
	for polygon: PackedVector2Array in Geometry2D.intersect_polygons(earth,window): draw_colored_polygon(polygon,Color(0.34,0.23,0.12))
	for angle: int in range(-40,41,10):
		var point: Vector2 = horizon-down*float(angle)*scale_px
		var half: float = 600.0 if angle==0 else 70.0
		for segment: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([point-right*half,point+right*half]),window):
			draw_polyline(segment,P_WHITE,4 if angle==0 else 2,true)
		if angle!=0 and rect.grow(-40).has_point(point-right*96): _p(label_font,point-right*96+Vector2(-14,8),str(absi(angle)),20,P_WHITE)
	# Fixed aircraft symbol and frame.
	draw_polyline(PackedVector2Array([center+Vector2(-120,0),center+Vector2(-44,0),center+Vector2(0,30),center+Vector2(44,0),center+Vector2(120,0)]),P_AMBER,7,true)
	draw_rect(rect,P_LINE,false,2)
	draw_rect(Rect2(rect.position,Vector2(rect.size.x,44)),Color(P_BACK.r,P_BACK.g,P_BACK.b,0.55))
	_p(label_font,rect.position+Vector2(16,32),"HORIZON",22,P_GREEN)
	_p(label_font,rect.position+Vector2(rect.size.x-216,32),"CLIMB %+d" % (int(climb/100.0)*100),22,P_WHITE,HORIZONTAL_ALIGNMENT_RIGHT,200)
