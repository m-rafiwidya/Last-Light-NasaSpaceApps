extends SceneTree
## The main menu's PLAY popup and the save index: both states (no save file after `clearsaves`,
## the save list after `fakesaves`), the cards' contents and order, that the menu and the Moon
## take no input while it is open, keyboard and mouse selection, scrolling a long list, broken
## metadata files being skipped, Esc closing only the popup (focus back on PLAY), loading a save
## and START NEW CAMPAIGN (both the Moon level for now) and the `testlevel` console command.
## user://saves is moved aside while it runs and put back afterwards.
## The save and popup scripts use autoloads, so they are loaded at run time, not named as types
## here (a test script compiles before the autoloads exist).
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_play_popup.gd
##
## Windowed with `-- --shot=<dir>` it also saves popup_empty.png, popup_saves.png (newest card
## selected) and popup_scrolled.png (eight saves, scrolled to the last).

const BACKUP_DIR: String = "user://saves_test_backup"
const SAVE_DIR: String = "user://saves"

var GS: Node
var SL: Node
var DBG: Node
var SI: GDScript   # SaveIndex
var SlotInfo: GDScript   # SaveSlotInfo
var failures: int = 0
var shot_dir: String = ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_dir = arg.trim_prefix("--shot=")
	_move_saves_aside()
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-62s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _wait_state(state: int, level_id: String = "", seconds: float = 120.0) -> bool:
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


func _mouse_to(control: Control) -> Vector2:
	var at: Vector2 = root.get_final_transform() * control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = Vector2(3.0, 0.0)
	Input.parse_input_event(motion)
	await process_frame
	await process_frame
	return at


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
	await process_frame
	await process_frame


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	DBG = root.get_node("Debug")
	SI = load("res://src/save/save_index.gd")
	SlotInfo = load("res://src/save/save_slot_info.gd")
	_check_index()
	if not await _wait_state(GS.State.MAIN_MENU):
		_check("the main menu comes up", false)
		_finish()
		return
	var menu: Node = root.get_node("Main/UIManager/MainMenu")
	var loading := root.get_node("Main/UIManager/LoadingScreen") as CanvasLayer
	await _seconds(0.3)
	menu.skip_intro()
	await process_frame
	while loading.visible:
		await process_frame
	await _seconds(0.6)
	var popup: Control = menu.find_child("PlayPopup", true, false)
	var play: Button = menu.find_child("Play", true, false)
	var sub: Control = menu.get_node("MainMenuSubScreen")
	var moon: MenuMoon = menu.find_child("Moon", true, false)
	_check("the main menu no longer lists the levels", menu.find_child("LevelChoice", true, false) == null)
	_check("PLAY has focus", play.has_focus())

	# 1. No save file
	DBG.parse_command("clearsaves")
	play.pressed.emit()
	await _seconds(0.6)
	_check("[no saves] PLAY opens the popup", popup.is_open and popup.visible)
	await _shot("popup_empty.png")
	_check("[no saves] 'There's no save file.' and START, no list",
		popup.get_node("%NoSave").visible and not popup.has_saves() and popup.get_cards().is_empty())
	_check("[no saves] START NEW CAMPAIGN has focus", popup.get_node("%StartEmpty").has_focus())
	_check("[no saves] footer: Esc Cancel only, no Enter Load",
		not popup.get_node("%LoadChip").visible and popup.find_child("CancelChip", true, false).visible)
	_check("[no saves] back button top-left", popup.get_node("%Back").position == BackButton.DESIGN_POSITION)
	_check("[no saves] the menu takes no mouse or focus",
		sub.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_DISABLED
		and sub.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED)
	var clicked: Array = [0]
	moon.moon_clicked.connect(func() -> void: clicked[0] += 1)
	await _click(root.get_final_transform() * (moon.get_global_transform() * Vector2(700.0, 700.0)))
	_check("[no saves] clicking the Moon does nothing", clicked[0] == 0)
	for key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB]:
		await _key(key)
	_check("[no saves] arrows and Tab keep focus on START", popup.get_node("%StartEmpty").has_focus())

	await _esc_closes_only_popup(menu, popup, play, sub, "[no saves]")
	await _mouse_to(play)   # (the cursor ends up off the Moon)
	await _click(root.get_final_transform() * (moon.get_global_transform() * Vector2(700.0, 700.0)))
	_check("after closing: the Moon takes clicks again", clicked[0] == 1)

	# 2. The save list
	DBG.parse_command("fakesaves")
	play.grab_focus()
	play.pressed.emit()
	await _seconds(0.6)
	var cards: Array = popup.get_cards()
	_check("[saves] the list is shown", popup.has_saves() and not popup.get_node("%NoSave").visible
		and popup.get_node("%LoadChip").visible)
	_check("[saves] five cards", cards.size() == 5, str(cards.size()))
	if cards.size() == 5:
		var expected: Array = [
			["12/10/2026 22:41", "First Signal", "16 min played", "38%", false],
			["12/10/2026 22:38", "First Signal", "13 min played", "31%", true],
			["12/10/2026 22:31", "First Signal", "9 min played", "25%", true],
			["12/10/2026 22:27", "Wake Kite", "7 min played", "19%", true],
			["11/10/2026 21:05", "Wake Kite", "3 min played", "6%", true],
		]
		for i in 5:
			var c: Control = cards[i]
			var got: Array = [_text(c, "Date"), _text(c, "Title"), _text(c, "Played"), _text(c, "Percent"),
				c.find_child("AutosaveTag", true, false) != null]
			_check("[saves] card %d: newest first, date, title, time, %%, tag" % (i + 1), got == expected[i], str(got))
		_check("[saves] cards show the mission image", cards.all(func(c: Control) -> bool:
			return (c.find_child("Image", true, false) as TextureRect).texture != null))
		_check("[saves] 16:9 image", is_equal_approx(cards[0].IMAGE_SIZE.aspect(), 16.0 / 9.0))
		_check("[saves] the newest card has focus and is selected", cards[0].has_focus() and cards[0].selected
			and cards.slice(1).all(func(c: Control) -> bool: return not c.selected))
		await _shot("popup_saves.png")

		# Keyboard: up/down walk the cards, then START; focus never leaves the popup
		await _key(KEY_DOWN)
		_check("[keys] down: second card", cards[1].has_focus() and cards[1].selected and not cards[0].selected)
		for i in 3:
			await _key(KEY_DOWN)
		_check("[keys] down x3: last card", cards[4].has_focus())
		await _key(KEY_DOWN)
		_check("[keys] down: START NEW CAMPAIGN", popup.get_node("%StartList").has_focus())
		await _key(KEY_DOWN)
		_check("[keys] down at the end stays on START", popup.get_node("%StartList").has_focus())
		await _key(KEY_UP)
		_check("[keys] up: back to the last card", cards[4].has_focus())
		for i in 5:
			await _key(KEY_UP)
		_check("[keys] up at the top stays on the newest card", cards[0].has_focus())
		await _key(KEY_LEFT)
		await _key(KEY_RIGHT)
		_check("[keys] left/right stay on the card", cards[0].has_focus())

		# Mouse: hovering a card selects it
		await _mouse_to(cards[2])
		_check("[mouse] hovering a card focuses and selects it", cards[2].has_focus() and cards[2].selected
			and not cards[0].selected)

	await _esc_closes_only_popup(menu, popup, play, sub, "[saves]")

	# 3. A long list scrolls and keeps the selected card in view; broken files are skipped
	for i in 3:
		var extra = SlotInfo.new()
		extra.slot_id = "fake_extra_%d" % i
		extra.mission_id = "beyond_the_rim"
		extra.saved_at = 1_700_000_000 - i * 60
		extra.play_time_sec = 72 * 60
		extra.story_progress = 0.9
		SI.write_meta(extra)
	_write_raw("fake_broken_json", "{ not json")
	_write_raw("fake_broken_fields", JSON.stringify({"saved_at": 5}))
	_check("[index] broken metadata files are skipped", SI.list_saves().size() == 8,
		str(SI.list_saves().size()))
	play.pressed.emit()
	await _seconds(0.6)
	cards = popup.get_cards()
	var scroll: ScrollContainer = popup.get_node("%Scroll")
	_check("[scroll] eight cards, the list is capped", cards.size() == 8
		and scroll.size.y <= popup.MAX_LIST_HEIGHT + 0.5, "%d cards, %.0f px" % [cards.size(), scroll.size.y])
	if cards.size() == 8:
		_check("[scroll] an older save of another mission", _text(cards[7], "Title") == "Beyond the Rim"
			and _text(cards[7], "Played") == "1 h 12 min played")
		for i in 7:
			await _key(KEY_DOWN)
		await process_frame
		_check("[scroll] down to the last card scrolls the list", cards[7].has_focus() and scroll.scroll_vertical > 0,
			"scroll %d" % scroll.scroll_vertical)
		_check("[scroll] the selected card is in view, brackets included",
			scroll.get_global_rect().grow(1.0).encloses(cards[7].get_global_rect().grow(popup.LIST_MARGIN)))
		await _seconds(0.2)
		await _shot("popup_scrolled.png")
		for i in 7:
			await _key(KEY_UP)
		await process_frame
		_check("[scroll] back up to the newest card", cards[0].has_focus() and scroll.scroll_vertical == 0)
	await _esc_closes_only_popup(menu, popup, play, sub, "[scroll]")
	DBG.parse_command("clearsaves")
	_check("clearsaves removes the fake saves", SI.list_saves().is_empty())

	# 4. Loading a save (a stub: the Moon level) and START NEW CAMPAIGN
	DBG.parse_command("fakesaves")
	play.pressed.emit()
	await _seconds(0.6)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_check("[load] Enter on a card loads the Moon level (load_slot stub)", SL.loading_scene_id == "moon_level"
		and not popup.is_open)
	_check("[load] the Moon level comes up", await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"))
	await _seconds(0.6)
	DBG.parse_command("testlevel")
	_check("`testlevel` loads the test level", await _wait_state(GS.State.IN_GAME_PLAYER, "test_level"))
	await _seconds(0.6)
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)
	await process_frame
	DBG.parse_command("clearsaves")
	_check("back on the menu: popup closed, PLAY focused", not popup.is_open and play.has_focus())
	play.pressed.emit()
	await _seconds(0.6)
	await _key(KEY_ENTER)
	_check("[new] START NEW CAMPAIGN loads the Moon level", SL.loading_scene_id == "moon_level")
	_check("[new] the Moon level comes up", await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"))
	_finish()


func _esc_closes_only_popup(menu: Node, popup: Control, play: Button, sub: Control, tag: String) -> void:
	await _key(KEY_ESCAPE)
	_check(tag + " Esc closes the popup", not popup.is_open)
	_check(tag + " Esc does nothing else (still the main menu, no pause)", GS.state == GS.State.MAIN_MENU
		and not paused and menu.sub_screen == menu.SubScreen.MAIN_MENU and menu.get_node("Background").visible
		and not DBG.console_open)
	_check(tag + " focus is back on PLAY, the menu takes input again", play.has_focus()
		and sub.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_INHERITED
		and sub.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_INHERITED)
	await _seconds(0.4)
	_check(tag + " the popup has faded out", not popup.visible)
	await _key(KEY_ESCAPE)
	_check(tag + " a second Esc on the menu changes nothing", GS.state == GS.State.MAIN_MENU and not popup.is_open
		and play.has_focus())


## Formats and parsing, without the menu
func _check_index() -> void:
	_check("[index] no saves: empty list", SI.list_saves().is_empty())
	_check("[index] mission titles from MISSIONS.json", SI.mission_title("wake_kite") == "Wake Kite"
		and SI.mission_title("first_signal") == "First Signal"
		and SI.mission_title("beyond_the_rim") == "Beyond the Rim")
	_check("[index] play time", SI.format_play_time(16 * 60 + 30) == "16 min played"
		and SI.format_play_time(72 * 60) == "1 h 12 min played"
		and SI.format_play_time(120 * 60) == "2 h played")
	var info = SlotInfo.from_dict("a", {"mission_id": "wake_kite", "saved_at": 10.0, "story_progress": 3})
	_check("[index] metadata: defaults and clamping", info != null and info.saved_at == 10
		and info.story_progress == 1.0 and not info.is_autosave and info.current_objective == "")
	_check("[index] metadata: missing fields rejected", SlotInfo.from_dict("b", {"mission_id": "x"}) == null
		and SlotInfo.from_dict("c", [1, 2]) == null and SlotInfo.from_dict("d", null) == null)


func _text(card: Control, node_name: String) -> String:
	var label: Label = card.find_child(node_name, true, false)
	return label.text if label else "<none>"


func _write_raw(slot_id: String, text: String) -> void:
	var file := FileAccess.open(SAVE_DIR.path_join(slot_id + ".meta.json"), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _move_saves_aside() -> void:
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.rename_absolute(SAVE_DIR, BACKUP_DIR)


func _restore_saves() -> void:
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		for file_name in DirAccess.get_files_at(SAVE_DIR):
			DirAccess.remove_absolute(SAVE_DIR.path_join(file_name))
		DirAccess.remove_absolute(SAVE_DIR)
	if DirAccess.dir_exists_absolute(BACKUP_DIR):
		DirAccess.rename_absolute(BACKUP_DIR, SAVE_DIR)


func _finish() -> void:
	_restore_saves()
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
