extends Node
class_name EngineAudio

var player: AudioStreamPlayer
var tone: AudioStreamPlayer
var music: AudioStreamPlayer
var geese: AudioStreamPlayer
var wind: AudioStreamPlayer
var engine_pitch := 1.0
var muted := false
var effects: Dictionary = {}
var effect_players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = -36
	add_child(player)
	tone = AudioStreamPlayer.new()
	tone.volume_db = -18
	add_child(tone)
	wind = AudioStreamPlayer.new()
	wind.volume_db = -60
	add_child(wind)
	music = AudioStreamPlayer.new()
	music.volume_db = -24
	add_child(music)
	geese = AudioStreamPlayer.new()
	geese.volume_db = -27
	add_child(geese)
	# Headless regression runs have no audio device or presentation to render.
	if DisplayServer.get_name() != "headless":
		if ResourceLoader.exists("res://assets/audio/music.ogg"):
			music.stream = load("res://assets/audio/music.ogg")
			music.stream.loop = true
		if ResourceLoader.exists("res://assets/audio/geese.ogg"):
			geese.stream = load("res://assets/audio/geese.ogg")
			geese.stream.loop = true
		player.stream = loop_sample("res://assets/audio/jet.wav")
		wind.stream = loop_sample("res://assets/audio/wind.wav")
		wind.play()
		tone.stream = make_sound(0.22, true)
		player.play()
		for effect_name: String in ["cannon","missile","explosion","impact","flare","eject","plasma"]:
			effects[effect_name] = load("res://assets/audio/%s.%s" % [effect_name,"wav" if effect_name=="cannon" else "ogg"])
		for index in range(12):
			var effect := AudioStreamPlayer.new()
			add_child(effect)
			effect_players.append(effect)

func play_effect(effect_name: String, volume: float = -12.0, pitch: float = 1.0) -> void:
	if muted or not effects.has(effect_name):
		return
	for effect: AudioStreamPlayer in effect_players:
		if not effect.playing:
			effect.stream = effects[effect_name]
			effect.volume_db = volume
			effect.pitch_scale = pitch
			effect.play()
			return

func loop_sample(path: String) -> AudioStreamWAV:
	var stream: AudioStreamWAV = load(path).duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length()*stream.mix_rate)
	return stream

func set_aircraft(profile: Dictionary) -> void:
	engine_pitch = 1.17 if str(profile.id)=="f35" else 0.72 if str(profile.id)=="an225" else 0.87

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
	if is_instance_valid(music): music.volume_db = -80 if muted else -24
	if is_instance_valid(geese): geese.volume_db = -80 if muted else -27
	if muted:
		for effect: AudioStreamPlayer in effect_players:
			effect.stop()
	player.pitch_scale = (0.70 + engine * 0.7 + speed * 0.0007)*engine_pitch
	player.volume_db = -80 if muted else (-29.0 + engine * 11.0 if flying else -45.0)
	wind.volume_db = -80 if muted or not flying else lerpf(-58,-25,clampf(speed/220,0,1))

func ping() -> void:
	if not muted and tone.stream != null:
		tone.play()

func _exit_tree() -> void:
	# Release looping playback before the scene disappears during test shutdown.
	for stream_player: AudioStreamPlayer in [player,tone,wind,music,geese]:
		if is_instance_valid(stream_player):
			stream_player.stop()
			stream_player.stream = null

func campaign_audio(enabled: bool) -> void:
	for sound: AudioStreamPlayer in [music,geese]:
		if enabled and sound.stream!=null and not sound.playing: sound.play()
		elif not enabled: sound.stop()
