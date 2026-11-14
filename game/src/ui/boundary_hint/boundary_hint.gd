class_name BoundaryHint

extends Label

## "Survey area boundary in 12 m": shown at the top of the HUD while the player (on foot) or the
## driven rover is within WARN_DISTANCE of the level's play boundary (a node in the
## "play_boundary" group, MoonTerrain). Nothing in levels without one.

const WARN_DISTANCE: float = 20.0

## Whose position counts: the player on foot (HUD) or the driven rover (robot HUD)
var follow_rover: bool = false


func _init(rover: bool = false) -> void:
	follow_rover = rover
	name = "BoundaryHint"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_top = 140.0
	add_theme_font_size_override("font_size", 28)
	add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func _process(_delta: float) -> void:
	var boundary: Node = get_tree().get_first_node_in_group(&"play_boundary")
	var body: Node3D = Debug.current_robot if follow_rover else GameState.player
	if boundary == null or not is_instance_valid(body):
		hide()
		return
	var distance: float = boundary.distance_to_boundary(body.global_position)
	var was_visible: bool = visible
	visible = distance < WARN_DISTANCE
	# A soft notification when the hint appears on the HUD that is showing
	if visible and not was_visible and is_visible_in_tree():
		AudioManager.play_ui(&"notification")
	if visible:
		text = "Survey area boundary in %d m" % maxi(int(distance), 0)
