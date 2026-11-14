class_name SlantedToggle

extends Button

## Slanted on/off switch (settings rows): 52 x 22 design px x 1.2. Off: dark track and a grey
## square knob on the left. On: light track and a dark knob on the right. The knob slides in
## 0.2 s. Focus draws a muted 2 px outline round the slab. `toggled` is the Button signal.

const SIZE: Vector2 = Vector2(62.4, 26.4)
const SLANT: float = 12.0
const KNOB: float = 14.4
const KNOB_Y: float = 6.0
const KNOB_X_OFF: float = 15.6
const KNOB_X_ON: float = 33.6
const SLIDE_TIME: float = 0.2
const OUTLINE: float = 2.4
const OUTLINE_GAP: float = 3.6

var _slide: float = 0.0
var _tween: Tween


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	toggle_mode = true
	custom_minimum_size = SIZE
	flat = true
	# Only the knob and track are drawn here; the button's own boxes stay empty
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())


func _ready() -> void:
	toggled.connect(_on_toggled)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_slide = 1.0 if button_pressed else 0.0


## Sets the state without the `toggled` signal or the slide (a reset or a value loaded from disk)
func set_on(on: bool) -> void:
	set_pressed_no_signal(on)
	if _tween:
		_tween.kill()
	_slide = 1.0 if on else 0.0
	queue_redraw()


func _on_toggled(on: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(_set_slide, _slide, 1.0 if on else 0.0, SLIDE_TIME)


func _set_slide(value: float) -> void:
	_slide = value
	queue_redraw()


func _draw() -> void:
	var off_track: Color = get_theme_color(&"line_3", &"UIColor")
	var on_track: Color = get_theme_color(&"text", &"UIColor")
	var off_knob: Color = get_theme_color(&"dim", &"UIColor")
	var on_knob: Color = get_theme_color(&"ink", &"UIColor")
	draw_colored_polygon(_slab(Vector2.ZERO, SIZE), off_track.lerp(on_track, _slide))
	var knob_at := Vector2(lerpf(KNOB_X_OFF, KNOB_X_ON, _slide), KNOB_Y)
	draw_rect(Rect2(knob_at, Vector2(KNOB, KNOB)), off_knob.lerp(on_knob, _slide))
	if has_focus():
		var gap := Vector2(OUTLINE_GAP, OUTLINE_GAP)
		var outline := _slab(-gap, SIZE + gap * 2.0)
		outline.append(outline[0])
		draw_polyline(outline, get_theme_color(&"muted", &"UIColor"), OUTLINE)


## The parallelogram of the design's clip-path: top edge shifted right by SLANT
func _slab(at: Vector2, extent: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		at + Vector2(SLANT, 0.0), at + Vector2(extent.x, 0.0),
		at + Vector2(extent.x - SLANT, extent.y), at + Vector2(0.0, extent.y)])
