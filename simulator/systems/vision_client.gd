extends RefCounted
class_name VisionClient

const MAX_PACKET_BYTES: int = 2048
const STALE_AFTER_MS: int = 350
const MAX_JSON_INTEGER: float = 9007199254740991.0

var socket := WebSocketPeer.new()
var endpoint := "ws://127.0.0.1:8765"
var connected := false
# Yoke availability for input merging. Throttle confidence is independent.
var tracking := false
var yoke := Vector2.ZERO
var throttle: float = 0.0
var yoke_confidence: float = 0.0
var throttle_confidence: float = 0.0
var last_received: int = -1
var retry_at: int = 0
var sequence: int = -1
var primary_switch:=false
var salvo_switch:=false
var weapons_revision:=0
var weapons_available:=false
var status := "KEYBOARD / MOUSE"
var enabled := false:
	set(value):
		if enabled == value:
			return
		enabled = value
		if not value:
			socket.close()
			socket = WebSocketPeer.new()
			connected = false
			tracking = false
			yoke = Vector2.ZERO
			yoke_confidence = 0.0
			throttle_confidence = 0.0
			if primary_switch or salvo_switch:weapons_revision+=1
			primary_switch=false;salvo_switch=false
			last_received = -1
			sequence = -1
			status = "KEYBOARD / MOUSE"
		retry_at = 0

func poll(dt: float) -> void:
	if not enabled:
		return
	var now: int = Time.get_ticks_msec()
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		connected = false
		if now >= retry_at:
			socket = WebSocketPeer.new()
			socket.inbound_buffer_size = 8192
			socket.max_queued_packets = 8
			socket.connect_to_url(endpoint)
			retry_at = now + 3000
			# A restarted tracker begins again at zero; a handshake cannot
			# make old confidence or controls valid again by itself.
			sequence = -1
			last_received = -1
			yoke_confidence = 0.0
			throttle_confidence = 0.0
		status = "TRACKER DISCONNECTED · KEYBOARD READY"
	socket.poll()
	connected = socket.get_ready_state() == WebSocketPeer.STATE_OPEN
	if connected:
		while socket.get_available_packet_count() > 0:
			var packet: PackedByteArray = socket.get_packet()
			if socket.was_string_packet():
				_accept_packet(packet, now)
	var fresh: bool = connected and last_received >= 0 and now - last_received < STALE_AFTER_MS
	tracking = fresh and yoke_confidence > 0.4
	if not fresh and weapons_available and (primary_switch or salvo_switch):
		primary_switch=false;salvo_switch=false;weapons_revision+=1
	if not fresh:
		yoke = yoke.move_toward(Vector2.ZERO, maxf(dt, 0.0) * 1.5)
		yoke_confidence = 0.0
		throttle_confidence = 0.0
	if connected:
		status = "YOKE TRACKED" if tracking else "YOKE LOST · KEYBOARD READY"
		if throttle_confidence>0.4:
			status = "YOKE + THROTTLE TRACKED" if tracking else "THROTTLE TRACKED · KEYBOARD STEERING"

func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _is_integer(value: Variant) -> bool:
	return _is_number(value) and float(value) >= 0.0 and float(value) <= MAX_JSON_INTEGER and floorf(float(value)) == float(value)

func _accept_packet(packet: PackedByteArray, now: int) -> bool:
	# Validate every field before mutating state. Bad data must not refresh a
	# timeout, advance sequence, or briefly override the pilot's controls.
	if packet.is_empty() or packet.size() > MAX_PACKET_BYTES:
		return false
	var parser := JSON.new()
	if parser.parse(packet.get_string_from_utf8()) != OK:
		return false
	if not parser.data is Dictionary:
		return false
	var data: Dictionary = parser.data
	if not _is_number(data.get("version")) or float(data.version) != 1.0:
		return false
	if not _is_integer(data.get("sequence")) or not _is_integer(data.get("timestamp")):
		return false
	if not data.get("tracking") is bool or not data.get("yoke") is Dictionary or not data.get("throttle") is Dictionary:
		return false
	var seq: int = int(data.sequence)
	if seq <= sequence:
		return false
	var y: Dictionary = data.yoke
	var t: Dictionary = data.throttle
	var values: Array = [y.get("roll"), y.get("pitch"), y.get("confidence"), t.get("value"), t.get("confidence")]
	for index: int in range(values.size()):
		var value: Variant = values[index]
		if not _is_number(value):
			return false
		var minimum: float = -1.0 if index < 2 else 0.0
		if float(value) < minimum or float(value) > 1.0:
			return false
	if data.has("weapons"):
		if not data.weapons is Dictionary:return false
		var weapons: Dictionary=data.weapons
		for key in ["primary","salvo"]:
			if not weapons.get(key) is bool:return false
			var confidence=weapons.get(key+"_confidence")
			if not _is_number(confidence) or confidence<0 or confidence>1:return false
		var new_primary: bool=weapons.primary and float(weapons.primary_confidence)>.35
		var new_salvo: bool=weapons.salvo and float(weapons.salvo_confidence)>.35
		if not weapons_available or new_primary!=primary_switch or new_salvo!=salvo_switch:weapons_revision+=1
		weapons_available=true;primary_switch=new_primary;salvo_switch=new_salvo
	elif weapons_available and (primary_switch or salvo_switch):
		primary_switch=false;salvo_switch=false;weapons_revision+=1
	sequence = seq
	last_received = now
	yoke = Vector2(float(y.roll), float(y.pitch))
	yoke_confidence = float(y.confidence)
	throttle = float(t.value)
	throttle_confidence = float(t.confidence)
	return true
