extends SceneTree
## Headless test: the HUD's "New control" tip cards (TipCard).
##   1. The card: rows and keys from the bindings (following a rebind), never takes the mouse,
##      auto-hides, hides once every control is used, one tip at a time.
##   2. Once per campaign: a shown tip isn't offered again; saved in CampaignState and not shown
##      again after load_state; a reset (new campaign) brings them back.
##   3. In the game: on foot in the workshop shows "on_foot", the first drive of Kite "drive", each
##      once, and neither after loading the save.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_tip_cards.gd

const TICKS: int = 240

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var tip_script: GDScript


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("%s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail else ""])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _keys(card: Node) -> Array:
	return card._chips.map(func(chip: KeyChip) -> String: return chip.key_text())


func _ignores_mouse(node: Node) -> bool:
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	return node.get_children().all(_ignores_mouse)


func _run() -> void:
	await process_frame
	tip_script = load("res://src/ui/tip_card/tip_card.gd")
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	CS.reset()
	InputBindings.reset()

	var card: Node = tip_script.new()
	root.add_child(card)
	_check("card: hidden until offered", not card.visible)
	card.offer(&"on_foot")
	_check("on foot: shown with move, look, interact", card.visible and _keys(card) == ["WASD", "Mouse", "E"], str(_keys(card)))
	_check("on foot: recorded in CampaignState", CS.is_tip_shown("on_foot") and not CS.is_tip_shown("drive"))
	_check("card: never takes the mouse", _ignores_mouse(card))
	card.offer(&"drive")
	_check("card: one tip at a time", card.tip == &"on_foot" and not CS.is_tip_shown("drive"))
	card._process(card.DURATION + 1.0)
	_check("card: hides by itself after its time", not card.visible)
	card.offer(&"on_foot")
	_check("on foot: not shown a second time", not card.visible)

	var rebound := InputEventKey.new()
	rebound.physical_keycode = KEY_K
	InputBindings.rebind(&"camera_next", rebound)
	card.offer(&"drive")
	_check("drive: shown with the keys as bound now", card.visible and _keys(card) == ["WASD", "K", "F", "L"], str(_keys(card)))
	var other := InputEventKey.new()
	other.physical_keycode = KEY_J
	InputBindings.rebind(&"camera_next", other)
	_check("drive: follows a rebind while shown", _keys(card)[1] == "J", str(_keys(card)))
	InputBindings.reset()
	card.dismiss()

	CS.reset()
	card.offer(&"drive")
	Input.action_press(&"camera_next")
	Input.action_press(&"robot_reset")
	Input.action_press(&"lights")
	Input.action_press(&"move_forward")
	await process_frame
	await process_frame
	var all_used: bool = not card.used.has(false)
	Input.action_release(&"camera_next")
	Input.action_release(&"robot_reset")
	Input.action_release(&"lights")
	Input.action_release(&"move_forward")
	_check("drive: each control is marked used by pressing it", all_used, str(card.used))
	await _ticks(card.LINGER + card.FADE_OUT + 0.3)
	_check("drive: hides soon after every control was used", not card.visible, "age %.1f" % card.age)
	CS.reset()
	card.offer(&"on_foot")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(200.0, 0.0)
	card._input(motion)
	card._process(0.016)
	_check("on foot: moving the mouse marks Look used", card.used == [false, true, false], str(card.used))
	card.queue_free()

	CS.reset()
	var first: Node = tip_script.new()
	root.add_child(first)
	first.offer(&"on_foot")
	first.dismiss()
	var saved: Dictionary = CS.save_state()
	_check("save: the shown tips are saved", saved["tips_shown"] == ["on_foot"], str(saved.get("tips_shown")))
	CS.reset()
	_check("reset: a new campaign starts without shown tips", not CS.is_tip_shown("on_foot"))
	_check("load: the save loads", CS.load_state(saved))
	var second: Node = tip_script.new()
	root.add_child(second)
	second.offer(&"on_foot")
	_check("load: a loaded tip doesn't show again", not second.visible and CS.is_tip_shown("on_foot"))
	second.offer(&"drive")
	_check("load: a tip not yet shown still does", second.visible and second.tip == &"drive")
	first.queue_free()
	second.queue_free()
	var old_save: Dictionary = saved.duplicate()
	old_save.erase("tips_shown")
	_check("load: a save from before tips loads, with none shown", CS.load_state(old_save) and not CS.is_tip_shown("on_foot"))

	CS.reset()
	load("res://src/save/save_index.gd").start_new_campaign()
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	var hud: Node = root.get_node("Main/UIManager/HUD").tips
	var robot_hud: Node = root.get_node("Main/UIManager/RobotHUD").tips
	await _ticks(1.0)
	_check("game: on foot in the workshop the on-foot tip shows", hud.visible and hud.tip == &"on_foot" and CS.is_tip_shown("on_foot"))
	_check("game: the drive tip isn't up yet", not robot_hud.visible and not CS.is_tip_shown("drive"))
	GS.drive(level.get_node("ReadyRover"))
	await _ticks(1.0)
	_check("game: first drive of Kite shows the drive tip", robot_hud.visible and robot_hud.tip == &"drive" and CS.is_tip_shown("drive"))
	_check("game: the on-foot tip is gone while driving", not hud.visible)
	robot_hud.dismiss()
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(1.0)
	GS.drive(level.get_node("ReadyRover"))
	await _ticks(1.0)
	_check("game: neither shows again in the same campaign", not hud.visible and not robot_hud.visible)

	var data: Dictionary = CS.save_state()
	CS.reset()
	CS.load_state(data)
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level" and SL.current_scene != level):
		await physics_frame
	level = SL.current_scene
	await _ticks(1.0)
	_check("game: after loading, no tip shows on foot", not hud.visible)
	GS.drive(level.get_node("ReadyRover"))
	await _ticks(1.0)
	_check("game: ... or when driving", not robot_hud.visible)

	print("RESULT test_tip_cards %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
