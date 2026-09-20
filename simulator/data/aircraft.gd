extends RefCounted
class_name AircraftCatalog
const Tune = preload("res://data/balance.gd")
## One fictional airframe. Numerical tuning is for this game, not a real aircraft.
const PROFILE: Dictionary = {
	"id":"f35", "name":"SPECTRE X-26", "short":"X-26", "maker":"SPECTRE FLIGHT SYSTEMS",
	"type":"NEXT-GENERATION INTERCEPTOR", "tag":"CONTROL THE SKY.",
	"description":"A single airframe. A permanent combat loadout.\nPrecision, momentum and pilot judgment.",
	"span":12.6, "length":17.4, "engines":1,
	"rotation_speed":Tune.ROTATION_SPEED, "max_speed":Tune.MAX_SPEED, "acceleration":Tune.BASE_ACCELERATION,
	"roll_rate":Tune.ROLL_RATE, "pitch_rate":Tune.PITCH_RATE, "clearance":3.0,
	"color":Color(0.22,0.27,0.31), "label":"CANNON / GUIDED MISSILES"
}
const PLANES: Array[Dictionary] = [PROFILE]
