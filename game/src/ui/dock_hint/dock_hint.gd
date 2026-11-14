class_name DockHint

extends Label

## "Charging pad: 0.8 m ahead, 0.3 m to the right" / "Stop here to charge" / "Charging 63%":
## shown on the robot HUD while the driven rover is near a workshop's charging pad (a node in the
## "charging_pad" group, ChargingPad). Below the boundary hint.


func _init() -> void:
	name = "DockHint"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_top = 190.0
	add_theme_font_size_override("font_size", 28)
	add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func _process(_delta: float) -> void:
	var rover: Robot = Debug.current_robot
	var hint := ""
	if is_instance_valid(rover):
		for pad in get_tree().get_nodes_in_group(&"charging_pad"):
			hint = pad.get_dock_hint(rover)
			if hint != "":
				break
	var was_visible: bool = visible
	visible = hint != ""
	text = hint
	# The same soft notification as the boundary hint when it appears on the HUD that is showing
	if visible and not was_visible and is_visible_in_tree():
		AudioManager.play_ui(&"notification")
