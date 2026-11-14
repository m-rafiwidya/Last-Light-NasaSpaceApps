class_name ScanHint

extends Label

## "SCANNING  IRIS  60%" / "SCANNED  IRIS" under the crosshair while the driven rover's mast camera
## holds on a scan target (RoverScanner).


func _init() -> void:
	name = "ScanHint"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -400.0
	offset_right = 400.0
	offset_top = 44.0
	offset_bottom = 84.0
	add_theme_font_size_override("font_size", 24)
	add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func _process(_delta: float) -> void:
	var rover: Robot = Debug.current_robot
	var scanner: RoverScanner = rover.get_node_or_null("RoverScanner") if is_instance_valid(rover) else null
	var hint: String = scanner.get_hint() if scanner else ""
	visible = hint != ""
	text = hint
