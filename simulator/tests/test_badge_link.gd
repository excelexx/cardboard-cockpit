extends SceneTree
const Badge=preload("res://systems/badge_link.gd")
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);push_error(label)
func packet(sequence: int,mask: int,connected: bool=true,session: String="test-session") -> PackedByteArray:
	return JSON.stringify({"version":1,"session":session,"sequence":sequence,"mask":mask,"connected":connected,"phase_supported":true}).to_utf8_buffer()
func _initialize() -> void:
	var b=Badge.new()
	check(b.accept_input(packet(1,1),100) and b.mask==0,"Reconnect requires neutral before actions")
	check(b.accept_input(packet(2,0),110),"Neutral handshake")
	check(b.accept_input(packet(3,3),120) and b.held(0) and b.held(1),"Simultaneous A+B decoded")
	check(not b.accept_input(packet(3,0),130) and b.mask==3,"Duplicate sequence cannot mutate state")
	check(not b.accept_input(packet(4,128),130) and b.mask==3,"Unused code 7 rejected")
	check(not b.accept_input('{"version":1}'.to_utf8_buffer(),130),"Malformed packet rejected")
	check(b.accept_input(packet(4,0,false),140) and b.mask==0 and not b.connected,"Disconnect releases input")
	b.accept_input(packet(1,256,true,"new-session"),150)
	check(b.mask==0,"New session requires neutral")
	b.accept_input(packet(2,0,true,"new-session"),160);b.accept_input(packet(3,256,true,"new-session"),170)
	check(b.held(8),"START bit 8 remains available")
	b.last_received=Time.get_ticks_msec()-501;b.poll()
	check(not b.connected and b.mask==0,"Stale heartbeat clears held inputs")
	b.close();print("BADGE PROTOCOL: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
