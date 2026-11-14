extends SceneTree
## Headless test: MissionDirector completes m2.module_loaded and m3.logger_recovered when the part is mounted.
##   1. The radio module in the cargo socket completes m2.module_loaded, but not before m2.cargo_ordered.
##   2. The far logger completes m3.logger_recovered in m3 only; other parts complete nothing.
##   3. A save restored with the part already mounted completes nothing; a new mount afterwards still does.
##   4. The guidance steps resolve their targets.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_field_objectives.gd

const MODULE: String = "res://src/robot/socket/radio_module_part.tscn"
const LOGGER: String = "res://src/robot/socket/field_logger_part.tscn"
const M1_DONE: Array = ["m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]
const M2_DONE: Array = ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed", "m2.iris_activated",
	"m2.kite_docked", "m2.telemetry_received"]

var GS: Node
var SL: Node
var CS: Node
var SI: GDScript
var failures: int = 0
var level: Node
var rover: Node
var socket: Node
var completed: Array = []


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-66s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * 240):
		await physics_frame


func _wait_state(state: int, level_id: String = "", seconds: float = 120.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if GS.state == state and (level_id.is_empty() or SL.current_level_id == level_id):
			return true
		await process_frame
	return false


func _clear_dir() -> void:
	var dir: String = SI.save_dir()
	if DirAccess.dir_exists_absolute(dir):
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))


func _state(mission: String, objectives: Array, done: Array) -> void:
	CS.load_state({"current": mission, "objectives": objectives, "missions_done": done, "flags": [], "items": {}})


func _mount(part: Node) -> void:
	rover.get_parent().add_child(part)
	part.global_position = socket.global_position
	socket.mount(part)
	await physics_frame


func _empty_socket() -> void:
	var old: Node = socket.unmount()
	if old and old.name != "FarLogger":
		old.queue_free()


func _load_level(mission: String, objectives: Array, done: Array, cargo: String) -> bool:
	SL.load_scene("main_menu")
	if not await _wait_state(GS.State.MAIN_MENU):
		return false
	_state(mission, objectives, done)
	SI.pending_kite = {"sockets": {"CargoSocket": {"scene": cargo, "properties": {}}}}
	SL.load_scene("moon_level")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		return false
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	socket = rover.get_node("CargoSocket")
	completed.clear()
	await _ticks(1.0)
	return true


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	SI = load("res://src/save/save_index.gd")
	CS.objective_completed.connect(func(id: String) -> void: completed.append(id))
	if not await _wait_state(GS.State.MAIN_MENU):
		_check("main menu comes up", false)
		_finish()
		return
	_clear_dir()
	CS.reset()
	SI.start_new_campaign("slot_1")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("the Moon level comes up", false)
		_finish()
		return
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	socket = rover.get_node("CargoSocket")
	var far_logger: Node = level.get_node("FarLogger")
	await _ticks(1.0)

	# 1. The module
	_state("m2", M1_DONE, ["m1"])
	await _mount(load(MODULE).instantiate())
	_check("[module] mounted before the order: m2.module_loaded stays open", not CS.is_objective_done("m2.module_loaded")
		and completed.is_empty(), str(completed))
	_empty_socket()
	CS.complete_objective("m2.cargo_ordered")
	completed.clear()
	await _mount(far_logger)
	_check("[module] another cargo part completes nothing in m2", completed.is_empty(), str(completed))
	_empty_socket()
	await _mount(load(MODULE).instantiate())
	_check("[module] mounted in the cargo socket: m2.module_loaded", CS.is_objective_done("m2.module_loaded")
		and completed == ["m2.module_loaded"], str(completed))

	# 2. The logger
	_empty_socket()
	await _mount(far_logger)
	_check("[logger] mounted in m2: m3.logger_recovered stays open", not CS.is_objective_done("m3.logger_recovered"))
	_empty_socket()
	_state("m3", M1_DONE + M2_DONE, ["m1", "m2"])
	completed.clear()
	await _mount(load(MODULE).instantiate())
	_check("[logger] the module completes nothing in m3", completed.is_empty(), str(completed))
	_empty_socket()
	await _mount(far_logger)
	_check("[logger] mounted in m3: m3.logger_recovered", CS.is_objective_done("m3.logger_recovered")
		and completed == ["m3.logger_recovered"], str(completed))

	# 4. Guidance targets (the logger lying in the level again)
	_empty_socket()
	await physics_frame
	var guidance: Node = level.get_node("Guidance")
	var module_steps: Array = guidance.steps("m2.module_loaded")
	_check("[guidance] module: pick up, then the cargo socket", module_steps.size() == 2
		and module_steps[0]["done_when"] == {"holding_part": "cargo"} and not module_steps[0].has("placeholder")
		and guidance.resolve(module_steps[1]["target"]) == socket.get_node("PartCapture"), str(module_steps))
	var logger_steps: Array = guidance.steps("m3.logger_recovered")
	_check("[guidance] logger: the FarLogger part", logger_steps.size() == 1 and not logger_steps[0].has("placeholder")
		and guidance.resolve(logger_steps[0]["target"]) == far_logger, str(logger_steps))

	# 3. Restoring a save
	if not await _load_level("m2", M1_DONE + ["m2.cargo_ordered"], ["m1"], MODULE):
		_check("[restore] the Moon level comes up (m2)", false)
		_finish()
		return
	_check("[restore] the module is on Kite", socket.part != null and socket.part.get_catalog_id() == "radio_module")
	_check("[restore] it does not complete m2.module_loaded", not CS.is_objective_done("m2.module_loaded") and completed.is_empty(),
		str(completed))
	_empty_socket()
	await _mount(load(MODULE).instantiate())
	_check("[restore] a new mount afterwards does", CS.is_objective_done("m2.module_loaded"), str(completed))
	if not await _load_level("m3", M1_DONE + M2_DONE, ["m1", "m2"], LOGGER):
		_check("[restore] the Moon level comes up (m3)", false)
		_finish()
		return
	_check("[restore] the logger is on Kite", socket.part != null and socket.part.get_catalog_id() == "field_logger")
	_check("[restore] it does not complete m3.logger_recovered", not CS.is_objective_done("m3.logger_recovered") and completed.is_empty(),
		str(completed))
	_empty_socket()
	await _mount(level.get_node("FarLogger"))
	_check("[restore] a new mount afterwards does", CS.is_objective_done("m3.logger_recovered"), str(completed))
	_finish()


func _finish() -> void:
	_clear_dir()
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
