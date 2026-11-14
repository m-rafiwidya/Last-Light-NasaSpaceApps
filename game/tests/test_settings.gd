extends SceneTree
## What every setting in the settings screen does (the layout is test_pause_settings.gd's):
##   1. Each row, changed through its control in the main menu's settings, is applied at once,
##      written to user://settings.cfg and read back after a simulated launch (the settings
##      classes reloaded from the file, the InputMap rebuilt from the project and the saved keys).
##      General: subtitles hidden / shown and their size on a playing line, the part tooltip, the
##      FPS counter (top right, IBM Plex Mono); RESET TO DEFAULTS. Audio: the Voice bus (dialogue
##      plays on it) and its volume, Master muted while the window is unfocused. Video: resolution,
##      vsync, Engine.max_fps, field of view, brightness, the quality preset (MSAA, Terrain
##      Detail / Dust and Tracks, Custom). Controls: sensitivity and invert, toggle crouch.
##   2. Key bindings: a slab rebinds its action in the InputMap, a key in use is swapped (the note
##      says so), the console's key is refused, Esc only cancels; key chips, the HUD hint and the
##      part tooltip show the new key; RESET BINDINGS puts the project's keys back (and nothing
##      stays saved); locked rows show their key.
##   3. Hidden rows (Language, Camera Shake, Speaker Setup, Motion Blur) are hidden and stay so
##      through tab switches, closing / opening and both resets.
##   4. In the test level: field of view on the player's camera and on the rover's mast and chase
##      views, brightness on the level's WorldEnvironment and the rover's tool camera, mouse
##      sensitivity and invert on foot and driving, toggle crouch.
## user://settings.cfg is moved aside while it runs (the test starts from no saved settings) and put
## back afterwards.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_settings.gd
##
## Windowed (without --headless) it also checks the window really resizing and vsync really
## switching, which the headless display server ignores:
##
##     Godot --path game -s res://tests/test_settings.gd --resolution 1920x1080

const SETTINGS_PATH: String = "user://settings.cfg"
const HIDDEN: Dictionary = {"General": ["Language", "Camera Shake"], "Audio": ["Speaker Setup"], "Video": ["Motion Blur"]}

var GS: Node
var SL: Node
var AM: Node
var failures: int = 0
var _deadline_ms: int = 0
var _had_settings: bool = false
var _saved_settings: String = ""
var settings: Control
var tabs: Array[Node] = []


func _initialize() -> void:
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_saved_settings = FileAccess.get_file_as_string(SETTINGS_PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	# This test is about the saved file: read it as a launch would
	SettingsSection.read_saved = true
	_relaunch()
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_deadline_ms = Time.get_ticks_msec() + 300 * 1000
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline_ms:
		printerr("WATCHDOG: no result after 300 s, quitting")
		_restore()
		quit(2)
	return false


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-66s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _restore() -> void:
	if _had_settings:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		file.store_string(_saved_settings)
		file.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


## Reads every setting back from the file, as a new launch would (the InputMap starts from the
## project's bindings, then gets the saved keys)
func _relaunch() -> void:
	GeneralSettings.section.reload()
	VideoSettings.section.reload()
	ControlSettings.section.reload()
	AudioSettings.options.reload()
	AudioSettings._loaded = false
	AudioSettings.load_settings()
	GraphicsSettings._loaded = false
	GraphicsSettings.load_settings()
	InputMap.load_from_project_settings()
	InputBindings.reload_saved()


func _saved(section: String, key: String) -> Variant:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return null
	return config.get_value(section, key, null)


func _wait(seconds: float) -> void:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _wait_state(state: int, level_id: String = "", seconds: float = 120.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if GS.state == state and (level_id.is_empty() or SL.current_level_id == level_id):
			return true
		await process_frame
	return false


func _key_event(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		_key_event(keycode, pressed)
		await _frames(2)


## Mouse motion. Small: the root window's stretch to 1920 x 1080 scales it up a lot headless
func _mouse(relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = relative
	motion.screen_relative = relative
	Input.parse_input_event(motion)
	await _frames(2)


func _rows_node(tab_name: String) -> Node:
	return settings.find_child("Pages", true, false).get_node(tab_name).get_node("Rows")


func _control(tab_name: String, label: String) -> Control:
	for panel in _rows_node(tab_name).get_children():
		if panel is PanelContainer and panel.visible:
			var hbox: Node = panel.get_child(0)
			if (hbox.get_child(0) as Label).text == label:
				return hbox.get_child(1)
	return null


func _show_tab(index: int) -> void:
	(tabs[index] as Button).pressed.emit()
	await _wait(0.05)


func _pick(select: OptionButton, index: int) -> void:
	select.select(index)
	select.item_selected.emit(index)


func _button(text: String) -> Button:
	for button in settings.find_children("*", "SolidButton", true, false):
		if button.text == text:
			return button
	return null


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	AM = root.get_node("AudioManager")
	if not await _wait_state(GS.State.MAIN_MENU):
		_check("the main menu comes up", false)
		_finish()
		return
	var menu: Node = root.get_node("Main/UIManager/MainMenu")
	var loading := root.get_node("Main/UIManager/LoadingScreen") as CanvasLayer
	await _wait(0.3)
	menu.skip_intro()
	while loading.visible:
		await process_frame
	await _wait(0.5)
	settings = menu.get_node("SettingsSubMenu")
	tabs = settings.find_child("Tabs", true, false).get_children()
	(menu.find_child("Settings", true, false) as Button).pressed.emit()
	await _wait(0.8)
	_check("the settings screen is open", settings.is_open)

	await _check_general()
	await _check_audio()
	await _check_video()
	await _check_controls()
	await _check_bindings()
	await _check_hidden_rows()
	await _check_in_level()
	_finish()


func _finish() -> void:
	_restore()
	InputMap.load_from_project_settings()
	Engine.max_fps = 0
	print("RESULT test_settings %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)


# --- 1. General ----------------------------------------------------------------------------------

func _check_general() -> void:
	await _show_tab(0)
	var subtitles: Button = _control("General", "Subtitles")
	var size: Range = _control("General", "Subtitle Size")
	var tooltips: Button = _control("General", "Show Tooltips")
	var fps: Button = _control("General", "Show FPS Counter")
	var hud: Node = root.get_node("Main/UIManager/HUD")
	var boxes: Control = hud.get_node("DialogBoxContainer")

	# A line playing (with a voice stream, to see its bus) while the subtitle settings change
	var dialog: Resource = load("res://src/dialog/dialog.gd").new()
	dialog.subtitle = "Testing the subtitle settings."
	dialog.min_duration = 30.0
	var tone := AudioStreamWAV.new()
	tone.data = PackedByteArray([0, 0, 0, 0])
	dialog.audio_stream = tone
	var server: Node = root.get_node("DialogServer")
	server.play_dialog(dialog)
	await _frames(2)
	var box: Control = boxes.get_node("Boxes").get_child(-1) if boxes.get_node("Boxes").get_child_count() > 0 else null
	var label: RichTextLabel = box.get_node("Content/RichTextLabel") if box else null
	_check("[General] a playing line shows its subtitle at 24 px", boxes.visible and label != null
		and label.get_theme_font_size(&"normal_font_size") == 24)
	var voice_player: AudioStreamPlayer = null
	for child in server.get_children():
		if child is AudioStreamPlayer:
			voice_player = child
	_check("[Audio] dialogue plays on the Voice bus", voice_player != null and voice_player.bus == &"Voice")

	subtitles.button_pressed = false
	_check("[General] Subtitles off hides the subtitles at once", not boxes.visible)
	_check("[General] Subtitles off is saved", _saved("general", "subtitles") == false)
	subtitles.button_pressed = true
	_check("[General] Subtitles on shows the playing line again", boxes.visible)
	size.value = 150.0
	_check("[General] Subtitle Size 150 % makes the playing line 36 px", label != null
		and label.get_theme_font_size(&"normal_font_size") == 36, str(label.get_theme_font_size(&"normal_font_size")) if label else "")
	_check("[General] Subtitle Size is saved", _saved("general", "subtitle_size") == 150.0)
	server.stop_all()

	# The part tooltip on an interact trigger
	var tooltip: Control = load("res://src/ui/part_tooltip/part_tooltip.gd").new()
	root.add_child(tooltip)
	var trigger: Node = load("res://src/interact_trigger/interact_trigger.gd").new()
	trigger.tooltip = 'Press "E" to talk'
	tooltip.show_for(trigger, true, false)
	_check("[General] the part tooltip shows by default", tooltip.visible)
	tooltips.button_pressed = false
	tooltip.show_for(trigger, true, false)
	_check("[General] Show Tooltips off hides the part tooltip", not tooltip.visible)
	_check("[General] Show Tooltips is saved", _saved("general", "show_tooltips") == false)
	tooltips.button_pressed = true
	tooltip.show_for(trigger, true, false)
	_check("[General] Show Tooltips on shows it again", tooltip.visible)

	var counter: CanvasLayer = root.get_node("Main/UIManager/FpsCounter")
	_check("[General] no FPS counter by default", not counter.visible)
	fps.button_pressed = true
	await _frames(3)
	var fps_label: Label = counter.label
	var rect: Rect2 = fps_label.get_global_rect()
	_check("[General] Show FPS Counter shows it at once", counter.visible and fps_label.text.ends_with(" FPS"), fps_label.text)
	_check("[General] the FPS counter is in the top-right corner", absf(rect.end.x - 1904.0) < 2.0 and absf(rect.position.y - 16.0) < 2.0,
		str(rect))
	var font: Font = fps_label.get_theme_font(&"font")
	_check("[General] the FPS counter is in IBM Plex Mono", font is FontFile and (font as FontFile).resource_path.contains("IBMPlexMono"))
	_check("[General] Show FPS Counter is saved", _saved("general", "show_fps") == true)

	subtitles.button_pressed = false
	tooltips.button_pressed = false
	_relaunch()
	_check("[General] restored at launch", not GeneralSettings.subtitles() and is_equal_approx(GeneralSettings.subtitle_scale(), 1.5)
		and not GeneralSettings.show_tooltips() and GeneralSettings.show_fps())

	_button("RESET TO DEFAULTS").pressed.emit()
	_check("[General] RESET TO DEFAULTS resets the real values", GeneralSettings.subtitles() and GeneralSettings.subtitle_scale() == 1.0
		and GeneralSettings.show_tooltips() and not GeneralSettings.show_fps())
	_check("[General] ... and saves them", _saved("general", "subtitles") == true and _saved("general", "subtitle_size") == 100.0
		and _saved("general", "show_fps") == false)
	_check("[General] ... and the controls show them", subtitles.button_pressed and size.value == 100.0 and tooltips.button_pressed
		and not fps.button_pressed)
	_check("[General] ... and the FPS counter goes", not counter.visible)
	tooltip.queue_free()
	trigger.free()


# --- 1. Audio ------------------------------------------------------------------------------------

func _check_audio() -> void:
	await _show_tab(1)
	var voice_index: int = AudioServer.get_bus_index(&"Voice")
	_check("[Audio] the Voice bus exists and sends to Master", voice_index > 0 and AudioServer.get_bus_send(voice_index) == &"Master")
	var voice: Range = _control("Audio", "Voice Volume")
	_check("[Audio] Voice Volume starts at 90 %", voice.value == 90.0)
	voice.value = 25.0
	_check("[Audio] Voice Volume sets the Voice bus", is_equal_approx(AudioServer.get_bus_volume_db(voice_index), linear_to_db(0.25)))
	_check("[Audio] Voice Volume is saved", _saved("audio", "voice") == 25.0)

	var master: int = AudioServer.get_bus_index(&"Master")
	var mute: Button = _control("Audio", "Mute When Unfocused")
	AM.mute_when_unfocused_allowed = true
	_check("[Audio] Mute When Unfocused is on by default", mute.button_pressed)
	AM.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("[Audio] losing the focus mutes Master", AudioServer.is_bus_mute(master))
	AM.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check("[Audio] the focus back unmutes it", not AudioServer.is_bus_mute(master))
	mute.button_pressed = false
	AM.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("[Audio] off: losing the focus leaves Master on", not AudioServer.is_bus_mute(master))
	AM.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check("[Audio] Mute When Unfocused is saved", _saved("audio", "mute_when_unfocused") == false)

	_relaunch()
	_check("[Audio] restored at launch", AudioSettings.get_volume("voice") == 25.0 and not AudioSettings.mute_when_unfocused())
	settings.close(false)
	settings.open()
	await _wait(0.6)
	_check("[Audio] the controls show the saved values", voice.value == 25.0 and not mute.button_pressed)
	mute.button_pressed = true
	voice.value = 90.0


# --- 1. Video ------------------------------------------------------------------------------------

func _check_video() -> void:
	await _show_tab(2)
	var resolution: OptionButton = _control("Video", "Resolution")
	var quality: OptionButton = _control("Video", "Quality Preset")
	var terrain: OptionButton = _control("Video", "Terrain Detail")
	var dust: OptionButton = _control("Video", "Dust and Tracks")
	var vsync: Button = _control("Video", "VSync")
	var frame_rate: OptionButton = _control("Video", "Frame Rate Limit")
	var fov: Range = _control("Video", "Field Of View")
	var brightness: Range = _control("Video", "Brightness")

	var windowed: bool = DisplayServer.get_name() != "headless"
	var window_size: Vector2i = DisplayServer.window_get_size()
	_check("[Video] Resolution lists the board's sizes", resolution.item_count == 4 and resolution.get_item_text(0) == "1280x720")
	_pick(resolution, 0)
	_check("[Video] Resolution is saved", _saved("video", "resolution") == 0 and VideoSettings.resolution_index() == 0)
	if windowed:
		await _wait(0.5)
		var usable: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		_check("[Video] (windowed) Resolution resizes the window", DisplayServer.window_get_size() == Vector2i(1280, 720).min(usable.size),
			"%s, screen %s" % [DisplayServer.window_get_size(), usable.size])
		_check("[Video] (windowed) the picture still fills it at 1920 x 1080", root.get_visible_rect().size.x >= 1919.0,
			str(root.get_visible_rect().size))
	_check("[Video] VSync on by default", vsync.button_pressed)
	vsync.button_pressed = false
	_check("[Video] VSync off is saved", _saved("video", "vsync") == false)
	if windowed:
		_check("[Video] (windowed) VSync off switches vsync off", DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED)
		vsync.button_pressed = true
		_check("[Video] (windowed) VSync on switches it back on", DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED)
		vsync.button_pressed = false
	_check("[Video] Frame Rate Limit starts Unlimited", frame_rate.get_item_text(frame_rate.selected) == "Unlimited" and Engine.max_fps == 0)
	_pick(frame_rate, 1)
	_check("[Video] Frame Rate Limit 60 sets Engine.max_fps", Engine.max_fps == 60, str(Engine.max_fps))
	_check("[Video] Frame Rate Limit is saved", _saved("video", "frame_rate_limit") == 1)
	_check("[Video] Field Of View runs 60 to 120 from 90", fov.min_value == 60.0 and fov.max_value == 120.0 and fov.value == 90.0)
	fov.value = 110.0
	_check("[Video] Field Of View is saved", _saved("video", "fov") == 110.0)
	brightness.value = 100.0
	_check("[Video] Brightness 100 doubles the exposure", is_equal_approx(VideoSettings.exposure_multiplier(), 2.0))
	_check("[Video] Brightness is saved", _saved("video", "brightness") == 100.0)
	# The menu's Moon (its own WorldEnvironment, if it has one) follows at once
	var worlds: Array[Node] = root.find_children("*", "WorldEnvironment", true, false)
	_check("[Video] Brightness reaches every WorldEnvironment", worlds.all(func(w: Node) -> bool:
		return w.camera_attributes != null and is_equal_approx(w.camera_attributes.exposure_multiplier, 2.0)), "%d" % worlds.size())

	_check("[Video] Quality Preset starts at High", quality.get_item_text(quality.selected) == "High")
	_pick(quality, 0)
	_check("[Video] Low: no MSAA, hard shadows", root.msaa_3d == Viewport.MSAA_DISABLED)
	_check("[Video] Low sets Terrain Detail and Dust and Tracks", GraphicsSettings.get_terrain_detail() == GraphicsSettings.TerrainDetail.LOW
		and GraphicsSettings.get_surface_effects() == GraphicsSettings.SurfaceEffects.OFF and terrain.selected == 1 and dust.selected == 2)
	_pick(quality, 3)
	_check("[Video] Ultra: 4x MSAA, high detail", root.msaa_3d == Viewport.MSAA_4X
		and GraphicsSettings.get_terrain_detail() == GraphicsSettings.TerrainDetail.HIGH and terrain.selected == 0 and dust.selected == 0)
	_check("[Video] Quality Preset is saved", _saved("video", "quality") == 3)
	_pick(terrain, 1)
	_check("[Video] changing Terrain Detail alone shows Custom", quality.get_item_text(quality.selected) == "Custom")
	_check("[Video] Custom can't be picked", quality.is_item_disabled(4))

	_relaunch()
	_check("[Video] restored at launch", VideoSettings.section.get_value("resolution") == 0 and not VideoSettings.section.get_value("vsync")
		and VideoSettings.section.get_value("frame_rate_limit") == 1 and VideoSettings.fov() == 110.0
		and is_equal_approx(VideoSettings.exposure_multiplier(), 2.0) and VideoSettings.section.get_value("quality") == 3)
	VideoSettings.apply_saved()
	_check("[Video] applied at launch (frame cap, MSAA)", Engine.max_fps == 60 and root.msaa_3d == Viewport.MSAA_4X)

	# Back to the defaults (the level part sets what it needs)
	if windowed:
		DisplayServer.window_set_size(window_size)
	_pick(quality, 2)
	_pick(frame_rate, 4)
	vsync.button_pressed = true
	_check("[Video] Unlimited clears the cap", Engine.max_fps == 0 and root.msaa_3d == Viewport.MSAA_DISABLED)
	fov.value = 90.0
	brightness.value = 50.0


# --- 1. Controls (other than the keys) -----------------------------------------------------------

func _check_controls() -> void:
	await _show_tab(3)
	var sensitivity: Range = _control("Controls", "Mouse Sensitivity")
	var invert: Button = _control("Controls", "Invert Y Axis")
	var toggle_crouch: Button = _control("Controls", "Toggle Crouch")
	_check("[Controls] defaults: sensitivity 40, not inverted, hold to crouch", sensitivity.value == 40.0 and not invert.button_pressed
		and not toggle_crouch.button_pressed)
	_check("[Controls] at 40 the look is as tuned", ControlSettings.look_pixels(Vector2(10.0, 10.0)) == Vector2(10.0, 10.0))
	sensitivity.value = 80.0
	invert.button_pressed = true
	toggle_crouch.button_pressed = true
	_check("[Controls] 80 doubles the look, invert flips y", ControlSettings.look_pixels(Vector2(10.0, 10.0)) == Vector2(20.0, -20.0))
	_check("[Controls] saved", _saved("controls", "mouse_sensitivity") == 80.0 and _saved("controls", "invert_y") == true
		and _saved("controls", "toggle_crouch") == true)
	_relaunch()
	_check("[Controls] restored at launch", ControlSettings.section.get_value("mouse_sensitivity") == 80.0
		and ControlSettings.section.get_value("invert_y") and ControlSettings.toggle_crouch())
	sensitivity.value = 40.0
	invert.button_pressed = false
	toggle_crouch.button_pressed = false


# --- 2. Key bindings -----------------------------------------------------------------------------

func _slab(label: String) -> Button:
	return _control("Controls", label) as Button


func _bind(label: String, keycode: Key) -> void:
	_slab(label).pressed.emit()
	await _key(keycode)


func _check_bindings() -> void:
	await _show_tab(3)
	var labels: Array = []
	for entry in InputBindings.ACTIONS + InputBindings.LOCKED:
		labels.append(entry[1])
	var shown: Array = []
	for panel in _rows_node("Controls").get_children():
		if panel is PanelContainer and panel.visible and panel.get_child(0).get_child(1) is KeyBindSlab:
			shown.append((panel.get_child(0).get_child(0) as Label).text)
	_check("[Keys] a slab per real action, then the fixed ones", shown == labels, str(shown))
	var unknown: Array = InputBindings.ACTIONS.filter(func(entry: Array) -> bool: return not InputMap.has_action(entry[0]))
	_check("[Keys] every listed action is in the InputMap", unknown.is_empty(), str(unknown))
	_check("[Keys] slabs show the project's keys", _slab("Move Forward").text == "W" and _slab("Jump").text == "Space"
		and _slab("Crouch").text == "Ctrl" and _slab("Toggle Fullscreen").text == "F11" and _slab("Zoom In").text == "=")
	var throw: Button = _slab("Throw")
	var pause: Button = _slab("Pause / Back")
	_check("[Keys] Throw and Pause are fixed: LMB, Esc", throw.text == "LMB" and throw.disabled and pause.text == "Esc"
		and pause.disabled and throw.focus_mode == Control.FOCUS_NONE)

	var chip: Node = load("res://src/ui/components/key_chip.tscn").instantiate()
	root.add_child(chip)
	chip.action = &"interact_use"
	var hud_hint: Label = root.get_node("Main/UIManager/HUD/MarginContainer/Hint")
	_check("[Keys] the HUD hint shows the project's keys", hud_hint.text.begins_with("WASD: move") and hud_hint.text.contains("E: use"))

	await _bind("Move Forward", KEY_K)
	_check("[Keys] rebinding changes the InputMap", InputBindings.key_code(InputBindings.key_event(&"move_forward")) == KEY_K
		and _slab("Move Forward").text == "K")
	_key_event(KEY_K, true)
	await _frames(2)
	_check("[Keys] the new key works the action", Input.is_action_pressed(&"move_forward"))
	_key_event(KEY_K, false)
	await _frames(2)
	_key_event(KEY_W, true)
	await _frames(2)
	_check("[Keys] the old key doesn't", not Input.is_action_pressed(&"move_forward"))
	_key_event(KEY_W, false)
	await _frames(2)
	_check("[Keys] the binding is saved", _saved("bindings", "move_forward") == KEY_K)
	_check("[Keys] the HUD hint follows", hud_hint.text.begins_with("KASD: move"), hud_hint.text.get_slice("\n", 0))

	# Conflict: K is Move Forward's, so the two swap
	var note: Label = settings.find_child("BindingNote", true, false)
	await _bind("Move Backward", KEY_K)
	_check("[Keys] a key in use swaps: the other action gets the old key",
		InputBindings.key_code(InputBindings.key_event(&"move_backward")) == KEY_K
		and InputBindings.key_code(InputBindings.key_event(&"move_forward")) == KEY_S)
	_check("[Keys] both slabs show it", _slab("Move Backward").text == "K" and _slab("Move Forward").text == "S")
	_check("[Keys] the note says what was swapped", note.text.contains("swapped") and note.text.contains("Move Forward"), note.text)
	var on_k: int = 0
	for action in InputMap.get_actions():
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and InputBindings.key_code(event) == KEY_K:
				on_k += 1
	_check("[Keys] no key is left on two actions", on_k == 1)

	# Esc only cancels; the console's key is refused
	_slab("Jump").pressed.emit()
	await _key(KEY_ESCAPE)
	_check("[Keys] Esc cancels listening, binds nothing, keeps the menu open", not _slab("Jump").listening
		and InputBindings.key_code(InputBindings.key_event(&"move_jump")) == KEY_SPACE and settings.is_open)
	await _bind("Jump", KEY_QUOTELEFT)
	_check("[Keys] the debug console's key is refused", InputBindings.key_code(InputBindings.key_event(&"move_jump")) == KEY_SPACE
		and _slab("Jump").text == "Space" and note.text.contains("console"), note.text)
	_check("[Keys] Esc can't be bound through the API either", InputBindings.rebind(&"move_jump", _esc()) != ""
		and InputBindings.key_code(InputBindings.key_event(&"move_jump")) == KEY_SPACE)

	# Key chips, the tooltip prompt, the HUD hint
	await _bind("Interact", KEY_G)
	_check("[Keys] key chips show the new key", chip.key_text() == "G" and chip.get_child(0).get_child(0).text == "G")
	_check("[Keys] the HUD hint shows it", hud_hint.text.contains("G: use"))
	_check("[Keys] tooltip prompts use it", InputBindings.with_current_keys('Press "E" to talk') == 'Press "G" to talk'
		and InputBindings.with_current_keys("Park again and press E.") == "Park again and press G.")

	_relaunch()
	_check("[Keys] restored at launch", InputBindings.key_code(InputBindings.key_event(&"move_backward")) == KEY_K
		and InputBindings.key_code(InputBindings.key_event(&"move_forward")) == KEY_S
		and InputBindings.key_code(InputBindings.key_event(&"interact_use")) == KEY_G)
	_check("[Keys] the zoom keeps its wheel after a launch", InputMap.action_get_events(&"camera_zoom_in").any(
		func(e: InputEvent) -> bool: return e is InputEventMouseButton))

	_button("RESET BINDINGS").pressed.emit()
	await _frames(1)
	var all_default: bool = InputBindings.ACTIONS.all(func(entry: Array) -> bool:
		var key := InputBindings.key_event(entry[0])
		return key != null and InputBindings.key_code(key) == InputBindings.default_key_code(entry[0]))
	_check("[Keys] RESET BINDINGS puts the project's keys back", all_default)
	_check("[Keys] ... with the zoom's wheel and fullscreen's Alt+Enter", InputMap.action_get_events(&"camera_zoom_in").size() == 2
		and InputMap.action_get_events(&"toggle_fullscreen").size() == 2)
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	_check("[Keys] ... and nothing stays saved", not config.has_section("bindings"))
	_check("[Keys] ... and the slabs, chips and hint show them", _slab("Move Forward").text == "W" and _slab("Interact").text == "E"
		and chip.key_text() == "E" and hud_hint.text.begins_with("WASD: move") and note.text == "")
	_relaunch()
	_check("[Keys] still the project's after a launch", InputBindings.key_code(InputBindings.key_event(&"move_forward")) == KEY_W)
	chip.queue_free()


func _esc() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	return event


# --- 3. Hidden rows ------------------------------------------------------------------------------

func _hidden_ok() -> bool:
	for tab_name in HIDDEN:
		for label: String in HIDDEN[tab_name]:
			var panel: Control = _rows_node(tab_name).get_node_or_null("Hidden" + label.replace(" ", ""))
			if panel == null or panel.visible or panel.is_visible_in_tree() or panel.get_child(0).get_child_count() != 1:
				return false
			if _control(tab_name, label) != null:
				return false
	return true


func _check_hidden_rows() -> void:
	_check("[Hidden] Language, Camera Shake, Speaker Setup, Motion Blur are hidden", _hidden_ok())
	for tab_name in HIDDEN:
		for label: String in HIDDEN[tab_name]:
			var panel: Control = _rows_node(tab_name).get_node_or_null("Hidden" + label.replace(" ", ""))
			_check("[Hidden] %s says why" % label, panel != null and str(panel.get_meta(&"hidden_reason", "")) != "",
				str(panel.get_meta(&"hidden_reason", "")) if panel else "")
	for i in tabs.size():
		await _show_tab(i)
	_check("[Hidden] still hidden after visiting every tab", _hidden_ok())
	_button("RESET TO DEFAULTS").pressed.emit()
	_button("RESET BINDINGS").pressed.emit()
	_check("[Hidden] still hidden after both resets", _hidden_ok())
	settings.close(false)
	settings.open()
	await _wait(0.6)
	_check("[Hidden] still hidden after closing and opening", _hidden_ok())
	var in_focus: bool = false
	for i in settings._focusables.size():
		for control in settings._focusables[i]:
			if control.get_parent().get_parent().name.begins_with("Hidden"):
				in_focus = true
	_check("[Hidden] not in the keyboard focus order", not in_focus)
	settings.back_requested.emit()
	await _wait(0.6)


# --- 4. In the test level ------------------------------------------------------------------------

func _check_in_level() -> void:
	SL.load_scene("test_level")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "test_level"):
		_check("the test level loads", false)
		return
	await _wait(0.5)
	var player: Node = GS.player
	var controller: Node = player.controller

	# Field of view and brightness
	_check("[Level] the player's camera starts at 90", is_equal_approx(player.camera.fov, 90.0))
	VideoSettings.set_value("fov", 110.0)
	_check("[Level] Field Of View changes the player's camera at once", is_equal_approx(player.camera.fov, 110.0))
	VideoSettings.set_value("brightness", 100.0)
	var world: WorldEnvironment = SL.current_scene.get_node("WorldEnvironment")
	_check("[Level] Brightness is on the level's WorldEnvironment", world.camera_attributes != null
		and is_equal_approx(world.camera_attributes.exposure_multiplier, 2.0))
	VideoSettings.set_value("brightness", 0.0)
	_check("[Level] ... and follows a change", is_equal_approx(world.camera_attributes.exposure_multiplier, 0.5))

	# Mouse look on foot: sensitivity scales it, invert flips the pitch
	var yaw: float = controller.camera_azimuth
	await _mouse(Vector2(1.0, 0.0))
	var turn_40: float = absf(controller.camera_azimuth - yaw)
	ControlSettings.section.set_value("mouse_sensitivity", 80.0)
	yaw = controller.camera_azimuth
	await _mouse(Vector2(1.0, 0.0))
	var turn_80: float = absf(controller.camera_azimuth - yaw)
	_check("[Level] on foot: sensitivity 80 turns twice as far as 40", turn_40 > 0.0 and is_equal_approx(turn_80, 2.0 * turn_40),
		"%.4f / %.4f rad" % [turn_40, turn_80])
	ControlSettings.section.set_value("mouse_sensitivity", 40.0)
	var pitch: float = controller.camera_altitude
	await _mouse(Vector2(0.0, 1.0))
	var down: float = controller.camera_altitude - pitch
	ControlSettings.section.set_value("invert_y", true)
	pitch = controller.camera_altitude
	await _mouse(Vector2(0.0, 1.0))
	var inverted: float = controller.camera_altitude - pitch
	_check("[Level] on foot: Invert Y flips the pitch", down < 0.0 and is_equal_approx(inverted, -down), "%.4f / %.4f" % [down, inverted])
	ControlSettings.section.set_value("invert_y", false)

	# Crouch: held by default, toggled with Toggle Crouch
	_key_event(KEY_CTRL, true)
	await _frames(3)
	var held_down: bool = player.is_crouching
	_key_event(KEY_CTRL, false)
	await _frames(3)
	_check("[Level] crouch is held by default", held_down and not player.is_crouching)
	ControlSettings.section.set_value("toggle_crouch", true)
	await _key(KEY_CTRL)
	await _frames(2)
	var toggled_down: bool = player.is_crouching
	await _key(KEY_CTRL)
	await _frames(2)
	_check("[Level] Toggle Crouch: a press crouches, the next stands up", toggled_down and not player.is_crouching)
	ControlSettings.section.set_value("toggle_crouch", false)

	# The rover: mast and chase field of view, tool camera brightness, look
	var rover: Node = SL.current_scene.get_node_or_null("ReadyRover")
	if rover == null:
		_check("[Level] the test level has its ready rover", false)
		return
	GS.drive(rover)
	await _frames(10)
	var rig: Node = rover.get_node("CameraRig")
	_check("[Rover] driving, in the mast view", GS.state == GS.State.IN_GAME_ROBOT and rig.view == 1)
	_check("[Rover] the mast camera unzoomed has the Field Of View", is_equal_approx(rover.camera.fov, 110.0)
		and is_equal_approx(rig.mast_zoom(), 1.0), "%.1f" % rover.camera.fov)
	VideoSettings.set_value("fov", 70.0)
	await _frames(2)
	_check("[Rover] ... and follows a change", is_equal_approx(rover.camera.fov, 70.0), "%.1f" % rover.camera.fov)
	_check("[Rover] Brightness on the tool camera too", is_equal_approx(rig._tool_attributes.exposure_multiplier, 0.5))
	var azimuth: float = rover.controller.camera_azimuth
	await _mouse(Vector2(1.0, 0.0))
	var rover_40: float = absf(rover.controller.camera_azimuth - azimuth)
	ControlSettings.section.set_value("mouse_sensitivity", 80.0)
	azimuth = rover.controller.camera_azimuth
	await _mouse(Vector2(1.0, 0.0))
	var rover_80: float = absf(rover.controller.camera_azimuth - azimuth)
	_check("[Rover] sensitivity 80 turns twice as far as 40", rover_40 > 0.0 and is_equal_approx(rover_80, 2.0 * rover_40),
		"%.4f / %.4f rad" % [rover_40, rover_80])
	ControlSettings.section.set_value("mouse_sensitivity", 40.0)
	var altitude: float = rover.controller.camera_altitude
	await _mouse(Vector2(0.0, 1.0))
	var rover_down: float = rover.controller.camera_altitude - altitude
	ControlSettings.section.set_value("invert_y", true)
	altitude = rover.controller.camera_altitude
	await _mouse(Vector2(0.0, 1.0))
	var rover_inverted: float = rover.controller.camera_altitude - altitude
	_check("[Rover] Invert Y flips the pitch", rover_down < 0.0 and is_equal_approx(rover_inverted, -rover_down),
		"%.4f / %.4f" % [rover_down, rover_inverted])
	ControlSettings.section.set_value("invert_y", false)
	VideoSettings.set_value("fov", 108.0)
	while rig.view != 0:
		rig.next_view()
	await _frames(3)
	_check("[Rover] the chase view scales with it (70 at 90)", is_equal_approx(rover.camera.fov, 70.0 * 108.0 / 90.0),
		"%.1f" % rover.camera.fov)
	VideoSettings.set_value("fov", 90.0)
	VideoSettings.set_value("brightness", 50.0)
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _frames(3)
	_check("[Level] back on foot, the player's camera is back at 90", is_equal_approx(player.camera.fov, 90.0))
