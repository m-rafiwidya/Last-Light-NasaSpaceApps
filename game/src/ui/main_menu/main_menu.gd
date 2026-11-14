extends UIScreen

enum SubScreen{
	MAIN_MENU,
	SETTINGS
}

var sub_screen: SubScreen = SubScreen.MAIN_MENU


func _ready() -> void:
	$MainMenuSubScreen/VBoxContainer/VBoxContainer/Start.pressed.connect(_on_start_pressed)
	$MainMenuSubScreen/VBoxContainer/VBoxContainer/Quit.pressed.connect(_on_quit_pressed)
	$MainMenuSubScreen/VBoxContainer/VBoxContainer/Settings.pressed.connect(_on_settings_pressed)
	$SettingsSubMenu/VBoxContainer/Back.pressed.connect(_on_back_pressed)
	$MainMenuSubScreen.position = Vector2(-SLIDE_DISTANCE, 0.0)
	$SettingsSubMenu.position = Vector2(SLIDE_DISTANCE, 0.0)


func _on_start_pressed():
	SceneLoader.load_scene("test_level")


func _on_settings_pressed():
	sub_screen = SubScreen.SETTINGS
	update_subscreen()


func _on_quit_pressed():
	get_tree().quit()


func _on_back_pressed():
	sub_screen = SubScreen.MAIN_MENU
	update_subscreen()


func update_subscreen():
	if sub_screen == SubScreen.MAIN_MENU:
		slide_to($SettingsSubMenu, SLIDE_DISTANCE)
		slide_to($MainMenuSubScreen, 0.0)
	elif sub_screen == SubScreen.SETTINGS:
		slide_to($MainMenuSubScreen, -SLIDE_DISTANCE)
		slide_to($SettingsSubMenu, 0.0)


func fade_in():
	sub_screen = SubScreen.MAIN_MENU
	update_subscreen()


func fade_out():
	slide_to($MainMenuSubScreen, -SLIDE_DISTANCE)
	slide_to($SettingsSubMenu, SLIDE_DISTANCE)
