class_name MissionHint

extends PanelContainer
## The rover HUD's objective, step, stuck hint and battery / return alerts, top-left, in the v2 style
## (GuidanceOverlay.UI_THEME): Exo 2 light text on a dark backing, red only for alerts.

var objective_label := Label.new()
var step_label := Label.new()
var stuck_label := Label.new()
var return_label := Label.new()
var alert_label := Label.new()
var _warned: bool = false


func _init() -> void:
	name = "MissionHint"
	theme = GuidanceOverlay.UI_THEME
	theme_type_variation = &"HudBacking"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 64.0
	offset_top = 100.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	for item in [[objective_label, &"LabelHudObjective"], [step_label, &"LabelHudStep"], [stuck_label, &"LabelHudStuck"],
			[return_label, &"LabelHudObjective"], [alert_label, &"LabelHudAlert"]]:
		var label: Label = item[0]
		label.theme_type_variation = item[1]
		column.add_child(label)
	stuck_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stuck_label.custom_minimum_size.x = 560.0


func _process(_delta: float) -> void:
	var objective := CampaignState.current_objective()
	objective_label.text = ("OBJECTIVE  " + CampaignState.objective_title(objective)) if objective else ""
	var guidance := get_tree().get_first_node_in_group(&"guidance") as Guidance
	var guided := guidance != null and Guidance.enabled()
	step_label.text = guidance.step_text() if guided else ""
	stuck_label.text = guidance.stuck_text() if guided else ""
	var director := get_tree().get_first_node_in_group(&"mission_director") as MissionDirector
	var rover: Robot = Debug.current_robot
	return_label.text = ""
	alert_label.text = ""
	var warn := false
	if director and is_instance_valid(rover) and rover == director.rover:
		alert_label.text = director.alert
		if rover.battery and not director.pad.is_in_zone(rover) and not director.recovering:
			var needed: int = ceili(director.return_fraction_needed() * 100.0)
			warn = director.return_warning()
			return_label.text = "%sRETURN  ~%d%% needed, %d m to the pad" % [
				"LOW BATTERY: RETURN TO BASE   " if warn else "", needed, roundi(director.distance_to_pad())]
	if warn:
		return_label.add_theme_color_override("font_color", GuidanceOverlay.ui_color(&"warn"))
	else:
		return_label.remove_theme_color_override("font_color")
	for label in [objective_label, step_label, stuck_label, return_label, alert_label]:
		label.visible = label.text != ""
	visible = objective_label.visible or step_label.visible or stuck_label.visible or return_label.visible or alert_label.visible
	if warn and not _warned and is_visible_in_tree():
		AudioManager.play_ui(&"notification")
	_warned = warn
