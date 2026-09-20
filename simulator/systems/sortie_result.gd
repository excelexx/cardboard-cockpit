extends RefCounted
## One assessment drives text, advice, score eligibility and the result radio cue.
## The showcase branch is keyed on the flock: how many geese came down out of how
## many arrived, and whether the jet is stopped on the SFO runway.
## `cinematic_state` is the mission's live tally. DemoMission publishes it every
## tick so the debrief is right even when the caller passes only generic state.
static var cinematic_state: Dictionary = {}
static func make(code: String,success: bool,headline: String,summary: String,advice: String) -> Dictionary:
	return {"code":code,"success":success,"headline":headline,"summary":summary,"advice":advice,"radio":"success" if success else "failure"}
static func assess(s: Dictionary,requested_success: bool,reason: String) -> Dictionary:
	var landed: bool=s.get("contact","")=="landed" and s.get("stopped",false)
	if s.get("judge_demo",false) and landed:return make("demo_complete",true,"DEMO COMPLETE","%d geese cleared. Aircraft safely landed." % int(s.get("kills",0)),"Nice flying. Play again whenever you want.")
	if s.get("ejected",false):return make("ejected",false,"YOU EJECTED","You are safe. The jet is gone.","Try again. Press H for auto-fly before you lose control.")
	if s.get("contact","") in ["overrun","excursion"]:return make("runway_excursion",false,"OFF THE RUNWAY","The jet left the runway.","Press badge B and the jet lands itself. Stay on the centre line while braking.")
	if s.get("contact","")=="crash":
		return make("crash",false,"YOU CRASHED","The jet hit the ground.","Press badge B: it drops the gear and flaps and lands for you." if s.get("landing",false) else "Steer gently and stay high. Press H for auto-fly.")
	if s.get("cause","")=="sector":return make("sector",false,"TOO FAR OUT","You left the map.","Follow the green diamond, or press H for auto-fly.")
	if s.get("cinematic",false):
		var total: int=int(s.get("total",cinematic_state.get("total",0)))
		var down: int=clampi(int(s.get("down",cinematic_state.get("down",0))),0,maxi(total,0))
		var cleared: bool=bool(s.get("cleared",cinematic_state.get("cleared",false))) or (total>0 and down>=total)
		var left: int=maxi(0,total-down)
		if cleared and landed:return make("mission_complete",true,"MISSION COMPLETE","You cleared the flock and landed at SFO.","Both jobs done. Go again for a higher score.")
		# Booth rule: almost all of them plus a landing still counts as a win.
		if landed and total>0 and down>=ceili(total*0.75):return make("mostly_clear",true,"MOSTLY CLEAR","You shot down %d of %d geese and landed at SFO." % [down,total],"Get every one of them next time. Go again for a higher score.")
		if landed:
			return make("skein_incomplete",false,"THE SKEIN GOT THROUGH","Safe landing. %d geese are still flying." % left if total>0 else "Safe landing. The flock got through.","Clear the flock before you land." if s.get("early_landing",false) else "Hold the gun on the flock while the ring is on a goose.")
		if cleared:return make("recovery_incomplete",false,"NOT LANDED","You cleared the flock but never landed.","Press badge B or L and the jet lands itself.")
		return make("mission_incomplete",false,"OUT OF TIME","You shot down %d of %d geese." % [down,total] if total>0 else "The flock is still flying and you did not land.","Put the ring on a goose, hold the gun, then press badge B to land.")
	return make("sortie_complete" if requested_success else "sortie_failed",requested_success,"LANDED" if requested_success and landed else "FLIGHT COMPLETE" if requested_success else "FLIGHT FAILED",reason,"Nice landing." if landed and requested_success else "Try again with auto-fly on (H)." if not requested_success else "All done.")
