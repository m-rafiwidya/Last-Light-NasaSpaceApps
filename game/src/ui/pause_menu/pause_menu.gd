extends UIScreen

## Pause menu (docs/ui/UI_SPEC.md "Pause", board Pause.dc.html, design x 1.2). The game view behind
## is blurred 6 px and darkened to 50 % (backdrop_blur.gdshader); centred PAUSED, a rule, and
## RESUME / SWITCH TO <level> / SETTINGS / QUIT TO MENU / QUIT TO DESKTOP as underline buttons
## that grow from the centre. The items fade in one after another, rising 12 px.
## SETTINGS opens the shared settings screen (SettingsSubMenu) over the game, blurred 10 px and
## darkened to 30 %; the pause blur gives way to it. BACK or Esc there returns to this menu.
## Keyboard / gamepad focus starts on RESUME; hovering an item focuses it, so mouse and keyboard
## share one highlight.

enum SubScreen{
	PAUSE_MENU,
	SETTINGS
}

## Entrance (.ll-item: fade and 10 px rise in 0.45 s, staggered .04 s from .14 s; x 1.2)
const RISE: float = 12.0
const RISE_TIME: float = 0.45
const TITLE_DELAY: float = 0.05
const RULE_DELAY: float = 0.1
const FIRST_ITEM_DELAY: float = 0.14
const ITEM_STAGGER: float = 0.04
const BLUR_IN_TIME: float = 0.45
const BLUR_OUT_TIME: float = 0.3

var sub_screen: SubScreen = SubScreen.PAUSE_MENU

var _shown: bool = false
## Counts openings, so an entrance that was waiting for the layout notices it was cancelled
var _generation: int = 0
var _blur_tween: Tween
var _content_tween: Tween
var _items_tween: Tween
var _blur_material: ShaderMaterial
## Why the game can't be saved right now (SaveGate), under the items; hidden when it can
var save_note := Label.new()

@onready var _root: Control = %Root
@onready var _blur: ColorRect = %Blur
@onready var _content: Control = %Content
@onready var _resume: Button = %Resume
@onready var _level_choice: LevelChoice = %LevelChoice
@onready var _settings_button: Button = %Settings
@onready var _quit_to_menu: Button = %QuitToMenu
@onready var _quit_to_desktop: Button = %QuitToDesktop
@onready var _settings: SettingsSubMenu = %SettingsSubMenu


func _ready() -> void:
	_blur_material = _blur.material
	save_note.name = "SaveNote"
	save_note.theme_type_variation = &"LabelHudCaption"
	save_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_note.hide()
	_resume.get_parent().get_parent().add_child(save_note)
	_resume.pressed.connect(_on_resume_pressed)
	_level_choice.level_chosen.connect(_on_level_chosen)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_to_menu.pressed.connect(_on_quit_to_menu_pressed)
	_quit_to_desktop.pressed.connect(_on_quit_to_desktop_pressed)
	_settings.back_requested.connect(_on_settings_back)
	# The mouse and keyboard/gamepad share one highlight: hovering an item focuses it
	for button in _menu_buttons():
		button.mouse_entered.connect(button.grab_focus)


func _menu_buttons() -> Array[Button]:
	var buttons: Array[Button] = [_resume]
	for child in _level_choice.get_children():
		if child is Button:
			buttons.append(child)
	buttons.append_array([_settings_button, _quit_to_menu, _quit_to_desktop])
	return buttons


## Title, rule, then the buttons in order: the things that fade in one after another
func _entrance_items() -> Array[Control]:
	return [%Title, %Rule, _resume, _level_choice, _settings_button, _quit_to_menu, _quit_to_desktop]


## The reason saving is unavailable ("Return to the habitat to save", "Release the claw to save"), or nothing
func refresh_save_note() -> void:
	save_note.text = SaveGate.block_reason(get_tree())
	save_note.visible = save_note.text != ""


func _on_resume_pressed():
	GameState.return_to_game()


# Loads the chosen level in place of this one; leaving PAUSED unpauses the tree, and the old
# level (player, rovers, held props, cameras) is freed before the new one is set up
func _on_level_chosen(level_id: String):
	SceneLoader.load_scene(level_id)


func _on_quit_to_menu_pressed():
	SceneLoader.load_scene("main_menu")


func _on_quit_to_desktop_pressed():
	get_tree().quit()


func _on_settings_pressed():
	if sub_screen == SubScreen.SETTINGS:
		return
	sub_screen = SubScreen.SETTINGS
	# The settings blur takes over from this one, so the two don't stack
	_set_content_interactive(false)
	_animate_blur(0.0, FADE_DURATION)
	_animate_content(0.0, BLUR_OUT_TIME)
	_settings.open()


func _on_settings_back():
	if sub_screen != SubScreen.SETTINGS:
		return
	sub_screen = SubScreen.PAUSE_MENU
	_settings.close()
	_set_content_interactive(true)
	_animate_blur(1.0, FADE_DURATION)
	_animate_content(1.0, BLUR_IN_TIME)
	_settings_button.grab_focus()


## True while the settings screen is up: Esc is for the settings, not for resuming the game
func is_settings_open() -> bool:
	return _shown and sub_screen == SubScreen.SETTINGS


func fade_in():
	_generation += 1
	_shown = true
	sub_screen = SubScreen.PAUSE_MENU
	_settings.close(false)
	_level_choice.refresh()
	refresh_save_note()
	_kill_tweens()
	_root.show()
	_set_content_interactive(true)
	_content.modulate.a = 1.0
	_animate_blur(1.0, BLUR_IN_TIME)
	for item in _entrance_items():
		item.modulate.a = 0.0
	_resume.grab_focus()
	_rise_items(_generation)


func fade_out():
	if not _shown:
		return
	_generation += 1
	_shown = false
	sub_screen = SubScreen.PAUSE_MENU
	_settings.close(false)
	_set_content_interactive(false)
	if _items_tween:
		_items_tween.kill()
	_animate_blur(0.0, BLUR_OUT_TIME)
	_animate_content(0.0, BLUR_OUT_TIME)
	_content_tween.tween_callback(_hide_root.bind(_generation))


func _hide_root(generation: int) -> void:
	if generation == _generation:
		_root.hide()


## The items fade in and rise to where the layout put them. That is known only once the
## containers have laid the (just shown) menu out, so this waits one frame, with the items
## invisible meanwhile.
func _rise_items(generation: int) -> void:
	await get_tree().process_frame
	if generation != _generation:
		return
	_items_tween = create_tween()
	_items_tween.set_ignore_time_scale(true)
	_items_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_items_tween.set_ease(Tween.EASE_OUT)
	_items_tween.set_trans(Tween.TRANS_CUBIC)
	_items_tween.set_parallel(true)
	var items: Array[Control] = _entrance_items()
	for i in items.size():
		var item: Control = items[i]
		var delay: float = TITLE_DELAY if i == 0 else RULE_DELAY if i == 1 else FIRST_ITEM_DELAY + ITEM_STAGGER * (i - 2)
		var rest_y: float = item.position.y
		item.position.y = rest_y + RISE
		_items_tween.tween_property(item, "modulate:a", 1.0, RISE_TIME).set_delay(delay)
		_items_tween.tween_property(item, "position:y", rest_y, RISE_TIME).set_delay(delay)


func _kill_tweens() -> void:
	for tween in [_blur_tween, _content_tween, _items_tween]:
		if tween:
			tween.kill()


func _animate_blur(amount: float, duration: float) -> void:
	if _blur_tween:
		_blur_tween.kill()
	_blur_tween = create_ui_tween()
	_blur_tween.set_ease(Tween.EASE_OUT)
	_blur_tween.tween_method(func(v: float) -> void: _blur_material.set_shader_parameter(&"amount", v),
		float(_blur_material.get_shader_parameter(&"amount")), amount, duration)


func _animate_content(alpha: float, duration: float) -> void:
	if _content_tween:
		_content_tween.kill()
	_content_tween = create_ui_tween()
	_content_tween.set_ease(Tween.EASE_OUT)
	_content_tween.tween_property(_content, "modulate:a", alpha, duration)


## While the settings (or nothing) are shown the menu items take no mouse or focus
func _set_content_interactive(on: bool) -> void:
	_content.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED if on else Control.MOUSE_BEHAVIOR_DISABLED
	_content.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if on else Control.FOCUS_BEHAVIOR_DISABLED
