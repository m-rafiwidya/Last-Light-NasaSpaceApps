extends SceneTree
## Headless test: the M1 "Wake Kite" loop on the Moon (CampaignState, MissionDirector, the mission
## console, the rover HUD's MissionHint).
##   1. New campaign: SaveIndex.start_new_campaign starts m1; Kite's battery is taken out.
##   2. Order: scanning, docking and the downlink don't count before the objectives before them.
##   3. Prepare: the rack's battery dropped into Kite's socket completes m1.kite_prepared.
##   4. Scan: from 12 m in front of IRIS, RoverScanner's ray (mask 1|2) hits the placeholder, not
##      IRIS's collider, at the panel's middle and corners; holding it scans m1.iris_scanned.
##   5. Reserve: the HUD shows the objective and the return estimate; a low battery warns.
##   6. Retry: a flat battery in the field brings Kite back to the pad, recharged, progress kept;
##      being returned doesn't count as docking.
##   7. Dock: driving back onto the pad completes m1.kite_docked.
##   8. Downlink: the console sends the inspection, shows the diagnosis, m1 completes, the next
##      mission button starts m2. Control Kite drives Kite.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_m1_loop.gd

const TICKS: int = 240
const MAST: int = 1

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var workshop: Node3D
var rover: RigidBody3D
var iris: Node3D
var panel: Node3D
var director: Node
var console: Node
var hint: Node


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


func _release_all() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(action)


func _place(at: Vector3, facing: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0, 1)
	var hit: Dictionary = rover.get_world_3d().direct_space_state.intersect_ray(query)
	var ground: float = (hit["position"] as Vector3).y if hit else at.y
	var yaw: float = atan2(-facing.x, -facing.z)
	rover.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, ground + 0.3, at.z))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(1.5)


func _put_on_dock() -> void:
	var dock: Transform3D = workshop.get_dock_transform()
	dock.origin += Vector3.UP * 0.3
	rover.global_transform = dock
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(4.0)


func _aim_mast_at(world_point: Vector3) -> void:
	var local: Vector3 = rover.to_local(world_point)
	var cam: Vector3 = rover.to_local(rover.camera.global_position)
	var d: Vector3 = local - cam
	rover.controller.camera_azimuth = atan2(-d.x, -d.z)
	rover.controller.camera_altitude = atan2(d.y, Vector2(d.x, d.z).length())


func _scanner_hit(world_point: Vector3) -> Object:
	var from: Vector3 = rover.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + (world_point - from).normalized() * 30.0, 1 | 2)
	query.exclude = [rover.get_rid()]
	var hit: Dictionary = rover.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["collider"] if hit else null


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	CS.reset()
	load("res://src/save/save_index.gd").start_new_campaign()
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	workshop = level.get_node("Workshop")
	rover = level.get_node("ReadyRover")
	iris = level.get_node("Iris")
	panel = level.get_node("Iris/ServicePanel")
	director = level.get_node("MissionDirector")
	console = root.get_node("Main").find_child("MissionConsole", true, false)
	hint = root.get_node("Main").find_child("MissionHint", true, false)
	await _ticks(2.0)

	# 1. New campaign
	_check("new campaign: m1 is the current mission", CS.current_mission() == "m1", CS.current_mission())
	_check("new campaign: Kite's battery is taken out", rover.battery_socket.part == null)
	_check("objective: the console and HUD name the first objective",
		CS.objective_title(CS.current_objective()) == "Fit a battery to Kite", CS.current_objective())

	# 2. Order
	panel.mark_scanned(rover)
	_check("order: a scan before the battery doesn't count, the target can be scanned again",
		not CS.is_objective_done("m1.iris_scanned") and not panel.is_scanned)
	_check("order: docking can't be completed first", not director.try_complete("m1.kite_docked"))
	console.select_section(console.Section.DOWNLINK)
	_check("order: the downlink is disabled before the dock", console.get_node("%Action").disabled,
		console.get_node("%Action").text)

	# 3. Prepare
	var battery: RigidBody3D = null
	for part in workshop.rack_stock.get_children():
		if part.has_method("add_charge"):
			battery = part
	battery.global_position = rover.battery_socket.global_position + Vector3(0.0, 0.05, 0.0)
	battery.linear_velocity = Vector3.ZERO
	await _ticks(2.0)
	_check("prepare: the rack's battery fits Kite", rover.battery_socket.part == battery)
	_check("prepare: m1.kite_prepared", CS.is_objective_done("m1.kite_prepared"))
	await _ticks(3.0)
	_check("dock before the scan: Kite is docked on the pad", workshop.pad.is_docked(), workshop.pad.get_status_text())
	_check("dock before the scan: m1.kite_docked not done", not CS.is_objective_done("m1.kite_docked"))

	# 4. Scan
	GS.drive(rover)
	await _ticks(0.5)
	var front: Vector3 = -iris.global_basis.z
	front.y = 0.0
	front = front.normalized()
	await _place(panel.global_position + front * 12.0, -front)
	rover.get_node("CameraRig")._switch(MAST)
	var half: Vector3 = panel.PANEL_SIZE * 0.5 - Vector3(0.05, 0.05, 0.0)
	var points: Array = [panel.global_position]
	for corner in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
		points.append(panel.to_global(Vector3(half.x * corner.x, half.y * corner.y, 0.0)))
	_aim_mast_at(panel.global_position)
	await _ticks(0.2)
	var hits: PackedStringArray = []
	for point in points:
		var collider := _scanner_hit(point)
		hits.append(str(collider.name) if collider else "nothing")
	_check("scan: the scanner's ray hits the placeholder at the panel's middle and corners, not IRIS",
		hits.count(String(panel.name)) == points.size(), ", ".join(hits))
	_aim_mast_at(panel.global_position)
	await _ticks(2.0)
	_check("scan: m1.iris_scanned", CS.is_objective_done("m1.iris_scanned"))
	_check("scan: IRIS's own collider wasn't scanned", not iris.is_scanned)
	rover.controller.camera_azimuth = 0.0
	rover.controller.camera_altitude = 0.0

	# 5. Reserve
	_check("hud: the objective line shows the next objective",
		hint.objective_label.text == "OBJECTIVE  Return Kite to the charging pad", hint.objective_label.text)
	var needed: float = director.return_fraction_needed()
	_check("hud: the return estimate is shown, no warning on a full battery",
		needed > 0.0 and needed < 0.5 and not director.return_warning() and hint.return_label.text.begins_with("RETURN"),
		"%.1f%% needed, %s" % [needed * 100.0, hint.return_label.text])
	await _place(rover.global_position, front)
	Input.action_press("move_forward", 0.5)
	await _ticks(10.0)
	_release_all()
	await _ticks(3.0)
	print("INFO  measured %.4f Wh/m over the test drive (default %.4f)" % [director.wh_per_metre(), director.DEFAULT_WH_PER_M])
	rover.battery.charge = rover.battery.capacity * (director.return_fraction_needed() + 0.05)
	await _ticks(0.2)
	_check("hud: a battery close to the return need warns", director.return_warning()
		and hint.return_label.text.begins_with("LOW BATTERY"), hint.return_label.text)

	# 6. Retry
	rover.battery.charge = 0.0
	await _ticks(0.5)
	_check("retry: a flat battery in the field starts the recovery, the HUD says so",
		director.recovering and hint.alert_label.text == director.RECOVERY_MESSAGE, hint.alert_label.text)
	await _ticks(director.RECOVERY_DELAY + 4.0)
	_check("retry: Kite is back on the pad, recharged", workshop.pad.is_docked() and rover.battery.get_charge_fraction() > 0.99,
		"%s, %.0f%%" % [workshop.pad.get_status_text(), rover.battery.get_charge_fraction() * 100.0])
	_check("retry: completed objectives kept", CS.is_objective_done("m1.kite_prepared") and CS.is_objective_done("m1.iris_scanned"))
	_check("retry: being returned doesn't count as docking", not CS.is_objective_done("m1.kite_docked"))

	# 7. Dock
	await _place(workshop.get_dock_transform().origin - workshop.global_basis.z * 2.0, -workshop.global_basis.z)
	await _put_on_dock()
	_check("dock: driving back onto the pad after the scan completes m1.kite_docked", CS.is_objective_done("m1.kite_docked"))

	# 8. Downlink
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.3)
	workshop._on_console_used(GS.player)
	await _ticks(0.3)
	_check("console: E on the workshop console opens the mission console", GS.state == GS.State.MISSION_CONSOLE)
	console.select_section(console.Section.MISSION)
	var mission_text: String = console.get_node("%Description").text
	_check("console: the Mission section lists the objectives with their state",
		mission_text.count("[s]") == 4 and mission_text.contains("Downlink the inspection"), mission_text)
	console.select_section(console.Section.DOWNLINK)
	var action: Button = console.get_node("%Action")
	_check("console: Send inspection is enabled after the dock", action.visible and not action.disabled
		and action.text.nocasecmp_to("Send inspection") == 0, action.text)
	var completed: Array = []
	CS.mission_completed.connect(func(id: String) -> void: completed.append(id))
	console._on_action_pressed()
	await _ticks(console.DOWNLINK_TIME + 0.5)
	_check("downlink: m1.inspection_sent and m1 completed", CS.is_objective_done("m1.inspection_sent") and completed == ["m1"],
		str(completed))
	_check("downlink: the report names the failed radio-power module",
		console.get_node("%Description").text.contains("radio-power module has failed"))
	_check("console: offers the next mission", action.visible and action.text.nocasecmp_to("Start next mission: First Signal") == 0, action.text)
	console._on_action_pressed()
	await _ticks(0.3)
	_check("console: the next mission button starts m2", CS.current_mission() == "m2", CS.current_mission())
	console._on_control_kite_pressed()
	await _ticks(0.5)
	_check("console: Control Kite drives Kite", GS.state == GS.State.IN_GAME_ROBOT and GS.robot == rover)

	print("RESULT test_m1_loop %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
