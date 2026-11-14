class_name FpsCounter

extends CanvasLayer

## Small frames-per-second readout in the top-right corner, above every screen, while
## Settings > General > Show FPS Counter is on (GeneralSettings). IBM Plex Mono, updated four
## times a second, also while paused. The UIManager adds it.

const FONT: FontFile = preload("res://res/fonts/IBMPlexMono-Regular.ttf")
const FONT_SIZE: int = 18
const MARGIN: float = 16.0
const INTERVAL_MS: int = 250
const COLOR := Color(0.9254902, 0.9137255, 0.8901961)

var label: Label
# Real time of the last update (pausing scales the frame time to 0)
var _updated_ms: int = -INTERVAL_MS


func _init() -> void:
	name = "FpsCounter"
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = Label.new()
	label.add_theme_font_override(&"font", FONT)
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.add_theme_color_override(&"font_color", COLOR)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override(&"outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.offset_right = -MARGIN
	label.offset_top = MARGIN
	add_child(label)


func _ready() -> void:
	GeneralSettings.section.changed.connect(_on_general_setting_changed)
	_apply()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _updated_ms < INTERVAL_MS:
		return
	_updated_ms = now
	label.text = "%d FPS" % roundi(Engine.get_frames_per_second())


func _on_general_setting_changed(key: String) -> void:
	if key == "show_fps":
		_apply()


func _apply() -> void:
	visible = GeneralSettings.show_fps()
	set_process(visible)
	_updated_ms = -INTERVAL_MS
