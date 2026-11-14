extends SceneTree
## The credits during gameplay: the CREDITS TEST box in the test level (Interact on it), the
## `credits` console command in a level, the CREDITS state (the game is paused behind it) and the
## way back: SKIP -> MAIN MENU, Esc, Esc and MAIN MENU all return to the test level, the player
## where they stood, never to the pause menu or the main menu.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_credits_in_game.gd

var GS: Node
var SL: Node
var failures: int = 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-62s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _seconds(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _wait_state(state: int, seconds: float = 120.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if GS.state == state:
			return true
		await process_frame
	return false


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame
	await process_frame


func _back_in_level(where: Vector3, label: String) -> void:
	_check("%s: back in the test level, playing" % label, GS.state == GS.State.IN_GAME_PLAYER
		and SL.current_level_id == "test_level")
	_check("%s: the player stands where they were" % label, GS.player.global_position.distance_to(where) < 0.05,
		"%.3f m off" % GS.player.global_position.distance_to(where))
	_check("%s: the game runs again, not paused" % label, not paused and Engine.time_scale > 0.0)


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	SL.load_scene("test_level")
	if not await _wait_state(GS.State.IN_GAME_PLAYER):
		_check("the test level loads", false)
		quit(1)
		return
	var credits: CanvasLayer = root.get_node("Main/UIManager/Credits")
	# (the player drops onto the floor first)
	await _seconds(2.0)
	var where: Vector3 = GS.player.global_position

	# --- The box ----------------------------------------------------------------------------
	var box: Node = root.find_child("CreditsTrigger", true, false)
	_check("a CREDITS TEST box with the interaction prompt", box != null and box.has_method("interact")
		and box.get_node("Label3D").text == "CREDITS TEST" and (box.tooltip as String).contains("E"))

	box.interact(GS.player)
	await process_frame
	await process_frame
	_check("Interact on it opens the credits (state CREDITS)", GS.state == GS.State.CREDITS and credits.visible and credits.rolling)
	await _seconds(0.8)
	_check("the game is paused behind them", paused)
	_check("the mouse is free", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	_check("the HUD is gone", not root.get_node("Main/UIManager/HUD").visible)
	credits.get_node("%Skip").pressed.emit()
	await process_frame
	credits.get_node("%MainMenu").pressed.emit()
	await process_frame
	await process_frame
	_back_in_level(where, "SKIP -> MAIN MENU")
	_check("the credits are closed and the HUD is back", not credits.visible and root.get_node("Main/UIManager/HUD").visible)

	# --- The console command, Esc -----------------------------------------------------------
	root.get_node("Debug").parse_command("credits")
	await process_frame
	await process_frame
	_check("`credits` works in a level", GS.state == GS.State.CREDITS and credits.visible and credits.rolling)
	await _key(KEY_ESCAPE)
	_check("Esc skips to the ending, still in the credits", credits.ended and GS.state == GS.State.CREDITS)
	await _key(KEY_ESCAPE)
	await process_frame
	_back_in_level(where, "Esc, Esc")
	await process_frame
	await process_frame
	_check("that Esc did not also pause the game", GS.state == GS.State.IN_GAME_PLAYER)

	# --- MAIN MENU straight from the ending ---------------------------------------------------
	box.interact(GS.player)
	await process_frame
	credits.skip()
	await process_frame
	credits.get_node("%MainMenu").pressed.emit()
	await process_frame
	await process_frame
	_back_in_level(where, "MAIN MENU")

	# --- Not from a menu --------------------------------------------------------------------
	GS.change_state_to(GS.State.PAUSED)
	GS.open_credits()
	_check("open_credits() does nothing while paused", GS.state == GS.State.PAUSED)
	GS.return_to_game()

	print("RESULT credits in game ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
