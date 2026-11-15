extends SceneTree
## Saves (SaveIndex, KiteSave, CampaignState.save_state / load_state):
##   1. CampaignState round trip through JSON; load_state emits no signal; bad data changes nothing.
##   2. Slots: a new campaign takes the first empty slot, then the oldest when all are used.
##   3. Corrupt, old-version and incomplete files read as unreadable, don't load, can be deleted.
##   4. On the Moon: completing an objective autosaves, quitting alone doesn't save; loading the
##      slot gives the same campaign and Kite parts and charge, Kite docked, IRIS scanned, and no
##      objective or mission signal.
##   5. The M2 crate at the landing zone keeps its spot and mass through a load; saved aboard Kite out
##      in the field, a load puts Kite back there with the crate still aboard.
##   6. Tray parts, a stranded Kite in the field, the toast ("Saving..." / "Saved" / a failed write that
##      keeps the last save), the blocked reasons (carrying, EVA) with the pause menu's SAVE GAME and quit
##      question, the autosave on coming back inside, and two loads in a row giving the same world.
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
	for objective in ["m1.workshop_entered", "m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]:
		CS.complete_objective(objective)
	CS.start_mission("m2")
	CS.complete_objective("m2.cargo_ordered")
	CS.complete_objective("m2.cargo_retrieved")
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
	# The thermal turret is always on the rack (not a cargo item); only ordered items are gated
	_check("[rack] a new campaign leaves the cargo slots empty", gated["total"] == 14 and gated["wheel"] == 6
		and not gated.has("wheel_high_grip") and not gated.has("radio_module") and gated.get("arm_tool_thermal", 0) == 1
		and gated["battery"] == 1 and gated["battery_light"] == 1 and workshop.rack_stock.has_node("Slot12"), str(gated))
	CS.add_item("cargo.grip_wheels")
	CS.set_flag("cargo_at_landing_zone")
	await physics_frame
	var waiting: Dictionary = _rack(workshop)
	_check("[rack] ordered grip wheels stay off the rack while the crate is out", not waiting.has("wheel_high_grip")
		and waiting.get("arm_tool_thermal", 0) == 1 and waiting["total"] == 14, str(waiting))
	CS.set_flag("cargo_at_landing_zone", false)
	await physics_frame
	var full_rack: Dictionary = _rack(workshop)
	_check("[rack] delivered grip wheels fill their slots", full_rack["total"] == 18 and full_rack["wheel_high_grip"] == 4
		and full_rack.get("arm_tool_thermal", 0) == 1, str(full_rack))
	workshop._on_restock_interacted(null)
	await physics_frame
	_check("[rack] Restock keeps it the same", _rack(workshop) == full_rack, str(_rack(workshop)))
	var early: Variant = JSON.parse_string(FileAccess.get_file_as_string(SI.slot_path("slot_1"))) \
		if FileAccess.file_exists(SI.slot_path("slot_1")) else null
	_check("[moon] the walk into the workshop is the first progress saved", early is Dictionary
		and early["campaign"]["objectives"] == ["m1.workshop_entered"], str(early))
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
	await _frames(3)
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
	_check("[save] save_now writes", SI.save_now() == OK)
	light.charge = 20.0
	var before_quit: String = FileAccess.get_file_as_string(SI.slot_path("slot_1"))
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)
	_check("[quit] quitting alone doesn't save", FileAccess.get_file_as_string(SI.slot_path("slot_1")) == before_quit)
	saved = _read("slot_1")
	_check("[save] the saved battery charge", saved is Dictionary
		and is_equal_approx(saved["kite"]["sockets"][battery_name].get("charge", 0.0), 37.5)
		and saved["meta"]["is_autosave"] == false)
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
	_check("[load] Kite has the same parts", JSON.stringify(kite_after["sockets"]) == JSON.stringify(kite_before["sockets"]),
		JSON.stringify(kite_after["sockets"]))
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

	# 5. The cargo crate out at the landing zone: where it lies and whether it is aboard survive a load
	CS.load_state({"current": "m2", "objectives": ["m1.workshop_entered", "m1.kite_prepared", "m1.iris_scanned",
		"m1.kite_docked", "m1.inspection_sent"], "missions_done": ["m1"], "flags": [], "items": {}})
	var plan: GDScript = load("res://src/levels/cargo_plan.gd")
	plan.deliver("courier", ["radio_module", "thermal_kit"])
	await _ticks(1.0)
	var crate_at: Vector3 = _crate(level).global_position
	await _save_and_quit()
	CS.reset()
	SI.load_slot("slot_1")
	await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level")
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	await _ticks(2.0)
	var crate: Node3D = _crate(level)
	_check("[cargo] at the landing zone after a load: same spot, same mass, flag set, lander there", crate != null
		and crate.global_position.distance_to(crate_at) < 0.2 and is_equal_approx(crate.mass, plan.crate_mass())
		and CS.has_flag("cargo_at_landing_zone") and level.has_node("LandingZone/CargoLander")
		and CS.current_objective() == "m2.cargo_retrieved", str(crate.global_position if crate else null))
	var out_there: Vector3 = crate_at + Vector3(-60.0, 0.0, -20.0)
	rover.freeze = true
	rover.global_position = out_there + Vector3.UP * 1.0
	crate.freeze = false
	rover.get_node("CargoSocket").mount(crate)
	await _ticks(0.3)
	out_there = rover.global_position
	await _save_and_quit()
	_check("[cargo] saved aboard Kite with where Kite was", _read("slot_1")["kite"]["sockets"]["CargoSocket"] is Dictionary
		and _read("slot_1")["kite"]["on_pad"] == false)
	CS.reset()
	SI.load_slot("slot_1")
	await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level")
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	await _ticks(2.0)
	crate = _crate(level)
	var off: Vector3 = rover.global_position - out_there
	off.y = 0.0
	_check("[cargo] loaded: Kite where it was, the crate still aboard, nothing left behind", crate != null
		and _crate_count(level) == 1 and rover.get_node("CargoSocket").part == crate
		and not level.get_node("Workshop").pad.is_in_zone(rover) and off.length() < 1.0
		and not level.get_node("MissionDirector").left_parts.has_parts()
		and not CS.is_objective_done("m2.cargo_retrieved"), "%.2f m" % off.length())
	await _check_field_saves()
	_finish()


func _save_and_quit() -> void:
	_check("[save] save_now before quitting", SI.save_now() == OK)
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _load_moon() -> void:
	CS.reset()
	SI.load_slot("slot_1")
	await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level")
	await _ticks(2.0)


## What a load must give back: where Kite is, stranded, its charge and cargo, the tray, the rack
func _world() -> Dictionary:
	var level: Node = SL.current_scene
	var rover = level.get_node("ReadyRover")
	var director: Node = level.get_node("MissionDirector")
	var tray: Node3D = rover.get_node("StorageBox")
	var items: Array = []
	for part in tray.items():
		var local: Transform3D = tray.global_transform.affine_inverse() * part.global_transform
		items.append([part.get_catalog_id(), local.origin])
	items.sort_custom(func(a, b) -> bool: return a[0] < b[0] if a[0] != b[0] else a[1].x < b[1].x)
	var loose: Dictionary = {}
	for part in level.find_children("*", "RigidBody3D", true, false):
		if part.has_method("get_catalog_id") and not part.is_mounted() and not part.is_queued_for_deletion() \
				and not level.get_node("Workshop").rack_stock.is_ancestor_of(part) and not level.get_node("Workshop").bench_stock.is_ancestor_of(part):
			loose[part.get_catalog_id()] = int(loose.get(part.get_catalog_id(), 0)) + 1
	return {"at": rover.global_position, "stranded": director.stranded, "cause": director.stranded_cause,
		"charge": rover.battery.charge, "cargo": rover.get_node("CargoSocket").part.get_catalog_id()
		if rover.get_node("CargoSocket").part else "", "tray": items, "rack": _rack(level.get_node("Workshop")),
		"loose": loose}


func _same_world(a: Dictionary, b: Dictionary) -> bool:
	if a["tray"].size() != b["tray"].size():
		return false
	for i in a["tray"].size():
		if a["tray"][i][0] != b["tray"][i][0] or a["tray"][i][1].distance_to(b["tray"][i][1]) > 0.05:
			return false
	return a["at"].distance_to(b["at"]) < 0.3 and a["stranded"] == b["stranded"] and a["cause"] == b["cause"] \
		and is_equal_approx(a["charge"], b["charge"]) and a["cargo"] == b["cargo"] and a["rack"] == b["rack"] \
		and a["loose"] == b["loose"]


func _check_field_saves() -> void:
	var level: Node = SL.current_scene
	var rover = level.get_node("ReadyRover")
	var workshop: Node = level.get_node("Workshop")
	var director: Node = level.get_node("MissionDirector")
	var tray: Node3D = rover.get_node("StorageBox")
	var toast: Node = root.get_node("Main/UIManager/SaveToast")
	# Two sample jars into the tray (as test_tray), then Kite runs flat out here: stranded
	var picked: Array = []
	for x in [-0.05, 0.05]:
		var part: RigidBody3D = (load(JAR) as PackedScene).instantiate()
		level.add_child(part)
		part.global_transform = Transform3D(rover.global_basis, tray.drop_point() + rover.global_basis.x * x)
		picked.append(part)
	rover.battery.drain(rover.battery.capacity)
	await _ticks(2.0)
	_check("[tray] two parts ride in the tray", picked.size() == 2 and tray.items().size() == 2, str(tray.items()))
	_check("[stranded] Kite is stranded out in the field", director.stranded and director.stranded_cause == "battery"
		and not workshop.pad.is_in_zone(rover))

	# The toast: "Saving..." for a frame, then "Saved" once the file is written
	var before: String = FileAccess.get_file_as_string(SI.slot_path("slot_1"))
	SI.request_save(false)
	SI.request_save()
	await _frames(1)
	_check("[toast] Saving... first", toast.state == toast.State.SAVING and toast.text() == "Saving...", toast.text())
	await _frames(3)
	_check("[toast] Saved after the write", toast.state == toast.State.SAVED and toast.text() == "Saved"
		and FileAccess.get_file_as_string(SI.slot_path("slot_1")) != before, toast.text())
	var saved: Dictionary = _world()
	var file: Variant = _read("slot_1")
	_check("[tray] saved with scene and transform in the tray", file["kite"]["tray"].size() == 2
		and file["kite"]["tray"].all(func(e) -> bool: return e["scene"].begins_with("res://") and e["local"].size() == 12))
	_check("[stranded] saved stranded, off the pad", file["kite"]["stranded"] == true and file["kite"]["on_pad"] == false
		and file["kite"]["stranded_cause"] == "battery")

	# A failed write says so and keeps the last save
	var good: String = FileAccess.get_file_as_string(SI.slot_path("slot_1"))
	DirAccess.make_dir_recursive_absolute(SI.slot_path("slot_1") + ".tmp")
	var error: Error = SI.save_now()
	_check("[toast] a failed write says so", error != OK and toast.state == toast.State.FAILED
		and toast.text().contains("last save is kept"), toast.text())
	_check("[save] the last valid save is kept", FileAccess.get_file_as_string(SI.slot_path("slot_1")) == good)
	DirAccess.remove_absolute(SI.slot_path("slot_1") + ".tmp")

	# Blocked: carrying something. SAVE GAME is disabled with the reason, an autosave waits for it
	var player = GS.player
	var spare: RigidBody3D = load(picked[0].scene_file_path).instantiate()
	level.add_child(spare)
	spare.global_position = player.global_position + Vector3.UP * 1.2
	player.holder.pickup(spare)
	await physics_frame
	_check("[gate] carrying blocks saving", SI.block_reason() == SG.CARRYING, SI.block_reason())
	GS.change_state_to(GS.State.PAUSED)
	await _frames(2)
	var pause: Node = root.get_node("Main/UIManager/PauseMenu")
	var save_button: Button = pause.find_child("SaveGame", true, false)
	_check("[pause] SAVE GAME disabled with the reason", save_button.disabled and pause.save_note.visible
		and pause.save_note.text == SG.CARRYING)
	pause.find_child("QuitToMenu", true, false).pressed.emit()
	await _frames(1)
	_check("[pause] quit asks: Save & Quit disabled while blocked", pause.is_quit_confirm_open()
		and pause.quit_confirm.find_child("SaveAndQuit", true, false).disabled
		and not pause.quit_confirm.find_child("QuitWithoutSaving", true, false).disabled)
	pause.quit_confirm.find_child("Cancel", true, false).pressed.emit()
	await _frames(1)
	_check("[pause] Cancel stays paused", not pause.is_quit_confirm_open() and GS.state == GS.State.PAUSED)
	GS.return_to_game()
	await _frames(2)
	before = FileAccess.get_file_as_string(SI.slot_path("slot_1"))
	SI.request_save()
	await _frames(5)
	_check("[gate] a blocked autosave doesn't write", FileAccess.get_file_as_string(SI.slot_path("slot_1")) == before)
	player.holder.release()
	await _frames(5)
	_check("[gate] it writes once saving is allowed", FileAccess.get_file_as_string(SI.slot_path("slot_1")) != before)
	spare.queue_free()
	await _frames(2)

	# Out on EVA: blocked; coming back inside autosaves
	var inside: Vector3 = player.global_position
	player.global_position = workshop.global_position + Vector3(0.0, 1.0, 40.0)
	await _ticks(0.2)
	_check("[gate] EVA blocks saving", SI.block_reason() == SG.ON_EVA, SI.block_reason())
	before = FileAccess.get_file_as_string(SI.slot_path("slot_1"))
	player.global_position = inside
	await _ticks(0.1)
	await _frames(4)
	_check("[autosave] coming back inside saves", FileAccess.get_file_as_string(SI.slot_path("slot_1")) != before)
	saved = _world()
	SI.save_now()

	# Two loads in a row: the same Kite, tray, rack and floor; nothing teleported or refilled
	await _quit_without_saving()
	await _load_moon()
	var first: Dictionary = _world()
	_check("[load 1] Kite stranded where it was: same charge, cargo, tray, rack", _same_world(first, saved),
		"%s\n  vs %s" % [first, saved])
	await _ticks(2.0)
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	_check("[load 1] still stranded, not refilled", level.get_node("MissionDirector").stranded and rover.battery.charge == 0.0
		and not level.get_node("Workshop").pad.is_in_zone(rover))
	_check("[load 1] the player starts in the workshop", level.get_node("Workshop").contains(GS.player.global_position))
	level.get_node("Workshop").drive_from_console(GS.player)
	await _frames(2)
	_check("[load 1] Control Kite from the console works", GS.state == GS.State.IN_GAME_ROBOT and GS.robot == rover)
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _frames(2)
	SI.save_now()
	await _quit_without_saving()
	await _load_moon()
	var second: Dictionary = _world()
	_check("[load 2] the same again, no duplicates", _same_world(second, first), "%s\n  vs %s" % [second, first])


func _quit_without_saving() -> void:
	GS.change_state_to(GS.State.PAUSED)
	await _frames(2)
	var pause: Node = root.get_node("Main/UIManager/PauseMenu")
	pause.find_child("QuitToMenu", true, false).pressed.emit()
	await _frames(1)
	pause.quit_confirm.find_child("QuitWithoutSaving", true, false).pressed.emit()
	await _wait_state(GS.State.MAIN_MENU)


func _crate_count(level: Node) -> int:
	return level.find_children("*", "RigidBody3D", true, false).filter(func(p: Node) -> bool:
		return p.has_method("get_catalog_id") and p.get_catalog_id() == "cargo_crate" and not p.is_queued_for_deletion()).size()


func _crate(level: Node) -> RigidBody3D:
	for part in level.find_children("*", "RigidBody3D", true, false):
		if part.has_method("get_catalog_id") and part.get_catalog_id() == "cargo_crate" and not part.is_queued_for_deletion():
			return part
	return null


const SlotInfoState = preload("res://src/save/save_slot_info.gd").State
const SG = preload("res://src/save/save_gate.gd")
const JAR: String = "res://src/robot/socket/sample_container_part.tscn"


func _finish() -> void:
	_clear_dir()
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
