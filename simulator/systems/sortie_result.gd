extends RefCounted
## One assessment drives text, advice, score eligibility and the result radio cue.
static func make(code: String,success: bool,headline: String,summary: String,advice: String) -> Dictionary:
	return {"code":code,"success":success,"headline":headline,"summary":summary,"advice":advice,"radio":"success" if success else "failure"}
static func assess(s: Dictionary,requested_success: bool,reason: String) -> Dictionary:
	var landed: bool=s.get("contact","")=="landed" and s.get("stopped",false)
	if s.get("ejected",false):return make("ejected",false,"MISSION ABORTED","Pilot recovered; aircraft abandoned.","Retry the sortie. Use H for route assistance before losing control.")
	if s.get("contact","") in ["overrun","excursion"]:return make("runway_excursion",false,"LANDING FAILED","The aircraft left the runway.","Use B on the badge for assisted landing; keep the centreline while braking.")
	if s.get("contact","")=="crash":
		return make("crash",false,"AIRCRAFT LOST","The aircraft struck the ground or an obstacle.","Use badge B for gear, flaps and landing assistance." if s.get("landing",false) else "Use smaller steering inputs and maintain altitude. H restores route assistance.")
	if s.get("cause","")=="sector":return make("sector",false,"MISSION ABORTED","The aircraft left the operating area.","Follow the navigation marker or use H to restore route assistance.")
	if s.get("cinematic",false):
		if s.get("boss",false) and landed:return make("mission_complete",true,"MISSION COMPLETE","Boss defeated; aircraft landed and stopped at SFO.","Both objectives complete: intercept and safe recovery.")
		if not s.get("boss",false) and landed:
			return make("intercept_incomplete",false,"OBJECTIVE INCOMPLETE","Safe landing confirmed. The boss was not defeated.","Defeat the boss before requesting landing." if s.get("early_landing",false) else "Use both weapon switches against the boss before the intercept window closes.")
		if s.get("boss",false):return make("recovery_incomplete",false,"LANDING INCOMPLETE","Boss defeated, but the aircraft was not secured.","Press badge B or keyboard L to complete the assisted landing.")
		return make("mission_incomplete",false,"OBJECTIVE INCOMPLETE","The boss and safe-landing objectives are unfinished.","Bring targets into the aim ring, use both weapons, then land with badge B.")
	return make("sortie_complete" if requested_success else "sortie_failed",requested_success,"AIRCRAFT SECURED" if requested_success and landed else "SORTIE COMPLETE" if requested_success else "SORTIE FAILED",reason,"Landing complete." if landed and requested_success else "Retry with route assistance enabled." if not requested_success else "Sortie objectives complete.")
