class_name PlanetTab

extends Button

## The explorer's MOON / EARTH tabs (theme type PlanetTab): mono text that brightens on hover
## and focus, a 2 px underline in the planet's colour (UIColor moon / earth) under the
## active one, and a small lock before the label while the planet is locked.

const UNDERLINE: float = 2.0
## The lock icon (12 px in the design, x 1.2) and its gap to the label
const LOCK_SIZE: float = 14.4
const LOCK_GAP: float = 9.6

var planet_color: StringName = &"moon"
var active: bool = false:
	set(value):
		active = value
		_refresh()
var locked: bool = false:
	set(value):
		locked = value
		_refresh()


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	theme_type_variation = &"PlanetTab"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	for sig in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
		sig.connect(queue_redraw)
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	# Room for the lock on the left (from the theme's style, not a previous override); the active
	# tab's text stays bright
	for state in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]:
		remove_theme_stylebox_override(state)
	var style := get_theme_stylebox(&"normal").duplicate() as StyleBox
	style.content_margin_left += (LOCK_SIZE + LOCK_GAP) if locked else 0.0
	for state in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]:
		add_theme_stylebox_override(state, style)
	if active:
		add_theme_color_override(&"font_color", get_theme_color(&"text", &"UIColor"))
	elif locked:
		add_theme_color_override(&"font_color", get_theme_color(&"disabled", &"UIColor"))
	else:
		remove_theme_color_override(&"font_color")
	queue_redraw()


func _draw() -> void:
	if active:
		draw_rect(Rect2(0.0, size.y - UNDERLINE, size.x, UNDERLINE), get_theme_color(planet_color, &"UIColor"))
	if locked:
		var lit: bool = is_hovered() or has_focus() or active
		var color: Color = get_theme_color(&"text" if lit else &"disabled", &"UIColor")
		var left: float = get_theme_stylebox(&"normal").content_margin_left - LOCK_SIZE - LOCK_GAP
		draw_lock(self, Vector2(left + LOCK_SIZE / 2.0, size.y / 2.0), LOCK_SIZE, color, 2.0 * LOCK_SIZE / 24.0)


## The board's lock icon (24 px viewBox: body 14 x 10 at (5, 11), shackle from y 11 up to a
## radius-4 arch) drawn `size` px big around `centre`
static func draw_lock(item: CanvasItem, centre: Vector2, size: float, color: Color, width: float) -> void:
	var k: float = size / 24.0
	var origin: Vector2 = centre - Vector2(12.0, 12.0) * k
	item.draw_rect(Rect2(origin + Vector2(5.0, 11.0) * k, Vector2(14.0, 10.0) * k), color, false, width, true)
	var arch: Vector2 = origin + Vector2(12.0, 8.0) * k
	item.draw_arc(arch, 4.0 * k, PI, TAU, 16, color, width, true)
	item.draw_line(origin + Vector2(8.0, 8.0) * k, origin + Vector2(8.0, 11.0) * k, color, width, true)
	item.draw_line(origin + Vector2(16.0, 8.0) * k, origin + Vector2(16.0, 11.0) * k, color, width, true)
