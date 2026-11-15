extends SceneTree
## The restyled settings screen and pause menu (docs/ui/UI_SPEC.md "Pause", "Settings"):
##   1. Settings from the main menu: opens over the blurred menu (the menu takes no input, the Moon
##      keeps rendering), the tabs and the rows of every tab with the board's labels, order and
##      control kinds, a tab switch, toggles, the key slab's PRESS A KEY (a key binds, Esc only
##      cancels listening), RESET TO DEFAULTS / RESET BINDINGS, BACK and Esc both return to the
##      menu with SETTINGS focused.
##   2. Pause menu in a level: Esc pauses, the game is blurred, PAUSED and the five items in order,
##      focus on RESUME, the staggered fade-in; SETTINGS opens the shared screen, Esc there goes
##      back to the pause menu (it does not resume), a second Esc resumes.
## Wiring and layout are checked here (test_settings.gd checks what each setting does). What it
## changes is saved, so user://settings.cfg is put back as it was afterwards. The settings script
## uses autoloads, so it is not named as a type here (a test script compiles before the autoloads
## exist).
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_pause_settings.gd
##
## Windowed with `-- --shot=<dir>` it also saves settings_<tab>.png (main menu), pause.png and
## pause_settings.png.

## What each tab shows, in the board's order: [label, control kind]. The board's Language, Camera
## Shake, Speaker Setup and Motion Blur rows are hidden (test_settings.gd). Controls: then a key
## slab per InputBindings.ACTIONS entry and the locked ones (checked there too).
const BOARD: Dictionary = {
	"General": [["Subtitles", "toggle"], ["Subtitle Size", "slider"], ["Show Tooltips", "toggle"], ["Show FPS Counter", "toggle"]],
	"Audio": [["Master Volume", "slider"], ["Music Volume", "slider"], ["Effects Volume", "slider"], ["Voice Volume", "slider"],
		["Interface Volume", "slider"], ["Mute When Unfocused", "toggle"]],
	"Video": [["Display Mode", "select"], ["Resolution", "select"], ["Quality Preset", "select"], ["Terrain Detail", "select"],
		["Dust and Tracks", "select"], ["VSync", "toggle"], ["Frame Rate Limit", "select"], ["Field Of View", "slider"],
		["Brightness", "slider"]],
	"Controls": [["Mouse Sensitivity", "slider"], ["Invert Y Axis", "toggle"], ["Toggle Crouch", "toggle"], ["Move Forward", "key"],
		["Move Backward", "key"], ["Move Left", "key"], ["Move Right", "key"], ["Sprint", "key"], ["Jump", "key"], ["Crouch", "key"],
		["Interact", "key"]],
}
const SETTINGS_PATH: String = "user://settings.cfg"

var GS: Node
var SL: Node
var failures: int = 0
var shot_dir: String = ""
var _deadline_ms: int = 0
var _had_settings: bool = false
var _saved_settings: String = ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_dir = arg.trim_prefix("--shot=")
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_deadline_ms = Time.get_ticks_msec() + 240 * 1000
	_run.call_deferred()


# Real-time watchdog (a game-time timer would fire early under --fixed-fps)
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline_ms:
		printerr("WATCHDOG: no result after 240 s, quitting")
		quit(2)
	return false


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-62s %s %s" % [name, "PASS" if ok else "FAIL", detail])


## Real-time wait (works while paused, regardless of Engine.time_scale and --fixed-fps)
func _wait(seconds: float) -> void:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _wait_state(state: int, level_id: String = "", seconds: float = 120.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if GS.state == state and (level_id.is_empty() or SL.current_level_id == level_id):
			return true
		await process_frame
	return false


func _shot(file: String) -> void:
	if shot_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shot_dir.path_join(file))


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
		await process_frame


func _amount(blur: ColorRect) -> float:
	return float((blur.material as ShaderMaterial).get_shader_parameter(&"amount"))


## The shown rows of a settings page: [{label, control}]
func _rows(settings: Node, tab_name: String) -> Array:
	var rows: Array = []
	for panel in settings.find_child("Pages", true, false).get_node(tab_name).get_node("Rows").get_children():
		var hbox := panel.get_child(0) if panel is PanelContainer and panel.visible else null
		if hbox == null:
			continue
		rows.append({"label": (hbox.get_child(0) as Label).text, "control": hbox.get_child(1)})
	return rows


func _kind(control: Node) -> String:
	if control is SlantedSelect:
		return "select"
	if control is SlantedToggle:
		return "toggle"
	if control is SettingsSlider:
		return "slider"
	if control is KeyBindSlab:
		return "key"
	return "other"


func _control(settings: Node, tab_name: String, label: String) -> Control:
	for row in _rows(settings, tab_name):
		if row["label"] == label:
			return row["control"]
	return null


func _backup_settings() -> void:
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_saved_settings = FileAccess.get_file_as_string(SETTINGS_PATH)


func _restore_settings() -> void:
	if _had_settings:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		file.store_string(_saved_settings)
		file.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _run() -> void:
	_backup_settings()
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	if not await _wait_state(GS.State.MAIN_MENU):
		_check("the main menu comes up", false)
		quit(1)
		return
	await _check_main_menu_settings()
	await _check_pause()
	_restore_settings()
	print("RESULT test_pause_settings %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)


func _check_main_menu_settings() -> void:
	var menu: Node = root.get_node("Main/UIManager/MainMenu")
	var loading := root.get_node("Main/UIManager/LoadingScreen") as CanvasLayer
	await _wait(0.3)
	menu.skip_intro()
	await process_frame
	while loading.visible:
		await process_frame
	await _wait(0.6)
	var settings: Control = menu.get_node("SettingsSubMenu")
	var settings_button: Button = menu.find_child("Settings", true, false)
	var sub: Control = menu.get_node("MainMenuSubScreen")
	var moon: MenuMoon = menu.find_child("Moon", true, false)

	_check("[menu] the settings screen starts closed", not settings.is_open and not settings.visible)
	settings_button.pressed.emit()
	await _wait(0.8)
	_check("[menu] SETTINGS opens the screen", settings.is_open and settings.visible)
	_check("[menu] the menu behind takes no mouse or focus",
		sub.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_DISABLED
		and sub.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED)
	_check("[menu] the Moon keeps rendering behind the blur", moon.is_active() and moon.is_visible_in_tree())
	_check("[menu] the backdrop is blurred", _amount(settings.get_node("Blur")) > 0.99)
	var tabs: Array[Node] = settings.find_child("Tabs", true, false).get_children()
	_check("[menu] tabs GENERAL / AUDIO / VIDEO / CONTROLS", tabs.map(func(t: Node) -> String: return t.text)
		== ["GENERAL", "AUDIO", "VIDEO", "CONTROLS"])
	_check("[menu] the title is SETTINGS", settings.find_child("Title", true, false).text == "SETTINGS")
	_check("[menu] focus starts on the GENERAL tab", tabs[0].has_focus() and tabs[0].active)

	for tab_index in BOARD.size():
		var tab_name: String = BOARD.keys()[tab_index]
		(tabs[tab_index] as Button).pressed.emit()
		await _wait(0.1)
		var shown: int = 0
		for page in settings.find_child("Pages", true, false).get_children():
			shown += 1 if page.visible else 0
		_check("[%s] one page shown, its tab active" % tab_name, shown == 1 and tabs[tab_index].active
			and settings.find_child("Pages", true, false).get_node(tab_name).visible)
		var got: Array = _rows(settings, tab_name).map(func(r: Dictionary) -> Array: return [r["label"], _kind(r["control"])])
		got = got.slice(0, BOARD[tab_name].size())
		_check("[%s] the board's rows, in order" % tab_name, got == BOARD[tab_name], str(got))
		await _shot("settings_%s.png" % tab_name.to_lower())
		for row in _rows(settings, tab_name):
			if row["control"] is SlantedSelect:
				_check("[%s] %s keeps the board's 360 px width" % [tab_name, row["label"]], is_equal_approx(row["control"].size.x, 360.0))

	# Look of an open list and of keyboard focus (screenshots only)
	if not shot_dir.is_empty():
		(tabs[2] as Button).pressed.emit()
		await _wait(0.1)
		var terrain: SlantedSelect = _control(settings, "Video", "Terrain Detail")
		terrain.grab_focus()
		terrain.show_popup()
		await _wait(0.3)
		await _shot("settings_select_open.png")
		terrain.get_popup().hide()
		await _wait(0.2)
		(tabs[0] as Button).pressed.emit()
		await _wait(0.1)
		var slider_focus: Control = _control(settings, "General", "Subtitle Size")
		slider_focus.grab_focus()
		await _wait(0.2)
		await _shot("settings_focus_slider.png")
		_control(settings, "General", "Subtitles").grab_focus()
		await _wait(0.2)
		await _shot("settings_focus_toggle.png")

	# General: toggles, slider, select, reset
	(tabs[0] as Button).pressed.emit()
	await _wait(0.1)
	var subtitles: SlantedToggle = _control(settings, "General", "Subtitles")
	var size: SettingsSlider = _control(settings, "General", "Subtitle Size")
	var fps: SlantedToggle = _control(settings, "General", "Show FPS Counter")
	_check("[General] defaults: subtitles on, size 100 %, no FPS counter", subtitles.button_pressed and size.value == 100.0
		and not fps.button_pressed)
	_check("[General] size runs 50 to 200", size.min_value == 50.0 and size.max_value == 200.0)
	subtitles.button_pressed = false
	size.value = 150.0
	fps.button_pressed = true
	_check("[General] the slider shows its value", (size.get_meta(&"value_label") as Label).text == "150%")
	var reset: Button = null
	for button in settings.find_children("*", "SolidButton", true, false):
		if button.text == "RESET TO DEFAULTS":
			reset = button
	_check("[General] RESET TO DEFAULTS is there", reset != null and reset.is_visible_in_tree())
	reset.pressed.emit()
	_check("[General] reset restores the defaults", subtitles.button_pressed and size.value == 100.0 and not fps.button_pressed
		and (size.get_meta(&"value_label") as Label).text == "100%")

	# Controls: the key slab
	(tabs[3] as Button).pressed.emit()
	await _wait(0.1)
	var forward: KeyBindSlab = _control(settings, "Controls", "Move Forward")
	_check("[Controls] key slabs show their keys", forward.text == "W" and (_control(settings, "Controls", "Jump") as Button).text == "Space")
	forward.pressed.emit()
	_check("[Controls] a click starts listening: PRESS A KEY", forward.listening and forward.text == "PRESS A KEY")
	await _key(KEY_K)
	_check("[Controls] the next key binds", not forward.listening and forward.text == "K")
	forward.pressed.emit()
	await _key(KEY_ESCAPE)
	_check("[Controls] Esc only cancels listening", not forward.listening and forward.text == "K" and settings.is_open)
	forward.pressed.emit()
	forward.focus_exited.emit()
	_check("[Controls] losing focus cancels listening", not forward.listening and forward.text == "K")
	var reset_bindings: Button = null
	for button in settings.find_children("*", "SolidButton", true, false):
		if button.text == "RESET BINDINGS":
			reset_bindings = button
	_check("[Controls] RESET BINDINGS is there", reset_bindings != null and reset_bindings.is_visible_in_tree())
	reset_bindings.pressed.emit()
	_check("[Controls] reset restores the keys", forward.text == "W")
	_check("[Controls] no reset button on the other tabs", settings.find_children("*", "SolidButton", true, false).size() == 3)

	# Keyboard: down from a tab goes into the page, the last row goes to BACK
	(tabs[0] as Button).pressed.emit()
	await _wait(0.1)
	tabs[0].grab_focus()
	await _key(KEY_DOWN)
	_check("[focus] down from the tab: the first row's control", subtitles.has_focus())
	var back: Button = settings.find_child("Back", true, false)
	_check("[focus] BACK is the last stop", settings.find_child("Back", true, false) != null
		and reset.get_node(reset.focus_neighbor_bottom) == back)

	# Esc and BACK return to the menu
	await _key(KEY_ESCAPE)
	await _wait(0.5)
	_check("[menu] Esc closes the settings", not settings.is_open and not settings.visible)
	_check("[menu] back on the main menu, SETTINGS has focus", menu.sub_screen == menu.SubScreen.MAIN_MENU
		and settings_button.has_focus())
	_check("[menu] the menu takes input again", sub.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_INHERITED)
	settings_button.pressed.emit()
	await _wait(0.6)
	back.pressed.emit()
	await _wait(0.5)
	_check("[menu] BACK closes the settings the same way", not settings.is_open and menu.sub_screen == menu.SubScreen.MAIN_MENU
		and settings_button.has_focus())
	_check("[menu] still in the main menu state", GS.state == GS.State.MAIN_MENU)


func _check_pause() -> void:
	SL.load_scene("test_level")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "test_level"):
		_check("the test level loads", false)
		return
	await _wait(0.5)
	var pause: Node = root.get_node("Main/UIManager/PauseMenu")
	var pause_root: Control = pause.find_child("Root", true, false)
	var blur: ColorRect = pause.find_child("Blur", true, false)
	var content: Control = pause.find_child("Content", true, false)
	var resume: Button = pause.find_child("Resume", true, false)
	var settings: Control = pause.find_child("SettingsSubMenu", true, false)
	_check("[pause] hidden while playing", not pause_root.visible)

	await _key(KEY_ESCAPE)
	await _wait(0.1)
	_check("[pause] Esc pauses", GS.state == GS.State.PAUSED and pause_root.visible)
	_check("[pause] items fade in one after another", resume.modulate.a < 1.0 or pause.find_child("Title", true, false).modulate.a < 1.0)
	await _wait(1.0)
	_check("[pause] the game is blurred and darkened", absf(_amount(blur) - 1.0) < 0.01
		and absf((blur.material as ShaderMaterial).get_shader_parameter(&"brightness") - 0.5) < 0.01
		and absf((blur.material as ShaderMaterial).get_shader_parameter(&"radius_px") - 7.2) < 0.01)
	_check("[pause] PAUSED", pause.find_child("Title", true, false).text == "PAUSED")
	var items: Array = pause.find_child("Nav", true, false).find_children("*", "Button", true, false).filter(
		func(b: Node) -> bool: return b.is_visible_in_tree())
	_check("[pause] the six items in order, no level switch", items.map(func(b: Node) -> String: return b.text)
		== ["RESUME", "SAVE GAME", "LOAD GAME", "SETTINGS", "QUIT TO MENU", "QUIT TO DESKTOP"],
		str(items.map(func(b: Node) -> String: return b.text)))
	var save_button: Button = pause.find_child("SaveGame", true, false)
	var load_button: Button = pause.find_child("LoadGame", true, false)
	var SI: GDScript = load("res://src/save/save_index.gd")
	_check("[pause] no campaign here: SAVE GAME disabled, the note says why", save_button.disabled
		and pause.save_note.visible and pause.save_note.text == SI.NO_CAMPAIGN, pause.save_note.text)
	_check("[pause] LOAD GAME needs a save", load_button.disabled == SI.list_saves().is_empty())
	_check("[pause] the save toast is there, hidden", root.get_node_or_null("Main/UIManager/SaveToast") != null
		and root.get_node("Main/UIManager/SaveToast").text() == "")
	_check("[pause] all items are in", items.all(func(b: Control) -> bool: return b.modulate.a > 0.99))
	_check("[pause] the items are centred", items.all(func(b: Control) -> bool:
		return absf(b.get_global_rect().get_center().x - 960.0) < 2.0))
	_check("[pause] focus starts on RESUME", resume.has_focus())
	await _shot("pause.png")

	# SETTINGS, then Esc goes back to the pause menu
	var settings_button: Button = pause.find_child("Settings", true, false)
	settings_button.pressed.emit()
	await _wait(0.8)
	_check("[pause] SETTINGS opens the shared screen", settings.is_open and pause.is_settings_open())
	_check("[pause] the pause blur gives way to the settings blur", _amount(blur) < 0.01 and _amount(settings.get_node("Blur")) > 0.99)
	_check("[pause] the pause items take no input behind it", content.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_DISABLED
		and content.modulate.a < 0.01)
	await _shot("pause_settings.png")
	await _key(KEY_ESCAPE)
	await _wait(0.8)
	_check("[pause] Esc in settings goes back to the pause menu, not to the game",
		GS.state == GS.State.PAUSED and not settings.is_open and not pause.is_settings_open())
	_check("[pause] the pause menu is back, SETTINGS has focus", content.modulate.a > 0.99 and settings_button.has_focus()
		and absf(_amount(blur) - 1.0) < 0.01)
	settings_button.pressed.emit()
	await _wait(0.6)
	var back: Button = settings.find_child("Back", true, false)
	back.pressed.emit()
	await _wait(0.8)
	_check("[pause] BACK does the same", GS.state == GS.State.PAUSED and not settings.is_open and settings_button.has_focus())
	await _key(KEY_ESCAPE)
	await _wait(0.8)
	_check("[pause] Esc on the pause menu resumes", GS.state == GS.State.IN_GAME_PLAYER and not pause_root.visible)

	# Pause again; RESUME resumes
	await _key(KEY_ESCAPE)
	await _wait(1.0)
	_check("[pause] paused again, RESUME has focus", GS.state == GS.State.PAUSED and resume.has_focus())
	resume.pressed.emit()
	await _wait(0.8)
	_check("[pause] RESUME resumes", GS.state == GS.State.IN_GAME_PLAYER and not pause_root.visible)

	# LOAD GAME: the save list in load-only mode (no Delete, no START NEW CAMPAIGN); Esc returns
	DirAccess.make_dir_recursive_absolute(SI.save_dir())
	var fake_slots: int = SI.write_fake_saves()
	await _key(KEY_ESCAPE)
	await _wait(1.0)
	_check("[load] LOAD GAME enabled with saves", fake_slots == 3 and not load_button.disabled)
	load_button.pressed.emit()
	await _wait(0.7)
	var popup: Node = pause.find_child("LoadPopup", true, false)
	_check("[load] the save list opens over the pause menu", popup.is_open and pause.is_overlay_open()
		and popup.get_cards().size() == 3)
	_check("[load] load only: no Delete, no START NEW CAMPAIGN", popup.get_cards().all(func(c: Node) -> bool:
		return c.find_child("Delete", true, false) == null) and not popup.find_child("StartList", true, false).visible)
	await _key(KEY_ESCAPE)
	await _wait(0.7)
	_check("[load] Esc closes it, still paused, LOAD GAME focused", not popup.is_open and GS.state == GS.State.PAUSED
		and load_button.has_focus())
	SI.clear_fake_saves()
	# Outside a campaign QUIT TO MENU doesn't ask
	pause.find_child("QuitToMenu", true, false).pressed.emit()
	await _wait(0.1)
	_check("[quit] no campaign: QUIT TO MENU quits at once", not pause.is_quit_confirm_open()
		and SL.loading_scene_id == "main_menu")
	await _wait_state(GS.State.MAIN_MENU)
