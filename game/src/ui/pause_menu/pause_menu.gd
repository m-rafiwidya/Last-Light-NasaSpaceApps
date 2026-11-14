extends UIScreen


enum SubScreen{
	PAUSE_MENU,
	SETTINGS
}


var sub_screen: SubScreen = SubScreen.PAUSE_MENU


func _ready() -> void:
	$PauseMenuSubScreen/VBoxContainer/VBoxContainer/Resume.pressed.connect(_on_resume_pressed)
	$PauseMenuSubScreen/VBoxContainer/VBoxContainer/LevelChoice.level_chosen.connect(_on_level_chosen)
	$PauseMenuSubScreen/VBoxContainer/VBoxContainer/QuitToMenu.pressed.connect(_on_quit_to_menu_pressed)
	$PauseMenuSubScreen/VBoxContainer/VBoxContainer/QuitToDesktop.pressed.connect(_on_quit_to_desktop_pressed)
	$PauseMenuSubScreen/VBoxContainer/VBoxContainer/Settings.pressed.connect(_on_settings_pressed)
	$SettingsSubMenu/VBoxContainer/Back.pressed.connect(_on_back_pressed)
	$PauseMenuSubScreen.position = Vector2(-SLIDE_DISTANCE, 0.0)
	$SettingsSubMenu.position = Vector2(SLIDE_DISTANCE, 0.0)


func _on_resume_pressed():
	GameState.return_to_game()


# Loads the chosen level in place of this one; leaving PAUSED unpauses the tree, and the old
# level (player, rovers, held props, cameras) is freed before the new one is set up
func _on_level_chosen(level_id: String):
	SceneLoader.load_scene(level_id)


func _on_settings_pressed():
	sub_screen = SubScreen.SETTINGS
	update_subscreen()


func _on_quit_to_menu_pressed():
	SceneLoader.load_scene("main_menu")


func _on_quit_to_desktop_pressed():
	get_tree().quit()


func _on_back_pressed():
	sub_screen = SubScreen.PAUSE_MENU
	update_subscreen()


func update_subscreen():
	if sub_screen == SubScreen.PAUSE_MENU:
		slide_to($SettingsSubMenu, SLIDE_DISTANCE)
		slide_to($PauseMenuSubScreen, 0.0)
	elif sub_screen == SubScreen.SETTINGS:
		slide_to($PauseMenuSubScreen, -SLIDE_DISTANCE)
		slide_to($SettingsSubMenu, 0.0)


func _fade_bg_tint(alpha: float) -> void:
	create_ui_tween().tween_property($BGTint, "color", Color(0.0, 0.0, 0.0, alpha), FADE_DURATION)


func fade_in():
	sub_screen = SubScreen.PAUSE_MENU
	$PauseMenuSubScreen/VBoxContainer/VBoxContainer/LevelChoice.refresh()
	_fade_bg_tint(0.5)
	update_subscreen()


func fade_out():
	slide_to($PauseMenuSubScreen, -SLIDE_DISTANCE)
	slide_to($SettingsSubMenu, SLIDE_DISTANCE)
	_fade_bg_tint(0.0)
