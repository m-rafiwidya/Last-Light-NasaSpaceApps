class_name AudioSettings

extends RefCounted

## Volume settings (0-100 %) of the audio buses that exist so far, kept in user://settings.cfg
## (section "audio") next to GraphicsSettings. AudioManager applies them at start and is the
## one place that changes them (AudioManager.set_volume), so every open settings menu can follow.

const PATH: String = GraphicsSettings.PATH
const SECTION: String = "audio"
## Setting key -> bus it controls
const BUSES: Dictionary = {"master": &"Master", "music": &"Music", "interface": &"UI"}
## Setting key -> default percent (the settings menu's original defaults)
const DEFAULTS: Dictionary = {"master": 80.0, "music": 70.0, "interface": 50.0}

static var _percent: Dictionary = {}
static var _loaded: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	var ok: bool = config.load(PATH) == OK
	for key in BUSES:
		var value: float = config.get_value(SECTION, key, DEFAULTS[key]) if ok else DEFAULTS[key]
		_percent[key] = clampf(value, 0.0, 100.0)


static func get_volume(key: String) -> float:
	load_settings()
	return _percent[key]


## Sets, applies and saves one volume
static func set_volume(key: String, percent: float) -> void:
	load_settings()
	_percent[key] = clampf(percent, 0.0, 100.0)
	_apply_bus(key)
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value(SECTION, key, _percent[key])
	config.save(PATH)


## Applies all saved volumes to their buses
static func apply() -> void:
	load_settings()
	for key in BUSES:
		_apply_bus(key)


static func _apply_bus(key: String) -> void:
	var index: int = AudioServer.get_bus_index(BUSES[key])
	if index < 0:
		push_warning("AudioSettings: no bus %s" % BUSES[key])
		return
	var percent: float = _percent[key]
	AudioServer.set_bus_volume_db(index, linear_to_db(percent / 100.0) if percent > 0.0 else -80.0)
	AudioServer.set_bus_mute(index, percent <= 0.0)
