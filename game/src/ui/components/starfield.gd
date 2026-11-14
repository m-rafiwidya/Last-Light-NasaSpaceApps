class_name Starfield

extends Control

## Static starfield on the `bg` colour: seeded, so it looks the same every time. About 560 stars
## per 1600 x 900 (the density of the design boards), scaled with the area.

const SEED: int = 42
const STARS_PER_DESIGN_AREA: float = 560.0 / (1600.0 * 900.0)
const SCALE: float = 1.2


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), get_theme_color(&"bg", &"UIColor"))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var count: int = roundi(size.x * size.y * STARS_PER_DESIGN_AREA / (SCALE * SCALE))
	var base: Color = get_theme_color(&"text", &"UIColor")
	for i in count:
		var pos := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var m: float = rng.randf()
		var radius: float = (1.6 if m > 0.985 else 1.1 if m > 0.9 else 0.7) * SCALE
		var alpha: float = 0.25 + rng.randf() * 0.65
		var hue: float = rng.randf()
		var color: Color = base
		if hue > 0.85:
			color = Color(190.0 / 255.0, 210.0 / 255.0, 1.0)
		elif hue < 0.12:
			color = Color(1.0, 225.0 / 255.0, 190.0 / 255.0)
		color.a = alpha
		draw_circle(pos, radius, color)
