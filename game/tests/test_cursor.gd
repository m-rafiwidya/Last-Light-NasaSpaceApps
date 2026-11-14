extends SceneTree
## Windowed test (not --headless: headless Godot always reports a visible mouse): the cursor and
## the menus through a whole session, with real mouse and key events (Input.parse_input_event,
## as the OS would send them) and real focus changes (the window minimised and restored):
##   1. The main menu shows the cursor, a click skips its opening sequence, and its buttons take
##      clicks (Settings, Back, Play, START NEW CAMPAIGN).
##   2. In game the cursor is captured, on foot and driving, and mouse look turns the view.
##   3. Esc shows the cursor with the pause menu; Resume captures it again.
##   4. Losing and regaining the window's focus never leaves the cursor hidden in a menu or
##      free in game (focus back re-applies the state's mouse mode), and main.gd's unfocused-window
##      throttling is off when the game runs embedded in the editor.
##   5. Switching levels from the pause menu and quitting to the main menu leave it right.
## Each level load waits for the loading screen to fade out and hide (while it is up it takes
## the mouse, as for a player).
## Prints one line per check and PASS / FAIL.
##
##     Godot --path game -s res://tests/test_cursor.gd --resolution 1920x1080

const MODES: Array[String] = ["visible", "hidden", "captured", "confined", "confined hidden"]

var GS: Node
var SL: Node
var failures: int = 0


func _initialize() -> void:
	_watchdog(240.0)
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-62s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _mode() -> String:
	return MODES[Input.mouse_mode]


func _check_mode(name: String, expected: Input.MouseMode) -> void:
	_check(name, Input.mouse_mode == expected, "mouse %s, state %s, focused %s" % [_mode(), GS.State.keys()[GS.state], DisplayServer.window_is_focused()])


# A left click on `button`, at its centre in window coordinates, once it has stopped moving (menus
# slide in: a button that moves between press and release doesn't count the click) and is under
# the pointer; up to 3 s
func _click(button: Control) -> bool:
	if button == null:
		return false
	var at := Vector2.ZERO
	var start: int = Time.get_ticks_msec()
	var last := Vector2(INF, INF)
	while true:
		at = root.get_final_transform() * button.get_global_rect().get_center()
		var still: bool = at.is_equal_approx(last)
		last = at
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		Input.parse_input_event(motion)
		await _frames(2)
		var hovered: Control = root.gui_get_hovered_control()
		if still and button.is_visible_in_tree() and hovered and (hovered == button or button.is_ancestor_of(hovered)):
			break
		if Time.get_ticks_msec() - start > 3000:
			print("INFO click meant for %s would land on %s (at %s)" % [button.name, hovered.name if hovered else "nothing", at])
			return false
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(click)
		await _frames(2)
	return true


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(3)


func _mouse_look(dx: float) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(dx, 0.0)
	motion.screen_relative = Vector2(dx, 0.0)
	Input.parse_input_event(motion)
	await _frames(3)


func _button(path: String) -> Button:
	return root.get_node_or_null("Main/UIManager/" + path) as Button


func _wait_state(state: int, level_id: String = "", seconds: float = 60.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if GS.state == state and (level_id.is_empty() or SL.current_level_id == level_id):
			# The loading screen fades out over the level, then hides; until then it takes the mouse
			var loading := root.get_node("Main/UIManager/LoadingScreen") as CanvasLayer
			while loading.visible and Time.get_ticks_msec() - start < seconds * 1000.0:
				await process_frame
			await _frames(10)
			return not loading.visible
		await process_frame
	return false


# Loses the window's focus (minimised) and gets it back, as switching to another app and back
func _away_and_back() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	await create_timer(1.5, true, false, true).timeout
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	await create_timer(1.5, true, false, true).timeout


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	DisplayServer.window_move_to_foreground()
	if not await _wait_state(GS.State.MAIN_MENU):
		_check("the main menu comes up", false)
		quit(1)
		return
	await _frames(60)

	# 1. Main menu
	_check_mode("main menu: cursor visible", Input.MOUSE_MODE_VISIBLE)
	var menu: Node = root.get_node("Main/UIManager/MainMenu")
	_check("main menu: opening sequence playing", menu.is_intro_playing())
	await _click(_button("MainMenu/Intro/Skip"))
	_check("main menu: a click skips the opening sequence", not menu.is_intro_playing())
	await _click(_button("MainMenu/MainMenuSubScreen/Column/Nav/Settings"))
	await _frames(40)
	var back := _button("MainMenu/SettingsSubMenu/Panel/Margin/Column/Footer/Back")
	_check("main menu: Settings takes a click", back != null and back.is_visible_in_tree())
	_check_mode("settings: cursor visible", Input.MOUSE_MODE_VISIBLE)
	await _click(back)
	await _frames(40)
	var play := _button("MainMenu/MainMenuSubScreen/Column/Nav/Play")
	_check("main menu: Back takes a click", play != null and play.is_visible_in_tree())
	await _away_and_back()
	_check_mode("main menu after losing and regaining focus: cursor visible", Input.MOUSE_MODE_VISIBLE)
	await _click(play)
	await _frames(40)
	var popup: Node = root.find_child("PlayPopup", true, false)
	var start: Button = popup.get_start_button() if popup and popup.is_open else null
	_check("main menu: Play takes a click and opens the popup", start != null and start.is_visible_in_tree())
	_check_mode("PLAY popup: cursor visible", Input.MOUSE_MODE_VISIBLE)
	await _click(start)
	_check("START NEW CAMPAIGN takes a click and loads the Moon", await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"))

	# The unfocused-window handling (main.gd): off when embedded in the editor, and when it is on,
	# focus coming back restores the frame pacing and the mouse mode
	var main: Node = root.get_node("Main")
	_check("unfocused-window throttling is off when embedded in the editor", main.throttle_when_unfocused == not Engine.is_embedded_in_editor())

	# 2. In game
	_check_mode("on foot: cursor captured", Input.MOUSE_MODE_CAPTURED)
	var player: Node = GS.player
	if player == null:
		print("DONE %d failures" % (failures + 1))
		quit(1)
		return
	var camera: Camera3D = player.camera
	var yaw: float = camera.global_rotation.y
	await _mouse_look(200.0)
	await _frames(10)
	_check("on foot: mouse look turns the view", absf(camera.global_rotation.y - yaw) > 0.01, "%.3f rad" % (camera.global_rotation.y - yaw))
	var rover: Node = SL.current_scene.get_node("ReadyRover")
	GS.drive(rover)
	await _frames(10)
	_check_mode("driving: cursor captured", Input.MOUSE_MODE_CAPTURED)
	var azimuth: float = rover.controller.camera_azimuth
	await _mouse_look(200.0)
	_check("driving: mouse look turns the view", absf(rover.controller.camera_azimuth - azimuth) > 0.01)
	await _away_and_back()
	_check_mode("driving after losing and regaining focus: cursor captured", Input.MOUSE_MODE_CAPTURED)
	# Focus coming back re-applies the state's mouse mode even if something freed the cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames(3)
	_check_mode("focus back re-captures the cursor in game", Input.MOUSE_MODE_CAPTURED)
	_check("focus back restores the frame cap", Engine.max_fps == 0, "max_fps %d" % Engine.max_fps)
	await _key(KEY_ESCAPE)
	_check("Esc while driving: back on foot", GS.state == GS.State.IN_GAME_PLAYER)
	_check_mode("back on foot: cursor captured", Input.MOUSE_MODE_CAPTURED)

	# 3. Pause and resume
	await _key(KEY_ESCAPE)
	await _frames(40)
	_check("Esc on foot: paused", GS.state == GS.State.PAUSED)
	_check_mode("pause menu: cursor visible", Input.MOUSE_MODE_VISIBLE)
	await _away_and_back()
	_check_mode("pause menu after losing and regaining focus: cursor visible", Input.MOUSE_MODE_VISIBLE)
	await _click(_button("PauseMenu/Root/Content/Column/Nav/Resume"))
	await _frames(40)
	_check("pause menu: Resume takes a click", GS.state == GS.State.IN_GAME_PLAYER)
	_check_mode("resumed: cursor captured", Input.MOUSE_MODE_CAPTURED)

	# 5. Switch level, then quit to the menu
	await _key(KEY_ESCAPE)
	await _frames(40)
	var switch := root.get_node("Main/UIManager/PauseMenu").find_child("test_level", true, false) as Button
	await _click(switch)
	_check("pause menu: Switch to Test level takes a click and loads it", await _wait_state(GS.State.IN_GAME_PLAYER, "test_level"))
	_check_mode("test level: cursor captured", Input.MOUSE_MODE_CAPTURED)
	await _key(KEY_ESCAPE)
	await _frames(40)
	await _click(_button("PauseMenu/Root/Content/Column/Nav/QuitToMenu"))
	_check("pause menu: Quit To Menu takes a click", await _wait_state(GS.State.MAIN_MENU))
	_check_mode("back at the main menu: cursor visible", Input.MOUSE_MODE_VISIBLE)
	await _click(_button("MainMenu/MainMenuSubScreen/Column/Nav/Settings"))
	await _frames(40)
	_check("main menu again: Settings takes a click", back.is_visible_in_tree())

	print("DONE %d failures" % failures)
	quit(1 if failures else 0)


# A hang fails the run instead of stalling it
func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
