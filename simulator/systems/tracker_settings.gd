extends RefCounted

# Coalesce slider drags, acknowledge exact values, and resend after reconnect.
var socket := WebSocketPeer.new()
var applied: Dictionary = {}
var pending: Dictionary = {}
var request_id := ""
var sent_at := -1
var retry_at := 0

func synced(gains: Dictionary) -> bool:
	return socket.get_ready_state() == WebSocketPeer.STATE_OPEN and applied == gains

func poll(endpoint: String, now: int, gains: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		applied = {}; pending = {}; request_id = ""; sent_at = -1
		if now >= retry_at:
			socket = WebSocketPeer.new()
			socket.inbound_buffer_size = 4096; socket.max_queued_packets = 8
			socket.connect_to_url(endpoint.trim_suffix("/")+"/settings")
			retry_at = now+1000
	socket.poll()
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return
	while socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		if not socket.was_string_packet() or packet.size()>1024: continue
		var ack: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if ack is Dictionary and ack.get("request_id") == request_id and ack.get("sensitivity") == pending:
			applied = pending.duplicate(); pending = {}; request_id = ""; sent_at = -1
	if sent_at >= 0:
		if now-sent_at > 2000: socket.close()
		return
	if applied != gains:
		pending = gains.duplicate()
		request_id = "%s-%s" % [get_instance_id(),Time.get_ticks_usec()]
		if socket.send_text(JSON.stringify({"action":"set_sensitivity","request_id":request_id,"sensitivity":pending})) == OK:
			sent_at = now
