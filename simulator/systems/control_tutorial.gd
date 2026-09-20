extends RefCounted

# Every step uses fresh tracker observations. Time spent rendering the same
# packet, disconnected, or without a live picture cannot complete a check.
const HOLD_MS := 450
const OVERVIEW_MS := 4000
const READY_HOLD_MS := 1000
const READ_SECONDS := 1.0
const FEEDBACK_SECONDS := 0.55
const CALIBRATION_STEP := ["calibrate", "yoke", "Hold the yoke upright for 3 seconds", "Hold it level in your normal flying position, with the yoke tag facing the camera.", "Keep still. These three seconds set your neutral position."]
const STEPS := [
	["idle", "throttle", "Slide the throttle to 0%", "Slide toward the idle end until the power reads 0%.", "Keep the handle tag and both end tags visible."],
	["full", "throttle", "Slide the throttle to 100%", "Move the handle along the rail to the full-power end.", "The power bar should rise as you slide."],
	["idle", "throttle", "Bring the throttle back to 0%", "Slide back toward the idle end until the power reads 0%.", "Leave the throttle here for the next checks."],
	["yoke_info", "yoke", "The yoke controls your flight", "Turn to bank, tilt to climb or descend, and swivel to steer left or right.", "No movement check needed. The gun checks are next."],
	["grip", "weapons", "Set your shooting grip", "Put your middle finger on the green elastic band and ring finger on the blue elastic band.", "Show the gun tag. Keep your left hand free for the throttle."],
	["cover_gun", "weapons", "Cover the gun tag with your pointer finger", "Cover most of the printed pattern. Keep the yoke tag visible.", "The gun should turn OFF. Middle finger stays on green; ring finger stays on blue."],
	["show", "weapons", "Lift your pointer finger to shoot", "Lift your pointer finger off the gun tag so the camera can see it.", "Minigun and plasma turn ON. Cover the tag to stop both."],
]
var index := 0
var calibrating := true
var calibration_progress := 0.0
var age := 0.0
var held_ms := 0
var passed := false
var feedback := 0.0
var last_sequence := -1
var last_sample := -1
var ready_ms := 0
var can_start := false
var status := "Waiting for the camera and tracker..."

func reset() -> void:
	index = 0
	calibrating = true
	retry()
func retry() -> void:
	calibration_progress = 0.0
	age = 0; held_ms = 0; passed = false; feedback = 0
	last_sequence = -1; last_sample = -1; ready_ms = 0; can_start = false
func complete() -> bool: return not calibrating and index >= STEPS.size()
func step() -> Array: return CALIBRATION_STEP if calibrating else STEPS[mini(index, STEPS.size()-1)]
func focus() -> String: return "all" if complete() else str(step()[1])
func progress() -> float: return calibration_progress if calibrating else clampf(float(held_ms)/(OVERVIEW_MS if step()[0]=="yoke_info" else HOLD_MS), 0, 1)
func live(v: VisionClient, picture: bool, now: int) -> bool:
	return picture and v.enabled and v.connected and v.last_received >= 0 and now-v.last_received < 150
func ready_pose(v: VisionClient) -> bool:
	return v.yoke_enabled and v.tracking and v.yoke.length() < .25 and absf(v.yoke_yaw) < .25 and v.throttle_confidence > .4 and v.throttle <= .1 and not v.gun_trigger
func matches(v: VisionClient) -> bool:
	var key: String = step()[0]
	if key=="yoke_info": return true
	if focus()=="throttle":
		return v.throttle_confidence > .4 and (v.throttle >= .9 if key=="full" else v.throttle <= .1)

	match key:
		"grip", "show": return v.gun_trigger
		"cover_gun": return v.tracking and not v.gun_trigger
	return false

func tick(dt: float, v: VisionClient, picture: bool, now: int) -> void:
	age += clampf(dt, 0, .1)
	if not live(v, picture, now):
		calibration_progress = 0
		held_ms = 0; ready_ms = 0; can_start = false; last_sample = -1
		passed = false; feedback = 0
		status = "Waiting for the live camera..." if not picture else "Waiting for fresh control tracking..."
		return
	if calibrating:
		var capture = v.yoke_calibration
		if not capture.fresh(now):
			calibration_progress = 0; passed = false; feedback = 0
			status = "Connecting to yoke calibration..."
			return
		calibration_progress = capture.elapsed/3.0
		if capture.state == "complete":
			status = "Yoke calibrated — neutral position saved."
			passed = true; feedback += clampf(dt, 0, .1)
			if feedback >= FEEDBACK_SECONDS:
				calibrating = false
				capture.stop()
				retry()
		else:
			passed = false; feedback = 0
			if capture.state == "unavailable": status = "Start the yoke tracker and finish its camera setup."
			elif capture.state == "holding": status = "Hold still — %.1f seconds remaining." % (3.0-capture.elapsed)
			else: status = "Show the yoke tag and hold it upright to start."
		return
	if complete():
		status = "Controls ready — starting flight..." if ready_pose(v) else "Centre the yoke, set 0% throttle and cover the gun tag."
		if not ready_pose(v): ready_ms = 0; can_start = false
	elif focus()=="throttle" and v.throttle_confidence <= .4:
		status = "Show the throttle handle tag and both end tags."
	elif step()[0]=="yoke_info":
		status = "No movement needed — gun checks follow automatically."
	elif focus()=="yoke" and not v.tracking:
		status = "Show the yoke tag and hold the yoke still so it can centre."
	else:
		status = "Hold that position..." if held_ms > 0 else "Follow the instruction above."
	if passed:
		feedback += clampf(dt, 0, .1)
		status = "Next: gun checks" if step()[0]=="yoke_info" else "CHECK PASSED"
		if feedback >= FEEDBACK_SECONDS:
			index += 1
			retry()
		return
	if v.sequence == last_sequence: return
	var interval := v.last_received-last_sample if last_sample >= 0 and v.sequence > last_sequence else 0
	last_sequence = v.sequence; last_sample = v.last_received
	if interval < 0 or interval >= 150:
		held_ms = 0; ready_ms = 0; interval = 0
	if complete():
		ready_ms = ready_ms+interval if ready_pose(v) else 0
		can_start = ready_ms >= READY_HOLD_MS
		return
	# Allow time to read the finger placements before the first shooting check.
	var read_seconds := 4.0 if step()[0] == "grip" else 0.0 if step()[0]=="yoke_info" else READ_SECONDS
	if age < read_seconds or not matches(v):
		held_ms = 0
		return
	held_ms += interval
	if held_ms >= (OVERVIEW_MS if step()[0]=="yoke_info" else HOLD_MS):
		passed = true; feedback = 0
