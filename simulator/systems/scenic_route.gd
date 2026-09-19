extends RefCounted
class_name ScenicRoute
## Authored in world metres. The same route drives guidance, encounters and tests.
const POINTS: Array[Vector3] = [
	Vector3(-400,260,-2200), Vector3(150,300,-3400),
	Vector3(350,320,-4700), Vector3(250,340,-5500),
	Vector3(100,370,-6600), Vector3(-250,550,-7500),
	Vector3(-100,920,-8500), Vector3(-350,1100,-9400),
	Vector3(-150,680,-10400), Vector3(0,300,-11400),
	Vector3(0,145,-12000)
]
const NAMES: Array[String] = [
	"AZURE BAY", "THE MARINA", "WATERFRONT SKYLINE",
	"DOWNTOWN FLYBY", "THE WORKING HARBOR", "SUSPENSION BRIDGE",
	"THE ISLAND CHANNEL", "PACIFIC PANORAMA", "LIGHTHOUSE POINT",
	"HOMEWARD DESCENT", "CAPE NORTH APPROACH"
]
const HINTS: Array[String] = [
	"Lift off over the bay · Follow the blue diamond",
	"Yachts and waterfront promenades on your right",
	"Follow the coast · The skyline is just ahead",
	"Downtown on your right · Islands on your left",
	"Pass the ferry terminal · Begin a gentle climb",
	"Cross above the bridge · Keep following the diamond",
	"Wooded islands below · Snowy peaks to the east",
	"Level out for the ocean view · Then lower the nose",
	"Descend past the lighthouse toward Cape North",
	"Ease off power · Keep the runway straight ahead",
	"Landing guidance takes over · H enables the copilot"
]
static func stage_for(index: int) -> int:
	return clampi(1+index/2,1,6)
