extends SceneTree

# Godot --headless --path simulator --script ../tools/test_vision_client.gd
# Starts only --simulate; this integration check never opens a camera.
const Client = preload("res://systems/vision_client.gd")
var client = Client.new()
var child: int = -1
var stage: int = 0
var begun: int = 0
var observed_sequence: int = -1
var held_throttle: float = -1.0
var failure := false
var test_port := 0

func _initialize() -> void:
	if not _validation_tests():
		return
	client = Client.new()
	var probe := TCPServer.new()
	if probe.listen(0,"127.0.0.1")!=OK:
		_fail("Cannot reserve local integration-test port")
		return
	test_port=probe.get_local_port()
	probe.stop()
	client.endpoint="ws://127.0.0.1:"+str(test_port)
	client.enabled = true
	begun = Time.get_ticks_msec()
	_start_tracker(2.0)
	# Give the subprocess a moment to bind before the normal reconnect timer.
	client.retry_at = begun + 350

func _valid(sequence_number: int = 1) -> Dictionary:
	return {"version": 1, "sequence": sequence_number, "timestamp": 1789737600123,
		"tracking": true, "yoke": {"roll": 0.5, "pitch": -0.2, "confidence": 0.95},
		"throttle": {"value": 0.72, "confidence": 0.98}}

func _fail(message: String) -> void:
	failure = true
	push_error("VISION TEST FAILED: " + message)
	if child > 0 and OS.is_process_running(child):
		OS.kill(child)
	quit(1)

func _validation_tests() -> bool:
	var good: Dictionary = _valid()
	if not client._accept_packet(JSON.stringify(good).to_utf8_buffer(), 100):
		_fail("Valid packet rejected")
		return false
	var invalid: Array = [{}, [], "hello", 1, false]
	for field: String in ["version", "sequence", "timestamp", "tracking", "yoke", "throttle"]:
		var missing: Dictionary = _valid(2)
		missing.erase(field)
		invalid.append(missing)
	for malformed: Variant in ["2", {}, [], true, null, -1, 2.5, 1e99]:
		var packet: Dictionary = _valid(2)
		packet.sequence = malformed
		invalid.append(packet)
	for field: String in ["roll", "pitch", "confidence"]:
		for malformed: Variant in ["0.5", [], {}, true, null, 1.01, -1.01]:
			var packet: Dictionary = _valid(2)
			packet.yoke[field] = malformed
			invalid.append(packet)
	for field: String in ["value", "confidence"]:
		for malformed: Variant in ["0.5", [], {}, false, null, -0.01, 1.01]:
			var packet: Dictionary = _valid(2)
			packet.throttle[field] = malformed
			invalid.append(packet)
	invalid.append(_valid(0))
	invalid.append(good)
	var wrong_version: Dictionary = _valid(2)
	wrong_version.version = 2
	invalid.append(wrong_version)
	var wrong_tracking: Dictionary = _valid(2)
	wrong_tracking.tracking = "true"
	invalid.append(wrong_tracking)
	for malformed: Variant in [null, [], "true", 1]:
		var packet: Dictionary = _valid(2)
		packet.yoke_enabled = malformed
		invalid.append(packet)
	for malformed: Variant in [null, [], true, "fire", {}, {"gun": 1}, {"gun": "true"}]:
		var packet: Dictionary = _valid(2)
		packet.weapons = malformed
		invalid.append(packet)
	for bad: Variant in invalid:
		if client._accept_packet(JSON.stringify(bad).to_utf8_buffer(), 900):
			_fail("Malformed packet accepted: " + JSON.stringify(bad))
			return false
		if client.sequence != 1 or client.last_received != 100 or client.yoke != Vector2(0.5, -0.2):
			_fail("Rejected packet changed controls or refreshed timeout")
			return false
	for text: String in ["{", "null", " ".repeat(2049), '{"version":1,"sequence":2,"timestamp":1,"tracking":true,"yoke":{"roll":1e999,"pitch":0,"confidence":1},"throttle":{"value":0,"confidence":1}}']:
		if client._accept_packet(text.to_utf8_buffer(), 900):
			_fail("Invalid raw JSON accepted")
			return false
	var independent: Dictionary = _valid(2)
	independent.tracking = false
	independent.yoke.confidence = 0.0
	independent.yoke_enabled = false
	if not client._accept_packet(JSON.stringify(independent).to_utf8_buffer(), 200) or client.throttle_confidence < 0.9:
		_fail("Independent throttle rejected when yoke lost")
		return false
	assert(not client.yoke_enabled, "Explicit throttle-only mode does not require a yoke")
	var firing: Dictionary = _valid(3)
	firing.tracking = false
	firing.yoke.confidence = 0
	firing.weapons = {"gun": true}
	assert(client._accept_packet(JSON.stringify(firing).to_utf8_buffer(), 300))
	assert(client.gun_trigger, "Gun tag is independent of yoke visibility")
	client.enabled = true; client.connected = true
	client._expire_weapons(449)
	assert(client.gun_trigger)
	client._expire_weapons(450)
	assert(not client.gun_trigger, "Fire expires after 150 ms")
	firing.sequence = 4
	assert(client._accept_packet(JSON.stringify(firing).to_utf8_buffer(), 500))
	client.connected = false; client._expire_weapons(501)
	assert(not client.gun_trigger, "Disconnect stops fire immediately")
	firing.sequence = 5
	assert(client._accept_packet(JSON.stringify(firing).to_utf8_buffer(), 600))
	assert(client._accept_packet(JSON.stringify(_valid(6)).to_utf8_buffer(), 601))
	assert(not client.gun_trigger, "Legacy packet releases the trigger")
	firing.sequence = 7
	assert(client._accept_packet(JSON.stringify(firing).to_utf8_buffer(), 700))
	client.enabled = false
	assert(not client.gun_trigger, "Keyboard takeover releases fire")
	print("VISION VALIDATION PASS: %d malformed packets rejected without state mutation" % (invalid.size() + 4))
	return true

func _start_tracker(duration: float) -> void:
	var root: String = ProjectSettings.globalize_path("res://..").simplify_path()
	var interpreter: String = root.path_join(".venv/bin/python")
	if not FileAccess.file_exists(interpreter):
		_fail("Install vision/requirements.txt in .venv before integration test")
		return
	child = OS.create_process(interpreter, PackedStringArray([root.path_join("vision/tracker.py"), "--simulate", "--port",str(test_port), "--duration", str(duration)]))
	if child <= 0:
		_fail("Could not start simulated tracker")

func _process(delta: float) -> bool:
	if failure:
		return false
	client.poll(delta)
	var elapsed: int = Time.get_ticks_msec() - begun
	if elapsed > 13000:
		_fail("Connection/reconnection timed out at stage %d" % stage)
		return false
	if stage == 0 and client.tracking and client.sequence > 15:
		observed_sequence = client.sequence
		if client.yoke.length() < 0.01 or client.throttle <= 0.1:
			_fail("Connected but controls did not move")
			return false
		stage = 1
		print("VISION INTEGRATION: received controls at sequence %d" % observed_sequence)
	elif stage == 1 and elapsed > 2400 and not client.connected:
		if held_throttle < 0.0:
			held_throttle = client.throttle
		if client.yoke.length() < 0.002 and client.yoke_confidence == 0.0 and client.throttle_confidence == 0.0:
			if not is_equal_approx(client.throttle, held_throttle):
				_fail("Throttle changed during disconnect")
				return false
			print("VISION INTEGRATION: stale yoke neutralized; throttle held")
			stage = 2
			_start_tracker(8.0)
	elif stage == 2 and client.tracking:
		print("VISION INTEGRATION PASS: reconnected to restarted service, sequence %d" % client.sequence)
		client.enabled = false
		if client.tracking or client.throttle_confidence > 0 or client.yoke != Vector2.ZERO:
			_fail("Keyboard takeover retained live vision state")
			return false
		if child > 0 and OS.is_process_running(child):
			OS.kill(child)
		quit(0)
	return false
