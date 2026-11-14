class_name UnderlineButton

extends Button

## Michroma text button with a 1 px underline that grows in 0.35 s. Hover and keyboard/gamepad
## focus drive the same state, so they look identical. Used for the main menu, pause menu and
## console tabs. Style comes from the theme variation (UnderlineButtonMenu / UnderlineButton /
## UnderlineButtonPrimary in res/ui_theme_v2.tres).

const GROW_TIME: float = 0.35
## Gap between the text baseline area and the bottom of the button (6 px in the design, x 1.2)
const BOTTOM_GAP: float = 7.0
const UNDERLINE_HEIGHT: float = 1.0

## Pause and centred menus grow from the middle, main menu and console tabs from the left
@export var grow_from_centre: bool = false
## Share of the text width the underline already has at rest (0.25 for the Loading CONTINUE button)
@export_range(0.0, 1.0) var rest_fraction: float = 0.0
## An active tab keeps the full underline and the bright text colour
@export var active: bool = false:
	set(value):
		active = value
		if is_node_ready():
			_refresh(true)

var _underline: ColorRect
var _fraction: float = 0.0
var _hovered: bool = false
var _tween: Tween


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	flat = true
	theme_type_variation = &"UnderlineButton"
	alignment = HORIZONTAL_ALIGNMENT_CENTER if grow_from_centre else HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size.y = 53.0
	_underline = ColorRect.new()
	_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underline.show_behind_parent = false
	add_child(_underline, false, Node.INTERNAL_MODE_FRONT)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	alignment = HORIZONTAL_ALIGNMENT_CENTER if grow_from_centre else HORIZONTAL_ALIGNMENT_LEFT
	_underline.color = get_theme_color(&"text", &"UIColor")
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	focus_entered.connect(_refresh.bind(false))
	focus_exited.connect(_refresh.bind(false))
	resized.connect(_layout_underline)
	# Redrawn on text / theme changes, which the underline width follows
	draw.connect(_layout_underline)
	_fraction = _target_fraction()
	_layout_underline()


func _on_hover(hovered: bool) -> void:
	_hovered = hovered
	_refresh(false)


func _target_fraction() -> float:
	if disabled:
		return rest_fraction
	if active or _hovered or has_focus():
		return 1.0
	return rest_fraction


func _refresh(instant: bool) -> void:
	if active:
		add_theme_color_override(&"font_color", get_theme_color(&"text", &"UIColor"))
	else:
		remove_theme_color_override(&"font_color")
	var target: float = _target_fraction()
	if _tween:
		_tween.kill()
	if instant:
		_fraction = target
		_layout_underline()
		return
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(_set_fraction, _fraction, target, GROW_TIME)


func _set_fraction(value: float) -> void:
	_fraction = value
	_layout_underline()


## Underline spans the text, not the whole button, minus the trailing letter-spacing
func _text_width() -> float:
	var font: Font = get_theme_font(&"font")
	var font_size: int = get_theme_font_size(&"font_size")
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if font is FontVariation:
		width -= (font as FontVariation).spacing_glyph
	return maxf(width, 0.0)


func _layout_underline() -> void:
	var full: float = _text_width()
	var width: float = full * _fraction
	var x: float = 0.0
	if grow_from_centre:
		x = (size.x - full) / 2.0 + (full - width) / 2.0
	_underline.position = Vector2(x, size.y - BOTTOM_GAP - UNDERLINE_HEIGHT)
	_underline.size = Vector2(width, UNDERLINE_HEIGHT)
