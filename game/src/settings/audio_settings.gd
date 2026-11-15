class_name AudioSettings

extends RefCounted

## Volume settings (0-100 %) of the audio buses, kept in user://settings.cfg (section "audio") next
## to GraphicsSettings. AudioManager applies them at start and is the one place that changes them
## (AudioManager.set_volume), so every open settings menu can follow.
## `options` holds the other audio setting, mute_when_unfocused: while the window isn't focused
## AudioManager mutes Master (set_focus_muted) and unmutes it when focus comes back.
## A script run (tests, tools) never touches the player's audio settings: it starts from DEFAULTS
## (reading saved ones only when SettingsSection.read_saved is set, as the other sections) and
## keeps what it saves in TEST_PATH.

const PATH: String = GraphicsSettings.PATH
const TEST_PATH: String = "user://settings_test.cfg"
const SECTION: String = "audio"
## Setting key -> bus it controls
## (effects: the gameplay sounds; the Ambience bus sends to SFX, so it follows too)
## (voice: DialogServer's spoken lines)
const BUSES: Dictionary = {"master": &"Master", "music": &"Music", "effects": &"SFX", "voice": &"Voice", "interface": &"UI"}
## Setting key -> default percent (the settings menu's original defaults)
const DEFAULTS: Dictionary = {"master": 80.0, "music": 70.0, "effects": 80.0, "voice": 90.0, "interface": 50.0}

## The file the audio settings live in (TEST_PATH in a script run)
static var path: String = TEST_PATH if SettingsSection._is_script_run() else PATH
static var options := _make_options()

static var _percent: Dictionary = {}
static var _loaded: bool = false
## Master is muted because the window lost focus (see options)
static var _focus_muted: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	var ok: bool = SettingsSection.read_saved and config.load(path) == OK
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
	config.load(path)
	config.set_value(SECTION, key, _percent[key])
	config.save(path)


static func _make_options() -> SettingsSection:
	var section := SettingsSection.new(SECTION, {"mute_when_unfocused": true})
	section.path = path
	return section


static func mute_when_unfocused() -> bool:
	return options.get_value("mute_when_unfocused")


## Mutes Master while the window is unfocused (AudioManager), whatever its volume
static func set_focus_muted(muted: bool) -> void:
	load_settings()
	_focus_muted = muted
	_apply_bus("master")


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
	AudioServer.set_bus_mute(index, percent <= 0.0 or (key == "master" and _focus_muted))
