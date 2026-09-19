extends RefCounted
## Independent, local JPEG stream; preview traffic never enters flight controls.

const MAX_BYTES := 65536
const STALE_MS := 1000
var socket := WebSocketPeer.new()
var texture: ImageTexture
var last_received := -1
var retry_at := 0
var active_endpoint := ""

func close() -> void:
	socket.close()
	socket = WebSocketPeer.new()
	texture = null
	last_received = -1
	retry_at = 0
	active_endpoint = ""

func poll(enabled: bool, endpoint: String) -> void:
	if not enabled:
		if not active_endpoint.is_empty(): close()
		return
	var url := endpoint.trim_suffix("/") + "/preview"
	if active_endpoint != url:
		close()
		active_endpoint = url
	var now := Time.get_ticks_msec()
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		texture = null
		last_received = -1
		if now >= retry_at:
			socket = WebSocketPeer.new()
			socket.inbound_buffer_size = 262144
			socket.max_queued_packets = 4
			socket.connect_to_url(url)
			retry_at = now + 3000
	socket.poll()
	var latest := PackedByteArray()
	while socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		if not socket.was_string_packet() and packet.size() <= MAX_BYTES:
			latest = packet
	if not latest.is_empty(): accept_frame(latest, now)
	if last_received >= 0 and now - last_received > STALE_MS:
		texture = null
		last_received = -1

func accept_frame(packet: PackedByteArray, now: int) -> bool:
	if packet.size() < 4 or packet.size() > MAX_BYTES:
		return false
	if packet[0] != 255 or packet[1] != 216:
		return false
	var frame := Image.new()
	if frame.load_jpg_from_buffer(packet) != OK:
		return false
	if frame.get_width() > 320 or frame.get_height() > 240:
		return false
	if texture == null or texture.get_size() != Vector2(frame.get_size()):
		texture = ImageTexture.create_from_image(frame)
	else:
		texture.update(frame)
	last_received = now
	return true
