class_name KeyChip

extends HBoxContainer

## Small light parallelogram with a key name, followed by the action label ("Esc Cancel",
## "E Insert module"). The key comes from the InputMap for `action` (InputBindings.action_text),
## and the chip follows rebinding (InputBindings.events.changed).
## Not focusable: it is a hint, not a control.

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
	InputBindings.events.changed.connect(refresh)
	refresh()


## Re-reads the binding; call it after the player rebinds the action
func refresh() -> void:
	if _key_label == null:
		return
	_key_label.text = key_text()
	_action_label.text = label_text
	_action_label.visible = label_text != ""


func key_text() -> String:
	return InputBindings.action_text(action, fallback_key) if action != &"" else fallback_key
