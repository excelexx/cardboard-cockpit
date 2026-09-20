extends RefCounted

# A fresh request on each Play/Retry. Only matching, recent tracker results count.
var socket := WebSocketPeer.new()
var active := false
var request_id := ""
var state := "waiting"
var elapsed := 0.0
var reason := "show_yoke"
var last_received := -1
var retry_at := 0
var sent := false

func start() -> void:
	stop()
	active = true
	request_id = "%s-%s" % [get_instance_id(), Time.get_ticks_usec()]

func stop() -> void:
	socket.close()
	socket = WebSocketPeer.new()
	active = false; sent = false; retry_at = 0
	state = "waiting"; elapsed = 0; last_received = -1

func fresh(now: int) -> bool:
	return active and last_received >= 0 and now-last_received < 150

func poll(endpoint: String, now: int) -> void:
	if not active: return
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		state = "waiting"; elapsed = 0; last_received = -1; sent = false
		if now >= retry_at:
			socket = WebSocketPeer.new()
			socket.inbound_buffer_size = 4096; socket.max_queued_packets = 8
			socket.connect_to_url(endpoint.trim_suffix("/")+"/calibration")
			retry_at = now+1000
	socket.poll()
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return
	if not sent:
		socket.send_text(JSON.stringify({"action": "start", "request_id": request_id}))
		sent = true
	while socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		if socket.was_string_packet(): accept_packet(packet, now)

func accept_packet(packet: PackedByteArray, now: int) -> bool:
	if not active or packet.is_empty() or packet.size() > 1024: return false
	var data: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if not data is Dictionary or data.get("request_id") != request_id: return false
	if data.get("state") not in ["waiting", "holding", "complete", "unavailable"]: return false
	var seconds: Variant = data.get("elapsed")
	if not (seconds is float or seconds is int) or not is_finite(float(seconds)) or seconds < 0 or seconds > 3: return false
	if data.state == "complete" and seconds != 3: return false
	if data.get("reason") not in ["show_yoke", "hold_still"]: return false
	state = data.state; elapsed = float(seconds); reason = data.reason; last_received = now
	return true
