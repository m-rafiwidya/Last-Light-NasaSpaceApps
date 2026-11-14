class_name GuidanceOverlay

extends CanvasLayer

const NORMAL := Color(0.85, 0.95, 1.0)
const ACCENT := Color(1.0, 0.8, 0.35)
const STUCK := Color(0.75, 0.85, 0.9)
const EDGE_MARGIN: float = 72.0
const MARKER_SIZE: float = 14.0
const MARKER_LIFT: float = 1.5

var guidance: Guidance = null
var tracker := VBoxContainer.new()
var objective_label := Label.new()
var step_label := Label.new()
var stuck_label := Label.new()
var marker := Control.new()
var marker_on_screen: bool = false
var marker_position: Vector2 = Vector2.ZERO
var marker_direction: Vector2 = Vector2.ZERO


func _init() -> void:
	name = "GuidanceOverlay"
	layer = 2
	tracker.name = "Tracker"
	tracker.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	tracker.offset_left = 64.0
	tracker.offset_top = 100.0
	tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for item in [[objective_label, 26, NORMAL], [step_label, 28, ACCENT], [stuck_label, 22, STUCK]]:
		var label: Label = item[0]
		label.add_theme_font_size_override("font_size", item[1])
		label.add_theme_color_override("font_color", item[2])
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 6)
		tracker.add_child(label)
	stuck_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stuck_label.custom_minimum_size.x = 640.0
	add_child(tracker)
	marker.name = "Waypoint"
	marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.draw.connect(_draw_marker)
	add_child(marker)


func _process(_delta: float) -> void:
	var state := GameState.state
	var objective := CampaignState.current_objective()
	objective_label.text = ("OBJECTIVE  " + CampaignState.objective_title(objective)) if objective else ""
	var on := Guidance.enabled() and guidance != null
	step_label.text = guidance.step_text() if on else ""
	stuck_label.text = guidance.stuck_text() if on else ""
	for label in [objective_label, step_label, stuck_label]:
		label.visible = label.text != ""
	tracker.visible = state == GameState.State.IN_GAME_PLAYER
	marker.visible = on and state == GameState.State.IN_GAME_ROBOT and guidance.is_waypoint()
	if marker.visible:
		marker.queue_redraw()


func place_marker() -> bool:
	var camera := marker.get_viewport().get_camera_3d()
	var target := guidance.target if guidance and is_instance_valid(guidance.target) else null
	if camera == null or target == null:
		return false
	var point: Vector3 = target.global_position + Vector3.UP * MARKER_LIFT
	var size: Vector2 = marker.get_viewport_rect().size
	var center := size * 0.5
	var inner := Rect2(Vector2.ONE * EDGE_MARGIN, size - Vector2.ONE * EDGE_MARGIN * 2.0)
	var behind := camera.is_position_behind(point)
	var screen := camera.unproject_position(point)
	if behind:
		screen = center - (screen - center)
	marker_on_screen = not behind and inner.has_point(screen)
	if marker_on_screen:
		marker_position = screen
		marker_direction = Vector2.ZERO
		return true
	marker_direction = (screen - center).normalized()
	if marker_direction == Vector2.ZERO:
		marker_direction = Vector2.DOWN
	var half := inner.size * 0.5
	var reach := minf(half.x / maxf(absf(marker_direction.x), 0.001), half.y / maxf(absf(marker_direction.y), 0.001))
	marker_position = center + marker_direction * reach
	return true


func marker_text() -> String:
	var distance: float = 0.0
	var rover: Robot = GameState.robot
	if is_instance_valid(rover) and is_instance_valid(guidance.target):
		var offset := guidance.target.global_position - rover.global_position
		offset.y = 0.0
		distance = offset.length()
	return "%s  %d m" % [guidance.current_step().get("label", ""), roundi(distance)]


func _draw_marker() -> void:
	if not place_marker():
		return
	var font := ThemeDB.fallback_font
	var text := marker_text()
	var at := marker_position
	var label_at: Vector2
	if marker_on_screen:
		var r := MARKER_SIZE
		marker.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), ACCENT)
		label_at = at + Vector2(-120, -r - 10)
	else:
		var side := marker_direction.orthogonal()
		marker.draw_colored_polygon(PackedVector2Array([at + marker_direction * 22.0, at + side * 14.0, at - side * 14.0]), ACCENT)
		label_at = at - marker_direction * 40.0 + Vector2(-120, 8)
	marker.draw_string_outline(font, label_at, text, HORIZONTAL_ALIGNMENT_CENTER, 240, 24, 6, Color.BLACK)
	marker.draw_string(font, label_at, text, HORIZONTAL_ALIGNMENT_CENTER, 240, 24, ACCENT)
