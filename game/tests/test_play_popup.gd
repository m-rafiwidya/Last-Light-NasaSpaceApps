extends SceneTree
## The main menu's PLAY popup and the save index: both states (no save file after `clearsaves`,
## the three slots after `fakesaves`), the cards' contents and order, that the menu and the Moon
## take no input while it is open, keyboard and mouse selection, empty and unreadable slots,
## deleting (Del twice, the Delete button twice), Esc closing only the popup (focus back on PLAY),
## loading a save, START NEW CAMPAIGN and the `testlevel` console command.
## Saves go to user://saves_test (SaveIndex under a script run), cleared before and after.
## The save and popup scripts use autoloads, so they are loaded at run time, not named as types
## here (a test script compiles before the autoloads exist).
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_play_popup.gd
##
## Windowed with `-- --shot=<dir>` it also saves popup_empty.png, popup_saves.png (newest card
## selected) and popup_slots.png (an empty and an unreadable slot).

const SAVE_DIR: String = "user://saves_test"

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
	_clear_saves()
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
	# That click opened the planet explorer; Esc returns to the menu
	await _key(KEY_ESCAPE)
	await _seconds(0.5)
	_check("the planet explorer closes again", not menu.is_explorer_open())

	# 2. The save list
	DBG.parse_command("fakesaves")
	play.grab_focus()
	play.pressed.emit()
	await _seconds(0.6)
	var cards: Array = popup.get_cards()
	_check("[saves] the list is shown", popup.has_saves() and not popup.get_node("%NoSave").visible
		and popup.get_node("%LoadChip").visible)
	_check("[saves] three cards, one per slot", cards.size() == 3, str(cards.size()))
	if cards.size() == 3:
		var expected: Array = [
			["12/10/2026 22:41", "First Signal", "16 min played", "50%", false],
			["12/10/2026 22:27", "Wake Kite", "7 min played", "29%", false],
			["11/10/2026 21:05", "Wake Kite", "3 min played", "14%", false],
		]
		for i in 3:
			var c: Control = cards[i]
			var got: Array = [_text(c, "Date"), _text(c, "Title"), _text(c, "Played"), _text(c, "Percent"),
				c.find_child("AutosaveTag", true, false) != null]
			_check("[saves] card %d: slot order, date, title, time, %%, no tag" % (i + 1), got == expected[i], str(got))
		_check("[saves] cards show the mission image", cards.all(func(c: Control) -> bool:
			return (c.find_child("Image", true, false) as TextureRect).texture != null))
		_check("[saves] 16:9 image", is_equal_approx(cards[0].IMAGE_SIZE.aspect(), 16.0 / 9.0))
		_check("[saves] the newest card has focus and is selected", cards[0].has_focus() and cards[0].selected
			and cards.slice(1).all(func(c: Control) -> bool: return not c.selected))
		await _shot("popup_saves.png")

		await _key(KEY_DOWN)
		_check("[keys] down: second card", cards[1].has_focus() and cards[1].selected and not cards[0].selected)
		await _key(KEY_DOWN)
		_check("[keys] down: last card", cards[2].has_focus())
		await _key(KEY_DOWN)
		_check("[keys] down: START NEW CAMPAIGN", popup.get_node("%StartList").has_focus())
		await _key(KEY_DOWN)
		_check("[keys] down at the end stays on START", popup.get_node("%StartList").has_focus())
		await _key(KEY_UP)
		_check("[keys] up: back to the last card", cards[2].has_focus())
		for i in 3:
			await _key(KEY_UP)
		_check("[keys] up at the top stays on the first card", cards[0].has_focus())
		await _key(KEY_LEFT)
		await _key(KEY_RIGHT)
		_check("[keys] left/right stay on the card", cards[0].has_focus())

		await _mouse_to(cards[2])
		_check("[mouse] hovering a card focuses and selects it", cards[2].has_focus() and cards[2].selected
			and not cards[0].selected)

		# 3. Deleting, empty and unreadable slots
		await _key(KEY_UP)
		await _key(KEY_DELETE)
		_check("[delete] one Del arms it, the slot stays", cards[1].is_delete_armed()
			and FileAccess.file_exists(SI.slot_path("slot_2")))
		await _key(KEY_DOWN)
		await _key(KEY_UP)
		_check("[delete] leaving the card disarms it", not cards[1].is_delete_armed())
		await _key(KEY_DELETE)
		await _key(KEY_DELETE)
		cards = popup.get_cards()
		_check("[delete] Del twice deletes the slot", not FileAccess.file_exists(SI.slot_path("slot_2")))
		_check("[delete] the slot shows as empty, focused", cards.size() == 3 and _text(cards[1], "Title") == "Empty slot"
			and _text(cards[1], "Date") == "Slot 2" and cards[1].has_focus())
		_check("[empty] no image, no delete button", (cards[1].find_child("Image", true, false) as TextureRect).texture == null
			and cards[1].find_child("Delete", true, false) == null)
	await _esc_closes_only_popup(menu, popup, play, sub, "[saves]")

	_write_raw("slot_3", "{ not json")
	play.pressed.emit()
	await _seconds(0.6)
	cards = popup.get_cards()
	if cards.size() == 3:
		_check("[unreadable] a corrupt file shows as unreadable", _text(cards[2], "Title") == "Unreadable save")
		await _shot("popup_slots.png")
		cards[2].grab_focus()
		await _key(KEY_ENTER)
		_check("[unreadable] Enter does not load it", popup.is_open and SL.loading_scene_id == "")
		var delete: Button = cards[2].find_child("Delete", true, false)
		_check("[unreadable] it has a Delete button", delete != null)
		if delete:
			delete.pressed.emit()
			_check("[unreadable] one press asks again", delete.text == "Press again to delete"
				and FileAccess.file_exists(SI.slot_path("slot_3")))
			delete.pressed.emit()
			cards = popup.get_cards()
			_check("[unreadable] a second press deletes it", not FileAccess.file_exists(SI.slot_path("slot_3"))
				and _text(cards[2], "Title") == "Empty slot")
	await _esc_closes_only_popup(menu, popup, play, sub, "[unreadable]")
	DBG.parse_command("clearsaves")
	_check("clearsaves removes the fake saves", SI.list_saves().is_empty())

	# 3b. All slots used: START NEW CAMPAIGN asks first
	DBG.parse_command("fakesaves")
	_write_raw("slot_2", "{ not json")
	_check("[full] unreadable slots are replaced first", SI.new_campaign_slot() == "slot_2")
	play.pressed.emit()
	await _seconds(0.6)
	popup.get_node("%StartList").grab_focus()
	popup.get_node("%StartList").pressed.emit()
	await process_frame
	var confirm: Control = popup.get_node("Confirm")
	var message: String = (confirm.find_child("Message", true, false) as Label).text
	_check("[full] START asks first and names the slot", popup.is_confirming() and message.contains("Slot 2")
		and message.contains("unreadable") and SL.loading_scene_id == "", message)
	_check("[full] Cancel has focus", popup.get_confirm_buttons()[1].has_focus())
	await _key(KEY_ESCAPE)
	_check("[full] Esc cancels the question only", not popup.is_confirming() and popup.is_open
		and popup.get_node("%StartList").has_focus() and SL.loading_scene_id == "")
	popup.get_node("%StartList").pressed.emit()
	await process_frame
	popup.get_confirm_buttons()[1].pressed.emit()
	_check("[full] Cancel returns to the popup, nothing replaced", not popup.is_confirming() and popup.is_open
		and FileAccess.file_exists(SI.slot_path("slot_2")) and SL.loading_scene_id == "")
	SI.delete_slot("slot_2")
	DBG.parse_command("fakesaves")
	_check("[full] with no unreadable slot: the oldest", SI.new_campaign_slot() == "slot_3")
	popup.close(false)
	play.pressed.emit()
	await _seconds(0.6)
	popup.get_node("%StartList").pressed.emit()
	await process_frame
	_check("[full] the question names the oldest save", popup.is_confirming()
		and (confirm.find_child("Message", true, false) as Label).text.contains("Slot 3 (Wake Kite, 11/10/2026 21:05)"))
	popup.get_confirm_buttons()[0].pressed.emit()
	_check("[full] confirming starts the campaign in that slot", SL.loading_scene_id == "moon_level"
		and SI.current_slot == "slot_3")
	_check("[full] the replaced slot is cleared", not FileAccess.file_exists(SI.slot_path("slot_3")))
	await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level")
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)
	await process_frame
	DBG.parse_command("clearsaves")
	for id in ["slot_1", "slot_2", "slot_3"]:
		SI.delete_slot(id)

	# 4. Loading a save and START NEW CAMPAIGN
	DBG.parse_command("fakesaves")
	play.pressed.emit()
	await _seconds(0.6)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_check("[load] Enter on a card loads the Moon level", SL.loading_scene_id == "moon_level"
		and not popup.is_open and SI.current_slot == "slot_2")
	_check("[load] the Moon level comes up", await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"))
	await _seconds(0.6)
	DBG.parse_command("testlevel")
	_check("`testlevel` loads the test level", await _wait_state(GS.State.IN_GAME_PLAYER, "test_level"))
	await _seconds(0.6)
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)
	await process_frame
	_check("[load] leaving the Moon saved the slot (no longer a fake)", SI.clear_fake_saves() == 2
		and SI.read_slot("slot_2").is_readable())
	SI.delete_slot("slot_2")
	_check("back on the menu: popup closed, PLAY focused", not popup.is_open and play.has_focus())
	play.pressed.emit()
	await _seconds(0.6)
	await _key(KEY_ENTER)
	_check("[new] START NEW CAMPAIGN loads the Moon level in slot 1", SL.loading_scene_id == "moon_level"
		and SI.current_slot == "slot_1")
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
	_check("[index] mission titles", SI.mission_title("m1") == "Wake Kite"
		and SI.mission_title("m2") == "First Signal" and SI.mission_title("m3") == "Beyond the Rim")
	_check("[index] mission images by legacy id", SI.mission_image("m1") != null and SI.mission_image("m3") != null)
	_check("[index] three slots, all empty", SI.list_slots().size() == 3
		and SI.list_slots().all(func(i) -> bool: return i.is_empty()))
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
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(SI.slot_path(slot_id), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clear_saves() -> void:
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		for file_name in DirAccess.get_files_at(SAVE_DIR):
			DirAccess.remove_absolute(SAVE_DIR.path_join(file_name))


func _finish() -> void:
	_clear_saves()
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
