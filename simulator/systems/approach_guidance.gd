extends RefCounted
class_name ApproachGuidance

const AIM_Z: float = -14100.0
const GLIDESLOPE: float = 0.05241 # Three-degree geometric path for the demo.

static func solution(position: Vector3) -> Dictionary:
	var remaining: float = maxf(position.z-AIM_Z,0.0)
	var height: float = maxf(3.0,3.0+remaining*GLIDESLOPE)
	return {
		"distance":remaining,
		"ideal_height":height,
		"localizer":clampf(-position.x/180.0,-1.0,1.0),
		"glideslope":clampf((height-position.y)/75.0,-1.0,1.0),
		"center_error":position.x,
		"height_error":position.y-height,
		"on_path":absf(position.x)<40.0 and absf(position.y-height)<25.0
	}
