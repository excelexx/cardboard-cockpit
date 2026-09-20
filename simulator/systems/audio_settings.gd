extends RefCounted
const DEFAULTS := {"music":2.0,"engine":.5,"effects":.5,"voice":.5}
var music:=2.0
var engine:=.5
var effects:=.5
var voice:=.5
func set_level(channel: String,value: float)->void:
	if not DEFAULTS.has(channel):return
	set(channel,clampf(value,0,4 if channel=="music" else 2) if is_finite(value) else DEFAULTS[channel])
func reset()->void:
	for channel: String in DEFAULTS:set(channel,DEFAULTS[channel])
func load_config(config: ConfigFile)->void:
	for channel: String in DEFAULTS:
		var value: Variant=config.get_value("audio",channel,DEFAULTS[channel])
		set_level(channel,float(value) if value is float or value is int else DEFAULTS[channel])
func save_config(config: ConfigFile)->void:
	for channel: String in DEFAULTS:config.set_value("audio",channel,get(channel))
