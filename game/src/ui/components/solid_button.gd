class_name SolidButton

extends Button

## Light slanted (parallelogram) button: START NEW CAMPAIGN, settings BACK / RESET.
## `compact` switches to the 36 px design height. Hover and focus look the same (pure white,
## 1 px lift) via the theme's hover/focus styleboxes.

@export var compact: bool = false:
	set(value):
		compact = value
		_apply_size()


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	_apply_size()


func _apply_size() -> void:
	theme_type_variation = &"SolidButtonSmall" if compact else &"SolidButton"
	# 48 / 36 px design height x 1.2. The theme's skew assumes this height.
	custom_minimum_size.y = 43.2 if compact else 57.6
