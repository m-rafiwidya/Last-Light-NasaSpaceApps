extends SceneTree
## Save slots are separate worlds: nothing of one slot shows in another.
##   1. Slot A (new campaign): tyre tracks, a loose part on the floor, Kite's battery and wheel,
##      a shown tip, a console order in flight, a queued dialogue; autosaved on quitting.
##   2. A new campaign in slot B starts clean (none of the above); B is saved by quitting.
##   3. Loading A again restores only what A saved (campaign, Kite, tips) and no tracks or floor parts.
##   4. Loading B shows none of A's state.
## Saves go to user://saves_test (SaveIndex under a script run), cleared before and after.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_save_isolation.gd

var GS: Node
var SL: Node
var CS: Node
var DS: Node
var DT: Node
var SI: GDScript
var failures: int = 0
var level: Node
var loose_baseline: int = -1
var a_sequence: RefCounted = null


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


func _enter_moon() -> bool:
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		return false
	level = SL.current_scene
	await _ticks(1.5)
	return true


func _to_menu() -> void:
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU, "main_menu")


func _loose_parts() -> int:
	var count: int = 0
	for child in level.get_children():
		if child.has_method("get_catalog_id"):
			count += 1
	return count


func _track_points() -> int:
	var tracks: Node = level.get_node_or_null("TyreTracks")
	return tracks.track_log.point_count() if tracks and tracks.track_log else -1


func _console() -> Node:
	return root.get_node("Main/UIManager/MissionConsole")


func _tips() -> Node:
	return root.get_node("Main/UIManager/HUD").tips


func _rover() -> Node:
	return level.get_node("ReadyRover")


func _battery_charge() -> float:
	var part = _rover().battery_socket.part
	return part.charge if part else -1.0


func _is_clean_world(label: String, wheel_is_grip: bool) -> void:
	var rover: Node = _rover()
	_check("[%s] no tyre tracks" % label, _track_points() == 0, str(_track_points()))
	_check("[%s] no extra loose parts" % label, _loose_parts() == loose_baseline, "%d vs %d" % [_loose_parts(), loose_baseline])
	_check("[%s] A's queued dialogue is gone" % label, not DS.is_sequence_pending(a_sequence))
	_check("[%s] no stale trigger sequence held" % label, DT.sequence_for("mission_started:m1") == null or label == "B new")
	_check("[%s] console has no order, flight or downlink" % label, not _console().flying()
		and _console()._sending < 0.0 and _console()._order.is_empty() and _console()._service_id == "")
	_check("[%s] Kite is on the pad" % label, level.get_node("Workshop").pad.is_in_zone(rover))
	var front_left = rover.front_left_socket.part
	_check("[%s] front-left wheel %s" % [label, "is the grip wheel" if wheel_is_grip else "is the stock wheel"],
		front_left != null and (front_left.get_catalog_id() == "wheel_high_grip") == wheel_is_grip)


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	DS = root.get_node("DialogServer")
	DT = root.get_node("DialogueTriggers")
	SI = load("res://src/save/save_index.gd")
	_clear_dir()
	if not await _wait_state(GS.State.MAIN_MENU):
		_check("the main menu comes up", false)
		_finish()
		return

	# 1. Slot A
	SI.start_new_campaign("slot_1")
	if not await _enter_moon():
		_check("[A] the Moon comes up", false)
		_finish()
		return
	loose_baseline = _loose_parts()
	var workshop: Node = level.get_node("Workshop")
	var rover: Node = _rover()
	var log: Object = level.get_node("TyreTracks").track_log
	var first: int = log.add_point(0.0, 0.0, 0.0, 0.01, 1.0, -1)
	log.add_point(0.08, 0.0, 0.08, 0.01, 1.0, first)
	_check("[A] tracks made", _track_points() == 2, str(_track_points()))
	CS.add_item("cargo.grip_wheels")
	workshop.account_rack()
	await physics_frame
	var grip = null
	var light = null
	for part in workshop.rack_stock.get_children():
		if part.has_method("get_catalog_id"):
			if part.get_catalog_id() == "wheel_high_grip" and grip == null:
				grip = part
			if part.get_catalog_id() == "battery_light" and light == null:
				light = part
	var loose: Node = null
	for part in workshop.rack_stock.get_children():
		if part.has_method("get_catalog_id") and part != grip and part != light:
			loose = part
			break
	var old_wheel = rover.front_left_socket.unmount()
	old_wheel.get_parent().remove_child(old_wheel)
	create_timer(1.0).timeout.connect(old_wheel.free)
	rover.front_left_socket.mount(grip)
	light.charge = 37.5
	_tips().offer(&"on_foot")
	CS.mark_tip_shown(&"drive")
	var console: Node = _console()
	console.select_service(str(load("res://src/levels/cargo_plan.gd").services()[0]["id"]))
	console._flight = 1.0
	console._order = {"service": console._service_id, "items": []}
	var line := Dialog.new()
	line.subtitle = "A line"
	line.min_duration = 60.0
	var sequence := DialogSequence.new()
	sequence.dialogs = [line]
	a_sequence = sequence
	DS.queue_sequence(sequence)
	rover.battery_socket.mount(light)
	await physics_frame
	loose.reparent(level)
	loose.global_position = Vector3(30.0, 5.0, 30.0)
	_check("[A] set up: battery objective, loose part, tip, flight, dialogue", CS.is_objective_done("m1.kite_prepared")
		and _loose_parts() == loose_baseline + 1 and _tips().visible and console.flying() and DS.is_playing())
	await _to_menu()
	_check("[A] saved on quitting, tips included", FileAccess.file_exists(SI.slot_path("slot_1"))
		and CS.is_tip_shown("on_foot"))

	# 2. New campaign in slot B
	SI.start_new_campaign("slot_2")
	if not await _enter_moon():
		_check("[B new] the Moon comes up", false)
		_finish()
		return
	_is_clean_world("B new", false)
	_check("[B new] no battery, nothing done, no tip shown", _rover().battery_socket.part == null
		and not CS.is_objective_done("m1.kite_prepared") and not CS.is_tip_shown("drive") and not CS.has_item("cargo.grip_wheels")
		and (not _tips().visible or _tips().age < 5.0))
	_check("[B new] slot is slot_2", SI.current_slot == "slot_2")
	await _to_menu()

	# 3. Load A again
	_check("[A again] load_slot works", SI.load_slot("slot_1"))
	if not await _enter_moon():
		_check("[A again] the Moon comes up", false)
		_finish()
		return
	_is_clean_world("A again", true)
	_check("[A again] only A's saved state: objective, item, tip, battery charge", CS.is_objective_done("m1.kite_prepared")
		and CS.has_item("cargo.grip_wheels") and CS.is_tip_shown("on_foot") and CS.is_tip_shown("drive") and is_equal_approx(_battery_charge(), 37.5)
		and CS.current_mission() == "m1")
	_check("[A again] slot is slot_1", SI.current_slot == "slot_1")
	var again_log: Object = level.get_node("TyreTracks").track_log
	again_log.add_point(5.0, 5.0, 0.0, 0.01, 1.0, -1)
	_check("[A again] new tracks made", _track_points() == 1)
	await _to_menu()

	# 4. Load B
	_check("[B] load_slot works", SI.load_slot("slot_2"))
	if not await _enter_moon():
		_check("[B] the Moon comes up", false)
		_finish()
		return
	_is_clean_world("B", false)
	_check("[B] none of A's campaign state", _rover().battery_socket.part == null and not CS.is_objective_done("m1.kite_prepared")
		and not CS.is_tip_shown("drive") and not CS.has_item("cargo.grip_wheels") and SI.current_slot == "slot_2")
	_finish()


func _finish() -> void:
	_clear_dir()
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
