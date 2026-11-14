class_name ButtonSoundComponent

extends Node

## Drop-in child of a button: hover and press sounds through AudioManager (UI bus, works while
## paused). Hover never plays for disabled buttons or when a menu slides in under a still cursor.
## `press_sound` names the press sound: "click" (a random variation, the default), any other
## AudioManager sound (e.g. "back", "menu_open"), or empty for none (when a state change already
## plays one, like Resume closing the pause menu).

@export var press_sound: StringName = &"click"

@onready var button: BaseButton = get_parent()


func _ready() -> void:
	button.mouse_entered.connect(_on_button_mouse_entered)
	button.pressed.connect(_on_button_pressed)


func _on_button_mouse_entered() -> void:
	AudioManager.play_hover(button)


func _on_button_pressed() -> void:
	if not button.disabled and not press_sound.is_empty():
		AudioManager.play_ui(press_sound)
