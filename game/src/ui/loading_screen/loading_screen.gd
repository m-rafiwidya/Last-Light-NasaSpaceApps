extends UIScreen

## Loading screen (docs/ui/UI_SPEC.md "Loading", design x 1.2): the starfield, one "Did you know?"
## fact at a time (random first, then in order every FACT_PERIOD s) with its source and dots, the
## floating astronaut, and at the bottom the stage text, the percentage and the 2 px bar.
## The bar and the stage text follow SceneLoader: overall_progress() and stage. When a gameplay
## level is ready (SceneLoader.Stage.AWAITING_CONTINUE) the stage text gives way to CONTINUE,
## which lets the level start (SceneLoader.continue_loading). The main menu never waits.

signal finished_fade_in
signal finished_fade_out

const MainMenuScript = preload("res://src/ui/main_menu/main_menu.gd")

## The board's `facts()`: the fact and the caption under it
const FACTS: Array[Dictionary] = [
	{"text": "Apollo 12 landed within walking distance of Surveyor 3, a robotic lander that had been waiting there for 31 months.", "source": "Apollo 12, November 1969"},
	{"text": "The Apollo 12 crew cut parts off Surveyor 3, including its camera, and brought them back to Earth.", "source": "Apollo 12 and Surveyor 3"},
	{"text": "With no air on the Moon, dust kicked up by a wheel flies in a clean arc and falls straight back down. It never hangs in a cloud.", "source": "The lunar surface"},
	{"text": "There is no wind or rain on the Moon, so the Apollo footprints and rover tracks are still there today.", "source": "The lunar surface"},
	{"text": "From the Moon’s near side, Earth stays in roughly the same spot in the sky. It never rises or sets.", "source": "Earth from the Moon"},
	{"text": "Earth seen from the Moon looks almost four times wider than the full Moon looks from Earth.", "source": "Earth from the Moon"},
	{"text": "One day on the Moon, from sunrise to sunrise, lasts about 29.5 Earth days.", "source": "A day on the Moon"},
	{"text": "The Moon’s surface swings from over 120 °C in sunlight to below −170 °C at night.", "source": "The lunar surface"},
]

const FACT_PERIOD: float = 7.0
## A fact fades in over 0.8 s, rising 8 px (x 1.2)
const FACT_FADE: float = 0.8
const FACT_RISE: float = 9.6
const DOT_SIZE: float = 7.2
const DOT_OFF: Color = Color("2E2E33")
const DOT_FADE: float = 0.3

## The stage text (SceneLoader.Stage): the first two split the threaded load of the level's scene
## (its workshop, Kite and the rest) at its halfway point
const STAGE_WORKSHOP: String = "PREPARING THE WORKSHOP"
const STAGE_KITE: String = "WAKING UP KITE"
const STAGE_TERRAIN: String = "LOADING TERRAIN"
const STAGE_ALMOST: String = "ALMOST THERE"
const PULSE_PERIOD: float = 1.8

## The bar follows SceneLoader.overall_progress() but never faster than this share per second, so
## a jump (the end of a level without terrain) is drawn as a quick fill
const BAR_SPEED: float = 1.5
const CONTINUE_FADE: float = 0.45

var fact_index: int = 0

var _fact_clock: float = 0.0
var _fact_generation: int = 0
var _shown_progress: float = 0.0
var _continue_shown: bool = false
var _continued: bool = false
var _dots: Array[Panel] = []
var _dot_style: StyleBoxFlat
var _float_tween: Tween
var _pulse_tween: Tween
var _fact_tween: Tween
var _dot_tween: Tween

@onready var _fact_box: Control = %FactBox
@onready var _fact: Label = %Fact
@onready var _source: Label = %Source
@onready var _dot_row: Control = %Dots
@onready var _logo: Control = %Logo
@onready var _stage: Label = %Stage
@onready var _percent: Label = %Percent
@onready var _fill: Control = %Fill
@onready var _continue: Button = %Continue


func _ready() -> void:
	$AnimationPlayer.animation_finished.connect(_on_animation_player_animation_finished)
	_continue.pressed.connect(_on_continue_pressed)
	_build_dots()
	visibility_changed.connect(_on_visibility_changed)
	_begin_load()
	_on_visibility_changed()


func reset():
	$AnimationPlayer.play("RESET")
	_begin_load()


func fade_in():
	$AnimationPlayer.play("RESET")
	$AnimationPlayer.play("fade_in")
	_begin_load()


func fade_out():
	$AnimationPlayer.play("RESET")
	$AnimationPlayer.play("fade_out")


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	match anim_name:
		"fade_in":
			finished_fade_in.emit()
		"fade_out":
			finished_fade_out.emit()
			hide()


## A new load starts: empty bar, a random first fact, no CONTINUE
func _begin_load() -> void:
	_continue_shown = false
	_continued = false
	_continue.hide()
	_stage.show()
	_stage.text = STAGE_WORKSHOP
	_set_progress(0.0)
	_fact_clock = 0.0
	_show_fact(randi() % FACTS.size())


func _process(delta: float) -> void:
	if not visible:
		return
	var stage: SceneLoader.Stage = SceneLoader.stage
	# Once the load is over (IDLE) the screen is only fading out: it keeps what it shows
	if stage != SceneLoader.Stage.IDLE:
		_set_progress(move_toward(_shown_progress, SceneLoader.overall_progress(), BAR_SPEED * delta))
		var text: String = _stage_text(stage)
		if text != _stage.text:
			_stage.text = text
		if stage == SceneLoader.Stage.AWAITING_CONTINUE and _shown_progress >= 1.0 and not _continue_shown:
			_show_continue()
	_fact_clock += delta
	if _fact_clock >= FACT_PERIOD:
		_fact_clock = 0.0
		_show_fact((fact_index + 1) % FACTS.size())


func _unhandled_input(event: InputEvent) -> void:
	if visible and _continue.visible and event.is_action_pressed(&"ui_accept") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_on_continue_pressed()


# Real stages where SceneLoader reports them (the content built after the scene loads is the
# terrain), the scene's own load split in half
func _stage_text(stage: SceneLoader.Stage) -> String:
	match stage:
		SceneLoader.Stage.BUILDING_CONTENT:
			return STAGE_TERRAIN
		SceneLoader.Stage.STARTING, SceneLoader.Stage.AWAITING_CONTINUE:
			return STAGE_ALMOST
	return STAGE_WORKSHOP if SceneLoader.progress[0] < 0.5 else STAGE_KITE


func _set_progress(value: float) -> void:
	_shown_progress = value
	_fill.anchor_right = value
	_percent.text = "%d%%" % floori(value * 100.0 + 0.0001)


# --- CONTINUE -----------------------------------------------------------------------------------

func _show_continue() -> void:
	_continue_shown = true
	_stage.hide()
	_continue.modulate.a = 0.0
	_continue.show()
	_continue.grab_focus()
	# The level that asked for the load may have captured the mouse (the console's `testlevel`)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	create_ui_tween().tween_property(_continue, "modulate:a", 1.0, CONTINUE_FADE)


func _on_continue_pressed() -> void:
	if _continued:
		return
	_continued = true
	SceneLoader.continue_loading()


# --- Facts --------------------------------------------------------------------------------------

func _build_dots() -> void:
	_dot_style = StyleBoxFlat.new()
	_dot_style.bg_color = Color.WHITE
	_dot_style.set_corner_radius_all(ceili(DOT_SIZE / 2.0))
	for i in FACTS.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override(&"panel", _dot_style)
		dot.self_modulate = DOT_OFF
		_dot_row.add_child(dot)
		_dots.append(dot)


# Shows fact `index`: the text fades in over FACT_FADE while rising FACT_RISE, the dots follow
func _show_fact(index: int) -> void:
	fact_index = index
	var fact: Dictionary = FACTS[index]
	_fact.text = fact["text"]
	_source.text = fact["source"]
	_fact_generation += 1
	var generation: int = _fact_generation
	_fact_box.modulate.a = 0.0
	if _dot_tween:
		_dot_tween.kill()
	_dot_tween = create_ui_tween().set_parallel()
	var on: Color = _dot_row.get_theme_color(&"text", &"UIColor")
	for i in _dots.size():
		_dot_tween.tween_property(_dots[i], "self_modulate", on if i == index else DOT_OFF, DOT_FADE)
	# The container lays the new text out by the next frame; the rise starts from there
	await get_tree().process_frame
	if generation != _fact_generation:
		return
	var rest_y: float = _fact_box.position.y
	_fact_box.position.y = rest_y + FACT_RISE
	if _fact_tween:
		_fact_tween.kill()
	_fact_tween = create_ui_tween().set_parallel()
	_fact_tween.set_ease(Tween.EASE_OUT)
	_fact_tween.tween_property(_fact_box, "modulate:a", 1.0, FACT_FADE)
	_fact_tween.tween_property(_fact_box, "position:y", rest_y, FACT_FADE)


# --- Motion that only runs while the screen is up -----------------------------------------------

func _on_visibility_changed() -> void:
	if visible:
		_start_float()
		_start_pulse()
	else:
		if _float_tween:
			_float_tween.kill()
			_float_tween = null
		if _pulse_tween:
			_pulse_tween.kill()
			_pulse_tween = null


# The main menu's astronaut: same keys and period
func _start_float() -> void:
	if _float_tween:
		return
	var keys: Array = MainMenuScript.FLOAT_KEYS
	_logo.position = keys[0][0]
	_logo.rotation_degrees = keys[0][1]
	_float_tween = create_tween().set_loops()
	_float_tween.set_ignore_time_scale(true)
	_float_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_float_tween.set_ease(Tween.EASE_IN_OUT)
	_float_tween.set_trans(Tween.TRANS_SINE)
	var step: float = MainMenuScript.FLOAT_PERIOD / keys.size()
	for i in keys.size():
		var key: Array = keys[(i + 1) % keys.size()]
		_float_tween.tween_property(_logo, "position", key[0], step)
		_float_tween.parallel().tween_property(_logo, "rotation_degrees", key[1], step)


# The stage text breathes between 45 % and full opacity
func _start_pulse() -> void:
	if _pulse_tween:
		return
	_stage.modulate.a = 1.0
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_ignore_time_scale(true)
	_pulse_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_pulse_tween.set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(_stage, "modulate:a", 0.45, PULSE_PERIOD / 2.0)
	_pulse_tween.tween_property(_stage, "modulate:a", 1.0, PULSE_PERIOD / 2.0)
