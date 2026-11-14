class_name LevelChoice

extends VBoxContainer

## One menu button per playable level (SceneLoader.PLAYABLE_LEVELS), styled like the other menu
## buttons. Used by the pause menu ("Switch to ...", without the level already loaded); the main
## menu's PLAY opens the save popup instead.

signal level_chosen(level_id: String)

const LEVEL_BUTTON: PackedScene = preload("res://src/ui/level_choice/level_button.tscn")

## Scene of each button; it needs a ButtonSoundComponent child (level_button_v2.tscn is the
## underline button of the new UI theme)
@export var button_scene: PackedScene = LEVEL_BUTTON
## Button text; %s is the level's display name
@export var text_format: String = "%s"
## Michroma menus are all caps
@export var uppercase: bool = false
## Hide the button of the level that is loaded now (call refresh() when the menu opens)
@export var hide_current_level: bool = false
## Sound the buttons play when pressed (AudioManager name): game_start on the main menu,
## confirm in the pause menu
@export var press_sound: StringName = &"click"

var _buttons: Dictionary = {}   # level id -> Button


func _ready() -> void:
	# Same spacing as the menu's own button list
	add_theme_constant_override("separation", get_parent().get_theme_constant("separation"))
	for level_id in SceneLoader.PLAYABLE_LEVELS:
		var button := button_scene.instantiate() as Button
		button.name = level_id
		button.text = text_format % SceneLoader.PLAYABLE_LEVELS[level_id]
		if uppercase:
			button.text = button.text.to_upper()
		button.pressed.connect(level_chosen.emit.bind(level_id))
		(button.get_node("ButtonSoundComponent") as ButtonSoundComponent).press_sound = press_sound
		add_child(button)
		_buttons[level_id] = button
	refresh()


func refresh() -> void:
	for level_id in _buttons:
		_buttons[level_id].visible = not (hide_current_level and level_id == SceneLoader.current_level_id)
