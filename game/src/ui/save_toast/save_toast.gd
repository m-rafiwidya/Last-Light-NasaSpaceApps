class_name SaveToast

extends CanvasLayer

## The small save notice in the bottom-right corner (SaveIndex calls it by the "save_toast" group):
## "Saving..." while a save is written, "Saved" once the file is in place, or why it failed. Shows
## over the pause menu and runs while the game is paused.

const GROUP: StringName = &"save_toast"
const SAVED_HOLD: float = 2.0
const FAILED_HOLD: float = 5.0
const FADE_TIME: float = 0.4
const MARGIN: float = 32.0
const FAILED_COLOR := Color(0.95, 0.55, 0.45)

enum State {HIDDEN, SAVING, SAVED, FAILED}

var state: State = State.HIDDEN
var label := Label.new()
var _panel := PanelContainer.new()
var _tween: Tween


func _ready() -> void:
	add_to_group(GROUP)
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.02, 0.03, 0.78)
	box.set_corner_radius_all(4)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override(&"panel", box)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.theme = load("res://res/ui_theme_v2.tres")
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -MARGIN
	_panel.offset_bottom = -MARGIN
	add_child(_panel)
	label.name = "Text"
	label.theme_type_variation = &"LabelHudCaption"
	_panel.add_child(label)
	_panel.modulate.a = 0.0
	_panel.hide()


func show_saving(text: String) -> void:
	_show(State.SAVING, text, 0.0)


func show_saved(text: String) -> void:
	_show(State.SAVED, text, SAVED_HOLD)


func show_failed(text: String) -> void:
	_show(State.FAILED, text, FAILED_HOLD)


func hide_toast(_text: String = "") -> void:
	if _tween:
		_tween.kill()
	state = State.HIDDEN
	_panel.hide()


func text() -> String:
	return label.text if state != State.HIDDEN else ""


## Holds `hold` s then fades out; 0 holds until the next state
func _show(new_state: State, text: String, hold: float) -> void:
	state = new_state
	label.text = text
	label.remove_theme_color_override(&"font_color")
	if new_state == State.FAILED:
		label.add_theme_color_override(&"font_color", FAILED_COLOR)
	_panel.show()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.15)
	if hold > 0.0:
		_tween.tween_interval(hold)
		_tween.tween_property(_panel, "modulate:a", 0.0, FADE_TIME)
		_tween.tween_callback(hide_toast)
