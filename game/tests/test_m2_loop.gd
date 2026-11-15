extends SceneTree
## Headless test: M2 "First Signal" from the cargo order to the telemetry downlink, through the
## game's own paths (the console's Planning tab, the player's holder and Kite's cargo mount, the
## console's CONTROL KITE, IRIS's module cradle, the charging pad, the Downlink action), with no
## debug command. The campaign starts at m2 as a loaded save would.
##   1. Delivery: the module is in the workshop's crate and nowhere else (not on the rack).
##   2. Guidance: its targets resolve to the crate, the module itself, the cargo socket, the console
##      and the IRIS module cradle, whose hint replaces the step line while driving.
##   3. The chain: m2.cargo_ordered, module_loaded, module_installed + iris_activated, kite_docked,
##      telemetry_received, and m2 completes.
##   4. Save and load after the install: no radio module in the workshop (rack or crate), one in
##      IRIS's bay.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_m2_loop.gd

const M1_DONE: Array = ["m1.workshop_entered", "m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]

var GS: Node
var SL: Node
var CS: Node
var SI: GDScript
var failures: int = 0
var level: Node3D
var workshop: Node3D
var rover: RigidBody3D
var iris: Node3D
var guidance: Node
var plan: Script
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


## Every radio-power module under `container`
func _modules(container: Node) -> Array:
	var found: Array = []
	for part in container.find_children("*", "RigidBody3D", true, false):
		if part.has_method("get_catalog_id") and part.get_catalog_id() == "radio_module" and not part.is_queued_for_deletion():
			found.append(part)
	return found


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
	plan = load("res://src/levels/cargo_plan.gd")
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
	CS.load_state({"current": "m2", "objectives": M1_DONE, "missions_done": ["m1"], "flags": [], "items": {}})
	SL.load_scene("moon_level")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("the Moon level comes up at m2", false)
		_finish()
		return
	_grab_level()
	await _ticks(1.0)
	var crate: Node3D = workshop.cargo_crate

	# 1. Delivery
	_check("[crate] before the order: hidden, no module anywhere", not crate.visible and _modules(level).is_empty())
	console.select_section(console.Section.PLANNING)
	console.select_service("courier")
	for entry in plan.items():
		console.set_item(entry["id"], entry["id"] == "radio_module")
	console._on_action_pressed()
	await _ticks(0.5)
	console.skip_flight()
	await _ticks(2.5)
	_check("[order] m2.cargo_ordered done through the console", CS.is_objective_done("m2.cargo_ordered")
		and CS.has_flag("cargo_delivered") and CS.current_objective() == "m2.module_loaded")
	var modules: Array = _modules(level)
	_check("[crate] open, and the module is in it and nowhere else", crate.visible and crate.is_open and modules.size() == 1
		and crate.is_ancestor_of(modules[0]) and _modules(workshop.rack_stock).is_empty()
		and _modules(rover).is_empty() and _modules(iris).is_empty(), str(modules))
	var local: Vector3 = crate.to_local(modules[0].global_position) if modules.size() == 1 else Vector3.INF
	_check("[crate] the module lies inside it", absf(local.x) < crate.SIZE.x / 2.0 and absf(local.z) < crate.SIZE.z / 2.0
		and local.y > 0.0 and local.y < crate.SIZE.y, str(local))
	var front: Vector3 = crate.global_basis.z
	var door: Vector3 = workshop.to_global(Vector3(2.1, 0.0, 2.0)) - crate.global_position
	door.y = 0.0
	_check("[crate] its label faces the personnel door, beside the pad", front.dot(door.normalized()) > 0.3
		and absf(crate.global_position.distance_to(workshop.pad.global_position)) < 2.5,
		"%.2f, %.1f m from the pad" % [front.dot(door.normalized()), crate.global_position.distance_to(workshop.pad.global_position)])

	# 2. Guidance and the module's pickup
	var player: Node3D = GS.player
	var module: RigidBody3D = modules[0]
	await _ticks(0.3)
	_check("[guidance] first the crate", guidance.index == 0 and guidance.target == crate, str(guidance.target))
	player.global_position = crate.global_position + crate.global_basis.z * 1.0 + Vector3.UP * 0.1
	await _ticks(0.3)
	_check("[guidance] near it: the module itself", guidance.index == 1 and guidance.target == module, str(guidance.target))
	player.holder.pickup(module)
	await _ticks(0.3)
	var cargo_socket: Node3D = rover.get_node("CargoSocket")
	_check("[guidance] holding it: the cargo socket", guidance.index == 2 and guidance.target == cargo_socket.get_node("PartCapture"),
		str(guidance.target))
	player.holder.release()
	module.global_position = cargo_socket.global_position + Vector3.UP * 0.05
	module.linear_velocity = Vector3.ZERO
	await _ticks(1.5)
	_check("[load] released over the cargo socket: mounted, m2.module_loaded", cargo_socket.part == module
		and CS.is_objective_done("m2.module_loaded") and CS.current_objective() == "m2.module_installed",
		"%s, %s" % [cargo_socket.part, CS.current_objective()])

	# 3. Install
	_check("[guidance] install: the console first", guidance.index == 0 and guidance.step_text().ends_with("Open the mission console"), guidance.step_text())
	console._on_control_kite_pressed()
	await _ticks(0.5)
	var cradle: Node3D = iris.get_node("ModuleCradle")
	_check("[guidance] driving: the IRIS module cradle", GS.state == GS.State.IN_GAME_ROBOT and guidance.target == cradle
		and guidance.is_waypoint(), str(guidance.target))
	var facing: Vector3 = iris.global_basis.x
	await _place(cradle.park_marker.global_position + facing * -20.0, facing)
	_check("[guidance] far from the bay the step shows its own text", guidance.target_hint() == ""
		and guidance.step_text() == guidance.current_step()["text"], guidance.step_text())
	await _place(cradle.park_marker.global_position + facing * -4.0, facing)
	_check("[guidance] near the bay the cradle's hint is the step line", guidance.step_text().contains("closer")
		and guidance.step_text() == cradle.get_hint(rover), guidance.step_text())
	await _place(cradle.park_marker.global_position, facing)
	_check("[guidance] parked: In position", guidance.step_text().begins_with("In position"), guidance.step_text())
	Input.action_press(&"interact_use")
	await _ticks(0.1)
	Input.action_release(&"interact_use")
	await _ticks(0.5)
	_check("[install] E at the bay: m2.module_installed and m2.iris_activated", CS.is_objective_done("m2.module_installed")
		and CS.is_objective_done("m2.iris_activated") and CS.has_flag("iris_online") and iris.is_online)
	_check("[install] the module is seated in IRIS's bay, once", cradle.occupant == module and _modules(level).size() == 1
		and _modules(workshop).is_empty())

	# 4. Back to the pad and the downlink
	await _place(workshop.get_dock_transform().origin - workshop.global_basis.z * 2.0, -workshop.global_basis.z)
	var dock: Transform3D = workshop.get_dock_transform()
	dock.origin += Vector3.UP * 0.3
	rover.global_transform = dock
	rover.linear_velocity = Vector3.ZERO
	await _ticks(2.0)
	_check("[dock] back on the pad: m2.kite_docked", CS.is_objective_done("m2.kite_docked"), CS.current_objective())
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.3)
	console.select_section(console.Section.DOWNLINK)
	var action: Button = console.get_node("%Action")
	_check("[downlink] Receive telemetry is enabled", action.visible and not action.disabled, action.text)
	console._on_action_pressed()
	await _ticks(console.DOWNLINK_TIME + 0.5)
	_check("[downlink] m2.telemetry_received and m2 complete, no debug command used", CS.is_objective_done("m2.telemetry_received")
		and CS.is_mission_completed("m2"), CS.current_objective())

	# 5. Save and load
	await _ticks(0.5)
	_check("[save] the slot was written", SI.save_current(rover) == OK)
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)
	CS.reset()
	_check("[load] load_slot starts loading", SI.load_slot("slot_1"))
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("[load] the Moon level comes up", false)
		_finish()
		return
	_grab_level()
	await _ticks(3.0)
	_check("[load] m2 is still complete", CS.is_mission_completed("m2") and CS.is_objective_done("m2.module_installed"))
	_check("[load] no radio module in the workshop (rack or crate)", _modules(workshop).is_empty(), str(_modules(workshop)))
	var cradle_after: Node3D = iris.get_node("ModuleCradle")
	_check("[load] one radio module in the level: IRIS's bay", _modules(level).size() == 1 and cradle_after.is_installed(),
		str(_modules(level)))
	_finish()


func _finish() -> void:
	_clear_dir()
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
