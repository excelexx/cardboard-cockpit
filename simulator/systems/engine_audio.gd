extends Node
class_name EngineAudio
const Radio = preload("res://systems/radio_director.gd")
var radio: RadioDirector
var ambience: AudioStreamPlayer
var wheels: AudioStreamPlayer
var burner: AudioStreamPlayer
var burner_wanted := false
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
var beam_loop: AudioStreamPlayer
var beam_wanted:=false
var muted := false
var effects: Dictionary = {}
var effect_players: Array[AudioStreamPlayer] = []

## The world gets a speed of sound. A kill at 700 m flashes now and is heard
## about two seconds later, with the high end rolled off by the air in between.
const SOUND_SPEED := 343.0
const SPATIAL_IMMEDIATE_RANGE := 120.0
var spatial_queue: Array[Dictionary] = []
## Flock voices. The shared eight spatial players would starve against kill and
## near-miss cues, so the geese get their own small pool.
var flock_players: Array[AudioStreamPlayer3D] = []
var flock_free: Array[AudioStreamPlayer3D] = []
var flock_state: Dictionary = {}
var honk_low: AudioStreamWAV
var honk_high: AudioStreamWAV
var flock_population := 0
var flock_seen_clock := 0.0
var flock_alerted := false
var pending_event: Dictionary = {}
var honk_rng := RandomNumberGenerator.new()

func _ready() -> void:
	beam_loop=AudioStreamPlayer.new();beam_loop.volume_db=-80;add_child(beam_loop)
	for i in range(8):
		var spatial:=AudioStreamPlayer3D.new();spatial.max_distance=2500;spatial.unit_size=120;spatial.attenuation_filter_cutoff_hz=8000;add_child(spatial);spatial_players.append(spatial)
	for i in range(6):
		var voice:=AudioStreamPlayer3D.new()
		voice.name="FlockVoice"+str(i)
		voice.attenuation_model=AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.unit_size=200.0
		voice.max_distance=2500.0
		voice.attenuation_filter_cutoff_hz=6500.0
		voice.doppler_tracking=AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP
		add_child(voice)
		flock_players.append(voice)
		flock_free.append(voice)
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
		beam_loop.stream=load("res://assets/audio/plasma_beam.ogg").duplicate();beam_loop.stream.loop=true;beam_loop.play()
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
		# geese.ogg is a looping bed, not a one-shot, so the individual calls
		# are synthesised: two registers of a two-syllable honk.
		honk_low = make_honk(462.0, 0.52)
		honk_high = make_honk(548.0, 0.44)
		player.play()
		for effect_name: String in ["gatling_attack","cannon","missile","explosion","impact","flare","eject","sonic","gear_motor","flap_motor","touchdown_tires","touchdown_thump"]:
			effects[effect_name] = load("res://assets/audio/%s.%s" % [effect_name,"wav" if effect_name in ["gatling_attack","cannon","gear_motor","flap_motor","touchdown_tires","touchdown_thump","sonic"] else "ogg"])
		for index in range(12):
			var effect := AudioStreamPlayer.new()
			add_child(effect)
			effect_players.append(effect)

func play_effect(effect_name: String, volume: float = -12.0, pitch: float = 1.0) -> void:
	if muted or not effects.has(effect_name):
		return
	# combat.gd plays a flat, non-positional bang for the same hit that
	# combat_visuals has just registered a world position for. Swallow the flat
	# copy: the spatial one is already queued with its propagation delay.
	if effect_name in ["explosion","impact"] and not pending_event.is_empty():
		if Time.get_ticks_msec()-int(pending_event.get("stamp",0))<60:
			pending_event.clear()
			return
		pending_event.clear()
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
	# Queued bangs must not fire across a replay boundary.
	spatial_queue.clear()
	pending_event.clear()
	_release_all_flock_voices()
	flock_population = 0
	flock_seen_clock = 0.0
	flock_alerted = false
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
## Sound travels. Anything past about 120 m is queued and fires when its
## wavefront arrives, with the air's high-frequency loss baked into the filter.
static func propagation_delay(distance: float) -> float:
	return maxf(0.0,(distance-SPATIAL_IMMEDIATE_RANGE)/SOUND_SPEED)

static func spatial_cutoff(distance: float) -> float:
	return lerpf(8000.0,1400.0,clampf(distance/1500.0,0.0,1.0))

## The geese bed follows the POPULATION of the sky, not how well the player is
## flying. An empty sky is silent.
static func bed_db(enemy_count: int,silent: bool) -> float:
	if silent or enemy_count<=0:return -80.0
	return lerpf(-45.0,-38.0,clampf(float(enemy_count)/12.0,0.0,1.0))

func listener_position() -> Vector3:
	var viewport: Viewport = get_viewport()
	if viewport==null:return Vector3.ZERO
	var camera: Camera3D = viewport.get_camera_3d()
	return camera.global_position if camera!=null else Vector3.ZERO

func play_spatial(effect_name: String,at: Vector3,volume: float=-18,pitch: float=1) -> void:
	if muted or not effects.has(effect_name):return
	var distance: float=listener_position().distance_to(at)
	var delay: float=propagation_delay(distance)
	if delay<=0.0:
		_emit_spatial(effect_name,at,volume,pitch,distance)
		return
	if spatial_queue.size()>24:return
	spatial_queue.append({"effect":effect_name,"at":at,"volume":volume,"pitch":pitch,"delay":delay})

func _emit_spatial(effect_name: String,at: Vector3,volume: float,pitch: float,distance: float) -> void:
	if muted or not effects.has(effect_name):return
	for sound in spatial_players:
		if not sound.playing:
			sound.position=at
			sound.stream=effects[effect_name]
			# Sitting inside the airframe, exterior bangs arrive through the
			# canopy: quieter and duller than they are from the chase camera.
			sound.volume_db=volume+(-5.0 if context_cockpit else 0.0)
			sound.attenuation_filter_cutoff_hz=spatial_cutoff(distance)*(0.55 if context_cockpit else 1.0)
			sound.pitch_scale=pitch
			sound.play()
			return

func _tick_spatial_queue(dt: float) -> void:
	if context_paused:return
	for i in range(spatial_queue.size()-1,-1,-1):
		var entry: Dictionary=spatial_queue[i]
		entry.delay-=dt
		if entry.delay<=0.0:
			spatial_queue.remove_at(i)
			if not muted:
				var at: Vector3=entry.at
				_emit_spatial(entry.effect,at,entry.volume,entry.pitch,listener_position().distance_to(at))

## Bridge for combat's own kill bang: register the world position, and the flat
## non-positional copy that follows is folded into this one.
func mark_event_position(effect_name: String,at: Vector3,volume: float=-18,pitch: float=1.0) -> void:
	play_spatial(effect_name,at,volume,pitch)
	pending_event={"stamp":Time.get_ticks_msec()}

# --- the flock's voice --------------------------------------------------
## A Canada goose honk: a two-syllable call that dips in the middle, rich in
## odd harmonics with a breathy rasp on the attack.
func make_honk(fundamental: float,duration: float) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var count: int = int(duration*sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5507
	var phase: float = 0.0
	var noise: float = 0.0
	for i: int in count:
		var u: float = float(i)/maxf(count-1,1)
		# Mid-syllable dip: the pitch falls about 60 Hz through the middle of
		# the call and recovers, which is what makes it read as a honk.
		var frequency: float = fundamental-(fundamental*0.115)*exp(-pow((u-0.46)/0.17,2.0))
		phase += TAU*frequency/sample_rate
		noise = lerpf(noise,rng.randf_range(-1,1),0.35)
		var tone_value: float = sin(phase)*0.54+sin(phase*2.0)*0.29+sin(phase*3.0)*0.17+sin(phase*5.0)*0.07
		var attack: float = clampf(u/0.045,0.0,1.0)
		var release: float = clampf((1.0-u)/0.30,0.0,1.0)
		var body: float = 0.82+0.18*sin(u*PI)
		var envelope: float = attack*release*body
		var sample: float = (tone_value+noise*0.16*clampf(1.0-u*3.0,0.0,1.0))*envelope*0.62
		bytes.encode_s16(i*2,int(clampf(sample,-1,1)*26000))
	var wav := AudioStreamWAV.new()
	wav.data = bytes
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	return wav

func _flock_key(enemy: Dictionary) -> String:
	for field in ["skein","skein_id","flock","flock_id"]:
		if enemy.has(field):return field+":"+str(enemy[field])
	return "skein:all"

## Driven from combat_visuals.tick(). Groups the contacts into skeins, keeps one
## spatial voice on each skein's lead bird, and tightens the calling when the
## jet closes: a panicking skein is the best audio cue in the game.
func update_flock(combat: Node,dt: float) -> void:
	flock_seen_clock = 0.75
	var enemies: Array = combat.enemies
	flock_population = enemies.size()
	flock_alerted = false
	if flock_players.is_empty() or muted or context_paused:
		_release_all_flock_voices()
		return
	var listener: Vector3 = listener_position()
	var jet: Vector3 = listener
	if combat.app!=null and combat.app.flight!=null:jet = combat.app.flight.position
	var groups: Dictionary = {}
	for enemy: Dictionary in enemies:
		if enemy.health<=0:continue
		var key: String = _flock_key(enemy)
		var at: Vector3 = enemy.position
		var distance: float = jet.distance_to(at)
		if not groups.has(key) or distance<float(groups[key].distance):
			groups[key] = {"lead":at,"distance":distance,"alerted":bool(enemy.get("alerted",false))}
		elif bool(enemy.get("alerted",false)):
			groups[key].alerted = true
	for key: String in flock_state.keys():
		if not groups.has(key):_release_flock_voice(key)
	for key: String in groups:
		var group: Dictionary = groups[key]
		# A skein that has the jet inside about 700 m is alarmed whether or not
		# combat.gd has told us so.
		var alarmed: bool = bool(group.alerted) or float(group.distance)<700.0
		flock_alerted = flock_alerted or alarmed
		if not flock_state.has(key):
			if flock_free.is_empty():continue
			flock_state[key] = {"player":flock_free.pop_back(),"clock":honk_rng.randf_range(0.2,1.6),"high":honk_rng.randf()>0.5}
		var state: Dictionary = flock_state[key]
		var voice: AudioStreamPlayer3D = state.player
		if not is_instance_valid(voice):continue
		# Updating the position every frame is what gives the voice its Doppler.
		voice.position = group.lead
		state.clock -= dt
		if state.clock>0.0:continue
		state.high = not bool(state.high)
		var stream: AudioStreamWAV = honk_high if bool(state.high) else honk_low
		if stream==null:
			state.clock = 2.0
			continue
		voice.stream = stream
		voice.pitch_scale = honk_rng.randf_range(1.10,1.22) if bool(state.high) else honk_rng.randf_range(0.88,0.96)
		voice.volume_db = (-10.0 if alarmed else -16.0)+(-4.0 if context_cockpit else 0.0)+duck_level*0.5
		voice.play()
		state.clock = honk_rng.randf_range(0.4,0.9) if alarmed else honk_rng.randf_range(1.5,4.0)

func _release_flock_voice(key: String) -> void:
	if not flock_state.has(key):return
	var voice: AudioStreamPlayer3D = flock_state[key].player
	flock_state.erase(key)
	if is_instance_valid(voice):
		voice.stop()
		if not flock_free.has(voice):flock_free.append(voice)

func _release_all_flock_voices() -> void:
	for key: String in flock_state.keys():_release_flock_voice(key)

func update(engine: float, speed: float, flying: bool, dt: float = 1.0/60.0) -> void:
	acquire_clock-=dt
	if acquisition>0 and acquisition<1 and acquire_clock<=0 and not context_paused:
		ping(.65+acquisition*.6);acquire_clock=.085
	for sound in spatial_players:
		sound.stream_paused=context_paused
		if muted:sound.stop()
	for voice in flock_players:
		voice.stream_paused=context_paused
		if muted:voice.stop()
	_tick_spatial_queue(dt)
	if not context_paused:
		flock_seen_clock=maxf(0.0,flock_seen_clock-dt)
		if flock_seen_clock<=0.0:
			flock_population=0
			flock_alerted=false
			if not flock_state.is_empty():_release_all_flock_voices()
	if muted:spatial_queue.clear()
	radio.tick(dt,context_paused,muted)
	if not context_paused: gun_envelope = move_toward(gun_envelope,1.0 if gun_wanted else 0.0,dt*(24 if gun_wanted else 7))
	beam_loop.stream_paused=context_paused
	beam_loop.volume_db=move_toward(beam_loop.volume_db,-24+duck_level*.4 if beam_wanted and not muted else -80,dt*220)
	gun_loop.volume_db = -80 if muted or gun_envelope<.001 else -13+linear_to_db(gun_envelope)+duck_level*.4
	gun_loop.pitch_scale = lerpf(.80,1.04,gun_envelope)
	gun_loop.stream_paused = context_paused
	var wanted_duck: float=minf(radio.duck_db(),-12.0 if instructor_speaking else 0.0)
	duck_level = move_toward(duck_level,wanted_duck,dt*(70 if wanted_duck<duck_level else 10))
	burner.volume_db = move_toward(burner.volume_db,-80 if muted or not burner_wanted else -17+duck_level*0.65,dt*80)
	burner.stream_paused = context_paused
	music.volume_db = -80 if muted else lerpf(-26,-18,flow_intensity)+duck_level
	# The skein ambience follows how many birds are actually up there. It used
	# to be loudest when the player was flying well and never stopped once the
	# sky was empty.
	geese.volume_db = bed_db(flock_population,muted)+(0.0 if muted else duck_level*0.7+(2.0 if flock_alerted else 0.0))
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
	# An honest cockpit/chase split: inside the tub the airframe muffles the
	# engine and the canopy takes the edge off the slipstream; from the chase
	# camera you are out in it.
	var exterior: float = 0.0 if context_cockpit else 2.0
	player.volume_db = -80 if muted else (-29.0 + engine * 11.0 if flying else -45.0)+duck_level*0.6+exterior
	wind.volume_db = -80 if muted or not flying else lerpf(-58,-25,clampf(speed/220,0,1))+duck_level*0.5+(-2.0 if context_cockpit else 1.0)

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
	for voice: AudioStreamPlayer3D in flock_players:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	spatial_queue.clear()
	flock_state.clear()

func set_music_active(enabled: bool) -> void:
	for sound: AudioStreamPlayer in [music,geese]:
		if enabled and sound.stream!=null and not sound.playing: sound.play()
		elif not enabled and not context_paused: sound.stop()
