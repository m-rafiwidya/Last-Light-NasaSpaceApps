extends SceneTree
## Main menu: boots the game and checks the launch (no loading screen, black until the opening
## sequence), the opening sequence (plays on the first menu only, any key skips it, F11 doesn't,
## PLAY is focused after it), keyboard navigation, PLAY's level list, the Moon (click emits
## moon_clicked, drag turns it, it only renders while the menu is up), PLAY opening its popup
## (tests/test_play_popup.gd covers the popup itself), that the menu backdrop is
## the empty level, not test_level, and the display mode setting (saved; the settings file is
## restored afterwards).
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_main_menu.gd
##
## Windowed with `-- --shot=<dir>` it also saves screenshots: the opening sequence at a few
## moments, the finished menu, the Moon hovered, and the menu in exclusive and borderless
## fullscreen (intro_*.png, menu.png, menu_hover.png, menu_fullscreen.png, menu_borderless.png).
## Windowed with `-- --measure` it only lets the whole opening sequence play and prints frame
## times (from launch, and per phase of the sequence), then quits.

var GS: Node
var SL: Node
var failures: int = 0
var shot_dir: String = ""
var measure: bool = false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_dir = arg.trim_prefix("--shot=")
		elif arg == "--measure":
			measure = true
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-58s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _wait_state(state: int, level_id: String = "", seconds: float = 60.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if GS.state == state and (level_id.is_empty() or SL.current_level_id == level_id):
			return true
		await process_frame
	return false


func _seconds(s: float) -> void:
	await create_timer(s, true, false, true).timeout


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


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	if measure:
		await _measure()
		quit(0)
		return
	# Launch: black (the menu's cover), never the loading screen
	var loading := root.get_node("Main/UIManager/LoadingScreen") as CanvasLayer
	var menu: Node = root.get_node("Main/UIManager/MainMenu")
	var loading_seen: bool = false
	var covered: bool = true
	var start: int = Time.get_ticks_msec()
	while GS.state != GS.State.MAIN_MENU and Time.get_ticks_msec() - start < 60000:
		loading_seen = loading_seen or loading.visible
		covered = covered and menu.get_node("Intro").visible
		await process_frame
	if GS.state != GS.State.MAIN_MENU:
		_check("the main menu comes up", false)
		quit(1)
		return
	for i in 30:
		loading_seen = loading_seen or loading.visible
		await process_frame
	_check("launch: no loading screen", not loading_seen)
	_check("launch: black cover until the menu is ready", covered)
	var moon: MenuMoon = menu.find_child("Moon", true, false)
	var play: Button = menu.find_child("Play", true, false)
	var settings: Button = menu.find_child("Settings", true, false)
	var quit_button: Button = menu.find_child("Quit", true, false)

	_check("menu backdrop is the empty level", SL.current_scene.name == "MenuBackdrop"
		and SL.current_scene.get_child_count() == 0, SL.current_scene.name)
	_check("no 3D camera in the main viewport", root.get_camera_3d() == null)
	_check("opening sequence plays on the first menu", menu.is_intro_playing())
	_check("the Moon renders while the menu is up", moon.is_active())

	await _seconds(0.5)
	_check("the sequence is still running", menu.is_intro_playing())
	var f11 := InputEventAction.new()
	f11.action = &"toggle_fullscreen"
	f11.pressed = true
	menu.get_node("Intro")._input(f11)
	_check("F11 (toggle_fullscreen) doesn't skip the sequence", menu.is_intro_playing())
	if not shot_dir.is_empty():
		# Frozen at fixed moments so the shots are repeatable
		var intro: OpeningSequence = menu.get_node("Intro")
		for at in [1.6, 3.9, 5.2, 7.6, 8.4, 9.4]:
			intro.seek(at)
			await _seconds(0.2)
			await _shot("intro_%04.1f.png" % at)

	await _key(KEY_SPACE)
	_check("any key skips the opening sequence", not menu.is_intro_playing())
	_check("PLAY has focus after the sequence", play.has_focus())
	for b in [play, settings, quit_button]:
		_check("%s: focus_mode ALL, fully shown" % b.name, b.focus_mode == Control.FOCUS_ALL
			and is_equal_approx(b.modulate.a, 1.0))

	await _key(KEY_DOWN)
	_check("down: PLAY -> SETTINGS", settings.has_focus())
	await _key(KEY_DOWN)
	_check("down: SETTINGS -> QUIT GAME", quit_button.has_focus())
	await _key(KEY_UP)
	await _key(KEY_UP)
	_check("up twice: back on PLAY", play.has_focus())

	# The loading screen takes the mouse until it has faded out and hidden
	while loading.visible:
		await process_frame
	await _seconds(0.6)
	await _shot("menu.png")

	# The Moon: a click (no movement) emits moon_clicked, a drag turns it
	var clicked: Array = [0]
	moon.moon_clicked.connect(func() -> void: clicked[0] += 1)
	# Input events are in window coordinates; the window may not be 1920 x 1080
	var centre: Vector2 = root.get_final_transform() * (moon.get_global_transform() * Vector2(700.0, 700.0))
	_check("the disc takes the mouse, the corner outside it doesn't",
		moon._has_point(Vector2(700.0, 700.0)) and not moon._has_point(Vector2(5.0, 5.0)))
	_mouse_button(centre, true)
	_mouse_button(centre, false)
	await process_frame
	_check("clicking the Moon emits moon_clicked", clicked[0] == 1)
	var lon_before: float = moon.lon
	_mouse_button(centre, true)
	var motion := InputEventMouseMotion.new()
	var drag: Vector2 = root.get_final_transform().basis_xform(Vector2(200.0, 0.0))
	motion.position = centre + drag
	motion.global_position = motion.position
	motion.relative = drag
	Input.parse_input_event(motion)
	await process_frame
	_mouse_button(centre + drag, false)
	await process_frame
	_check("dragging turns the Moon, without a click", moon.lon < lon_before - 0.1 and clicked[0] == 1,
		"%.3f -> %.3f" % [lon_before, moon.lon])
	# The Moon is anchored to the bottom-right corner and sized from the screen's height, at any
	# aspect ratio, and its SubViewport still renders at the real on-screen pixel size
	var original_size: Vector2i = root.size
	for window_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2560, 1080), Vector2i(1080, 1920)]:
		root.size = window_size
		await process_frame
		await process_frame
		var visible_size: Vector2 = root.get_visible_rect().size
		var corner: Vector2 = visible_size + moon.intro_offset
		var rect: Rect2 = moon.get_global_rect()
		var label: String = "%dx%d" % [window_size.x, window_size.y]
		_check("%s: the Moon reaches the bottom-right corner" % label, rect.end.distance_to(corner) < 1.0,
			"%s vs %s (screen %s)" % [rect.end, corner, visible_size])
		_check("%s: it is sized from the screen's height" % label, absf(moon.size.y - visible_size.y) < 1.0
			and absf(moon.size.x - MenuMoon.BASE_SIZE.x * visible_size.y / MenuMoon.DESIGN_HEIGHT) < 1.0, str(moon.size))
		var container: Control = moon.get_node("Container")
		_check("%s: its container fills it to the right edge" % label, container.get_global_rect().end.distance_to(corner) < 1.5)
		var pixels: Vector2 = moon.size * root.get_final_transform().get_scale().y
		_check("%s: the SubViewport renders at the on-screen pixel size" % label,
			Vector2(moon.get_node("Container/Viewport").size).distance_to(pixels) <= 1.5,
			"%s for %s" % [moon.get_node("Container/Viewport").size, pixels])
	root.size = original_size
	await process_frame
	await process_frame

	if not shot_dir.is_empty():
		var hover := InputEventMouseMotion.new()
		hover.position = centre
		hover.global_position = centre
		Input.parse_input_event(hover)
		await _seconds(1.0)
		await _shot("menu_hover.png")

	if not shot_dir.is_empty():
		# The same base picture scaled to the screen, both fullscreen kinds (not saved)
		for mode in [[DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, "fullscreen"],
				[DisplayServer.WINDOW_MODE_FULLSCREEN, "borderless"]]:
			DisplayServer.window_set_mode(mode[0])
			await _seconds(2.0)
			await _shot("menu_%s.png" % mode[1])
			print("SHOT %s: window %s, viewport %s" % [mode[1], DisplayServer.window_get_size(), root.get_visible_rect().size])
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			await _seconds(1.5)

	_check_display_settings()

	# PLAY opens the save popup (no level list on the menu any more); Esc closes it
	play.pressed.emit()
	await process_frame
	_check("PLAY opens the popup", menu.is_popup_open() and menu.find_child("LevelChoice", true, false) == null)
	await _key(KEY_ESCAPE)
	_check("Esc closes it, PLAY has focus again", not menu.is_popup_open() and play.has_focus())

	# Dragged and still hovered (the hover scale grows it past its corner), then into a level: no part of
	# the Moon stays on screen
	_mouse_button(centre, true)
	var motion2 := InputEventMouseMotion.new()
	var drag2: Vector2 = root.get_final_transform().basis_xform(Vector2(-150.0, 40.0))
	motion2.position = centre + drag2
	motion2.global_position = motion2.position
	motion2.relative = drag2
	Input.parse_input_event(motion2)
	await process_frame
	_mouse_button(centre + drag2, false)
	moon._set_hovered(true)
	await _seconds(0.3)
	# Into a level: the menu stops rendering; back to the menu: no second opening sequence
	SL.load_scene("test_level")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "test_level"):
		_check("test level loads", false)
	await _seconds(1.0)
	_check("in game: the Moon's viewport doesn't render", not moon.is_active())
	_check("in game: menu background hidden", not menu.get_node("Background").visible)
	_check("in game: the Moon is hidden (not just not rendering), at rest", not moon.visible and not moon.is_visible_in_tree()
		and moon.scale == Vector2.ONE and not menu.get_node("MainMenuSubScreen").visible,
		"visible %s, scale %s" % [moon.visible, moon.scale])
	SL.load_scene("main_menu")
	if not await _wait_state(GS.State.MAIN_MENU):
		_check("back to the menu", false)
	await process_frame
	await process_frame
	_check("no opening sequence the second time", not menu.is_intro_playing())
	_check("back on the menu: the Moon renders again", moon.is_active() and moon.is_visible_in_tree())
	_check("back on the menu: PLAY has focus", play.has_focus())

	print("DONE %d failures" % failures)
	quit(1 if failures else 0)


## DisplaySettings.set_mode saves the mode in user://settings.cfg; the file is put back as it was
func _check_display_settings() -> void:
	var path: String = GraphicsSettings.PATH
	var had_file: bool = FileAccess.file_exists(path)
	var original: String = FileAccess.get_file_as_string(path) if had_file else ""
	var headless: bool = DisplayServer.get_name() == "headless"
	if headless:
		DisplaySettings.set_mode(DisplaySettings.Mode.BORDERLESS)
		var config := ConfigFile.new()
		config.load(path)
		_check("display mode is saved", config.get_value("display", "window_mode", -1) == DisplaySettings.Mode.BORDERLESS)
		var option: OptionButton = null
		for row in root.get_node("Main/UIManager/MainMenu/SettingsSubMenu").find_children("*", "HBoxContainer", true, false):
			if row.get_child_count() > 1 and row.get_child(0) is Label and row.get_child(0).text == "Display Mode":
				option = row.get_child(1)
		_check("the settings menu follows the display mode", option != null and option.selected == DisplaySettings.Mode.BORDERLESS)
		DisplaySettings.set_mode(DisplaySettings.Mode.WINDOWED)
		_check("back to windowed", option != null and option.selected == DisplaySettings.Mode.WINDOWED)
	# Put the player's settings back
	if had_file:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(original)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DisplaySettings._loaded = false


## Frame times from launch until the opening sequence has finished by itself
func _measure() -> void:
	var launch: int = Time.get_ticks_usec()
	var last: int = launch
	var boot: Array[float] = []   # until the sequence starts
	var phases: Dictionary = {}   # phase name -> frame times (ms)
	var intro_start: int = 0
	var spikes: Array[String] = []   # frames over 20 ms in the sequence: "t s: ms"
	var menu: Node = null
	while true:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var ms: float = (now - last) / 1000.0
		last = now
		if menu == null:
			menu = root.get_node_or_null("Main/UIManager/MainMenu")
		if menu and menu.is_intro_playing():
			if intro_start == 0:
				intro_start = now
			var t: float = (now - intro_start) / 1e6
			var phase: String = "0-3.2 s black, PRESENTS" if t < 3.2 else (
				"3.2-7 s Moon, astronaut" if t < 7.0 else "7-10.2 s LAST LIGHT, items")
			if not phases.has(phase):
				phases[phase] = []
			phases[phase].append(ms)
			if ms > 20.0:
				spikes.append("%.2f s: %.1f ms" % [t, ms])
		elif intro_start != 0:
			break
		else:
			boot.append(ms)
		if (now - launch) > 40e6:
			print("MEASURE timed out")
			break
	print("MEASURE launch -> sequence start: %.0f ms, %d frames, longest %.1f ms" % [
		(intro_start - launch) / 1000.0, boot.size(), boot.max() if not boot.is_empty() else 0.0])
	for phase in phases:
		var times: Array = phases[phase]
		var sorted: Array = times.duplicate()
		sorted.sort()
		var mean: float = times.reduce(func(a, b): return a + b, 0.0) / times.size()
		var over: int = times.filter(func(x): return x > 25.0).size()
		print("MEASURE %-30s frames %4d  mean %5.1f ms  p95 %5.1f  max %6.1f  >25 ms: %d  first5 %s" % [
			phase, times.size(), mean, sorted[int(sorted.size() * 0.95)], sorted[-1], over,
			str(times.slice(0, 5).map(func(x): return snappedf(x, 0.1)))])
	print("MEASURE frames over 20 ms: %s" % str(spikes))


func _mouse_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)
