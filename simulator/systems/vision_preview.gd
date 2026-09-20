extends RefCounted

# This optional second socket carries only local camera JPEGs, never controls.
const MAX_FRAME_BYTES := 512 * 1024
const STALE_AFTER_MS := 700
var socket := WebSocketPeer.new()
var texture: ImageTexture
var last_received := -1
var retry_at := 0
var active := false
var endpoint := ""

func stop() -> void:
	if active:
		socket.close()
		socket = WebSocketPeer.new()
	active = false
	texture = null
	last_received = -1
	retry_at = 0

func poll(wanted: bool, control_endpoint: String, focus: String = "") -> void:
	var desired := control_endpoint.trim_suffix("/") + "/preview"
	if focus in ["throttle", "yoke", "weapons", "all"]: desired += "/" + focus
	if not wanted or desired != endpoint:
		stop()
		endpoint = desired
	if not wanted: return
	active = true
	var now := Time.get_ticks_msec()
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED and now >= retry_at:
		socket = WebSocketPeer.new()
		socket.inbound_buffer_size = MAX_FRAME_BYTES * 2
		socket.max_queued_packets = 2
		socket.connect_to_url(endpoint)
		retry_at = now + 1000
	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var latest := PackedByteArray()
		var received := false
		while socket.get_available_packet_count() > 0:
			var data := socket.get_packet()
			if not socket.was_string_packet():
				# A missing frame cannot discard a good image in the same batch.
				if not data.is_empty(): latest = data
				received = true
		if received: _accept_frame(latest, now)
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		texture = null
	_expire_frame(now)

func _expire_frame(now: int) -> void:
	if last_received < 0 or now-last_received >= STALE_AFTER_MS:
		texture = null

func _accept_frame(data: PackedByteArray, now: int) -> bool:
	if data.is_empty():
		# Keep the last image across a brief phone hiccup. Empty packets never
		# refresh its age, so a genuinely lost feed still clears after 700 ms.
		_expire_frame(now)
		return true
	if data.size() > MAX_FRAME_BYTES: return false
	var frame := Image.new()
	if frame.load_jpg_from_buffer(data) != OK or frame.get_width() > 960 or frame.get_height() > 540:
		return false
	if texture == null or texture.get_size() != Vector2(frame.get_size()):
		texture = ImageTexture.create_from_image(frame)
	else:
		texture.update(frame)
	last_received = now
	return true
