class_name SlantedTab

extends Button

## Settings tab (GENERAL / AUDIO / ...). Inactive: panel fill, muted text. Active: light fill,
## dark text. The owner of the tab row sets `active`; pressing only emits `pressed`.

@export var active: bool = false:
	set(value):
		active = value
		theme_type_variation = &"SlantedTabActive" if active else &"SlantedTab"


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	theme_type_variation = &"SlantedTab"
	custom_minimum_size.y = 43.2
