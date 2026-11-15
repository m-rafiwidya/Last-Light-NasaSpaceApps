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
	theme = preload("res://res/ui_theme_v2.tres")
	theme_type_variation = &"LabelHudPrompt"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func _process(_delta: float) -> void:
	var rover: Robot = Debug.current_robot
	var scanner: RoverScanner = rover.get_node_or_null("RoverScanner") if is_instance_valid(rover) else null
	var hint: String = scanner.get_hint() if scanner else ""
	visible = hint != ""
	text = hint
