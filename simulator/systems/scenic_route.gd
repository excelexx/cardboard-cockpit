extends RefCounted
class_name ScenicRoute
## Authored in world metres. The same route drives guidance, encounters and tests.
const POINTS: Array[Vector3] = [
	Vector3(200,260,-2200), Vector3(1200,270,-3400),
	Vector3(1900,290,-4700), Vector3(2300,320,-5500),
	Vector3(2000,380,-6600), Vector3(1100,550,-7700),
	Vector3(-100,920,-8500), Vector3(-350,1100,-9400),
	Vector3(-150,680,-10400), Vector3(0,300,-11400),
	Vector3(0,145,-12000)
]
const NAMES: Array[String] = [
	"CITY DEPARTURE", "THE MARINA", "WATERFRONT SKYLINE",
	"DOWNTOWN FLYBY", "THE WORKING HARBOR", "SUSPENSION BRIDGE",
	"METROPOLITAN CROSSING", "CITY PANORAMA", "NORTH DISTRICTS",
	"HOMEWARD DESCENT", "CAPE NORTH APPROACH"
]
const HINTS: Array[String] = [
	"Lift off between the city districts · Follow the blue diamond",
	"Turn inland over the marina · The city is ahead",
	"Cross the waterfront rooftops · Keep following the diamond",
	"Fly above downtown · Look down through the side windows",
	"Pass the ferry terminal · Begin a gentle climb",
	"Cross above the bridge · Keep following the diamond",
	"City blocks below · Snowy peaks to the east",
	"Level out for the metropolitan panorama · Then lower the nose",
	"Descend over the north districts toward Cape North",
	"Ease off power · Keep the runway straight ahead",
	"Landing guidance takes over · H enables the copilot"
]
static func stage_for(index: int) -> int:
	return clampi(1+index/2,1,6)
