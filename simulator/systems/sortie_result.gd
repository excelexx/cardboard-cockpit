extends RefCounted
## One assessment drives text, advice, score eligibility and the result radio cue.
static func make(code: String,success: bool,headline: String,summary: String,advice: String) -> Dictionary:
	return {"code":code,"success":success,"headline":headline,"summary":summary,"advice":advice,"radio":"success" if success else "failure"}
static func assess(s: Dictionary,requested_success: bool,reason: String) -> Dictionary:
	var landed: bool=s.get("contact","")=="landed" and s.get("stopped",false)
	if s.get("ejected",false):return make("ejected",false,"YOU EJECTED","You are safe. The jet is gone.","Try again. Press H for auto-fly before you lose control.")
	if s.get("contact","") in ["overrun","excursion"]:return make("runway_excursion",false,"OFF THE RUNWAY","The jet left the runway.","Press badge B and the jet lands itself. Stay on the centre line while braking.")
	if s.get("contact","")=="crash":
		return make("crash",false,"YOU CRASHED","The jet hit the ground.","Press badge B: it drops the gear and flaps and lands for you." if s.get("landing",false) else "Steer gently and stay high. Press H for auto-fly.")
	if s.get("cause","")=="sector":return make("sector",false,"TOO FAR OUT","You left the map.","Follow the green diamond, or press H for auto-fly.")
	if s.get("cinematic",false):
		if s.get("boss",false) and landed:return make("mission_complete",true,"MISSION COMPLETE","You beat Mother Goose and landed at SFO.","Both jobs done. Go again for a higher score.")
		if not s.get("boss",false) and landed:
			return make("intercept_incomplete",false,"BOSS GOT AWAY","Safe landing, but Mother Goose is still flying.","Beat the boss before you land." if s.get("early_landing",false) else "Turn on the gun and the missiles before time runs out on the boss.")
		if s.get("boss",false):return make("recovery_incomplete",false,"NOT LANDED","You beat Mother Goose but never landed.","Press badge B or L and the jet lands itself.")
		return make("mission_incomplete",false,"OUT OF TIME","The boss is still flying and you did not land.","Put the ring on a goose, use both weapons, then press badge B to land.")
	return make("sortie_complete" if requested_success else "sortie_failed",requested_success,"LANDED" if requested_success and landed else "FLIGHT COMPLETE" if requested_success else "FLIGHT FAILED",reason,"Nice landing." if landed and requested_success else "Try again with auto-fly on (H)." if not requested_success else "All done.")
