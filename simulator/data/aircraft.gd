extends RefCounted
class_name AircraftCatalog
## One fictional airframe. Numerical tuning is for this game, not a real aircraft.
const PROFILE: Dictionary = {
	"id":"f35", "name":"SPECTRE X-26", "short":"X-26", "maker":"SPECTRE FLIGHT SYSTEMS",
	"type":"NEXT-GENERATION INTERCEPTOR", "tag":"CONTROL THE SKY.",
	"description":"A single airframe. A permanent combat loadout.\nPrecision, momentum and pilot judgment.",
	"span":12.6, "length":17.4, "engines":1,
	"rotation_speed":56.0, "max_speed":430.0, "acceleration":29.0,
	"roll_rate":3.15, "pitch_rate":1.02, "clearance":3.0,
	"color":Color(0.22,0.27,0.31), "label":"CANNON / GUIDED MISSILES"
}
const PLANES: Array[Dictionary] = [PROFILE]
