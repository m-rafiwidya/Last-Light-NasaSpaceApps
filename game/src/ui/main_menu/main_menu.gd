extends UIScreen

## Main menu (docs/ui/UI_SPEC.md "Main menu", design x 1.2): starfield, the 3D Moon on the right
## (MenuMoon), and at x 180 the floating astronaut, LAST LIGHT and PLAY / SETTINGS / QUIT GAME.
## The first time it opens per launch it plays the opening sequence (OpeningSequence).
## PLAY shows the playable levels under it for now (the save popup replaces this later).

enum SubScreen{
	MAIN_MENU,
	SETTINGS
}

## The astronaut's float loop: 7 s, ease-in-out between keys (design px x 1.2, degrees)
const FLOAT_KEYS: Array = [
	[Vector2(0.0, 0.0), -2.0],
	[Vector2(8.4, -16.8), 1.5],
	[Vector2(2.4, -26.4), 4.0],
	[Vector2(-7.2, -12.0), 0.5],
]
const FLOAT_PERIOD: float = 7.0

var sub_screen: SubScreen = SubScreen.MAIN_MENU

var _shown: bool = false
var _background_tween: Tween
var _float_tween: Tween

@onready var _sub: Control = $MainMenuSubScreen
@onready var _background: Control = $Background
@onready var _intro: OpeningSequence = $Intro
@onready var _moon: MenuMoon = %Moon
@onready var _play: Button = %Play
@onready var _settings: Button = %Settings
@onready var _quit: Button = %Quit
@onready var _play_choices: Control = %PlayChoices
@onready var _level_choice: LevelChoice = %LevelChoice


func _ready() -> void:
	_play.pressed.connect(_on_play_pressed)
	_level_choice.level_chosen.connect(_on_level_chosen)
	_settings.pressed.connect(_on_settings_pressed)
	_quit.pressed.connect(_on_quit_pressed)
	$SettingsSubMenu/VBoxContainer/Back.pressed.connect(_on_back_pressed)
	_moon.moon_clicked.connect(_on_moon_clicked)
	_intro.finished.connect(_on_intro_finished)
	# The mouse and keyboard/gamepad share one highlight: hovering an item focuses it
	for button in _menu_buttons():
		button.mouse_entered.connect(button.grab_focus)
	# The title's holder keeps the final size, so the letters can spread out inside it during the
	# opening sequence without moving anything else
	%TitleHolder.custom_minimum_size = %Title.get_combined_minimum_size()
	_sub.position = Vector2(-SLIDE_DISTANCE, 0.0)
	$SettingsSubMenu.position = Vector2(SLIDE_DISTANCE, 0.0)
	_set_live(false)
	# At launch the screen stays black (no loading screen) until the opening sequence starts
	if SceneLoader.is_first_main_menu_load:
		_intro.cover()


func _menu_buttons() -> Array[Button]:
	var buttons: Array[Button] = [_play, _settings, _quit]
	for button in _level_choice.get_children():
		if button is Button:
			buttons.append(button)
	return buttons


func _on_play_pressed() -> void:
	# TODO(UI prompt 4): open the save popup instead of listing the levels
	_play_choices.visible = not _play_choices.visible
	if _play_choices.visible:
		var first: Control = _level_choice.get_child(0) as Control
		if first:
			first.grab_focus()


func _on_level_chosen(level_id: String) -> void:
	SceneLoader.load_scene(level_id)


func _on_moon_clicked() -> void:
	# TODO(UI prompt 5): open the planet explorer on the Moon
	pass


func _on_settings_pressed() -> void:
	sub_screen = SubScreen.SETTINGS
	update_subscreen()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_back_pressed() -> void:
	sub_screen = SubScreen.MAIN_MENU
	update_subscreen()
	_settings.grab_focus()


func update_subscreen() -> void:
	# The Moon is off-screen behind the settings: stop rendering it
	_moon.set_active(sub_screen == SubScreen.MAIN_MENU)
	if sub_screen == SubScreen.MAIN_MENU:
		slide_to($SettingsSubMenu, SLIDE_DISTANCE)
		slide_to(_sub, 0.0)
	elif sub_screen == SubScreen.SETTINGS:
		slide_to(_sub, -SLIDE_DISTANCE)
		slide_to($SettingsSubMenu, 0.0)


func fade_in() -> void:
	_shown = true
	sub_screen = SubScreen.MAIN_MENU
	_play_choices.hide()
	_set_live(true)
	if _background_tween:
		_background_tween.kill()
	_background.modulate.a = 1.0
	_background.show()
	if SceneLoader.is_first_main_menu_load:
		SceneLoader.is_first_main_menu_load = false
		_sub.position = Vector2.ZERO
		$SettingsSubMenu.position = Vector2(SLIDE_DISTANCE, 0.0)
		# After this frame's layout, so the menu items' resting positions are known
		_start_intro.call_deferred()
	else:
		update_subscreen()
		_play.grab_focus()


func fade_out() -> void:
	if not _shown:
		return
	_shown = false
	_intro.skip()
	slide_to(_sub, -SLIDE_DISTANCE)
	slide_to($SettingsSubMenu, SLIDE_DISTANCE)
	_background_tween = create_ui_tween()
	_background_tween.tween_property(_background, "modulate:a", 0.0, FADE_DURATION)
	_background_tween.tween_callback(_background.hide)
	_background_tween.tween_callback(_set_live.bind(false))


## Plays the opening sequence again (the `intro` console command), once the console has closed
## so the key that closes it doesn't skip it straight away
func replay_intro() -> void:
	while Debug.console_open:
		await get_tree().process_frame
	await get_tree().process_frame
	if _shown and sub_screen == SubScreen.MAIN_MENU and not _intro.playing:
		_start_intro()


func is_intro_playing() -> bool:
	return _intro.playing


func skip_intro() -> void:
	_intro.skip()


func _start_intro() -> void:
	if not _shown:
		return
	var items: Array[Control] = [_play, _settings, _quit]
	_intro.play(_moon, %Drift, %Title, %TitleGroup, items)


func _on_intro_finished() -> void:
	if _shown:
		_play.grab_focus()


## Moon rendering and the float loop run only while the menu is on screen
func _set_live(live: bool) -> void:
	_moon.set_active(live)
	if live:
		_start_float()
	elif _float_tween:
		_float_tween.kill()
		_float_tween = null


func _start_float() -> void:
	if _float_tween:
		return
	var logo: Control = %Logo
	logo.position = FLOAT_KEYS[0][0]
	logo.rotation_degrees = FLOAT_KEYS[0][1]
	_float_tween = create_tween().set_loops()
	_float_tween.set_ignore_time_scale(true)
	_float_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_float_tween.set_ease(Tween.EASE_IN_OUT)
	_float_tween.set_trans(Tween.TRANS_SINE)
	var step: float = FLOAT_PERIOD / FLOAT_KEYS.size()
	for i in FLOAT_KEYS.size():
		var key: Array = FLOAT_KEYS[(i + 1) % FLOAT_KEYS.size()]
		_float_tween.tween_property(logo, "position", key[0], step)
		_float_tween.parallel().tween_property(logo, "rotation_degrees", key[1], step)
