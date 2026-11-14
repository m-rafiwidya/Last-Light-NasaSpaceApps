class_name BackButton

extends Button

## 48 px (x 1.2) square back button with a left chevron. Same component for the planet
## explorer, the Play popups and anything else that goes back. Place it at (67, 58) for the
## design's (56, 48).

const DESIGN_POSITION: Vector2 = Vector2(67.0, 58.0)
const SIZE: float = 57.6
## Chevron from the design SVG (24 viewBox drawn at 20 px, path M15 5 l-7 7 7 7), x 1.2
const CHEVRON: PackedVector2Array = [Vector2(3.0, -7.0), Vector2(-4.0, 0.0), Vector2(3.0, 7.0)]
const STROKE: float = 1.8


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	theme_type_variation = &"BackButton"
	custom_minimum_size = Vector2(SIZE, SIZE)
	flat = false


func _ready() -> void:
	for sig in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
		sig.connect(queue_redraw)


func _draw() -> void:
	var lit: bool = is_hovered() or has_focus() or button_pressed
	var color: Color = get_theme_color(&"text" if lit else &"text_3", &"UIColor")
	var centre: Vector2 = size / 2.0
	var points := PackedVector2Array()
	for p in CHEVRON:
		points.append(centre + p)
	draw_polyline(points, color, STROKE, true)
