class_name OpeningSequence

extends Control

## The main menu's opening sequence (first launch only), from the design board's .ll-intro CSS
## (Main.dc.html), times in seconds, distances x 1.2:
##   0.0  black overlay; 0.7-3.5 "TANDBORSTE PRESENTS" fades in and out, spacing 4 -> 14 px;
##   1.0  SKIP fades in (0.6 s); 2.8 the overlay fades out (1.8 s);
##   3.2  the Moon rises in (3.2 s): from (+220, +180) px at 1.5x scale, black -> lit;
##   4.4  the astronaut drifts in from the left (5.6 s): x -520 px, y +190 px, -26 degrees;
##   7.0  "LAST LIGHT" resolves (2 s): blur 10 px -> 0, spacing 0 -> 22 px, fades in;
##   8.8 / 9.05 / 9.3  the menu items slide in (0.9 s each): x -24 px, fade in.
## Everything is a pure function of the time (_apply), so skipping just applies the end state.
## The clock is real time (not Engine.time_scale) and advances at most MAX_STEP per frame, so a
## first-frame hitch (shader compile, texture upload) slows the start instead of skipping it.
## SKIP, any key, click or gamepad button skips.

signal finished

const LENGTH: float = 10.2
const MAX_STEP: float = 1.0 / 20.0
## For the first moments (under the opaque black overlay) everything behind it is drawn as if
## visible: the Moon, its texture and shader, and the blurred title are used once while nobody
## can see them, so their first-use cost doesn't land on a visible animation
const WARM_UP: float = 0.5
const S: float = 1.2

## CSS timing functions used by the board
const EASE: Array[float] = [0.25, 0.1, 0.25, 1.0]
const MOON_CURVE: Array[float] = [0.25, 0.7, 0.2, 1.0]
const DRIFT_X_CURVE: Array[float] = [0.1, 0.55, 0.2, 1.0]
const DRIFT_Y_CURVE: Array[float] = [0.35, 0.35, 0.2, 1.0]
const WORD_CURVE: Array[float] = [0.2, 0.7, 0.2, 1.0]

const TITLE_SPACING: float = 22.0 * S
const PRESENTS_SPACING_FROM: float = 4.0 * S
const PRESENTS_SPACING_TO: float = 14.0 * S
## Mip level that looks like the design's 10 px blur (x 1.2)
const TITLE_BLUR_LOD: float = 3.6

var playing: bool = false

var _moon: MenuMoon
var _drift: Control
var _drift_home: Vector2
var _title: SpacedLabel
var _title_group: CanvasGroup
var _title_material: ShaderMaterial
var _blur_lod: float = -1.0
var _buttons: Array[Control] = []
var _button_homes: Array[Vector2] = []
var _time: float = 0.0
var _last_usec: int = 0
## Set by seek(): the clock stands still
var _held: bool = false

@onready var _overlay: ColorRect = $Overlay
@onready var _presents: SpacedLabel = $Presents
@onready var _skip: Button = $Skip


func _ready() -> void:
	hide()
	set_process(false)
	_skip.pressed.connect(skip)


## Just the black screen, before play() (the game's launch, while the menu loads)
func cover() -> void:
	_overlay.modulate.a = 1.0
	_overlay.show()
	_presents.modulate.a = 0.0
	_skip.modulate.a = 0.0
	show()


## `title` sits in `title_group`, whose material uses title_blur.gdshader; `drift` is the
## astronaut's holder (moved and turned; the float loop runs on its child)
func play(moon: MenuMoon, drift: Control, title: SpacedLabel, title_group: CanvasGroup,
		buttons: Array[Control]) -> void:
	_moon = moon
	_drift = drift
	_drift_home = drift.position
	_title = title
	_title_group = title_group
	if title_group.material:
		_title_material = title_group.material as ShaderMaterial
	_set_blur(TITLE_BLUR_LOD)
	_buttons = buttons
	_button_homes.clear()
	for b in buttons:
		_button_homes.append(b.position)
	playing = true
	_held = false
	_time = 0.0
	_last_usec = Time.get_ticks_usec()
	show()
	_apply(0.0)
	set_process(true)


func skip() -> void:
	if not playing:
		return
	_apply(LENGTH)
	_finish()


## Shows the sequence at `t` seconds and stops its clock there (screenshots, tests)
func seek(t: float) -> void:
	if not playing:
		return
	_held = true
	_time = clampf(t, 0.0, LENGTH)
	_apply(_time)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var step: float = minf((now - _last_usec) / 1e6, MAX_STEP)
	_last_usec = now
	if _held:
		return
	_time += step
	_apply(minf(_time, LENGTH))
	if _time >= LENGTH:
		_finish()


func _finish() -> void:
	playing = false
	set_process(false)
	hide()
	# The buttons were moved by hand inside their container; let it lay them out again
	if not _buttons.is_empty():
		(_buttons[0].get_parent() as Container).queue_sort()
	finished.emit()


func _input(event: InputEvent) -> void:
	if not playing:
		return
	# The fullscreen toggle works during the sequence without skipping it (UIManager handles it)
	if event.is_action(&"toggle_fullscreen"):
		return
	var skips: bool = (
		(event is InputEventKey and event.pressed and not event.echo)
		or (event is InputEventMouseButton and event.pressed)
		or (event is InputEventJoypadButton and event.pressed))
	if skips:
		get_viewport().set_input_as_handled()
		skip()


## Scene state at `t` seconds into the sequence
func _apply(t: float) -> void:
	# Black overlay, then the presents line
	_overlay.modulate.a = 1.0 - _progress(t, 2.8, 1.8, EASE)
	_overlay.visible = _overlay.modulate.a > 0.0
	var p: float = clampf((t - 0.7) / 2.8, 0.0, 1.0)
	var a: float = 0.0
	if p < 0.25:
		a = _ease(p / 0.25, EASE)
	elif p < 0.75:
		a = 1.0
	else:
		a = 1.0 - _ease((p - 0.75) / 0.25, EASE)
	_presents.modulate.a = a
	_presents.letter_spacing = lerpf(PRESENTS_SPACING_FROM, PRESENTS_SPACING_TO, _ease(p, EASE))
	_skip.modulate.a = _progress(t, 1.0, 0.6, EASE)

	# The Moon: transform over the whole 3.2 s; opacity and brightness have a key at 35 %
	var m: float = clampf((t - 3.2) / 3.2, 0.0, 1.0)
	var e: float = _ease(m, MOON_CURVE)
	_moon.intro_offset = Vector2(220.0, 180.0) * S * (1.0 - e)
	_moon.intro_scale = lerpf(1.5, 1.0, e)
	if m < 0.35:
		var k: float = _ease(m / 0.35, MOON_CURVE)
		_moon.modulate.a = k
		_moon.intro_brightness = 0.15 * k
	else:
		_moon.modulate.a = 1.0
		_moon.intro_brightness = lerpf(0.15, 1.0, _ease((m - 0.35) / 0.65, MOON_CURVE))

	# The astronaut drifts in (no fade: it starts off-screen)
	var dx: float = _progress(t, 4.4, 5.6, DRIFT_X_CURVE)
	var dy: float = _progress(t, 4.4, 5.6, DRIFT_Y_CURVE)
	_drift.position = _drift_home + Vector2(-520.0 * S * (1.0 - dx), 190.0 * S * (1.0 - dy))
	_drift.rotation = deg_to_rad(-26.0) * (1.0 - dy)

	# LAST LIGHT resolves from blur while its letters spread out; the blur is switched off
	# once it's sharp
	var w: float = _progress(t, 7.0, 2.0, WORD_CURVE)
	_title.modulate.a = w
	_title.letter_spacing = TITLE_SPACING * w
	_set_blur(TITLE_BLUR_LOD * (1.0 - w))

	# Menu items slide in one by one
	for i in _buttons.size():
		var b: float = _progress(t, 8.8 + 0.25 * i, 0.9, WORD_CURVE)
		_buttons[i].modulate.a = b
		_buttons[i].position = _button_homes[i] + Vector2(-24.0 * S * (1.0 - b), 0.0)

	if t < WARM_UP:
		_moon.modulate.a = 1.0
		_moon.intro_brightness = 1.0
		_title.modulate.a = 1.0


## Title blur: the CanvasGroup's material and mipmaps only while it is blurred
func _set_blur(lod: float) -> void:
	if is_equal_approx(lod, _blur_lod) or _title_group == null:
		return
	_blur_lod = lod
	var on: bool = lod > 0.001
	_title_group.material = _title_material if on else null
	_title_group.use_mipmaps = on
	if on and _title_material:
		_title_material.set_shader_parameter(&"blur_lod", lod)


## Eased progress of an animation that starts at `start` and lasts `duration`
func _progress(t: float, start: float, duration: float, curve: Array[float]) -> float:
	return _ease(clampf((t - start) / duration, 0.0, 1.0), curve)


func _ease(x: float, curve: Array[float]) -> float:
	return cubic_bezier(curve[0], curve[1], curve[2], curve[3], x)


## CSS cubic-bezier(x1, y1, x2, y2) at x (0..1)
static func cubic_bezier(x1: float, y1: float, x2: float, y2: float, x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	var lo: float = 0.0
	var hi: float = 1.0
	var s: float = x
	for i in 24:
		var bx: float = _bezier(x1, x2, s)
		if absf(bx - x) < 1e-5:
			break
		if bx < x:
			lo = s
		else:
			hi = s
		s = (lo + hi) * 0.5
	return _bezier(y1, y2, s)


static func _bezier(p1: float, p2: float, s: float) -> float:
	var u: float = 1.0 - s
	return 3.0 * u * u * s * p1 + 3.0 * u * s * s * p2 + s * s * s
