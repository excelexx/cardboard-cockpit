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
