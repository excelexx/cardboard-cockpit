extends Node
class_name EngineAudio

var player: AudioStreamPlayer
var tone: AudioStreamPlayer
var muted := false

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = -36
	add_child(player)
	tone = AudioStreamPlayer.new()
	tone.volume_db = -18
	add_child(tone)
	# Headless regression runs have no audio device or presentation to render.
	if DisplayServer.get_name() != "headless":
		player.stream = make_sound(2.0, false)
		tone.stream = make_sound(0.22, true)
		player.play()

func make_sound(duration: float, chime: bool) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var count: int = int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8412
	var noise: float = 0.0
	for i: int in count:
		var t: float = float(i) / sample_rate
		noise = lerpf(noise, rng.randf_range(-1,1), 0.14)
		var sample: float
		if chime:
			sample = (sin(t*TAU*880) + sin(t*TAU*1320)*0.4) * 0.3 * sin(PI*t/duration)
		else:
			sample = noise * 0.38 + sin(t*TAU*60)*0.20 + sin(t*TAU*120)*0.10 + sin(t*TAU*240)*0.03
		bytes.encode_s16(i*2, int(clampf(sample,-1,1)*26000))
	var wav := AudioStreamWAV.new()
	wav.data = bytes
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	if not chime:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = count
	return wav

func update(engine: float, speed: float, flying: bool) -> void:
	player.pitch_scale = 0.65 + engine * 1.7 + speed * 0.001
	player.volume_db = -80 if muted else (-29.0 + engine * 11.0 if flying else -45.0)

func ping() -> void:
	if not muted and tone.stream != null:
		tone.play()

func _exit_tree() -> void:
	# Release looping playback before the scene disappears during test shutdown.
	for stream_player: AudioStreamPlayer in [player,tone]:
		if is_instance_valid(stream_player):
			stream_player.stop()
			stream_player.stream = null
