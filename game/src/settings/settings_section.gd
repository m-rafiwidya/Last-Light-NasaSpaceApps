class_name SettingsSection

extends RefCounted

## A group of saved settings (key -> value) in one section of user://settings.cfg, for the
## settings classes (GeneralSettings, VideoSettings, ControlSettings, AudioSettings.options):
## loaded on first use, each value kept to its default's type and to its range, saved and
## announced (`changed`) when it changes, so every open settings menu can follow.
## A script driving the game (tests, tools: Godot's `-s`) starts from the defaults instead of the
## player's saved choices, so a frame cap, a slower mouse or a rebound key can't change a test;
## a test of saving sets `read_saved` and calls reload(). Saving always writes the file.

## changed(key): after `key` changed (set_value, reset)
signal changed(key: String)

const PATH: String = GraphicsSettings.PATH

## Whether load reads user://settings.cfg (false in a script run, see above)
static var read_saved: bool = not _is_script_run()

var section: String
var defaults: Dictionary
## key -> Vector2(min, max) for numbers
var ranges: Dictionary

var _values: Dictionary = {}
var _loaded: bool = false


func _init(section_name: String, section_defaults: Dictionary, value_ranges: Dictionary = {}) -> void:
	section = section_name
	defaults = section_defaults
	ranges = value_ranges


func get_value(key: String) -> Variant:
	_load()
	return _values[key]


## Sets, saves and announces one value; returns false (and does nothing) if it didn't change
func set_value(key: String, value: Variant) -> bool:
	_load()
	value = _clean(key, value)
	if _values[key] == value:
		return false
	_values[key] = value
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value(section, key, value)
	config.save(PATH)
	changed.emit(key)
	return true


## Every value back to its default (saved and announced)
func reset() -> void:
	for key in defaults:
		set_value(key, defaults[key])


## Reads the file again (tests: a launch with what was saved)
func reload() -> void:
	_loaded = false
	_load()


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	var ok: bool = read_saved and config.load(PATH) == OK
	for key in defaults:
		_values[key] = _clean(key, config.get_value(section, key, defaults[key]) if ok else defaults[key])


# The default's type (a hand-edited file can hold anything) and the key's range
func _clean(key: String, value: Variant) -> Variant:
	var default: Variant = defaults[key]
	if typeof(value) != typeof(default):
		var numbers: Array = [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]
		if typeof(value) in numbers and typeof(default) in numbers:
			value = type_convert(value, typeof(default))
		else:
			return default
	if ranges.has(key) and (value is float or value is int):
		var limits: Vector2 = ranges[key]
		value = clampf(value, limits.x, limits.y) if value is float else clampi(value, int(limits.x), int(limits.y))
	return value


static func _is_script_run() -> bool:
	var args: PackedStringArray = OS.get_cmdline_args()
	return args.has("-s") or args.has("--script")
