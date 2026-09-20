extends RefCounted

const DEFAULT_AGILITY := 1.3
const DEFAULT_AUTO_AIM := 1.4
const MIN_AGILITY := .5
const MAX_AGILITY := 3.0
const MAX_AUTO_AIM := 3.0

var pitch_agility: float = DEFAULT_AGILITY:
	set(value): pitch_agility = clampf(value,MIN_AGILITY,MAX_AGILITY) if is_finite(value) else DEFAULT_AGILITY
var bank_agility: float = DEFAULT_AGILITY:
	set(value): bank_agility = clampf(value,MIN_AGILITY,MAX_AGILITY) if is_finite(value) else DEFAULT_AGILITY
var yaw_agility: float = DEFAULT_AGILITY:
	set(value): yaw_agility = clampf(value,MIN_AGILITY,MAX_AGILITY) if is_finite(value) else DEFAULT_AGILITY
var auto_aim: float = DEFAULT_AUTO_AIM:
	set(value): auto_aim = clampf(value,0,MAX_AUTO_AIM) if is_finite(value) else DEFAULT_AUTO_AIM

func reset() -> void:
	pitch_agility = DEFAULT_AGILITY
	bank_agility = DEFAULT_AGILITY
	yaw_agility = DEFAULT_AGILITY
	auto_aim = DEFAULT_AUTO_AIM

func load_config(config: ConfigFile) -> void:
	# Migrate the previous shared slider without changing the pilot's preference.
	var legacy: Variant = config.get_value("gameplay","agility",DEFAULT_AGILITY)
	for axis: String in ["pitch","bank","yaw"]:
		var value: Variant = config.get_value("gameplay",axis+"_agility",legacy)
		set(axis+"_agility",float(value) if value is float or value is int else DEFAULT_AGILITY)
	var aim: Variant = config.get_value("gameplay","auto_aim",DEFAULT_AUTO_AIM)
	auto_aim = float(aim) if aim is float or aim is int else DEFAULT_AUTO_AIM

func save_config(config: ConfigFile) -> void:
	for axis: String in ["pitch","bank","yaw"]:
		config.set_value("gameplay",axis+"_agility",get(axis+"_agility"))
	if config.has_section_key("gameplay","agility"): config.erase_section_key("gameplay","agility")
	config.set_value("gameplay","auto_aim",auto_aim)
