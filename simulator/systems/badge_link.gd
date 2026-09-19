extends RefCounted
class_name BadgeLink

# Reports the sortie's flight phase to the HTN badge so its LEDs can follow
# along: a red runway sweep on the ground roll and the arrival, sky blue in
# the air. Fire-and-forget UDP to a local bridge (hardware/badge-controller/
# host/badge_bridge.py), which owns the Bluetooth side.
#
# Nothing here can block or fail the sortie: if the bridge is not running the
# datagrams land nowhere, and the badge reverts to idle on its own.

const HOST := "127.0.0.1"
const PORT := 8770
# The badge times out to idle after 5 s and the bridge after 3 s, so resend
# well inside the tighter of the two.
const HEARTBEAT := 1.0
# Gear down below this height above ground reads as an approach, not cruise.
const APPROACH_AGL := 320.0

var _udp := PacketPeerUDP.new()
var _open := false
var _phase := "idle"
var _since := 0.0
var telemetry_clock:=0.0

func _init() -> void:
	_open = _udp.connect_to_host(HOST, PORT) == OK

func phase_for(app: Node) -> String:
	var flight: Object = app.flight
	if app.mode == "rollout":
		return "landing"
	if app.mode != "flight":
		return "idle"
	if flight.airborne:
		# Only call it an approach once the gear is out and we are low.
		if flight.gear:
			var agl: float = flight.position.y - app.world.ground_height(flight.position.x, flight.position.z)
			if agl < APPROACH_AGL:
				return "landing"
		return "sky"
	# On the ground: before the first liftoff this is the takeoff roll,
	# afterwards it is the landing rollout.
	return "landing" if flight.ever_airborne else "takeoff"

func tick(app: Node, dt: float) -> void:
	if not _open:
		return
	telemetry_clock+=dt
	if telemetry_clock>=.05:
		telemetry_clock=0
		_udp.put_packet(JSON.stringify(instrument_snapshot(app)).to_utf8_buffer())
	var next: String = phase_for(app)
	_since += dt
	if next == _phase and _since < HEARTBEAT:
		return
	_phase = next
	_since = 0.0
	_udp.put_packet(next.to_utf8_buffer())

func close() -> void:
	if _open:
		_udp.put_packet("idle".to_utf8_buffer())
		_udp.close()
		_open = false
	receiver.close(); receiver_open=false;connected=false;mask=0
	if helper_pid>0 and OS.is_process_running(helper_pid):OS.kill(helper_pid)
	helper_pid=-1

# Existing BLE bridge now also returns the calibrated physical mask. It never
# synthesizes global keyboard events: these controls belong only to this game.
var helper_pid := -1
var receiver := PacketPeerUDP.new()
var receiver_open := false
var connected := false
var phase_supported := false
var mask := 0
var pressed := 0
var released := 0
var last_received := -1
var sequence := -1
var session := ""
var awaiting_neutral := true
var status := "BADGE OFFLINE"

func open_inputs(port: int = 8771) -> bool:
	if receiver_open: return true
	receiver_open = receiver.bind(port,"127.0.0.1")==OK
	var helper: String=OS.get_executable_path().get_base_dir().path_join("../Resources/BadgeBridge/BadgeBridge")
	if receiver_open and FileAccess.file_exists(helper):
		helper_pid=OS.create_process(helper,PackedStringArray(["--parent-pid",str(OS.get_process_id())]))
	return receiver_open
func poll() -> void:
	pressed = 0; released = 0
	if receiver_open:
		for _i in range(mini(32,receiver.get_available_packet_count())):
			accept_input(receiver.get_packet(),Time.get_ticks_msec())
	if last_received<0 or Time.get_ticks_msec()-last_received>500:
		released |= mask; mask = 0; connected = false; status = "BADGE OFFLINE"; awaiting_neutral = true
func accept_input(bytes: PackedByteArray,now: int) -> bool:
	if bytes.is_empty() or bytes.size()>512: return false
	var data = JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary or data.get("version")!=1: return false
	if not data.get("connected") is bool or not data.get("phase_supported") is bool or not data.get("session") is String: return false
	if data.session.length()<8 or data.session.length()>64: return false
	for field in ["mask","sequence"]:
		if not (data.get(field) is float or data.get(field) is int) or not is_finite(float(data[field])) or floorf(data[field])!=data[field] or data[field]<0: return false
	var next_mask: int = int(data.mask)
	if next_mask&~0x17f or float(data.sequence)>9007199254740991.0: return false
	if session!=data.session:
		session=data.session;sequence=-1;awaiting_neutral=true;mask=0
	if int(data.sequence)<=sequence: return false
	sequence=int(data.sequence);last_received=now;connected=data.connected;phase_supported=data.phase_supported
	if not connected: next_mask=0;awaiting_neutral=true
	if next_mask==0 and connected: awaiting_neutral=false
	if awaiting_neutral: next_mask=0
	pressed |= next_mask&~mask; released |= mask&~next_mask; mask=next_mask
	status="BADGE CONNECTED" if connected else "BADGE OFFLINE"
	return true
func held(code: int) -> bool: return connected and (mask&(1<<code))!=0
func tapped(code: int) -> bool: return connected and (pressed&(1<<code))!=0

func instrument_snapshot(app: Node) -> Dictionary:
	var f: FlightDynamics=app.flight
	var c: CombatDirector=app.combat
	var mode_value: int=2 if app.mode=="results" else 3 if app.mode=="paused" else 1 if app.mode in ["flight","rollout"] and f.airborne or app.mode=="rollout" else 0
	var flags:=0
	if c.target_id>=0 and c.lock_progress>=1 and c.active:flags|=1
	if c.incoming_distance<2200:flags|=2
	if app.mission.phase in ["aftermath","approach","rollout"] or app.landing_started:flags|=4
	if f.gear:flags|=8
	if f.flaps>0:flags|=16
	if app.copilot:flags|=32
	if app.mode=="results" and app.mission_success:flags|=64
	if c.active and c.gun_firing_time>0:flags|=128
	var right:=Vector3(cos(f.heading),0,sin(f.heading));var forward:=Vector3(sin(f.heading),0,-cos(f.heading))
	var contacts: Array=[]
	if app.mode in ["flight","paused"] and c.active:
		for enemy: Dictionary in c.enemies:
			if enemy.health<=0 or enemy.get("retiring",false):continue
			var delta: Vector3=enemy.position-f.position
			contacts.append({"x":clampf(delta.dot(right),-32767,32767),"y":clampf(delta.dot(forward),-32767,32767),"kind":2 if enemy.kind=="boss" else 1,"selected":1 if enemy.id==c.target_id else 0})
		for shot: Dictionary in c.shots:
			if contacts.size()>=12:break
			if shot.kind not in ["missile","hostile_missile"]:continue
			var delta: Vector3=shot.position-f.position
			contacts.append({"x":clampf(delta.dot(right),-32767,32767),"y":clampf(delta.dot(forward),-32767,32767),"kind":4 if shot.kind=="hostile_missile" else 3,"selected":0})
	var target: Dictionary=c.target()
	return {"kind":"instrument","version":1,"mode":mode_value,"flags":flags,"roll":clampf(rad_to_deg(f.roll),-180,180),"pitch":clampf(rad_to_deg(f.pitch),-90,90),"heading":fposmod(f.get_heading_degrees()+(298 if app.route_id=="sf" else 0),360),"speed":clampf(f.speed*1.94384,0,2000),"altitude":clampf(f.position.y*3.28084,-2000,1000000),"score":maxi(0,c.score),"kills":mini(c.kills,65535),"pilot":app.pilot_number,"name":"PILOT","landing":1 if f.contact=="landed" and f.speed<=.1 else 2 if app.landing_started else 0,"range":clampf(f.position.distance_to(target.position),0,65535) if not target.is_empty() else 0,"contacts":contacts.slice(0,12)}
