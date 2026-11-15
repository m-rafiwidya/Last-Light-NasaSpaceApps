class_name EvaHud

extends VBoxContainer

## The suit's oxygen on the on-foot HUD (top right): "O2 78%  ·  about 15 min left" while the player
## is outside or the suit isn't full, the low / critical warning (text, red, naming the way home), a
## short notice (a refused pickup, the oxygen recovery) and the stranded-Kite alert. Shows nothing in
## levels without an EvaRescue (the group "eva_rescue").

var oxygen_label := Label.new()
var warning_label := Label.new()
var notice_label := Label.new()
var alert_label := Label.new()


func _init() -> void:
	name = "EvaHud"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -560.0
	offset_right = -48.0
	offset_top = 100.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://res/ui_theme_v2.tres")
	for item in [[oxygen_label, &"LabelHudObjective"], [warning_label, &"LabelHudWarning"],
			[notice_label, &"LabelHudStep"], [alert_label, &"LabelHudAlert"]]:
		var label: Label = item[0]
		label.theme_type_variation = item[1]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 512.0
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
	hide()


func _process(_delta: float) -> void:
	var eva := get_tree().get_first_node_in_group(&"eva_rescue") as EvaRescue
	if eva == null:
		hide()
		return
	var outside: bool = eva.on_eva()
	oxygen_label.text = eva.hud_text() if outside or eva.fraction() < 0.999 else ""
	warning_label.text = eva.warning_text()
	notice_label.text = eva.notice()
	var director := eva.director
	alert_label.text = director.alert if director != null and director.stranded else ""
	for label in [oxygen_label, warning_label, notice_label, alert_label]:
		label.visible = label.text != ""
	visible = oxygen_label.visible or warning_label.visible or notice_label.visible or alert_label.visible
