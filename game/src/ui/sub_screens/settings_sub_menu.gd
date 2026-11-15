class_name SettingsSubMenu

extends Control

## Settings screen (docs/ui/UI_SPEC.md "Settings", board Settings.dc.html, design x 1.2), shared by
## the main menu and the pause menu. Opening it blurs and dims everything drawn before it (the
## menu with the Moon, or the paused game) behind a framed panel: SETTINGS, the tabs GENERAL /
## AUDIO / VIDEO / CONTROLS, rows of label + control, and BACK. The owner turns its own input off
## while this is open and closes it on `back_requested` (the BACK button or Esc).
## Exactly one tab is shown (GENERAL by default); pressing the active tab does nothing.
##
## Every row is a real setting, applied at once (or at the next level load where the row says
## so), saved in user://settings.cfg and restored at launch:
##   General   Subtitles, Subtitle Size, Show Tooltips, Show FPS Counter (GeneralSettings)
##   Audio     Master / Music / Effects / Voice / Interface Volume (AudioSettings through
##             AudioManager), Mute When Unfocused (AudioSettings.options)
##   Video     Display Mode (DisplaySettings), Terrain Detail and Dust and Tracks (GraphicsSettings),
##             Resolution, Quality Preset, VSync, Frame Rate Limit, Field Of View, Brightness
##             (VideoSettings)
##   Controls  Mouse Sensitivity, Invert Y Axis, Toggle Crouch (ControlSettings), then a key slab
##             per rebindable action (InputBindings.ACTIONS: click, press a key; a key in use is
##             swapped and the note under the slabs says so) and the fixed ones (InputBindings.LOCKED)
## Rows of the board that can't do anything in this game are hidden (HIDDEN_ROWS says why); they
## stay hidden whatever the menu does.
## RESET TO DEFAULTS (General) resets the General settings, RESET BINDINGS (Controls) the key
## bindings to the project's. Every control shows the setting's real value when the screen opens,
## and after each change (a preset or a swapped key changes other rows).
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

## Board rows that are hidden, and why (row label -> reason)
const HIDDEN_ROWS: Dictionary = {
	"Language": "the game has no translations, English only",
	"Camera Shake": "the game has no camera shake",
	"Speaker Setup": "Godot mixes to the output device's own speaker layout; there is nothing to pick",
	"Motion Blur": "Godot 4 has no motion blur",
}
## The Quality Preset list's last entry: shown while Terrain Detail / Dust and Tracks differ from
## the preset (not selectable)
const QUALITY_CUSTOM: String = "Custom"

## Node names of the tab buttons / pages, indexed by Tab.
const TAB_NAMES: Array[String] = ["General", "Audio", "Video", "Controls"]

var tab: Tab = Tab.GENERAL
var is_open: bool = false

var _pages: Array[Control] = []
var _tab_buttons: Array[SlantedTab] = []
## Per tab: the controls in row order, for keyboard / gamepad focus
var _focusables: Array[Array] = [[], [], [], []]
## Callables that show each control's setting as it is now (silently), see _refresh
var _refreshers: Array[Callable] = []
## Under the key slabs: what the last rebind did (a swap, a refusal)
var _binding_note: Label
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
	_refresh()
	_binding_note.text = ""
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
	var general := GeneralSettings.section
	_add_hidden(rows, "Language")
	_add_section_toggle(rows, t, "Subtitles", general, "subtitles")
	_add_slider(rows, t, "Subtitle Size", GeneralSettings.SUBTITLE_SIZE_MIN, GeneralSettings.SUBTITLE_SIZE_MAX, "%",
		general.get_value.bind("subtitle_size"), func(value: float) -> void: general.set_value("subtitle_size", value))
	_add_hidden(rows, "Camera Shake")
	_add_section_toggle(rows, t, "Show Tooltips", general, "show_tooltips")
	_add_section_toggle(rows, t, "Show FPS Counter", general, "show_fps")
	_add_section_toggle(rows, t, "Show Guidance", general, "guidance")
	_add_section_toggle(rows, t, "Show Traction Display", general, "show_traction")
	_add_reset(rows, t, "RESET TO DEFAULTS", general.reset)


func _build_audio(rows: VBoxContainer) -> void:
	var t := Tab.AUDIO
	_add_volume(rows, t, "Master Volume", "master")
	_add_volume(rows, t, "Music Volume", "music")
	_add_volume(rows, t, "Effects Volume", "effects")
	_add_volume(rows, t, "Voice Volume", "voice")
	_add_volume(rows, t, "Interface Volume", "interface")
	_add_section_toggle(rows, t, "Mute When Unfocused", AudioSettings.options, "mute_when_unfocused")
	_add_hidden(rows, "Speaker Setup")


func _build_video(rows: VBoxContainer) -> void:
	var t := Tab.VIDEO
	var video := VideoSettings.section
	_add_display_mode(rows, t)
	_add_choice(rows, t, "Resolution", VideoSettings.RESOLUTION_NAMES, VideoSettings.resolution_index,
		func(index: int) -> void: VideoSettings.set_value("resolution", index), "(windowed)")
	var quality := _add_choice(rows, t, "Quality Preset", VideoSettings.QUALITY_NAMES + [QUALITY_CUSTOM],
		func() -> int: return video.get_value("quality") if VideoSettings.quality_matches_graphics() else VideoSettings.Quality.size(),
		func(index: int) -> void: VideoSettings.set_quality(index as VideoSettings.Quality), "(ground, dust: next level load)")
	quality.set_item_disabled(VideoSettings.Quality.size(), true)
	_add_choice(rows, t, "Terrain Detail", GraphicsSettings.TERRAIN_DETAIL_NAMES, GraphicsSettings.get_terrain_detail,
		func(index: int) -> void: GraphicsSettings.set_terrain_detail(index as GraphicsSettings.TerrainDetail), "(next level load)")
	# The labels are the board's; the three entries are GraphicsSettings.SurfaceEffects in order
	_add_choice(rows, t, "Dust and Tracks", ["High", "Low", "Off"], GraphicsSettings.get_surface_effects,
		func(index: int) -> void: GraphicsSettings.set_surface_effects(index as GraphicsSettings.SurfaceEffects), "(next level load)")
	_add_toggle(rows, t, "VSync", video.get_value.bind("vsync"), func(on: bool) -> void: VideoSettings.set_value("vsync", on))
	_add_choice(rows, t, "Frame Rate Limit", VideoSettings.FRAME_RATE_NAMES, video.get_value.bind("frame_rate_limit"),
		func(index: int) -> void: VideoSettings.set_value("frame_rate_limit", index))
	_add_slider(rows, t, "Field Of View", VideoSettings.FOV_MIN, VideoSettings.FOV_MAX, "", video.get_value.bind("fov"),
		func(value: float) -> void: VideoSettings.set_value("fov", value))
	_add_slider(rows, t, "Brightness", 0.0, 100.0, "%", video.get_value.bind("brightness"),
		func(value: float) -> void: VideoSettings.set_value("brightness", value))
	_add_hidden(rows, "Motion Blur")


func _build_controls(rows: VBoxContainer) -> void:
	var t := Tab.CONTROLS
	var controls := ControlSettings.section
	_add_slider(rows, t, "Mouse Sensitivity", 1.0, 100.0, "", controls.get_value.bind("mouse_sensitivity"),
		func(value: float) -> void: controls.set_value("mouse_sensitivity", value))
	_add_section_toggle(rows, t, "Invert Y Axis", controls, "invert_y")
	_add_section_toggle(rows, t, "Toggle Crouch", controls, "toggle_crouch")
	for entry in InputBindings.ACTIONS:
		_add_key(rows, t, entry[0], entry[1])
	for entry in InputBindings.LOCKED:
		_add_locked_key(rows, entry[0], entry[1])
	_binding_note = Label.new()
	_binding_note.name = "BindingNote"
	_binding_note.theme_type_variation = &"LabelMonoNote"
	_binding_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_binding_note.custom_minimum_size.y = ROW_HEIGHT
	_binding_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rows.add_child(_binding_note)
	_add_reset(rows, t, "RESET BINDINGS", func() -> void:
		InputBindings.reset()
		_binding_note.text = "")


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


## A small grey note after a row's control ("(next level load)")
func _add_note(row: HBoxContainer, text: String) -> void:
	var note := Label.new()
	note.theme_type_variation = &"LabelMonoNote"
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.text = text
	row.add_child(note)


## A board row with nothing real behind it (HIDDEN_ROWS): just its label, hidden, not focusable,
## never shown (the reason is kept as the row's "hidden_reason" meta)
func _add_hidden(rows: VBoxContainer, label_text: String) -> void:
	var row := _make_row(rows, label_text)
	var panel := row.get_parent() as Control
	panel.name = "Hidden" + label_text.replace(" ", "")
	panel.set_meta(&"hidden_reason", HIDDEN_ROWS[label_text])
	panel.hide()


## Shows every control's setting as it is now, without their signals
func _refresh() -> void:
	for refresh in _refreshers:
		refresh.call()


## A toggle for `value` (a Callable returning it); `apply` gets the new state
func _add_toggle(rows: VBoxContainer, tab_index: Tab, label_text: String, value: Callable, apply: Callable) -> SlantedToggle:
	var row := _make_row(rows, label_text)
	var toggle: SlantedToggle = TOGGLE.instantiate()
	_place(row, tab_index, toggle)
	toggle.set_on(value.call())
	_add_sound(toggle, &"")
	toggle.toggled.connect(func(on: bool) -> void:
		AudioManager.play_toggle(on)
		apply.call(on)
		_refresh())
	_refreshers.append(func() -> void:
		if toggle.button_pressed != value.call():
			toggle.set_on(value.call()))
	return toggle


## A toggle for one key of a SettingsSection
func _add_section_toggle(rows: VBoxContainer, tab_index: Tab, label_text: String, section: SettingsSection,
		key: String) -> SlantedToggle:
	return _add_toggle(rows, tab_index, label_text, section.get_value.bind(key),
		func(on: bool) -> void: section.set_value(key, on))


## A slider showing `value` (a Callable); `apply` gets each new value
func _add_slider(rows: VBoxContainer, tab_index: Tab, label_text: String, min_value: float, max_value: float,
		suffix: String, value: Callable, apply: Callable) -> SettingsSlider:
	var row := _make_row(rows, label_text)
	var slider: SettingsSlider = SLIDER.instantiate()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.value = value.call()
	_place(row, tab_index, slider)

	var value_label := Label.new()
	value_label.theme_type_variation = &"LabelMonoValue"
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The slider is narrower than the control column; the label starts at the third column
	var indent := StyleBoxEmpty.new()
	indent.content_margin_left = CONTROL_WIDTH - SettingsSlider.WIDTH
	value_label.add_theme_stylebox_override(&"normal", indent)
	row.add_child(value_label)
	slider.set_meta(&"value_label", value_label)
	slider.set_meta(&"suffix", suffix)
	_set_slider_silently(slider, slider.value)
	slider.value_changed.connect(func(new_value: float) -> void:
		value_label.text = "%d%s" % [int(new_value), suffix]
		AudioManager.play_slider_tick()
		apply.call(new_value)
		_refresh())
	_refreshers.append(func() -> void:
		if not is_equal_approx(slider.value, value.call()):
			_set_slider_silently(slider, value.call()))
	return slider


func _set_slider_silently(slider: Slider, value: float) -> void:
	slider.set_value_no_signal(value)
	(slider.get_meta(&"value_label") as Label).text = "%d%s" % [int(value), slider.get_meta(&"suffix")]


## A volume slider (AudioSettings key "master", "music", "effects", "voice" or "interface"): applied
## and saved as it moves, and kept in step (silently) when the other menu's settings (main / pause)
## change it
func _add_volume(rows: VBoxContainer, tab_index: Tab, label_text: String, key: String) -> void:
	var slider := _add_slider(rows, tab_index, label_text, 0.0, 100.0, "%", AudioSettings.get_volume.bind(key),
		func(value: float) -> void: AudioManager.set_volume(key, value))
	var follow := func(changed_key: String, percent: float) -> void:
		if changed_key == key and not is_equal_approx(slider.value, percent):
			_set_slider_silently(slider, percent)
	AudioManager.volume_changed.connect(follow)
	slider.tree_exiting.connect(func() -> void: AudioManager.volume_changed.disconnect(follow))


## A select of `names` showing `value` (a Callable returning the index); `apply` gets the index
## picked. `note` follows the select.
func _add_choice(rows: VBoxContainer, tab_index: Tab, label_text: String, names: Array, value: Callable,
		apply: Callable, note: String = "") -> SlantedSelect:
	var row := _make_row(rows, label_text)
	var select: SlantedSelect = SELECT.instantiate()
	for item: String in names:
		select.add_item(item)
	_place(row, tab_index, select)
	_add_sound(select)
	select.selected = value.call()
	select.item_selected.connect(func(index: int) -> void:
		apply.call(index)
		AudioManager.play_ui(&"click")
		_refresh())
	_refreshers.append(func() -> void:
		if select.selected != value.call():
			select.select(value.call()))
	if not note.is_empty():
		_add_note(row, note)
	return select


## The window mode (DisplaySettings): applied and saved at once; follows F11 / Alt+Enter, silently
func _add_display_mode(rows: VBoxContainer, tab_index: Tab) -> void:
	var select := _add_choice(rows, tab_index, "Display Mode", DisplaySettings.MODE_NAMES, DisplaySettings.get_mode,
		func(index: int) -> void: DisplaySettings.set_mode(index as DisplaySettings.Mode))
	var follow := func(mode: int) -> void:
		if select.selected != mode:
			select.select(mode)
	DisplaySettings.events.mode_changed.connect(follow)
	select.tree_exiting.connect(func() -> void: DisplaySettings.events.mode_changed.disconnect(follow))


## A key-bind row for `action` (InputBindings): the slab shows its key; a click listens for the
## next one and rebinds the action. A swap or a refusal is written under the slabs.
func _add_key(rows: VBoxContainer, tab_index: Tab, action: StringName, label_text: String) -> void:
	var row := _make_row(rows, label_text)
	var slab: KeyBindSlab = KEY_SLAB.instantiate()
	slab.name = "Key_" + action
	_place(row, tab_index, slab)
	slab.key_text = InputBindings.action_text(action)
	_add_sound(slab)
	slab.key_bound.connect(func(event: InputEventKey) -> void:
		var message: String = InputBindings.rebind(action, event)
		AudioManager.play_ui(&"click" if InputBindings.is_bound_to(action, event) else &"error")
		_binding_note.text = message
		_refresh())
	_refreshers.append(func() -> void: slab.key_text = InputBindings.action_text(action))


## A binding that can't be changed (InputBindings.LOCKED): a disabled slab, not focusable
func _add_locked_key(rows: VBoxContainer, action: StringName, label_text: String) -> void:
	var row := _make_row(rows, label_text)
	var slab: KeyBindSlab = KEY_SLAB.instantiate()
	slab.name = "Key_" + action
	slab.disabled = true
	slab.focus_mode = Control.FOCUS_NONE
	slab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slab)
	slab.key_text = InputBindings.action_text(action)
	_add_note(row, "(fixed)")
	_refreshers.append(func() -> void: slab.key_text = InputBindings.action_text(action))


## The tab's reset button under its rows: `reset` puts the tab's settings back to their defaults
func _add_reset(rows: VBoxContainer, tab_index: Tab, button_text: String, reset: Callable) -> void:
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
	button.pressed.connect(func() -> void:
		reset.call()
		_refresh())


## Hover and press sounds for a widget built in code (press_sound empty: the widget plays its own,
## e.g. a toggle)
func _add_sound(button: BaseButton, press_sound: StringName = &"click") -> void:
	var sound := ButtonSoundComponent.new()
	sound.press_sound = press_sound
	button.add_child(sound)
