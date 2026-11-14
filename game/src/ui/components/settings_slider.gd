class_name SettingsSlider

extends HSlider

## Settings slider: a thin track with a round knob (theme variation SettingsSlider). Whole steps,
## Left/Right change it from the keyboard or gamepad.

const WIDTH: float = 312.0   # 260 design px x 1.2


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	theme_type_variation = &"SettingsSlider"
	step = 1.0
	custom_minimum_size.x = WIDTH
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
