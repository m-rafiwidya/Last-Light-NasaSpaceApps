extends MarginContainer
## Settings sub-screen. Pressing a tab button (General / Audio / Video / Controls) instantly shows
## that tab's list of dummy settings under the tab row. Exactly one tab is always shown
## (General by default); pressing the active tab again does nothing.
## Most widgets are placeholders; the real ones are Video > Terrain Detail and Dust and Tracks
## (GraphicsSettings) and
## Audio > Master / Music / Effects / Interface Volume (AudioSettings through AudioManager).
## Every button, toggle and slider plays its UI sound (ButtonSoundComponent, AudioManager).

const LABEL_MIN_WIDTH := 260.0
const WIDGET_MIN_WIDTH := 320.0

enum Tab { GENERAL, AUDIO, VIDEO, CONTROLS }

## Node names of the tab buttons / pages, indexed by Tab.
const TAB_NAMES: Array[String] = ["General", "Audio", "Video", "Controls"]

var tab: Tab = Tab.GENERAL
var _pages: Array[Control] = []


func _ready() -> void:
	for i in TAB_NAMES.size():
		var tab_name := TAB_NAMES[i]
		_pages.append($VBoxContainer/Pages.get_node(tab_name))
		var tab_button: Button = $VBoxContainer/HBoxContainer.get_node(tab_name)
		tab_button.pressed.connect(_set_tab.bind(i as Tab))

	_build_general(_rows("General"))
	_build_audio(_rows("Audio"))
	_build_video(_rows("Video"))
	_build_controls(_rows("Controls"))

	_set_tab(Tab.GENERAL)


func _set_tab(new_tab: Tab) -> void:
	tab = new_tab
	for i in _pages.size():
		_pages[i].visible = (i == tab)


func _rows(tab_name: String) -> VBoxContainer:
	return _pages[TAB_NAMES.find(tab_name)].get_node("Rows")


# --- Tabs ---------------------------------------------------------------------------------------

func _build_general(rows: VBoxContainer) -> void:
	_add_option(rows, "Language", ["English", "Svenska", "Deutsch", "Francais"])
	_add_check(rows, "Subtitles", true)
	_add_slider(rows, "Subtitle Size", 50.0, 150.0, 100.0, "%")
	_add_check(rows, "Camera Shake", true)
	_add_check(rows, "Show Tooltips", true)
	_add_check(rows, "Show FPS Counter", false)
	_add_button(rows, "Reset To Defaults")


func _build_audio(rows: VBoxContainer) -> void:
	_add_volume(rows, "Master Volume", "master")
	_add_volume(rows, "Music Volume", "music")
	_add_volume(rows, "Effects Volume", "effects")
	# Dummy until the game has a voice bus
	_add_slider(rows, "Voice Volume", 0.0, 100.0, 90.0, "%")
	_add_volume(rows, "Interface Volume", "interface")
	_add_check(rows, "Mute When Unfocused", true)
	_add_option(rows, "Speaker Setup", ["Stereo", "Headphones", "Surround 5.1"])


func _build_video(rows: VBoxContainer) -> void:
	_add_option(rows, "Display Mode", ["Windowed", "Fullscreen", "Borderless"])
	_add_option(rows, "Resolution", ["1280x720", "1920x1080", "2560x1440", "3840x2160"])
	_add_option(rows, "Quality Preset", ["Low", "Medium", "High", "Ultra"])
	_add_graphics_option(rows, "Terrain Detail", GraphicsSettings.TERRAIN_DETAIL_NAMES, GraphicsSettings.get_terrain_detail(),
		func(index: int) -> void: GraphicsSettings.set_terrain_detail(index as GraphicsSettings.TerrainDetail))
	_add_graphics_option(rows, "Dust and Tracks", GraphicsSettings.SURFACE_EFFECTS_NAMES, GraphicsSettings.get_surface_effects(),
		func(index: int) -> void: GraphicsSettings.set_surface_effects(index as GraphicsSettings.SurfaceEffects))
	_add_check(rows, "VSync", true)
	_add_option(rows, "Frame Rate Limit", ["30", "60", "120", "Unlimited"])
	_add_slider(rows, "Field Of View", 60.0, 120.0, 90.0, "")
	_add_slider(rows, "Brightness", 0.0, 100.0, 50.0, "%")
	_add_check(rows, "Motion Blur", false)


func _build_controls(rows: VBoxContainer) -> void:
	_add_slider(rows, "Mouse Sensitivity", 1.0, 100.0, 40.0, "")
	_add_check(rows, "Invert Y Axis", false)
	_add_check(rows, "Toggle Crouch", false)
	_add_button(rows, "Move Forward", "W")
	_add_button(rows, "Move Backward", "S")
	_add_button(rows, "Move Left", "A")
	_add_button(rows, "Move Right", "D")
	_add_button(rows, "Jump", "Space")
	_add_button(rows, "Crouch", "Ctrl")
	_add_button(rows, "Interact", "E")
	_add_button(rows, "Reset Bindings")


# --- Row helpers --------------------------------------------------------------------------------

func _make_row(rows: VBoxContainer, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	rows.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = LABEL_MIN_WIDTH
	row.add_child(label)
	return row


func _add_check(rows: VBoxContainer, label_text: String, default_value: bool) -> void:
	var row := _make_row(rows, label_text)
	var check := CheckButton.new()
	check.focus_mode = Control.FOCUS_NONE
	check.button_pressed = default_value
	row.add_child(check)
	_add_sound(check, &"")
	check.toggled.connect(AudioManager.play_toggle)


func _add_slider(rows: VBoxContainer, label_text: String, min_value: float, max_value: float,
		default_value: float, suffix: String) -> HSlider:
	var row := _make_row(rows, label_text)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = 1.0
	slider.value = default_value
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size.x = WIDGET_MIN_WIDTH
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size.x = 80.0
	value_label.text = "%d%s" % [int(default_value), suffix]
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = "%d%s" % [int(value), suffix]
		AudioManager.play_slider_tick()
	)
	return slider


## A real volume slider (AudioSettings key "master", "music", "effects" or "interface"): applied and saved as
## it moves, and kept in step (silently) when the other menu's settings (main / pause) change it
func _add_volume(rows: VBoxContainer, label_text: String, key: String) -> void:
	var slider := _add_slider(rows, label_text, 0.0, 100.0, AudioSettings.get_volume(key), "%")
	var value_label: Label = slider.get_parent().get_child(slider.get_index() + 1)
	slider.value_changed.connect(func(value: float) -> void: AudioManager.set_volume(key, value))
	var follow := func(changed_key: String, percent: float) -> void:
		if changed_key == key and not is_equal_approx(slider.value, percent):
			slider.set_value_no_signal(percent)
			value_label.text = "%d%%" % int(percent)
	AudioManager.volume_changed.connect(follow)
	slider.tree_exiting.connect(func() -> void: AudioManager.volume_changed.disconnect(follow))


func _add_option(rows: VBoxContainer, label_text: String, options: Array[String]) -> void:
	var row := _make_row(rows, label_text)
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.custom_minimum_size.x = WIDGET_MIN_WIDTH
	for item in options:
		option.add_item(item)
	row.add_child(option)
	_add_sound(option)
	option.item_selected.connect(func(_index: int) -> void: AudioManager.play_ui(&"click"))


# A real graphics setting (GraphicsSettings, saved in user://settings.cfg), used when a level loads:
# the Moon terrain's ground detail, the wheels' dust and tracks
func _add_graphics_option(rows: VBoxContainer, label_text: String, names: Array[String], selected: int, apply: Callable) -> void:
	var row := _make_row(rows, label_text)
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.custom_minimum_size.x = WIDGET_MIN_WIDTH
	for item in names:
		option.add_item(item)
	option.selected = selected
	option.item_selected.connect(func(index: int) -> void:
		apply.call(index)
		AudioManager.play_ui(&"click"))
	row.add_child(option)
	_add_sound(option)
	var note := Label.new()
	note.text = "(next level load)"
	row.add_child(note)


## With `button_text` the row is "label ... [button]" (e.g. a key binding); without it the
## label is the button's own text (e.g. "Reset To Defaults").
func _add_button(rows: VBoxContainer, label_text: String, button_text: String = "") -> void:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	if button_text.is_empty():
		button.text = label_text
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		rows.add_child(button)
		_add_sound(button)
		return

	var row := _make_row(rows, label_text)
	button.text = button_text
	button.custom_minimum_size.x = WIDGET_MIN_WIDTH
	row.add_child(button)
	_add_sound(button)


## Hover and press sounds for a widget built in code (press_sound empty: the widget plays its own,
## e.g. a toggle)
func _add_sound(button: BaseButton, press_sound: StringName = &"click") -> void:
	var sound := ButtonSoundComponent.new()
	sound.press_sound = press_sound
	button.add_child(sound)
