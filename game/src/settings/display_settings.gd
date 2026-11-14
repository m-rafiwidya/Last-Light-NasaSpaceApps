class_name DisplaySettings

extends RefCounted

## The window mode (Settings > Video > Display Mode, F11 / Alt+Enter), kept in
## user://settings.cfg (section "display"). Only the window mode: the project's base resolution
## and stretch settings stay as they are, so every mode shows the same 1920 x 1080 (expanded)
## picture, scaled to the window. Going back to windowed gives the window the size picked in
## Settings > Video > Resolution (VideoSettings).

## In the order of the settings menu's options
enum Mode {
	WINDOWED,
	FULLSCREEN,   ## exclusive fullscreen (macOS: covers the screen without a new desktop)
	BORDERLESS,   ## borderless fullscreen window (macOS: the native fullscreen desktop)
}

const MODE_NAMES: Array[String] = ["Windowed", "Fullscreen", "Borderless"]
const SECTION: String = "display"

## mode_changed(mode): emitted after the mode changes (settings menus follow it)
static var events: Events = Events.new()
static var mode: Mode = Mode.WINDOWED
## The fullscreen kind F11 goes back to
static var _last_fullscreen: Mode = Mode.FULLSCREEN
static var _loaded: bool = false


class Events:
	extends RefCounted
	signal mode_changed(mode: int)


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(GraphicsSettings.PATH) == OK:
		mode = clampi(config.get_value(SECTION, "window_mode", Mode.WINDOWED), 0, Mode.size() - 1) as Mode
	if mode != Mode.WINDOWED:
		_last_fullscreen = mode


static func get_mode() -> Mode:
	load_settings()
	return mode


## Applies the saved mode (at launch). Windowed leaves the window as the project opens it.
static func apply_saved() -> void:
	load_settings()
	if mode != Mode.WINDOWED:
		_apply(mode)


## Sets, applies and saves the mode
static func set_mode(value: Mode) -> void:
	load_settings()
	mode = value
	if value != Mode.WINDOWED:
		_last_fullscreen = value
	_apply(value)
	var config := ConfigFile.new()
	config.load(GraphicsSettings.PATH)
	config.set_value(SECTION, "window_mode", int(value))
	config.save(GraphicsSettings.PATH)
	events.mode_changed.emit(int(value))


## F11 / Alt+Enter: windowed <-> the last fullscreen kind (from what the window really is, in
## case the player left fullscreen another way)
static func toggle_fullscreen() -> void:
	load_settings()
	var window_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	var is_full: bool = (window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or window_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	set_mode(Mode.WINDOWED if is_full else _last_fullscreen)


static func _apply(value: Mode) -> void:
	if DisplayServer.get_name() == "headless":
		return
	match value:
		Mode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			# Deferred: leaving fullscreen can take the window a moment
			VideoSettings.apply_resolution.call_deferred()
		Mode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		Mode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
