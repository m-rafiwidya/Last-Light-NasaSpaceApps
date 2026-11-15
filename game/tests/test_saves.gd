extends SceneTree
## Saves (SaveIndex, KiteSave, CampaignState.save_state / load_state):
##   1. CampaignState round trip through JSON; load_state emits no signal; bad data changes nothing.
##   2. Slots: a new campaign takes the first empty slot, then the oldest when all are used.
##   3. Corrupt, old-version and incomplete files read as unreadable, don't load, can be deleted.
##   4. On the Moon: completing an objective autosaves, quitting to the menu saves; loading the
##      slot gives the same campaign and Kite parts and charge, Kite docked, IRIS scanned, and no
##      objective or mission signal.
## Saves go to user://saves_test (SaveIndex under a script run), cleared before and after.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_saves.gd

var GS: Node
var SL: Node
var CS: Node
var SI: GDScript
var KS: GDScript
var failures: int = 0
var signals: Array = []


func _initialize() -> void:
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


func _ticks(seconds: float) -> void:
	for i in int(seconds * 240):
		await physics_frame


func _clear_dir() -> void:
	var dir: String = SI.save_dir()
	if DirAccess.dir_exists_absolute(dir):
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))


func _write_raw(slot_id: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SI.save_dir())
	var file := FileAccess.open(SI.slot_path(slot_id), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(slot_id: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(SI.slot_path(slot_id)))


func _rack(workshop: Node) -> Dictionary:
	var counts: Dictionary = {"total": 0}
	for part in workshop.rack_stock.get_children():
		if part.has_method("get_catalog_id") and not part.is_queued_for_deletion():
			counts["total"] += 1
			counts[part.get_catalog_id()] = int(counts.get(part.get_catalog_id(), 0)) + 1
	return counts


func _campaign(state: Dictionary) -> String:
	var copy: Dictionary = state.duplicate()
	copy.erase("play_time_sec")
	copy.erase("mission_stats")
	return JSON.stringify(copy)


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	SI = load("res://src/save/save_index.gd")
	KS = load("res://src/save/kite_save.gd")
	for s in ["mission_started", "mission_completed", "objective_completed", "flag_changed"]:
		CS.connect(s, func(a = null, _b = null) -> void: signals.append("%s:%s" % [s, a]))
	_clear_dir()
	_check("tests save to user://saves_test", SI.save_dir() == "user://saves_test")

	# 1. CampaignState round trip
	CS.reset()
	CS.start_mission("m1")
	for objective in ["m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]:
		CS.complete_objective(objective)
	CS.start_mission("m2")
	CS.complete_objective("m2.cargo_ordered")
	CS.complete_objective("m2.module_loaded")
	CS.set_flag("iris_online")
	CS.add_item("sample", 2)
	CS.play_time_sec = 123.5
	var before: Dictionary = CS.save_state()
	var text: String = JSON.stringify(before)
	CS.reset()
	signals.clear()
	var ok: bool = CS.load_state(JSON.parse_string(text))
	_check("[state] load_state accepts saved data", ok)
	_check("[state] round trip through JSON is identical", JSON.stringify(CS.save_state()) == text,
		JSON.stringify(CS.save_state()))
	_check("[state] restored: mission, objectives, flags, items", CS.current_mission() == "m2"
		and CS.is_mission_completed("m1") and CS.is_objective_done("m2.module_loaded")
		and CS.has_flag("iris_online") and CS.has_item("sample") and CS.current_objective() == "m2.module_installed")
	_check("[state] load_state emits no signal", signals.is_empty(), str(signals))
	_check("[state] bad data is refused and changes nothing", not CS.load_state({"current": 5})
		and not CS.load_state({}) and JSON.stringify(CS.save_state()) == text)
	_check("[state] unknown ids are dropped", CS.load_state({"current": "m9", "objectives": ["nope", "m1.kite_prepared"],
		"missions_done": ["m9"], "flags": [], "items": {"x": -1}}) and CS.current_mission() == ""
		and CS.save_state()["objectives"] == ["m1.kite_prepared"] and CS.save_state()["items"].is_empty())
	CS.reset()

	if not await _wait_state(GS.State.MAIN_MENU):
		_check("the main menu comes up", false)
		_finish()
		return

	# 2. Slots
	_check("[slots] three empty slots", SI.list_slots().size() == 3
		and SI.list_slots().all(func(i) -> bool: return i.is_empty()) and SI.list_saves().is_empty())
	_check("[slots] new campaign slot: the first empty one", SI.new_campaign_slot() == "slot_1")
	SI.write_fake_saves()
	_check("[slots] all used: the oldest", SI.new_campaign_slot() == "slot_3")
	var fakes: Array = SI.list_saves()
	_check("[slots] fake saves are readable, newest first", fakes.size() == 3 and fakes[0].slot_id == "slot_1"
		and fakes[0].mission_title == "First Signal" and fakes[0].current_objective != "")
	_check("[slots] clearsaves removes them", SI.clear_fake_saves() == 3 and SI.list_saves().is_empty())

	# 3. Corrupt and old files
	_write_raw("slot_1", "{ not json")
	_write_raw("slot_2", JSON.stringify({"version": 0, "meta": {"mission_id": "m1", "saved_at": 5}, "campaign": {}}))
	_write_raw("slot_3", JSON.stringify({"version": 1, "meta": {"saved_at": 5}, "campaign": {}}))
	var slots: Array = SI.list_slots()
	_check("[corrupt] broken, old-version and incomplete files are unreadable",
		slots.all(func(i) -> bool: return i.state == SlotInfoState.UNREADABLE), str(slots.map(func(i): return i.state)))
	CS.start_mission("m1")
	var state_before: String = JSON.stringify(CS.save_state())
	_check("[corrupt] loading one fails and changes nothing", not SI.load_slot("slot_1") and not SI.load_slot("slot_2")
		and not SI.load_slot("slot_3") and JSON.stringify(CS.save_state()) == state_before and SL.loading_scene_id == "")
	_write_raw("slot_2", JSON.stringify({"version": 1, "meta": {"mission_id": "m1", "saved_at": 5},
		"campaign": {"current": 3}, "kite": {}}))
	_check("[corrupt] bad campaign data doesn't load", not SI.load_slot("slot_2"))
	_check("[corrupt] new campaign slot: an unreadable one", SI.new_campaign_slot() == "slot_1")
	for id in ["slot_1", "slot_2", "slot_3"]:
		SI.delete_slot(id)
	_check("[corrupt] they can be deleted", SI.list_slots().all(func(i) -> bool: return i.is_empty()))

	# 4. On the Moon
	CS.reset()
	SI.start_new_campaign()
	_check("[moon] new campaign: slot_1, m1", SI.current_slot == "slot_1" and CS.current_mission() == "m1")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("[moon] the Moon level comes up", false)
		_finish()
		return
	var level: Node = SL.current_scene
	var rover = level.get_node("ReadyRover")
	var workshop: Node = level.get_node("Workshop")
	await _ticks(1.0)
	var gated: Dictionary = _rack(workshop)
	_check("[rack] a new campaign leaves the cargo slots empty", gated["total"] == 13 and gated["wheel"] == 6
		and not gated.has("wheel_high_grip") and not gated.has("radio_module") and not gated.has("arm_tool_thermal")
		and gated["battery"] == 1 and gated["battery_light"] == 1 and workshop.rack_stock.has_node("Slot12"), str(gated))
	CS.add_item("cargo.grip_wheels")
	workshop.account_rack()
	await physics_frame
	var full_rack: Dictionary = _rack(workshop)
	_check("[rack] delivered grip wheels fill their slots", full_rack["total"] == 17 and full_rack["wheel_high_grip"] == 4,
		str(full_rack))
	workshop._on_restock_interacted(null)
	await physics_frame
	_check("[rack] Restock keeps it the same", _rack(workshop) == full_rack, str(_rack(workshop)))
	_check("[moon] nothing saved before progress", not FileAccess.file_exists(SI.slot_path("slot_1")))
	var light = null
	var grip = null
	for part in workshop.rack_stock.get_children():
		if part.has_method("get_catalog_id") and part.get_catalog_id() == "battery_light" and light == null:
			light = part
		if part.has_method("get_catalog_id") and part.get_catalog_id() == "wheel_high_grip" and grip == null:
			grip = part
	var old_wheel = rover.front_left_socket.unmount()
	old_wheel.get_parent().remove_child(old_wheel)
	create_timer(1.0).timeout.connect(old_wheel.free)
	rover.front_left_socket.mount(grip)
	rover.battery_socket.mount(light)
	await physics_frame
	_check("[moon] fitting the battery completes m1.kite_prepared", CS.is_objective_done("m1.kite_prepared"))
	var saved: Variant = _read("slot_1")
	_check("[autosave] objective_completed wrote the slot", saved is Dictionary and saved["version"] == 1
		and saved["campaign"]["objectives"].has("m1.kite_prepared"))
	if saved is Dictionary:
		_check("[autosave] card metadata", saved["meta"]["mission_id"] == "m1" and saved["meta"]["mission_title"] == "Wake Kite"
			and saved["meta"]["current_objective"] == CS.objective_title("m1.iris_scanned")
			and saved["meta"]["saved_at"] > 1_700_000_000)
		_check("[autosave] Kite's parts", saved["kite"]["sockets"][str(rover.battery_socket.name)]["scene"]
			== light.scene_file_path and saved["kite"]["sockets"][str(rover.front_left_socket.name)]["properties"]["catalog_id"]
			== "wheel_high_grip")
	level.get_node("Iris/ServicePanel").mark_scanned(rover)
	await physics_frame
	_check("[moon] scanning IRIS completes m1.iris_scanned", CS.is_objective_done("m1.iris_scanned"))
	light.charge = 37.5
	var battery_name: String = str(rover.battery_socket.name)
	var kite_before: Dictionary = KS.capture(rover)
	var state_saved: Dictionary = CS.save_state()
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)
	saved = _read("slot_1")
	_check("[quit] quitting to the menu saved the battery charge", saved is Dictionary
		and is_equal_approx(saved["kite"]["sockets"][battery_name].get("charge", 0.0), 37.5))
	_check("[menu] the card shows it", SI.list_saves().size() == 1 and SI.list_saves()[0].mission_title == "Wake Kite")

	CS.reset()
	signals.clear()
	_check("[load] load_slot starts loading", SI.load_slot("slot_1") and SL.loading_scene_id == "moon_level")
	_check("[load] the campaign is restored", _campaign(CS.save_state()) == _campaign(state_saved),
		_campaign(CS.save_state()))
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("[load] the Moon level comes up", false)
		_finish()
		return
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	workshop = level.get_node("Workshop")
	await _ticks(3.0)
	var kite_after: Dictionary = KS.capture(rover)
	var charge_after: float = kite_after["sockets"][battery_name].get("charge", -1.0)
	for k in [kite_before, kite_after]:
		k["sockets"][battery_name].erase("charge")
	_check("[load] Kite has the same parts", JSON.stringify(kite_after) == JSON.stringify(kite_before),
		JSON.stringify(kite_after))
	_check("[load] the battery kept its charge", charge_after >= 37.5 - 0.01 and charge_after < 40.0, str(charge_after))
	_check("[load] the high-grip wheel is on", rover.front_left_socket.part.get_catalog_id() == "wheel_high_grip"
		and is_equal_approx(rover.front_left_socket.part.grip, 1.3))
	_check("[load] Kite is on the pad", workshop.pad.is_in_zone(rover), str(workshop.pad.offset_of(rover)))
	_check("[load] IRIS's panel is already scanned", level.get_node("Iris/ServicePanel").is_scanned)
	_check("[load] the next objective is docking", CS.current_objective() == "m1.kite_docked")
	_check("[load] no objective or mission signal was emitted", signals.is_empty(), str(signals))
	_check("[load] saving continues in the same slot", SI.current_slot == "slot_1")
	var rack: Dictionary = _rack(workshop)
	_check("[rack] a battery on Kite means one fewer on the rack", rack.get("battery_light", 0) == full_rack["battery_light"] - 1
		and rack["battery"] == full_rack["battery"], str(rack))
	_check("[rack] a high-grip wheel on Kite: one fewer grip wheel, no duplicate", rack["wheel_high_grip"] == 3, str(rack))
	_check("[rack] Kite's original wheel is back on the rack", rack["wheel"] == 7 and rack["total"] == full_rack["total"] - 1, str(rack))
	workshop._on_restock_interacted(null)
	await physics_frame
	_check("[rack] Restock follows the same rule", _rack(workshop) == rack, str(_rack(workshop)))
	_finish()


const SlotInfoState = preload("res://src/save/save_slot_info.gd").State


func _finish() -> void:
	_clear_dir()
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
