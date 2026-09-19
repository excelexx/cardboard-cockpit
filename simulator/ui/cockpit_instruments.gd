extends Control
class_name CockpitInstruments

# Purpose-built training flight displays; these are artistic interpretations.
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
var position_world := Vector3.ZERO
var elapsed: float = 0.0
var instrument_time: float = 0.0
var navigation_kind: String = "valley"
var navigation_checkpoint: int = 0
var font: Font = ThemeDB.fallback_font
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
	var bounded: int = clampi(checkpoint,0,ROUTE.size())
	if navigation_kind == kind and navigation_checkpoint == bounded:
		return
	navigation_kind = kind
	navigation_checkpoint = bounded
	queue_redraw()
	_refresh_texture()

func navigation_target() -> Vector3:
	if navigation_kind == "valley" and navigation_checkpoint < ROUTE.size():
		return ROUTE[navigation_checkpoint]
	return NORTH_FIELD_AIM

func navigation_target_label() -> String:
	if navigation_kind == "valley" and navigation_checkpoint < ROUTE.size():
		return "CP%02d" % (navigation_checkpoint+1)
	return "NORTH FIELD"

func update_flight(flight: FlightDynamics, dt: float) -> void:
	speed = flight.speed * 1.94384
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
		_panel_transform(Vector2(12,12), 0.78)
		_pfd()
		draw_set_transform(Vector2.ZERO)
		# Large, readable essentials instead of three miniaturized avionics pages.
		_text("SPEED / KNOTS",Vector2(680,78),32,CYAN)
		_text("%03d" % int(speed),Vector2(675,215),124,WHITE)
		_text("ALTITUDE / FEET",Vector2(1120,78),32,CYAN)
		_text("%d" % int(altitude),Vector2(1110,215),112,WHITE)
		_text("HEADING",Vector2(680,305),30,MUTED)
		_text("%03d°" % int(heading),Vector2(675,405),82,WHITE)
		_text("THRUST",Vector2(1120,305),30,MUTED)
		_text("%d%%" % int(throttle*100),Vector2(1115,405),82,GREEN)
		_text("GEAR "+("DOWN" if gear else "UP"),Vector2(680,540),34,AMBER if gear else MUTED)
		_text("FLAPS %d" % flaps,Vector2(1120,540),34,MUTED)
		_text("STALL — LOWER NOSE" if stall else "SPECTRE  /  FLIGHT SYSTEM",Vector2(680,615),30,AMBER if stall else CYAN)
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
	_tape(Rect2(13,86,107,425),speed,20,50,"IAS",false)
	_tape(Rect2(615,86,136,425),altitude,200,50,"ALT",true)
	_text("KT",Vector2(28,545),21,CYAN)
	_text("FT",Vector2(696,545),21,CYAN)
	_center("%03d°" % roundi(heading),Vector2(369,557),41,CYAN)
	_center("HEADING",Vector2(369,587),17,MUTED)
	# Horizontal heading strip follows the live compass.
	draw_rect(Rect2(120,605,500,71), Color(0.045,0.065,0.085))
	for offset: int in range(-40,41,10):
		var absolute: float = floorf(heading/10.0)*10.0 + offset
		var x: float = 369 + wrapf(absolute-heading,-180,180)*5.5
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
	_center("%03d°  TRK" % roundi(heading),Vector2(382,40),29,WHITE)
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
			_center("%03d" % roundi(fposmod(heading+angle,360.0)),center+unit*288+Vector2(0,7),22)
	# Mission context, rather than position, chooses the active waypoint.
	var last := Vector2.ZERO
	if navigation_kind == "valley" and navigation_checkpoint < ROUTE.size():
		for index: int in ROUTE.size():
			var diff: Vector3 = ROUTE[index]-position_world
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
	for runway_z: float in [0.0,-15000.0]:
		var diff := Vector2(-position_world.x,runway_z-position_world.z).rotated(-deg_to_rad(heading))
		var r: Vector2 = center+diff*map_scale
		if Rect2(40,90,688,550).has_point(r):
			_line(r+Vector2(0,-1600*map_scale).rotated(-deg_to_rad(heading)),r+Vector2(0,1600*map_scale).rotated(-deg_to_rad(heading)),CYAN,6)
			_text("ALPINE" if runway_z == 0.0 else "NORTH FIELD",r+Vector2(13,3),19,CYAN)
	draw_colored_polygon(PackedVector2Array([center+Vector2(0,-22),center+Vector2(10,17),center,center+Vector2(-10,17)]),WHITE)
	_line(center+Vector2(-24,6),center+Vector2(24,6),WHITE,3)
	_text("GS  %03d KT" % roundi(speed),Vector2(24,614),26,GREEN)
	var checkpoint_active: bool = navigation_kind == "valley" and navigation_checkpoint < ROUTE.size()
	_text("VALLEY TOUR" if checkpoint_active else ("FREE FLIGHT" if navigation_kind == "free" else "RWY 36"),Vector2(477,614),24,CYAN)
	_line(Vector2(20,650),Vector2(748,650),MUTED)
	var target: Vector3 = navigation_target()
	var distance_nm: float = position_world.distance_to(target)/1852.0
	_text(navigation_target_label(),Vector2(24,700),29,MAGENTA if checkpoint_active else CYAN)
	_text("%.1f NM" % distance_nm,Vector2(174 if checkpoint_active else 311,700),29,WHITE)
	if checkpoint_active:
		_text("TARGET %04d FT" % roundi(target.y*3.28084),Vector2(405,700),24,CYAN)
		_text("ACTIVE LEG %02d  /  MOUNTAIN DEPARTURE" % (navigation_checkpoint+1),Vector2(24,746),19,MUTED)
	elif navigation_kind == "free":
		_text("AIRPORT REFERENCE  /  NO CHECKPOINTS",Vector2(24,746),19,MUTED)
	else:
		_text("3° APPROACH",Vector2(528,700),23,CYAN)
		_text("NORTH FIELD  /  RUNWAY 36 FINAL",Vector2(24,746),19,MUTED)

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
