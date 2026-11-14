class_name SettingsSubMenu

extends Control

## Settings screen (docs/ui/UI_SPEC.md "Settings", board Settings.dc.html, design x 1.2), shared by
## the main menu and the pause menu. Opening it blurs and dims everything drawn before it (the
## menu with the Moon, or the paused game) behind a framed panel: SETTINGS, the tabs GENERAL /
## AUDIO / VIDEO / CONTROLS, rows of label + control, and BACK. The owner turns its own input off
## while this is open and closes it on `back_requested` (the BACK button or Esc).
## Exactly one tab is shown (GENERAL by default); pressing the active tab does nothing.
##
## Wired settings: Audio > Master / Music / Effects / Interface Volume (AudioSettings through
## AudioManager), Video > Display Mode (DisplaySettings), Terrain Detail and Dust and Tracks
## (GraphicsSettings).
## Dummies, not wired to anything yet (they only keep their value while the menu exists):
## General > Language, Subtitles, Subtitle Size, Camera Shake, Show Tooltips, Show FPS Counter;
## Audio > Voice Volume, Mute When Unfocused, Speaker Setup; Video > Resolution, Quality Preset,
## VSync, Frame Rate Limit, Field Of View, Brightness, Motion Blur; Controls > everything
## (Mouse Sensitivity, Invert Y Axis, Toggle Crouch and the seven key-bind slabs).
## RESET TO DEFAULTS (General) and RESET BINDINGS (Controls) put the dummies of their tab back to
## the board's defaults; the wired settings are not touched.
## Every control plays its UI sound (ButtonSoundComponent, AudioManager).

## BACK or Esc: the owner closes this and shows what it came from
signal back_requested

const OPEN_TIME: float = 0.5
const CLOSE_TIME: float = 0.3

## Row geometry (design x 1.2): label column 220, control column 300, gap 20, min height 40
const ROW_HEIGHT: float = 48.0
const ROW_GAP: float = 24.0
const LABEL_WIDTH: float = 264.0
const CONTROL_WIDTH: float = 360.0
## RESET button: 22 px above it on the board
const RESET_GAP: float = 26.0

const TOGGLE: PackedScene = preload("res://src/ui/components/slanted_toggle.tscn")
const SELECT: PackedScene = preload("res://src/ui/components/slanted_select.tscn")
const SLIDER: PackedScene = preload("res://src/ui/components/settings_slider.tscn")
const KEY_SLAB: PackedScene = preload("res://src/ui/components/key_bind_slab.tscn")
const SOLID: PackedScene = preload("res://src/ui/components/solid_button.tscn")

enum Tab { GENERAL, AUDIO, VIDEO, CONTROLS }

## Node names of the tab buttons / pages, indexed by Tab.
const TAB_NAMES: Array[String] = ["General", "Audio", "Video", "Controls"]

var tab: Tab = Tab.GENERAL
var is_open: bool = false

var _pages: Array[Control] = []
var _tab_buttons: Array[SlantedTab] = []
## Per tab: what a tab's reset button restores (a Callable per dummy row) and the controls in
## row order, for keyboard / gamepad focus
var _resets: Array[Array] = [[], [], [], []]
var _focusables: Array[Array] = [[], [], [], []]
var _tween: Tween
var _blur_material: ShaderMaterial

@onready var _blur: ColorRect = $Blur
@onready var _panel: Control = $Panel
@onready var _back: Button = %Back


func _ready() -> void:
	_blur_material = _blur.material
	for i in TAB_NAMES.size():
		var tab_name := TAB_NAMES[i]
		_pages.append(%Pages.get_node(tab_name))
		var tab_button: SlantedTab = %Tabs.get_node(tab_name)
		_tab_buttons.append(tab_button)
		tab_button.pressed.connect(_set_tab.bind(i as Tab))
	_back.pressed.connect(back_requested.emit)

	_build_general(_rows("General"))
	_build_audio(_rows("Audio"))
	_build_video(_rows("Video"))
	_build_controls(_rows("Controls"))

	_set_tab(Tab.GENERAL)
	_wire_focus()
	_set_interactive(false)
	hide()


## Esc goes back, like BACK. In _input, before the GUI and before the UIManager sees it. A key slab
## that is listening or an open select list takes the Esc first.
func _input(event: InputEvent) -> void:
	if not is_open or Debug.console_open or get_viewport().is_input_handled():
		return
	if not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	if _is_listening() or _is_select_open():
		return
	get_viewport().set_input_as_handled()
	AudioManager.play_ui(&"back")
	back_requested.emit()


## Shows the screen over what is behind it. Focus goes to the active tab.
func open() -> void:
	if is_open:
		return
	is_open = true
	show()
	_set_interactive(true)
	_animate(1.0, OPEN_TIME)
	_panel.modulate.a = 0.0
	_tween.parallel().tween_property(_panel, "modulate:a", 1.0, OPEN_TIME)
	_tab_buttons[tab].grab_focus()


## Hides it (what is behind sharpens again). `animate = false` hides it at once.
func close(animate: bool = true) -> void:
	if not is_open:
		return
	is_open = false
	_set_interactive(false)
	if animate:
		_animate(0.0, CLOSE_TIME)
		_tween.parallel().tween_property(_panel, "modulate:a", 0.0, CLOSE_TIME)
		_tween.tween_callback(hide)
	else:
		if _tween:
			_tween.kill()
		_blur_material.set_shader_parameter(&"amount", 0.0)
		hide()


func _set_tab(new_tab: Tab) -> void:
	tab = new_tab
	for i in _pages.size():
		_pages[i].visible = (i == tab)
		_tab_buttons[i].active = (i == tab)
	_wire_tab_links()


func _rows(tab_name: String) -> VBoxContainer:
	return _pages[TAB_NAMES.find(tab_name)].get_node("Rows")


func _is_listening() -> bool:
	for slab in find_children("*", "KeyBindSlab", true, false):
		if (slab as KeyBindSlab).listening:
			return true
	return false


func _is_select_open() -> bool:
	for select in find_children("*", "SlantedSelect", true, false):
		if (select as SlantedSelect).get_popup().visible:
			return true
	return false


## While closed (or closing) nothing in the screen takes the mouse or focus
func _set_interactive(on: bool) -> void:
	_blur.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	_panel.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED if on else Control.MOUSE_BEHAVIOR_DISABLED
	_panel.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if on else Control.FOCUS_BEHAVIOR_DISABLED


func _animate(blur_to: float, duration: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(false)
	_tween.set_ignore_time_scale(true)
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(func(v: float) -> void: _blur_material.set_shader_parameter(&"amount", v),
		float(_blur_material.get_shader_parameter(&"amount")), blur_to, duration)


# --- Focus (keyboard / gamepad) -----------------------------------------------------------------

## Up / down walk the rows of a page, from its tab at the top to BACK at the bottom. The links
## that depend on the shown tab are set in _wire_tab_links.
func _wire_focus() -> void:
	var here := NodePath(".")
	for i in _focusables.size():
		var controls: Array = _focusables[i]
		for j in controls.size():
			var control: Control = controls[j]
			control.focus_neighbor_left = here
			control.focus_neighbor_right = here
			control.focus_neighbor_top = control.get_path_to(controls[j - 1] if j > 0 else _tab_buttons[i])
			control.focus_neighbor_bottom = control.get_path_to(controls[j + 1] if j + 1 < controls.size() else _back)
	_back.focus_neighbor_left = here
	_back.focus_neighbor_right = here
	_back.focus_neighbor_bottom = here
	_tab_buttons[0].focus_neighbor_left = here
	_tab_buttons[-1].focus_neighbor_right = here
	for button in _tab_buttons:
		button.focus_neighbor_top = here


func _wire_tab_links() -> void:
	var controls: Array = _focusables[tab]
	for button in _tab_buttons:
		button.focus_neighbor_bottom = button.get_path_to(controls[0] if not controls.is_empty() else _back)
	_back.focus_neighbor_top = _back.get_path_to(controls[-1] if not controls.is_empty() else _tab_buttons[tab])


# --- Tabs ---------------------------------------------------------------------------------------

func _build_general(rows: VBoxContainer) -> void:
	var t := Tab.GENERAL
	_add_option(rows, t, "Language", ["English", "Bahasa Indonesia"])
	_add_toggle(rows, t, "Subtitles", true)
	_add_slider(rows, t, "Subtitle Size", 50.0, 200.0, 100.0, "%")
	_add_toggle(rows, t, "Camera Shake", true)
	_add_toggle(rows, t, "Show Tooltips", true)
	_add_toggle(rows, t, "Show FPS Counter", false)
	_add_reset(rows, t, "RESET TO DEFAULTS")


func _build_audio(rows: VBoxContainer) -> void:
	var t := Tab.AUDIO
	_add_volume(rows, t, "Master Volume", "master")
	_add_volume(rows, t, "Music Volume", "music")
	_add_volume(rows, t, "Effects Volume", "effects")
	# Dummy until the game has a voice bus
	_add_slider(rows, t, "Voice Volume", 0.0, 100.0, 90.0, "%")
	_add_volume(rows, t, "Interface Volume", "interface")
	_add_toggle(rows, t, "Mute When Unfocused", true)
	_add_option(rows, t, "Speaker Setup", ["Stereo", "Headphones", "Mono", "Surround 5.1"])


func _build_video(rows: VBoxContainer) -> void:
	var t := Tab.VIDEO
	_add_display_mode(rows, t)
	_add_option(rows, t, "Resolution", ["1280x720", "1600x900", "1920x1080", "2560x1440"])
	_add_option(rows, t, "Quality Preset", ["Low", "Medium", "High", "Ultra"])
	_add_graphics_option(rows, t, "Terrain Detail", GraphicsSettings.TERRAIN_DETAIL_NAMES, GraphicsSettings.get_terrain_detail(),
		func(index: int) -> void: GraphicsSettings.set_terrain_detail(index as GraphicsSettings.TerrainDetail))
	# The labels are the board's; the three entries are GraphicsSettings.SurfaceEffects in order
	_add_graphics_option(rows, t, "Dust and Tracks", ["High", "Low", "Off"], GraphicsSettings.get_surface_effects(),
		func(index: int) -> void: GraphicsSettings.set_surface_effects(index as GraphicsSettings.SurfaceEffects))
	_add_toggle(rows, t, "VSync", true)
	_add_option(rows, t, "Frame Rate Limit", ["30", "60", "120", "144", "Unlimited"])
	_add_slider(rows, t, "Field Of View", 60.0, 120.0, 90.0, "")
	_add_slider(rows, t, "Brightness", 0.0, 100.0, 50.0, "%")
	_add_toggle(rows, t, "Motion Blur", false)


func _build_controls(rows: VBoxContainer) -> void:
	var t := Tab.CONTROLS
	_add_slider(rows, t, "Mouse Sensitivity", 1.0, 100.0, 40.0, "")
	_add_toggle(rows, t, "Invert Y Axis", false)
	_add_toggle(rows, t, "Toggle Crouch", false)
	_add_key(rows, t, "Move Forward", "W")
	_add_key(rows, t, "Move Backward", "S")
	_add_key(rows, t, "Move Left", "A")
	_add_key(rows, t, "Move Right", "D")
	_add_key(rows, t, "Jump", "Space")
	_add_key(rows, t, "Crouch", "Ctrl")
	_add_key(rows, t, "Interact", "E")
	_add_reset(rows, t, "RESET BINDINGS")


# --- Row helpers --------------------------------------------------------------------------------

## A row is a PanelContainer (the divider) holding an HBox: label, control, then what follows
## (a slider's value, a note). Returns the HBox.
func _make_row(rows: VBoxContainer, label_text: String) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SettingsRow"
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(ROW_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var label := Label.new()
	label.theme_type_variation = &"LabelMono"
	label.text = label_text
	label.custom_minimum_size.x = LABEL_WIDTH
	label.size_flags_vertical = Control.SIZE_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


## Adds a control to a row, centred, and to its tab's focus order
func _place(row: HBoxContainer, tab_index: Tab, control: Control) -> void:
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	_focusables[tab_index].append(control)


func _add_toggle(rows: VBoxContainer, tab_index: Tab, label_text: String, default_value: bool) -> SlantedToggle:
	var row := _make_row(rows, label_text)
	var toggle: SlantedToggle = TOGGLE.instantiate()
	_place(row, tab_index, toggle)
	toggle.set_on(default_value)
	_add_sound(toggle, &"")
	toggle.toggled.connect(AudioManager.play_toggle)
	_resets[tab_index].append(func() -> void: toggle.set_on(default_value))
	return toggle


func _add_slider(rows: VBoxContainer, tab_index: Tab, label_text: String, min_value: float, max_value: float,
		default_value: float, suffix: String) -> SettingsSlider:
	var row := _make_row(rows, label_text)
	var slider: SettingsSlider = SLIDER.instantiate()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.value = default_value
	_place(row, tab_index, slider)

	var value_label := Label.new()
	value_label.theme_type_variation = &"LabelMonoValue"
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The slider is narrower than the control column; the label starts at the third column
	var indent := StyleBoxEmpty.new()
	indent.content_margin_left = CONTROL_WIDTH - SettingsSlider.WIDTH
	value_label.add_theme_stylebox_override(&"normal", indent)
	value_label.text = "%d%s" % [int(default_value), suffix]
	row.add_child(value_label)
	slider.set_meta(&"value_label", value_label)
	slider.set_meta(&"suffix", suffix)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = "%d%s" % [int(value), suffix]
		AudioManager.play_slider_tick()
	)
	_resets[tab_index].append(func() -> void: _set_slider_silently(slider, default_value))
	return slider


func _set_slider_silently(slider: Slider, value: float) -> void:
	slider.set_value_no_signal(value)
	(slider.get_meta(&"value_label") as Label).text = "%d%s" % [int(value), slider.get_meta(&"suffix")]


## A real volume slider (AudioSettings key "master", "music", "effects" or "interface"): applied and saved as
## it moves, and kept in step (silently) when the other menu's settings (main / pause) change it
func _add_volume(rows: VBoxContainer, tab_index: Tab, label_text: String, key: String) -> void:
	var slider := _add_slider(rows, tab_index, label_text, 0.0, 100.0, AudioSettings.get_volume(key), "%")
	# Volumes are not part of a tab's reset
	_resets[tab_index].pop_back()
	slider.value_changed.connect(func(value: float) -> void: AudioManager.set_volume(key, value))
	var follow := func(changed_key: String, percent: float) -> void:
		if changed_key == key and not is_equal_approx(slider.value, percent):
			_set_slider_silently(slider, percent)
	AudioManager.volume_changed.connect(follow)
	slider.tree_exiting.connect(func() -> void: AudioManager.volume_changed.disconnect(follow))


func _add_select(row: HBoxContainer, tab_index: Tab, options: Array[String]) -> SlantedSelect:
	var select: SlantedSelect = SELECT.instantiate()
	for item in options:
		select.add_item(item)
	_place(row, tab_index, select)
	_add_sound(select)
	return select


func _add_option(rows: VBoxContainer, tab_index: Tab, label_text: String, options: Array[String]) -> void:
	var row := _make_row(rows, label_text)
	var select := _add_select(row, tab_index, options)
	select.item_selected.connect(func(_index: int) -> void: AudioManager.play_ui(&"click"))
	_resets[tab_index].append(func() -> void: select.select(0))


## The window mode (DisplaySettings): applied and saved at once; follows F11 / Alt+Enter and the
## other menu's settings (main / pause), silently
func _add_display_mode(rows: VBoxContainer, tab_index: Tab) -> void:
	var row := _make_row(rows, "Display Mode")
	var select := _add_select(row, tab_index, DisplaySettings.MODE_NAMES)
	select.selected = DisplaySettings.get_mode()
	select.item_selected.connect(func(index: int) -> void:
		DisplaySettings.set_mode(index as DisplaySettings.Mode)
		AudioManager.play_ui(&"click"))
	var follow := func(mode: int) -> void:
		if select.selected != mode:
			select.select(mode)
	DisplaySettings.events.mode_changed.connect(follow)
	select.tree_exiting.connect(func() -> void: DisplaySettings.events.mode_changed.disconnect(follow))


# A real graphics setting (GraphicsSettings, saved in user://settings.cfg), used when a level loads:
# the Moon terrain's ground detail, the wheels' dust and tracks
func _add_graphics_option(rows: VBoxContainer, tab_index: Tab, label_text: String, names: Array[String],
		selected: int, apply: Callable) -> void:
	var row := _make_row(rows, label_text)
	var select := _add_select(row, tab_index, names)
	select.selected = selected
	select.item_selected.connect(func(index: int) -> void:
		apply.call(index)
		AudioManager.play_ui(&"click"))
	var note := Label.new()
	note.theme_type_variation = &"LabelMonoNote"
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.text = "(next level load)"
	row.add_child(note)


## A key-bind row: the slab shows the key, a click listens for the next one (a dummy: nothing is
## rebound yet)
func _add_key(rows: VBoxContainer, tab_index: Tab, label_text: String, default_key: String) -> void:
	var row := _make_row(rows, label_text)
	var slab: KeyBindSlab = KEY_SLAB.instantiate()
	_place(row, tab_index, slab)
	slab.key_text = default_key
	_add_sound(slab)
	slab.key_bound.connect(func(_key_name: String) -> void: AudioManager.play_ui(&"click"))
	_resets[tab_index].append(func() -> void: slab.key_text = default_key)


## The tab's reset button under its rows: puts the tab's dummy rows back to their defaults
func _add_reset(rows: VBoxContainer, tab_index: Tab, button_text: String) -> void:
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", int(RESET_GAP))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(holder)
	var button: SolidButton = SOLID.instantiate()
	button.compact = true
	button.text = button_text
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.add_child(button)
	_focusables[tab_index].append(button)
	_add_sound(button)
	button.pressed.connect(reset_tab.bind(tab_index))


## Puts the dummy rows of a tab back to the board's defaults (the wired settings stay)
func reset_tab(tab_index: Tab) -> void:
	for restore: Callable in _resets[tab_index]:
		restore.call()


## Hover and press sounds for a widget built in code (press_sound empty: the widget plays its own,
## e.g. a toggle)
func _add_sound(button: BaseButton, press_sound: StringName = &"click") -> void:
	var sound := ButtonSoundComponent.new()
	sound.press_sound = press_sound
	button.add_child(sound)
