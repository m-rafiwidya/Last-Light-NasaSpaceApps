class_name BatteryBar

extends Control
## Segmented battery bar (UI_SPEC component 10): thin slanted segments, filled `text`, empty
## `line_3`; `warn` fills it while low.

const SEGMENTS: int = 10
const SEGMENT: Vector2 = Vector2(17.0, 10.0)
const SEGMENT_COMPACT: float = 12.0
const SLANT: float = 3.6
const GAP: float = 3.6

var fraction: float = 0.0:
	set(value):
		fraction = clampf(value, 0.0, 1.0)
		queue_redraw()
## Narrower segments (the rover stats on a narrow screen)
var compact: bool = false:
	set(value):
		compact = value
		custom_minimum_size.x = SEGMENTS * _segment_width() + (SEGMENTS - 1) * GAP
		queue_redraw()
var low: bool = false:
	set(value):
		low = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SEGMENTS * SEGMENT.x + (SEGMENTS - 1) * GAP, SEGMENT.y)


func _draw() -> void:
	var on: Color = get_theme_color(&"warn" if low else &"text", &"UIColor")
	var off: Color = get_theme_color(&"line_3", &"UIColor")
	var filled: int = ceili(fraction * SEGMENTS - 0.001)
	var top: float = (size.y - SEGMENT.y) / 2.0
	var w: float = _segment_width()
	for i in SEGMENTS:
		var x: float = i * (w + GAP)
		draw_colored_polygon(PackedVector2Array([Vector2(x + SLANT, top), Vector2(x + w, top),
			Vector2(x + w - SLANT, top + SEGMENT.y), Vector2(x, top + SEGMENT.y)]), on if i < filled else off)


func _segment_width() -> float:
	return SEGMENT_COMPACT if compact else SEGMENT.x
