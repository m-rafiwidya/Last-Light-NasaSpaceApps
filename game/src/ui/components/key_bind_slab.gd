class_name KeyBindSlab

extends Button

## Key-bind slab (settings Controls tab): shows the bound key; a click starts listening and the
## label becomes PRESS A KEY on a darker slab. The next key press binds it, Esc cancels, and so
## does losing focus. Only the shown name changes: nothing is rebound yet (part B).

signal key_bound(key_name: String)

const SIZE: Vector2 = Vector2(360.0, 36.0)
const PROMPT: String = "PRESS A KEY"
## Names the design shows for keys (Settings.dc.html keyName); others use the engine's name
const KEY_NAMES: Dictionary = {
	KEY_SPACE: "Space", KEY_CTRL: "Ctrl", KEY_SHIFT: "Shift", KEY_ALT: "Alt", KEY_ENTER: "Enter",
	KEY_KP_ENTER: "Enter", KEY_TAB: "Tab", KEY_BACKSPACE: "Backspace",
	KEY_UP: "Up", KEY_DOWN: "Down", KEY_LEFT: "Left", KEY_RIGHT: "Right",
}

var key_text: String = "":
	set(value):
		key_text = value
		if not listening:
			text = key_text
var listening: bool = false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	theme_type_variation = &"SettingsKeySlab"
	custom_minimum_size = SIZE


func _ready() -> void:
	pressed.connect(_on_pressed)
	focus_exited.connect(_stop_listening)


func _on_pressed() -> void:
	_set_listening(not listening)


func _set_listening(on: bool) -> void:
	listening = on
	theme_type_variation = &"SettingsKeySlabListening" if on else &"SettingsKeySlab"
	text = PROMPT if on else key_text


func _stop_listening() -> void:
	if listening:
		_set_listening(false)


## Before the GUI, so the key can't also press the focused slab again (Enter, Space) or reach
## the menu's own Esc handling
func _input(event: InputEvent) -> void:
	if not listening or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.keycode == KEY_ESCAPE:
		_set_listening(false)
		return
	key_text = key_name(key)
	_set_listening(false)
	key_bound.emit(key_text)


static func key_name(key: InputEventKey) -> String:
	var code: Key = key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	if KEY_NAMES.has(code):
		return KEY_NAMES[code]
	return OS.get_keycode_string(code)
