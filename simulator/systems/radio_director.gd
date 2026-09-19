extends Node
class_name RadioDirector
## Bounded, event-driven licensed radio chatter; never overlaps itself.
var player: AudioStreamPlayer
var cues: Dictionary = {}
var queue: Array[Dictionary] = []
var last_played: Dictionary = {}
var clock := 0.0
var remaining := 0.0
var gap := 0.0
var active_id := ""
var active_priority := -1
var caption := ""
var speaker := "CONTROL"
var muted := false
var paused := false
var enabled := true
var spoken_count := 0
func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = -9
	add_child(player)
	var path := "res://assets/audio/radio/manifest.json"
	if FileAccess.file_exists(path):
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		cues = manifest.cues
func say(id: String, priority: int = -1) -> bool:
	if not enabled or muted or not cues.has(id): return false
	var spec: Dictionary = cues[id]
	if clock-float(last_played.get(id,-1000))<float(spec.cooldown): return false
	if active_id==id: return false
	for item: Dictionary in queue:
		if item.id==id: return false
	var rank: int = int(spec.priority) if priority<0 else priority
	if rank>=3 and active_priority<rank and remaining>0:
		player.stop()
		remaining = 0
		caption = ""
		active_id = ""
		gap = 0.06
	var request := {"id":id,"priority":rank,"expires":clock+(8.0 if rank>0 else 3.0)}
	queue.append(request)
	queue.sort_custom(func(a: Dictionary,b: Dictionary): return a.priority>b.priority)
	if queue.size()>3: queue.resize(3)
	return request in queue
func reset() -> void:
	queue.clear()
	last_played.clear()
	if is_instance_valid(player): player.stop()
	remaining = 0
	active_priority = -1
	active_id = ""
	caption = ""
	gap = 0
func tick(dt: float, is_paused: bool, is_muted: bool) -> void:
	muted = is_muted
	paused = is_paused
	if muted:
		reset()
		return
	player.stream_paused = paused
	if paused: return
	clock += dt
	remaining = maxf(0,remaining-dt)
	if remaining>0: return
	if not active_id.is_empty():
		active_id = ""
		caption = ""
		active_priority = -1
		gap = 0.35
	gap = maxf(0,gap-dt)
	if gap>0: return
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		if item.expires<clock: continue
		var spec: Dictionary = cues[item.id]
		active_id = item.id
		active_priority = item.priority
		caption = str(spec.text)
		speaker = str(spec.speaker)
		remaining = float(spec.duration)
		last_played[active_id] = clock
		spoken_count += 1
		if DisplayServer.get_name()!="headless":
			player.stream = load("res://assets/audio/radio/"+str(spec.file))
			player.play()
		break
func duck_db() -> float:
	return -10.0 if remaining>0 and not muted else 0.0
func _exit_tree() -> void:
	if is_instance_valid(player):
		player.stop()
		player.stream = null
