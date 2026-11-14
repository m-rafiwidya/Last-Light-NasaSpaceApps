class_name MissionHint

extends VBoxContainer

const NORMAL := Color(0.85, 0.95, 1.0)
const WARN := Color(1.0, 0.4, 0.3)

var objective_label := Label.new()
var step_label := Label.new()
var stuck_label := Label.new()
var return_label := Label.new()
var alert_label := Label.new()
var _warned: bool = false


func _init() -> void:
	name = "MissionHint"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 64.0
	offset_top = 100.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for label in [objective_label, step_label, stuck_label, return_label, alert_label]:
		label.add_theme_font_size_override("font_size", 26)
		label.add_theme_color_override("font_color", NORMAL)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 6)
		add_child(label)
	step_label.add_theme_font_size_override("font_size", 28)
	step_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	stuck_label.add_theme_font_size_override("font_size", 22)
	stuck_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stuck_label.custom_minimum_size.x = 640.0
	alert_label.add_theme_font_size_override("font_size", 30)
	alert_label.add_theme_color_override("font_color", WARN)


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
	return_label.add_theme_color_override("font_color", WARN if warn else NORMAL)
	if warn and not _warned and is_visible_in_tree():
		AudioManager.play_ui(&"notification")
	_warned = warn
	for label in [objective_label, step_label, stuck_label, return_label, alert_label]:
		label.visible = label.text != ""
