class_name CreditsScreen

extends UIScreen

## Credits (docs/ui/UI_SPEC.md "Credits", board Credits.dc.html, design x 1.2): a 48 s linear roll
## on the starfield, the logo and title first, then the sections of CREDITS.md (CreditsData), with
## the astronaut drifting across behind it and floating like the main menu's. The roll ends on
## THANK YOU FOR PLAYING with WATCH AGAIN / MAIN MENU; SKIP (bottom-right, or Esc) jumps there.
## Opened by the `credits` console command (main menu only for now): open() / close().
## MAIN MENU closes the screen, back onto the main menu it covers.

signal closed

const MainMenuScript = preload("res://src/ui/main_menu/main_menu.gd")
const MICHROMA: Font = preload("res://res/fonts/michroma-latin-400-normal.woff2")
const PLEX_MONO: Font = preload("res://res/fonts/IBMPlexMono-Regular.ttf")

const GAME_TITLE: String = "LAST LIGHT"
const THANKS: String = "THANK YOU FOR PLAYING"
const EARTH_LINE: String = "EARTH UNLOCKED · VISIT IT FROM THE MAIN MENU"
## Sections titled like this show their first name row large (A GAME BY: the studio)
const STUDIO_SECTION: String = "A GAME BY"

## The roll takes 48 s, linear, from just below the screen to just above it (.ll-roll). That is the
## time for the roll without the engine licence; the licence's fine print (a hundred lines) adds time
## at the same speed, so `roll_time` is the real duration.
const ROLL_TIME: float = 48.0
## The engine licence's fine print: size, wrap width, line spacing, gap between its paragraphs
const FINE_SIZE: int = 12
const FINE_WIDTH: float = 880.0
const FINE_LINE_SPACING: int = 3
const FINE_GAP: int = 14
const SECTION_GAP: float = 144.0
const BOTTOM_PADDING: float = 240.0
## The astronaut drifts across in the same time (.ll-drift: from -260,120 / -20 deg to 160,-80 / 12 deg)
const DRIFT_HOME: Vector2 = Vector2(216.0, 396.0)
const DRIFT_FROM: Vector2 = Vector2(-312.0, 144.0)
const DRIFT_TO: Vector2 = Vector2(192.0, -96.0)
const DRIFT_ROTATION: Vector2 = Vector2(-20.0, 12.0)
## The ending (.ll-end 1.6 s, .ll-end-2 1.2 s after 1.4 s)
const END_FADE: float = 1.6
const BUTTONS_FADE: float = 1.2
const BUTTONS_DELAY: float = 1.4
const OPEN_FADE: float = 0.5
const CLOSING_WIDTH: float = 768.0
const LINE_SPACING: int = 12

var rolling: bool = false
var ended: bool = false
## How long this roll takes: ROLL_TIME stretched by the engine licence section (set in play())
var roll_time: float = ROLL_TIME

var _generation: int = 0
var _fonts: Dictionary = {}
var _roll_tween: Tween
var _float_tween: Tween
var _end_tween: Tween
var _fade_tween: Tween
var _column: VBoxContainer
var _engine_box: Control
## What had the keyboard focus before the screen opened (it takes the focus meanwhile, so Enter
## doesn't press a button of the screen underneath)
var _previous_focus: Control

@onready var _root: Control = %Root
@onready var _roll: Control = %Roll
@onready var _drift: Control = %Drift
@onready var _astronaut: Control = %Astronaut
@onready var _end: Control = %End
@onready var _end_text: Control = %EndText
@onready var _end_buttons: Control = %EndButtons
@onready var _again: Button = %WatchAgain
@onready var _menu: Button = %MainMenu
@onready var _skip: Button = %Skip


func _ready() -> void:
	add_to_group(&"credits_screen")
	_skip.pressed.connect(skip)
	_again.pressed.connect(play)
	_menu.pressed.connect(close)
	for button: Button in [_skip, _again, _menu]:
		button.add_child(ButtonSoundComponent.new())
	_add_label(_end_text, THANKS, MICHROMA, 41, 22, &"text")
	_add_label(_end_text, EARTH_LINE, PLEX_MONO, 16, 5, &"earth")
	hide()


func is_open() -> bool:
	return visible


func fade_in() -> void:
	open()


func fade_out() -> void:
	close()


## Shows the screen and starts the roll
func open() -> void:
	if not visible:
		_previous_focus = get_viewport().gui_get_focus_owner()
	show()
	_root.modulate.a = 0.0
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_ui_tween()
	_fade_tween.tween_property(_root, "modulate:a", 1.0, OPEN_FADE)
	play()


func close() -> void:
	if not visible:
		return
	_generation += 1
	_kill_tweens()
	rolling = false
	hide()
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	_previous_focus = null
	closed.emit()


## (Re)starts the roll from the logo
func play() -> void:
	_generation += 1
	var generation: int = _generation
	_kill_tweens()
	ended = false
	rolling = true
	_end.hide()
	_roll.show()
	_drift.show()
	_skip.show()
	_skip.grab_focus()
	_build_roll()
	# The roll's height is known after one layout pass
	await get_tree().process_frame
	if generation != _generation:
		return
	_roll_tween = create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_roll_tween.set_trans(Tween.TRANS_LINEAR)
	_column.position.y = _root.size.y
	# The speed is the one the roll has without the engine licence
	var main_height: float = _column.size.y
	if _engine_box:
		main_height -= _engine_box.size.y + SECTION_GAP
	roll_time = ROLL_TIME * (_root.size.y + _column.size.y) / (_root.size.y + main_height)
	_roll_tween.tween_property(_column, "position:y", -_column.size.y, roll_time)
	_roll_tween.parallel().tween_property(_drift, "position", DRIFT_HOME + DRIFT_TO, roll_time).from(DRIFT_HOME + DRIFT_FROM)
	_roll_tween.parallel().tween_property(_drift, "rotation_degrees", DRIFT_ROTATION.y, roll_time).from(DRIFT_ROTATION.x)
	_roll_tween.finished.connect(_show_end.bind(generation))
	_start_float()


## Jumps to THANK YOU FOR PLAYING
func skip() -> void:
	if rolling:
		_show_end(_generation)


# In _input, before the GUI: the focused SKIP button would take Esc first
func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if rolling:
		skip()
	else:
		close()


func _show_end(generation: int) -> void:
	if generation != _generation or ended:
		return
	rolling = false
	ended = true
	_kill_tweens()
	_roll.hide()
	_drift.hide()
	_skip.hide()
	_end.show()
	_end_text.modulate.a = 0.0
	_end_buttons.modulate.a = 0.0
	_end_tween = create_ui_tween()
	_end_tween.tween_property(_end_text, "modulate:a", 1.0, END_FADE)
	_end_tween.parallel().tween_property(_end_buttons, "modulate:a", 1.0, BUTTONS_FADE).set_delay(BUTTONS_DELAY)


func _kill_tweens() -> void:
	for tween: Tween in [_roll_tween, _float_tween, _end_tween]:
		if tween:
			tween.kill()
	_roll_tween = null
	_float_tween = null
	_end_tween = null


# The main menu's astronaut: same keys and period
func _start_float() -> void:
	var keys: Array = MainMenuScript.FLOAT_KEYS
	_astronaut.position = keys[0][0]
	_astronaut.rotation_degrees = keys[0][1]
	_float_tween = create_tween().set_loops()
	_float_tween.set_ignore_time_scale(true)
	_float_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_float_tween.set_ease(Tween.EASE_IN_OUT)
	_float_tween.set_trans(Tween.TRANS_SINE)
	var step: float = MainMenuScript.FLOAT_PERIOD / keys.size()
	for i in keys.size():
		var key: Array = keys[(i + 1) % keys.size()]
		_float_tween.tween_property(_astronaut, "position", key[0], step)
		_float_tween.parallel().tween_property(_astronaut, "rotation_degrees", key[1], step)


# --- The roll's content -------------------------------------------------------------------------

func _build_roll() -> void:
	if _column:
		_column.queue_free()
	_engine_box = null
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_column.add_theme_constant_override(&"separation", roundi(SECTION_GAP))
	_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	_roll.add_child(_column)

	var logo := VBoxContainer.new()
	logo.add_theme_constant_override(&"separation", 34)
	var image := TextureRect.new()
	image.texture = (_astronaut as TextureRect).texture
	image.custom_minimum_size = Vector2(158.0, 180.0)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.add_child(image)
	_add_label(logo, GAME_TITLE, MICHROMA, 43, 24, &"text")
	_column.add_child(logo)

	for section in CreditsData.sections():
		_column.add_child(_build_section(section))
	var padding := Control.new()
	padding.custom_minimum_size.y = BOTTOM_PADDING - SECTION_GAP
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(padding)


func _build_section(section: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 26)
	var title: String = section["title"]
	if title == CreditsData.ENGINE_TITLE:
		_engine_box = box
		box.add_theme_constant_override(&"separation", FINE_GAP)
	if not title.is_empty():
		_add_label(box, title, PLEX_MONO, 14, 7, &"muted")
	var first_name: bool = true
	for entry: Dictionary in section["entries"]:
		if entry.has("name"):
			var row := VBoxContainer.new()
			row.add_theme_constant_override(&"separation", 7)
			var studio: bool = title == STUDIO_SECTION and first_name
			_add_label(row, entry["name"], MICHROMA, 34 if studio else 26, 12 if studio else 7, &"text")
			_add_label(row, entry["sub"], PLEX_MONO, 16, 2, &"muted")
			box.add_child(row)
			first_name = false
		elif entry.has("fine"):
			# Fine print (the engine licence): small, left-aligned, wrapped
			var fine := _add_label(box, entry["fine"], PLEX_MONO, FINE_SIZE, 0, &"muted")
			fine.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			fine.add_theme_constant_override(&"line_spacing", FINE_LINE_SPACING)
			fine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			fine.custom_minimum_size.x = minf(FINE_WIDTH, _root.size.x - 160.0)
			fine.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		elif title.is_empty():
			# The closing note: muted, wrapped to a narrow column
			var note := _add_label(box, entry["text"], PLEX_MONO, 18, 0, &"muted")
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size.x = CLOSING_WIDTH
			note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		else:
			_add_label(box, entry["text"], PLEX_MONO, 18, 0, &"text_2")
	return box


## A centred label added to `parent`. Spaced text is padded on the left by its spacing, because
## the last letter is followed by one too (CSS: margin-right of minus the spacing).
func _add_label(parent: Control, text: String, font: Font, size: int, spacing: int, color: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", _font(font, spacing))
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", _root.get_theme_color(color, &"UIColor"))
	label.add_theme_constant_override(&"line_spacing", LINE_SPACING)
	if spacing > 0:
		var pad := MarginContainer.new()
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_theme_constant_override(&"margin_left", spacing)
		pad.add_child(label)
		parent.add_child(pad)
	else:
		parent.add_child(label)
	return label


func _font(base: Font, spacing: int) -> FontVariation:
	var key: String = "%d_%d" % [base.get_instance_id(), spacing]
	if not _fonts.has(key):
		var variation := FontVariation.new()
		variation.base_font = base
		variation.spacing_glyph = spacing
		_fonts[key] = variation
	return _fonts[key]
