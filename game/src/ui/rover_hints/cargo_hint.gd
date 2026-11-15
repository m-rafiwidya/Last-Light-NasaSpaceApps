class_name CargoHint

extends Label

## The driven rover's cargo delivery hint (CargoDelivery.get_hint(): "IRIS's port: 0.30 m closer",
## "In position: press E to insert the cartridge", ...), on the robot HUD under the dock hint.


func _init() -> void:
	name = "CargoHint"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_top = 240.0
	theme = preload("res://res/ui_theme_v2.tres")
	theme_type_variation = &"LabelHudPrompt"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func _process(_delta: float) -> void:
	var rover: Robot = Debug.current_robot
	var delivery: CargoDelivery = rover.get_node_or_null("CargoDelivery") if is_instance_valid(rover) else null
	var hint: String = delivery.get_hint() if delivery else ""
	var was_visible: bool = visible
	visible = hint != ""
	text = InputBindings.with_current_keys(hint)
	if visible and not was_visible and is_visible_in_tree():
		AudioManager.play_ui(&"notification")
