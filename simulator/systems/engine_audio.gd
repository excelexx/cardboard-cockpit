extends Node
class_name EngineAudio
const Radio = preload("res://systems/radio_director.gd")
var radio: RadioDirector
var ambience: AudioStreamPlayer
var wheels: AudioStreamPlayer
var burner: AudioStreamPlayer
var burner_wanted := false
var beam_loop: AudioStreamPlayer
var beam_wanted:=false
var flow_intensity:=0.0
var acquisition:=0.0
var instructor_speaking:=false
var acquire_clock:=0.0
var spatial_players: Array[AudioStreamPlayer3D]=[]
var gun_loop: AudioStreamPlayer
var gun_wanted := false
var gun_envelope := 0.0
var context_mode := "hangar"
var context_cockpit := false
var context_contact := ""
var context_paused := false
var duck_level := 0.0
var last_gear := true
var last_flaps := 0
var touchdown_announced := false

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
	beam_loop=AudioStreamPlayer.new();beam_loop.volume_db=-80;add_child(beam_loop)
	for i in range(8):
		var spatial:=AudioStreamPlayer3D.new();spatial.max_distance=2500;spatial.unit_size=120;spatial.attenuation_filter_cutoff_hz=8000;add_child(spatial);spatial_players.append(spatial)
	gun_loop = AudioStreamPlayer.new()
	gun_loop.volume_db = -80
	add_child(gun_loop)
	radio = Radio.new()
	add_child(radio)
	ambience = AudioStreamPlayer.new()
	ambience.volume_db = -80
	add_child(ambience)
	burner = AudioStreamPlayer.new()
	burner.volume_db = -80
	add_child(burner)
	wheels = AudioStreamPlayer.new()
	wheels.volume_db = -80
	add_child(wheels)
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
		gun_loop.stream = loop_sample("res://assets/audio/gatling_loop.wav")
		gun_loop.play()
		burner.stream = loop_sample("res://assets/audio/afterburner.wav")
		burner.play()
		ambience.stream = load("res://assets/audio/cockpit_ambience.ogg")
		ambience.stream.loop = true
		ambience.play()
		wheels.stream = loop_sample("res://assets/audio/wheel_roll.wav")
		wheels.play()
		player.stream = loop_sample("res://assets/audio/jet.wav")
		wind.stream = loop_sample("res://assets/audio/wind.wav")
		wind.play()
		tone.stream = make_sound(0.22, true)
		player.play()
		for effect_name: String in ["gatling_attack","cannon","explosion","impact","flare","eject","sonic","gear_motor","flap_motor","touchdown_tires","touchdown_thump"]:
			effects[effect_name] = load("res://assets/audio/%s.%s" % [effect_name,"wav" if effect_name in ["gatling_attack","cannon","gear_motor","flap_motor","touchdown_tires","touchdown_thump","sonic"] else "ogg"])
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
			effect.set_meta("base_db",volume)
			effect.volume_db = volume+duck_level*0.65
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

func set_context(mode: String, cockpit_view: bool, contact: String, paused_value: bool) -> void:
	context_mode = mode
	context_cockpit = cockpit_view
	context_contact = contact
	context_paused = paused_value
func reset_flight() -> void:
	radio.reset()
	gun_wanted = false; gun_envelope = 0; gun_loop.volume_db = -80
	last_gear = true
	last_flaps = 0
	touchdown_announced = false
func observe_flight(flight: FlightDynamics) -> void:
	if flight.gear!=last_gear:
		play_effect("gear_motor",-20)
		last_gear = flight.gear
	if flight.flaps!=last_flaps:
		play_effect("flap_motor",-25)
		last_flaps = flight.flaps
func play_spatial(effect_name: String,at: Vector3,volume: float=-18,pitch: float=1) -> void:
	if muted or not effects.has(effect_name):return
	for sound in spatial_players:
		if not sound.playing:
			sound.position=at;sound.stream=effects[effect_name];sound.volume_db=volume;sound.pitch_scale=pitch;sound.play();return

func update(engine: float, speed: float, flying: bool, dt: float = 1.0/60.0) -> void:
	beam_loop.stream_paused=context_paused
	beam_loop.volume_db=move_toward(beam_loop.volume_db,-20+duck_level*.4 if beam_wanted and not muted else -80,dt*220)
	beam_loop.pitch_scale=1.0+sin(Time.get_ticks_msec()*.0017)*.015
	acquire_clock-=dt
	if acquisition>0 and acquisition<1 and acquire_clock<=0 and not context_paused:
		ping(.65+acquisition*.6);acquire_clock=.085
	for sound in spatial_players:
		sound.stream_paused=context_paused
		if muted:sound.stop()
	radio.tick(dt,context_paused,muted)
	if not context_paused: gun_envelope = move_toward(gun_envelope,1.0 if gun_wanted else 0.0,dt*(24 if gun_wanted else 7))
	gun_loop.volume_db = -80 if muted or gun_envelope<.001 else -13+linear_to_db(gun_envelope)+duck_level*.4
	gun_loop.pitch_scale = lerpf(.80,1.04,gun_envelope)
	gun_loop.stream_paused = context_paused
	var wanted_duck: float=minf(radio.duck_db(),-12.0 if instructor_speaking else 0.0)
	duck_level = move_toward(duck_level,wanted_duck,dt*(70 if wanted_duck<duck_level else 10))
	burner.volume_db = move_toward(burner.volume_db,-80 if muted or not burner_wanted else -17+duck_level*0.65,dt*80)
	burner.stream_paused = context_paused
	music.volume_db = -80 if muted else lerpf(-26,-18,flow_intensity)+duck_level
	geese.volume_db = -80 if muted else lerpf(-34,-27,flow_intensity)+duck_level*0.7
	ambience.volume_db = -80 if muted else (-37 if context_cockpit and flying else -43 if context_mode in ["hangar","title","briefing"] else -80)+duck_level*0.6
	wheels.volume_db = -80 if muted or context_contact!="landed" or speed<0.2 else lerpf(-42,-20,clampf(speed/65,0,1))+duck_level*0.7
	wheels.pitch_scale = lerpf(0.6,1.15,clampf(speed/70,0,1))
	for sound: AudioStreamPlayer in [music,geese,player,wind,ambience,wheels]: sound.stream_paused = context_paused
	for effect: AudioStreamPlayer in effect_players:
		if muted: effect.stop()
		else:
			effect.stream_paused = context_paused
			effect.volume_db = float(effect.get_meta("base_db",-20))+duck_level*0.65
	player.pitch_scale = (0.70 + engine * 0.7 + speed * 0.0007)*engine_pitch
	player.volume_db = -80 if muted else (-29.0 + engine * 11.0 if flying else -45.0)+duck_level*0.6
	wind.volume_db = -80 if muted or not flying else lerpf(-58,-25,clampf(speed/220,0,1))+duck_level*0.5

func ping(pitch: float = 1.0) -> void:
	if not muted and tone.stream != null:
		tone.pitch_scale = pitch
		tone.play()

func _exit_tree() -> void:
	# Release looping playback before the scene disappears during test shutdown.
	for stream_player: AudioStreamPlayer in [player,tone,wind,music,geese,ambience,wheels,burner,gun_loop,beam_loop]:
		if is_instance_valid(stream_player):
			stream_player.stop()
			stream_player.stream = null

func set_music_active(enabled: bool) -> void:
	for sound: AudioStreamPlayer in [music,geese]:
		if enabled and sound.stream!=null and not sound.playing: sound.play()
		elif not enabled and not context_paused: sound.stop()
