extends SceneTree
## Headless test: M3 "Beyond the Rim" from "Start next mission" to the ending, through the game's own
## paths (the console, CONTROL KITE, Kite's cargo mount, FieldLoggerPickup's E, the charging pad, the
## Downlink action), with no debug command. The campaign starts with m2 complete, as a loaded save would.
##   1. Start: the console starts m3; the first guidance step is the logger (the mount is empty).
##   2. Guidance: a full cargo mount puts "Empty Kite's cargo mount" first and the pickup refuses.
##   3. The chain: E beside FarLogger completes m3.logger_recovered, docking m3.kite_docked, the
##      downlink m3.archive_sent, and m3 completes.
##   4. Ending: the campaign is complete and the result screen opens.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_m3_loop.gd

const STAND_IN: String = "res://src/robot/socket/radio_module_part.tscn"
const M1_DONE: Array = ["m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]
const M2_DONE: Array = ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed", "m2.iris_activated",
	"m2.kite_docked", "m2.telemetry_received"]

var GS: Node
var SL: Node
var CS: Node
var SI: GDScript
var failures: int = 0
var level: Node3D
var workshop: Node3D
var rover: RigidBody3D
var iris: Node3D
var director: Node
var guidance: Node
var console: Node


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


func _grab_level() -> void:
	level = SL.current_scene
	workshop = level.get_node("Workshop")
	rover = level.get_node("ReadyRover")
	iris = level.get_node("Iris")
	guidance = level.get_node("Guidance")
	console = root.get_node("Main").find_child("MissionConsole", true, false)


func _place(at: Vector3, facing: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0, 1)
	var hit: Dictionary = rover.get_world_3d().direct_space_state.intersect_ray(query)
	var ground: float = (hit["position"] as Vector3).y if hit else at.y
	rover.global_transform = Transform3D(Basis(Vector3.UP, atan2(-facing.x, -facing.z)), Vector3(at.x, ground + 0.3, at.z))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(2.0)


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	SI = load("res://src/save/save_index.gd")
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
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)
	CS.load_state({"current": "m2", "objectives": M1_DONE + M2_DONE, "missions_done": ["m1", "m2"], "flags": ["iris_online"], "items": {}})
	SL.load_scene("moon_level")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("the Moon level comes up at the end of m2", false)
		_finish()
		return
	_grab_level()
	await _ticks(1.0)
	var cargo: Node3D = rover.get_node("CargoSocket")
	var far_logger: RigidBody3D = level.get_node("FarLogger")
	var pickup: Node3D = level.get_node("FieldLoggerPickup")

	# 1. Start
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	console.select_section(console.Section.MISSION)
	var action: Button = console.get_node("%Action")
	_check("[start] the console offers the next mission", action.visible and not action.disabled and action.text.begins_with("Start next mission"), action.text)
	console._on_action_pressed()
	await _ticks(0.5)
	_check("[start] m3 is current, m3.logger_recovered first", CS.current_mission() == "m3" and CS.current_objective() == "m3.logger_recovered"
		and cargo.part == null, CS.current_objective())
	_check("[guidance] the mount is empty: straight to the far logger", guidance.index == 1 and guidance.target == far_logger
		and guidance.is_waypoint(), "%d %s" % [guidance.index, guidance.target])

	# 2. A full cargo mount
	var stand_in: RigidBody3D = load(STAND_IN).instantiate()
	level.add_child(stand_in)
	stand_in.global_position = cargo.global_position
	cargo.mount(stand_in)
	await _ticks(0.5)
	_check("[guidance] a full mount: empty it first", guidance.index == 0 and guidance.target == cargo.get_node("PartCapture"),
		"%d %s" % [guidance.index, guidance.target])
	_check("[pickup] a full mount is refused", not pickup.can_load(rover))
	cargo.unmount()
	stand_in.free()
	await _ticks(0.5)
	_check("[guidance] emptied: the far logger again", guidance.index == 1 and guidance.target == far_logger)

	# 3. The chain
	console._on_control_kite_pressed()
	await _ticks(0.5)
	_check("[drive] CONTROL KITE: driving", GS.state == GS.State.IN_GAME_ROBOT)
	await _place(far_logger.global_position + Vector3(1.0, 0.0, 0.0), Vector3.FORWARD)
	rover.linear_velocity = Vector3.ZERO
	await _ticks(0.3)
	_check("[pickup] beside the logger: In position", pickup.get_hint(rover).begins_with("In position"), pickup.get_hint(rover))
	_check("[guidance] the pickup's hint is the step line, the highlight stays on the logger", guidance.target == far_logger
		and guidance.step_text() == pickup.get_hint(rover), guidance.step_text())
	Input.action_press(&"interact_use")
	await _ticks(0.1)
	Input.action_release(&"interact_use")
	await _ticks(0.5)
	_check("[load] E beside the logger: on the cargo mount, m3.logger_recovered", cargo.part == far_logger
		and CS.is_objective_done("m3.logger_recovered") and CS.current_objective() == "m3.kite_docked", CS.current_objective())
	var dock: Transform3D = workshop.get_dock_transform()
	dock.origin += Vector3.UP * 0.3
	rover.global_transform = dock
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(2.0)
	_check("[dock] back on the pad: m3.kite_docked", CS.is_objective_done("m3.kite_docked"), CS.current_objective())
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.3)
	console.select_section(console.Section.DOWNLINK)
	_check("[downlink] Send archive is enabled", action.visible and not action.disabled and action.text == "Send archive", action.text)
	console._on_action_pressed()
	await _ticks(console.DOWNLINK_TIME + 0.5)
	_check("[downlink] m3.archive_sent and m3 complete, no debug command used", CS.is_objective_done("m3.archive_sent")
		and CS.is_mission_completed("m3"), CS.current_objective())

	# 4. Ending
	_check("[ending] the campaign is complete", CS.is_campaign_complete())
	var result: Node = root.get_node("Main").find_child("CampaignResult", true, false)
	var start: int = Time.get_ticks_msec()
	while result and not result.is_open() and Time.get_ticks_msec() - start < 90000:
		await process_frame
	_check("[ending] the result screen opens", result != null and result.is_open())
	_finish()


func _finish() -> void:
	_clear_dir()
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
