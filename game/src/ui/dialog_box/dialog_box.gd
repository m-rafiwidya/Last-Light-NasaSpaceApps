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
	var label: RichTextLabel = $Content/RichTextLabel
	var font_size: int = roundi(FONT_SIZE * GeneralSettings.subtitle_scale())
	for font_size_name in FONT_SIZE_NAMES:
		label.add_theme_font_size_override(font_size_name, font_size)


func set_text(text: String):
	$Content/RichTextLabel.text = text


func fade_in():
	reveal = 0.0
	modulate = Color.TRANSPARENT
	var tween := _create_tween(Tween.EASE_OUT)
	tween.tween_property(self, "reveal", 1.0, 0.5)
	tween.parallel().tween_property(self, "modulate", Color.WHITE, 0.5)


func fade_out():
	var tween := _create_tween(Tween.EASE_IN)
	tween.tween_interval(3.0)
	tween.tween_property(self, "reveal", 0.0, 0.5)
	tween.parallel().tween_property(self, "modulate", Color.TRANSPARENT, 0.5)
	tween.tween_callback(queue_free)


func _create_tween(ease_type: Tween.EaseType) -> Tween:
	var tween := create_tween()
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
