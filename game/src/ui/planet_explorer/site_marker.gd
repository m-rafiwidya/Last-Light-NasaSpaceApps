class_name SiteMarker

extends Button

## A site on the explorer's globe (the board's marker x 1.324: its 580 px canvas drawn at 640 px,
## x 1.2): a soft halo, a dot with a dark outline, and a ring while its tooltip is open. Green for
## the site with a badge (Apollo 12). Hover and keyboard focus grow the halo like the selection
## does; pressing it (click, Enter) selects it. The explorer moves it over the globe every frame.

const HIT_SIZE: float = 44.0
const HALO: float = 11.9
const HALO_LIT: float = 17.2
const DOT: float = 5.3
const OUTLINE: float = 6.3
const RING: float = 22.5
const LINE: float = 2.0
const OUTLINE_COLOR: Color = Color(0.0196, 0.0196, 0.0275, 0.85)

var site: Dictionary = {}
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	flat = true
	custom_minimum_size = Vector2(HIT_SIZE, HIT_SIZE)
	size = custom_minimum_size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Empty styles: the marker draws itself, no focus box
	for style in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())


func _ready() -> void:
	tooltip_text = ""
	for sig in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
		sig.connect(queue_redraw)


## Puts the marker's centre on `at`
func place(at: Vector2) -> void:
	position = at - size / 2.0


func _draw() -> void:
	var centre: Vector2 = size / 2.0
	var special: bool = site.has("badge")
	var text: Color = get_theme_color(&"text", &"UIColor")
	var color: Color = get_theme_color(&"ok", &"UIColor") if special else text
	var lit: bool = selected or is_hovered() or has_focus()
	draw_circle(centre, HALO_LIT if lit else HALO, Color(color, 0.28 if special else 0.22))
	draw_circle(centre, DOT, color)
	draw_arc(centre, OUTLINE, 0.0, TAU, 32, OUTLINE_COLOR, LINE * 0.75, true)
	if selected:
		draw_arc(centre, RING, 0.0, TAU, 48, text, LINE * 0.75, true)
