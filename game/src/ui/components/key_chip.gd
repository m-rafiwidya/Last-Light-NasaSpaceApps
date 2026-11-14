class_name KeyChip

extends HBoxContainer

## Small light parallelogram with a key name, followed by the action label ("Esc Cancel",
## "E Insert module"). The key comes from the InputMap for `action`, so rebinding is reflected.
## Not focusable: it is a hint, not a control.

const KEY_NAMES: Dictionary = {
	"Escape": "Esc",
	"Enter": "Enter",
	"Kp Enter": "Enter",
	"Space": "Space",
	"Left Mouse Button": "LMB",
	"Right Mouse Button": "RMB",
	"Middle Mouse Button": "MMB",
}

@export var action: StringName = &"":
	set(value):
		action = value
		refresh()
## Label after the chip, e.g. "Cancel"
@export var label_text: String = "":
	set(value):
		label_text = value
		refresh()
## Shown when `action` is empty or has no binding
@export var fallback_key: String = ""

var _chip: PanelContainer
var _key_label: Label
var _action_label: Label


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 12)
	_chip = PanelContainer.new()
	_chip.theme_type_variation = &"KeyChipPanel"
	_chip.custom_minimum_size = Vector2(26.4, 26.4)
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key_label = Label.new()
	_key_label.theme_type_variation = &"LabelKeyChip"
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_chip.add_child(_key_label)
	add_child(_chip)
	_action_label = Label.new()
	_action_label.theme_type_variation = &"LabelKeyAction"
	_action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_action_label)
	alignment = BoxContainer.ALIGNMENT_CENTER


func _ready() -> void:
	visibility_changed.connect(refresh)
	refresh()


## Re-reads the binding; call it after the player rebinds the action
func refresh() -> void:
	if _key_label == null:
		return
	_key_label.text = key_text()
	_action_label.text = label_text
	_action_label.visible = label_text != ""


func key_text() -> String:
	if action != &"" and InputMap.has_action(action):
		var chosen: InputEvent = null
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				chosen = event
				break
			if chosen == null:
				chosen = event
		if chosen != null:
			return _event_text(chosen)
	return fallback_key


func _event_text(event: InputEvent) -> String:
	var text: String
	if event is InputEventKey:
		var key := event as InputEventKey
		var code: Key = key.physical_keycode if key.keycode == KEY_NONE else key.keycode
		if key.keycode == KEY_NONE and key.physical_keycode != KEY_NONE \
				and DisplayServer.get_name() != "headless":
			# Show the label for the player's keyboard layout (WASD stays W on AZERTY)
			code = DisplayServer.keyboard_get_label_from_physical(key.physical_keycode)
		text = OS.get_keycode_string(code | key.get_modifiers_mask())
	else:
		text = event.as_text()
	return KEY_NAMES.get(text, text)
