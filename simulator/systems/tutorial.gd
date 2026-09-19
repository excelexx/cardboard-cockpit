extends RefCounted
class_name FlightTutorial
## Self-paced training. Uses local OS speech; no microphone, network or recording.
const LESSONS: Array[Dictionary]=[
 {"title":"MISSION BRIEFING","lines":["Defeat the geese and boss, then land safely at SFO.","Training waits for you. Audio uses your selected headphones or speakers.","Select Continue, press Enter, or press START on the badge when ready."],"practice":false},
 {"title":"CARDBOARD YOKE","lines":["Rotate the cardboard yoke left or right to bank and turn.","Tilt it toward you to raise the nose; tilt forward to lower it.","Calibrate and enable camera controls with C. Arrow keys also work."],"practice":false},
 {"title":"CARDBOARD THROTTLE","lines":["Move the cardboard throttle toward FULL to accelerate; the top end boosts.","Move it toward IDLE to slow down and apply the airbrake.","Keyboard: W accelerates, S brakes, and holding Shift boosts."],"practice":false},
 {"title":"PRIMARY WEAPON SWITCH","lines":["Flip yoke switch one ON: the minigun and energy cannon fire together.","It stays on until you flip it OFF. Keyboard Space does the same.","Try it now. Flight assistance will keep you aimed toward a target."],"practice":true},
 {"title":"FOUR-MISSILE SWITCH","lines":["Flip yoke switch two ON to launch repeated four-missile salvos.","Flip it OFF to stop. Keyboard T does the same. Ammunition is unlimited.","Try one salvo, then select Continue."],"practice":true},
 {"title":"CLEAR A TARGET","lines":["Bring a goose into the aiming ring. The lock helps the missiles guide.","Keep your weapons on until at least one goose is destroyed.","In the full mission, defeating the large boss is also required."],"practice":true},
 {"title":"WIRELESS BADGE","lines":["START begins or resumes; HOME pauses. LEFT changes the camera.","RIGHT shows the missile camera; UP toggles route assistance.","A toggles gear; DOWN toggles HUD text. B starts assisted landing."],"practice":false},
 {"title":"LAND AT SFO","lines":["Press B on the badge, L on the keyboard, or Land below.","This deploys gear and full flaps, switches weapons off, and assists landing.","A brief transition moves you to SFO final approach for this short demo."],"practice":true},
 {"title":"APPROACH AND TOUCHDOWN","lines":["Keep the runway centred. Landing assistance manages speed and descent.","After touchdown, automatic braking brings the aircraft to a stop.","Training completes only after a safe landing and full stop."],"practice":true}
]
var app: Node
var active:=false
var index:=0
var voice_id:=""
var voice_name:=""
var spoken_text:=""
var voice_paused:=false
var last_muted:=false
var last_paused:=false
func configure(owner: Node) -> void:
	app=owner
	if DisplayServer.get_name()=="headless":return
	for voice: Dictionary in DisplayServer.tts_get_voices():
		if not str(voice.language).begins_with("en"):continue
		if voice_id.is_empty() or str(voice.name).contains("Daniel"):
			voice_id=str(voice.id);voice_name=str(voice.name)
func start() -> void:
	if voice_id.is_empty():configure(app)
	active=true;index=0;app.text_hud=true
	app.audio.radio.reset();app.audio.radio.enabled=false
	last_muted=app.audio.muted;last_paused=false;speak()
func stop() -> void:
	if active and not voice_id.is_empty():DisplayServer.tts_stop()
	active=false;voice_paused=false
	if app!=null and is_instance_valid(app.audio):app.audio.radio.enabled=true
func lesson() -> Dictionary:return LESSONS[index]
func practice_active() -> bool:return active and lesson().practice
func ready() -> bool:
	match index:
		3:return app.combat.primary_used
		4:return app.combat.salvo_count>0
		5:return app.combat.kills>0
		7,8:return false
	return true
func training_ready() -> bool:return app.combat.primary_used and app.combat.salvo_count>0 and app.combat.kills>0 and index>=7
func advance() -> void:
	if not active or not ready() or index>=LESSONS.size()-1:return
	index+=1
	if index in [6,7]:
		app.primary_latched=false;app.salvo_latched=false;app.combat.gun_firing_time=0;app.combat.beam_active=false
	speak()
func landing_begun() -> void:
	if active:index=8;speak()
func speak() -> void:
	spoken_text=str(lesson().title)+". "+" ".join(lesson().lines)
	if voice_id.is_empty() or app.audio.muted or app.mode=="paused" or app.overlay_visible():return
	DisplayServer.tts_speak(spoken_text,voice_id,85,1.0,.96,index,true)
func speaking() -> bool:
	return active and not voice_id.is_empty() and DisplayServer.tts_is_speaking() and not DisplayServer.tts_is_paused()
func voice_status() -> String:
	if app.audio.muted:return "AUDIO MUTED — M TO UNMUTE / CAPTIONS AVAILABLE"
	if voice_id.is_empty():return "CAPTIONS AVAILABLE — NO ENGLISH SYSTEM VOICE"
	return "INSTRUCTOR: "+voice_name+" / SYSTEM AUDIO OUTPUT"
func tick() -> void:
	if not active:return
	var paused: bool=app.mode=="paused" or app.overlay_visible()
	if not voice_id.is_empty():
		if app.audio.muted and not last_muted:DisplayServer.tts_stop()
		elif not app.audio.muted and last_muted and not paused:speak()
		if paused and not last_paused:DisplayServer.tts_pause();voice_paused=true
		elif not paused and last_paused and not app.audio.muted:DisplayServer.tts_resume();voice_paused=false
	last_muted=app.audio.muted;last_paused=paused
