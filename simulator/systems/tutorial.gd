extends RefCounted
class_name FlightTutorial
## Coaching happens inside Play. It never stops simulation or requires a menu.
const LESSONS: Array[Dictionary]=[
 {"title":"FIRST CONTACTS","lines":["Let's clear your first three geese together.","Defeat the large boss later, then land safely at SFO."]},
 {"title":"YOUR CARDBOARD CONTROLS","lines":["Rotate the yoke to bank. Tilt toward you to climb; forward to descend.","Throttle forward accelerates; pull back to brake. Arrow keys and W/S also work."]},
 {"title":"PRIMARY SWITCH","lines":["Flip yoke switch 1 ON, or tap Space, for minigun and energy cannon.","Bring a goose into the aim ring. Flip OFF or tap again to stop firing."]},
 {"title":"MISSILE SWITCH","lines":["Flip yoke switch 2 ON, or tap T, for repeated four-missile salvos.","The lock guides your missiles. Both weapons have unlimited ammunition."]},
 {"title":"KEEP THE INTERCEPT GOING","lines":["Keep targets near the aiming ring and clear three geese.","Badge LEFT changes view; HOME pauses; UP toggles route assistance."]},
 {"title":"YOU'RE READY","lines":["Three geese cleared. You're ready to continue the intercept.","Defeat the boss, then press badge B or keyboard L to deploy flaps and land."]},
 {"title":"SFO LANDING ASSIST","lines":["Gear and full flaps deployed. Weapons safe. Follow the runway.","Assistance handles descent, touchdown and braking to a stop."]}
]
var app: Node
var active:=false
var index:=0
var age:=0.0
var total_age:=0.0
var handoff_done:=false
var voice_id:=""
var voice_name:=""
var spoken_text:=""
var last_muted:=false
var last_paused:=false
func configure(owner: Node) -> void:
	app=owner
	if DisplayServer.get_name()=="headless":return
	for voice: Dictionary in DisplayServer.tts_get_voices():
		if str(voice.language).begins_with("en") and (voice_id.is_empty() or str(voice.name).contains("Daniel")):
			voice_id=str(voice.id);voice_name=str(voice.name)
func start() -> void:
	if voice_id.is_empty():configure(app)
	active=true;index=0;age=0;total_age=0;handoff_done=false
	app.audio.radio.reset();app.audio.radio.enabled=false
	last_muted=app.audio.muted;last_paused=false;speak()
func stop() -> void:
	if active and not voice_id.is_empty():DisplayServer.tts_stop()
	active=false
	if app!=null and is_instance_valid(app.audio):app.audio.radio.enabled=true
func lesson() -> Dictionary:return LESSONS[index]
func show(next: int) -> void:
	if next==index:return
	index=next;age=0;speak()
func landing_begun() -> void:
	# Landing guidance is part of the mission too, even after the first-three handoff.
	active=true;app.audio.radio.reset();app.audio.radio.enabled=false;show(6)
func speak() -> void:
	spoken_text=str(lesson().title)+". "+" ".join(lesson().lines)
	if voice_id.is_empty() or app.audio.muted or app.mode=="paused" or app.overlay_visible():return
	DisplayServer.tts_speak(spoken_text,voice_id,85,1.0,.96,index,true)
func speaking() -> bool:return active and not voice_id.is_empty() and DisplayServer.tts_is_speaking() and not DisplayServer.tts_is_paused()
func tick(dt: float) -> void:
	if not active:return
	var paused: bool=app.mode=="paused" or app.overlay_visible()
	if not voice_id.is_empty():
		if app.audio.muted and not last_muted:DisplayServer.tts_stop()
		elif not app.audio.muted and last_muted and not paused:speak()
		if paused and not last_paused:DisplayServer.tts_pause()
		elif not paused and last_paused and not app.audio.muted:DisplayServer.tts_resume()
	last_muted=app.audio.muted;last_paused=paused
	if paused:return
	age+=dt;total_age+=dt
	if index in [5,6]:
		if age>12 and not speaking():stop()
		return
	if app.combat.kills>=3:
		handoff_done=true;show(5);return
	if index==0 and age>=5:show(1)
	elif index==1 and age>=9:show(2)
	elif index==2 and app.combat.primary_used and age>=4:show(3)
	elif index==3 and app.combat.salvo_count>0 and age>=4:show(4)
