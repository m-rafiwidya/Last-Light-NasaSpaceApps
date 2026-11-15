class_name GuidanceOverlay

extends CanvasLayer

## The v2 theme (docs/ui/UI_SPEC.md): Exo 2 text, colour tokens on "UIColor"
const UI_THEME: Theme = preload("res://res/ui_theme_v2.tres")
## Dark backing behind text and marker shapes, so light text reads over bright terrain
const BACKING := Color(0.0, 0.0, 0.0, 0.55)
const EDGE_MARGIN: float = 72.0
const MARKER_SIZE: float = 14.0
const MARKER_LIFT: float = 1.5
const LABEL_PAD: float = 8.0

var guidance: Guidance = null
var tracker := PanelContainer.new()
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
	tracker.theme = UI_THEME
	tracker.theme_type_variation = &"HudBacking"
	tracker.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	tracker.offset_left = 64.0
	tracker.offset_top = 100.0
	tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracker.add_child(column)
	for item in [[objective_label, &"LabelHudObjective"], [step_label, &"LabelHudStep"], [stuck_label, &"LabelHudStuck"]]:
		var label: Label = item[0]
		label.theme_type_variation = item[1]
		column.add_child(label)
	stuck_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stuck_label.custom_minimum_size.x = 560.0
	add_child(tracker)
	marker.name = "Waypoint"
	marker.theme = UI_THEME
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
	tracker.visible = state == GameState.State.IN_GAME_PLAYER and (objective_label.visible or step_label.visible or stuck_label.visible)
	var walking: bool = state == GameState.State.IN_GAME_PLAYER and guidance.current_step().get("on_foot", false)
	marker.visible = on and (state == GameState.State.IN_GAME_ROBOT or walking) and guidance.is_waypoint()
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
	var from: Node3D = GameState.robot if GameState.state == GameState.State.IN_GAME_ROBOT else GameState.player
	if is_instance_valid(from) and is_instance_valid(guidance.target):
		var offset := guidance.target.global_position - from.global_position
		offset.y = 0.0
		distance = offset.length()
	return "%s  %d m" % [guidance.current_step().get("label", ""), roundi(distance)]


## Horizontal shift that brings the label box `back` inside a viewport `width` wide
static func label_shift(back: Rect2, width: float) -> float:
	return maxf(LABEL_PAD - back.position.x, 0.0) - maxf(back.end.x - (width - LABEL_PAD), 0.0)


## A v2 theme colour token ("text", "warn", ...)
static func ui_color(token: StringName) -> Color:
	return UI_THEME.get_color(token, &"UIColor")


func _draw_marker() -> void:
	if not place_marker():
		return
	var font: Font = marker.get_theme_font(&"font", &"LabelHudWorld")
	var font_size: int = marker.get_theme_font_size(&"font_size", &"LabelHudWorld")
	var light: Color = ui_color(&"text")
	var text := marker_text()
	var at := marker_position
	var label_at: Vector2
	if marker_on_screen:
		var r := MARKER_SIZE
		_draw_shape(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), at, light)
		label_at = at + Vector2(-120, -r - 14)
	else:
		var side := marker_direction.orthogonal()
		_draw_shape(PackedVector2Array([at + marker_direction * 22.0, at + side * 14.0, at - side * 14.0]), at, light)
		label_at = at - marker_direction * 40.0 + Vector2(-120, 8)
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, 240, font_size).x
	var back := Rect2(label_at.x + (240.0 - width) * 0.5 - 8.0, label_at.y - font.get_ascent(font_size) - 3.0,
		width + 16.0, font.get_height(font_size) + 6.0)
	var dx: float = label_shift(back, marker.get_viewport_rect().size.x)
	back.position.x += dx
	label_at.x += dx
	marker.draw_rect(back, BACKING)
	marker.draw_string(font, label_at, text, HORIZONTAL_ALIGNMENT_CENTER, 240, font_size, light)


## A marker shape in `color` over the same shape grown 35 % about `center`, in the backing colour
func _draw_shape(points: PackedVector2Array, center: Vector2, color: Color) -> void:
	var grown := PackedVector2Array()
	for point in points:
		grown.append(center + (point - center) * 1.35)
	marker.draw_colored_polygon(grown, BACKING)
	marker.draw_colored_polygon(points, color)
