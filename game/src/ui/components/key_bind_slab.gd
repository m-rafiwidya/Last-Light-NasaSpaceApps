class_name KeyBindSlab

extends Button

## Key-bind slab (settings Controls tab): shows the bound key; a click starts listening and the
## label becomes PRESS A KEY on a darker slab. The next key press shows its name and is sent with
## `key_bound` (the settings menu rebinds the action, InputBindings, and sets the slab's key_text
## to what the action ends up with). Esc only cancels, it is never sent; so does losing focus.

signal key_bound(event: InputEventKey)

const SIZE: Vector2 = Vector2(360.0, 36.0)
const PROMPT: String = "PRESS A KEY"
var key_text: String = "":
	set(value):
		key_text = value
		if not listening:
			text = key_text
var listening: bool = false

# Process frame in which a slab last took a key press (see took_key_this_frame)
static var _key_frame: int = -1


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
	_key_frame = Engine.get_process_frames()
	if key.keycode == KEY_ESCAPE:
		_set_listening(false)
		return
	# The key itself, without the modifiers held with it (Shift alone is a key too)
	var bound := InputEventKey.new()
	bound.physical_keycode = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	key_text = InputBindings.event_text(bound)
	_set_listening(false)
	key_bound.emit(bound)


## True in the frame a listening slab took a key: actions polled with Input (the console's
## backtick) must ignore it, set_input_as_handled doesn't stop Input.is_action_just_pressed
static func took_key_this_frame() -> bool:
	return _key_frame == Engine.get_process_frames()
