extends Control
## The root is a plain Control "slot" that the HUD's VBoxContainer lays out. The text
## content lives inside it, pinned to the slot's bottom. Animating `reveal` shrinks/grows the
## slot's height (so sibling boxes move smoothly) and squashes the content to match.
## The background panel is provided by the HUD, which wraps all dialog boxes at once.
## The content is not a direct child of a Container, so nothing resets its scale.
## The text size follows Settings > General > Subtitle Size (GeneralSettings), at once.

## Text size at Subtitle Size 100 %
const FONT_SIZE: int = 24
const FONT_SIZE_NAMES: Array[StringName] = [&"normal_font_size", &"bold_font_size",
	&"bold_italics_font_size", &"italics_font_size", &"mono_font_size"]

@onready var _content: Control = $Content

## True once the line is on its way out (no hold left)
var leaving: bool = false
var _tween: Tween = null

## 0 = collapsed, 1 = fully shown.
var reveal: float = 1.0:
	set(value):
		reveal = value
		_apply_reveal()


func _ready() -> void:
	# The label's wrapped height can change after layout, so keep the slot in sync.
	_content.minimum_size_changed.connect(_apply_reveal)
	_apply_font_size()
	GeneralSettings.section.changed.connect(_on_general_setting_changed)
	_apply_reveal()


func _on_general_setting_changed(key: String) -> void:
	if key == "subtitle_size":
		_apply_font_size()


func _apply_font_size() -> void:
	var label: RichTextLabel = $Content/Column/RichTextLabel
	var font_size: int = roundi(FONT_SIZE * GeneralSettings.subtitle_scale())
	for font_size_name in FONT_SIZE_NAMES:
		label.add_theme_font_size_override(font_size_name, font_size)


func set_text(text: String):
	$Content/Column/RichTextLabel.text = text


## The line's text, with the speaker's name on its own small line above it (none: no name line)
func set_line(speaker: String, text: String) -> void:
	var name_label: Label = $Content/Column/Speaker
	name_label.text = speaker.to_upper()
	name_label.visible = not speaker.is_empty()
	set_text(text)


## Fades the line in; `grow` also opens its height (stacked lines slide), else only the alpha
func fade_in(seconds: float = 0.5, grow: bool = true):
	reveal = 0.0 if grow else 1.0
	modulate = Color.TRANSPARENT
	var tween := _create_tween(Tween.EASE_OUT)
	if grow:
		tween.tween_property(self, "reveal", 1.0, seconds)
	tween.parallel().tween_property(self, "modulate", Color.WHITE, seconds)


## Fades the line out after `hold` seconds on screen; `shrink` also closes its height
func fade_out(hold: float = 3.0, seconds: float = 0.5, shrink: bool = true):
	if leaving:
		return
	leaving = hold <= 0.0
	var tween := _create_tween(Tween.EASE_IN)
	if hold > 0.0:
		tween.tween_interval(hold)
	if shrink:
		tween.tween_property(self, "reveal", 0.0, seconds)
	tween.parallel().tween_property(self, "modulate", Color.TRANSPARENT, seconds)
	tween.tween_callback(queue_free)


func _create_tween(ease_type: Tween.EaseType) -> Tween:
	if _tween:
		_tween.kill()
	var tween := create_tween()
	_tween = tween
	tween.set_ignore_time_scale(true)
	tween.set_ease(ease_type)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween


func _apply_reveal() -> void:
	if _content == null:
		return
	# The content is bottom-anchored, so its height is its minimum height. Using that
	# directly avoids reading `size`, which lags a frame behind.
	var full_height := _content.get_combined_minimum_size().y
	custom_minimum_size.y = full_height * reveal
	_content.pivot_offset.y = full_height
	_content.scale.y = maxf(reveal, 0.001)
