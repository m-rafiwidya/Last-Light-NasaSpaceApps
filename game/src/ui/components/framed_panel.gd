class_name FramedPanel

extends PanelContainer

## Popup frame / save card. Selected: 78 % black, light 1 px border, soft glow and four corner
## brackets outside the frame. Unselected: dark 1 px border, no brackets.
## For a focusable card set `select_on_focus` (hover and keyboard/gamepad focus select it).

const BRACKET_LENGTH: float = 11.0
const BRACKET_THICKNESS: float = 2.4
const BRACKET_OFFSET: float = 5.0

@export var selected: bool = true:
	set(value):
		selected = value
		_apply_style()
## Hover/focus drive `selected`, and the panel takes focus (cards in a list)
@export var select_on_focus: bool = false:
	set(value):
		select_on_focus = value
		focus_mode = Control.FOCUS_ALL if value else Control.FOCUS_NONE
		if is_node_ready():
			_sync_from_input()

var _hovered: bool = false


func _init() -> void:
	# Cards are focus targets; a plain popup frame is not, so it only gets focus when asked to
	focus_mode = Control.FOCUS_ALL if select_on_focus else Control.FOCUS_NONE
	_apply_style()


func _ready() -> void:
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	focus_entered.connect(_sync_from_input)
	focus_exited.connect(_sync_from_input)
	_apply_style()


func _on_hover(hovered: bool) -> void:
	_hovered = hovered
	_sync_from_input()


func _sync_from_input() -> void:
	if select_on_focus:
		selected = _hovered or has_focus()


func _apply_style() -> void:
	theme_type_variation = &"FramedPanel" if selected else &"CardPanel"
	queue_redraw()


func _draw() -> void:
	if not selected:
		return
	var color: Color = get_theme_color(&"text", &"UIColor")
	var o: float = BRACKET_OFFSET
	var l: float = BRACKET_LENGTH
	var t: float = BRACKET_THICKNESS
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		# Corner point outside the frame, and the direction the two arms run (inward)
		var origin: Vector2 = r.position + r.size * corner + Vector2(
			-o if corner.x == 0 else o, -o if corner.y == 0 else o)
		var dx: float = 1.0 if corner.x == 0 else -1.0
		var dy: float = 1.0 if corner.y == 0 else -1.0
		draw_rect(_arm(origin, Vector2(dx * l, dy * t)), color)
		draw_rect(_arm(origin, Vector2(dx * t, dy * l)), color)


func _arm(origin: Vector2, extent: Vector2) -> Rect2:
	return Rect2(origin, extent).abs()
