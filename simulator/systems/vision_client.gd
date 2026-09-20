extends RefCounted
class_name VisionClient

const MAX_PACKET_BYTES: int = 2048
const STALE_AFTER_MS: int = 350
const WEAPON_STALE_AFTER_MS: int = 150
const MAX_JSON_INTEGER: float = 9007199254740991.0
const MIN_SENSITIVITY := 0.25
const MAX_SENSITIVITY := 6.0
const DEFAULT_PITCH_SENSITIVITY := 1.2
const DEFAULT_BANK_SENSITIVITY := 1.0
const DEFAULT_YAW_SENSITIVITY := 1.0

var pitch_sensitivity: float = DEFAULT_PITCH_SENSITIVITY:
	set(value): pitch_sensitivity = clampf(value, MIN_SENSITIVITY, MAX_SENSITIVITY) if is_finite(value) else DEFAULT_PITCH_SENSITIVITY
var bank_sensitivity: float = DEFAULT_BANK_SENSITIVITY:
	set(value): bank_sensitivity = clampf(value, MIN_SENSITIVITY, MAX_SENSITIVITY) if is_finite(value) else DEFAULT_BANK_SENSITIVITY
var yaw_sensitivity: float = DEFAULT_YAW_SENSITIVITY:
	set(value): yaw_sensitivity = clampf(value, MIN_SENSITIVITY, MAX_SENSITIVITY) if is_finite(value) else DEFAULT_YAW_SENSITIVITY

var socket := WebSocketPeer.new()
var tracker_settings = preload("res://systems/tracker_settings.gd").new()
var settings_sync_requested := false
var yoke_calibration = preload("res://systems/yoke_calibration.gd").new()
var endpoint := "ws://127.0.0.1:8765"
var connected := false
# Yoke availability for input merging. Throttle confidence is independent.
var tracking := false
var yoke_enabled := true
var yoke := Vector2.ZERO
var yoke_yaw := 0.0
var throttle: float = 0.0
var yoke_confidence: float = 0.0
var throttle_confidence: float = 0.0
var gun_trigger := false
var last_received: int = -1
var retry_at: int = 0
var sequence: int = -1
var status := "KEYBOARD / MOUSE"
var enabled := false:
	set(value):
		if enabled == value:
			return
		enabled = value
		if not value:
			yoke_calibration.stop()
			socket.close()
			socket = WebSocketPeer.new()
			connected = false
			tracking = false
			yoke = Vector2.ZERO
			yoke_yaw = 0.0
			yoke_confidence = 0.0
			throttle_confidence = 0.0
			gun_trigger = false
			last_received = -1
			sequence = -1
			yoke_enabled = true
			status = "KEYBOARD / MOUSE"
		retry_at = 0

func steering() -> Vector3:
	# Apply each gain once, leaving raw movement available for physical tutorial checks.
	return Vector3(clampf(yoke.x*bank_sensitivity,-1,1), clampf(yoke.y*pitch_sensitivity,-1,1), clampf(yoke_yaw*yaw_sensitivity,-1,1))

func reset_sensitivity() -> void:
	pitch_sensitivity = DEFAULT_PITCH_SENSITIVITY
	bank_sensitivity = DEFAULT_BANK_SENSITIVITY
	yaw_sensitivity = DEFAULT_YAW_SENSITIVITY

func load_sensitivity(config: ConfigFile) -> void:
	var pitch: Variant = config.get_value("controls", "yoke_pitch_sensitivity", DEFAULT_PITCH_SENSITIVITY)
	var bank: Variant = config.get_value("controls", "yoke_bank_sensitivity", DEFAULT_BANK_SENSITIVITY)
	var yaw: Variant = config.get_value("controls", "yoke_yaw_sensitivity", DEFAULT_YAW_SENSITIVITY)
	pitch_sensitivity = float(pitch) if _is_number(pitch) else DEFAULT_PITCH_SENSITIVITY
	bank_sensitivity = float(bank) if _is_number(bank) else DEFAULT_BANK_SENSITIVITY
	yaw_sensitivity = float(yaw) if _is_number(yaw) else DEFAULT_YAW_SENSITIVITY

func save_sensitivity(config: ConfigFile) -> void:
	config.set_value("controls", "yoke_pitch_sensitivity", pitch_sensitivity)
	config.set_value("controls", "yoke_bank_sensitivity", bank_sensitivity)
	config.set_value("controls", "yoke_yaw_sensitivity", yaw_sensitivity)

func sensitivity_values() -> Dictionary:
	return {"pitch":pitch_sensitivity,"bank":bank_sensitivity,"yaw":yaw_sensitivity}

func sync_sensitivity() -> void:
	settings_sync_requested = true

func poll(dt: float) -> void:
	if enabled or settings_sync_requested:
		tracker_settings.poll(endpoint, Time.get_ticks_msec(), sensitivity_values())
	if not enabled:
		return
	var now: int = Time.get_ticks_msec()
	yoke_calibration.poll(endpoint, now)
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
			gun_trigger = false
		status = "TRACKER DISCONNECTED · KEYBOARD READY"
	socket.poll()
	connected = socket.get_ready_state() == WebSocketPeer.STATE_OPEN
	if connected:
		while socket.get_available_packet_count() > 0:
			var packet: PackedByteArray = socket.get_packet()
			if socket.was_string_packet():
				_accept_packet(packet, now)
	var fresh: bool = connected and last_received >= 0 and now - last_received < STALE_AFTER_MS
	_expire_weapons(now)
	tracking = fresh and yoke_confidence > 0.4
	if not fresh:
		yoke = yoke.move_toward(Vector2.ZERO, maxf(dt, 0.0) * 1.5)
		yoke_yaw = move_toward(yoke_yaw, 0.0, maxf(dt,0.0)*1.5)
		yoke_confidence = 0.0
		throttle_confidence = 0.0
	if connected:
		status = "YOKE TRACKED" if tracking else "YOKE OUT OF VIEW" if yoke_enabled else "THROTTLE MODE · KEYBOARD STEERING"
		if throttle_confidence>0.4:
			status = "YOKE + THROTTLE TRACKED" if tracking else "YOKE OUT OF VIEW · THROTTLE TRACKED" if yoke_enabled else "THROTTLE TRACKED · KEYBOARD STEERING"

func _expire_weapons(now: int) -> void:
	if not enabled or not connected or last_received < 0 or now-last_received >= WEAPON_STALE_AFTER_MS:
		gun_trigger = false

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
	var yaw: Variant = y.get("yaw",0.0)
	if not _is_number(yaw) or float(yaw) < -1 or float(yaw) > 1: return false
	if not data.get("yoke_enabled", true) is bool:
		return false
	# Version-1 senders without weapon tags remain compatible and cannot fire.
	var weapons: Variant = data.get("weapons", {"gun": false})
	if not weapons is Dictionary or not weapons.get("gun") is bool:
		return false
	var values: Array = [y.get("roll"), y.get("pitch"), y.get("confidence"), t.get("value"), t.get("confidence")]
	for index: int in range(values.size()):
		var value: Variant = values[index]
		if not _is_number(value):
			return false
		var minimum: float = -1.0 if index < 2 else 0.0
		if float(value) < minimum or float(value) > 1.0:
			return false
	# New trackers send both physical and adjusted input. Always derive steering
	# from physical input so gain is applied once, including during a slider drag.
	var raw: Dictionary = y
	if data.has("raw_yoke") or data.has("sensitivity"):
		if not data.get("raw_yoke") is Dictionary or not data.get("sensitivity") is Dictionary: return false
		raw = data.raw_yoke
		for axis: String in ["roll","pitch","yaw"]:
			if not _is_number(raw.get(axis)) or absf(float(raw[axis]))>1: return false
		for axis: String in ["pitch","bank","yaw"]:
			var gain: Variant = data.sensitivity.get(axis)
			if not _is_number(gain) or gain<MIN_SENSITIVITY or gain>MAX_SENSITIVITY: return false
	sequence = seq
	last_received = now
	yoke = Vector2(float(raw.roll), float(raw.pitch))
	yoke_yaw = float(raw.get("yaw",0.0))
	yoke_confidence = float(y.confidence)
	throttle = float(t.value)
	throttle_confidence = float(t.confidence)
	yoke_enabled = data.get("yoke_enabled", true)
	gun_trigger = weapons.gun
	return true
