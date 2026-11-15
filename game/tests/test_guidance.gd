extends SceneTree
## Headless test: M1 guidance (Guidance, GuidanceOverlay, MissionHint) on the Moon.
##   1. Stuck hint: not before 45 s on a step, shown after; cleared when the step changes.
##   2. kite_prepared: pick up a battery -> fit it; dropping it steps back; the highlight moves from the
##      rack battery to the socket's box and the old overlay is removed.
##   3. iris_scanned: console -> Control Kite -> drive (Control Kite doesn't step back to the console)
##      -> mast camera near IRIS -> hold on the panel; the waypoint marker; leaving IRIS steps back.
##   4. kite_docked: driving away from IRIS keeps "drive back onto the pad"; the marker is on screen
##      facing the pad and clamped to the edge facing away.
##   5. inspection_sent: leave Kite -> console -> Downlink tab -> Send inspection.
##   Throughout: guidance never completes an objective itself.
##   6. Off switch (debug command): no steps, highlights, labels or marker; the objective stays.
##   7. Purely visual: markers live under Guidance (never inside a target's subtree), have no
##      collision, and no ray or point query finds them.
##   8. No mission: the level loaded without one, Guidance and its overlay don't process and make nothing.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_guidance.gd

const TICKS: int = 240
const MAST: int = 1
const CHASE: int = 0

var GS: Node
var SL: Node
var CS: Node
var DBG: Node
var failures: int = 0
var level: Node3D
var workshop: Node3D
var rover: RigidBody3D
var player: RigidBody3D
var panel: Node3D
var guidance: Node
var console: Node
var hint: Node
var completed: Array = []
var expected: Array = []


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


func _step() -> String:
	return guidance.current_step().get("text", "")


func _place(at: Vector3, facing: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0, 1)
	var hit: Dictionary = rover.get_world_3d().direct_space_state.intersect_ray(query)
	var ground: float = (hit["position"] as Vector3).y if hit else at.y
	rover.global_transform = Transform3D(Basis(Vector3.UP, atan2(-facing.x, -facing.z)), Vector3(at.x, ground + 0.3, at.z))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(1.0)


class ErrorCounter extends Logger:
	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool,
			_error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1


func _test_target() -> Node3D:
	var node := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	node.add_child(mesh)
	node.add_to_group(&"test_guidance_target")
	level.add_child(node)
	node.global_position = rover.global_position + Vector3(0.0, 1.0, -5.0)
	return node


func _overlay_count() -> int:
	var count: int = 0
	for node in level.find_children("*", "GeometryInstance3D", true, false):
		if (node as GeometryInstance3D).material_overlay == guidance._material:
			count += 1
	return count


func _markers() -> Array:
	return level.find_children("Guidance*", "", true, false).filter(
		func(n: Node) -> bool: return n.name.begins_with("GuidanceLabel") or n.name.begins_with("GuidanceBox"))


func _all_under(meshes: Array, parent: Node) -> bool:
	for mesh in meshes:
		if not parent.is_ancestor_of(mesh):
			return false
	return not meshes.is_empty()


func _expect(objective: String) -> void:
	expected.append(objective)


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	DBG = root.get_node("Debug")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	DBG.parse_command("guidance on")
	CS.reset()
	load("res://src/save/save_index.gd").start_new_campaign()
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	workshop = level.get_node("Workshop")
	rover = level.get_node("ReadyRover")
	panel = level.get_node("Iris/ServicePanel")
	guidance = level.get_node("Guidance")
	console = root.get_node("Main").find_child("MissionConsole", true, false)
	hint = root.get_node("Main").find_child("MissionHint", true, false)
	player = GS.player
	CS.objective_completed.connect(func(id: String) -> void: completed.append(id))
	if CS.is_objective_done("m1.workshop_entered") and not completed.has("m1.workshop_entered"):
		completed.append("m1.workshop_entered")
	await _ticks(1.0)
	_expect("m1.workshop_entered")
	_check("arrival: spawned inside the workshop, the walk-in is done", CS.is_objective_done("m1.workshop_entered")
		and CS.current_objective() == "m1.kite_prepared", CS.current_objective())
	var overlay = guidance.overlay
	var battery: RigidBody3D = workshop.rack_stock.get_node("Slot16")

	# 1-2. kite_prepared, stuck hint
	_check("prepared: step 1 is picking up the light battery", guidance.index == 0 and _step() == "Pick up the light battery from the parts rack", _step())
	_check("tracker: on foot it shows the objective and the step with its key",
		overlay.tracker.visible and overlay.objective_label.text == "OBJECTIVE  Fit a battery to Kite"
		and overlay.step_label.text.ends_with("]  Pick up the light battery from the parts rack"), overlay.step_label.text)
	_check("highlight: the rack battery glows, one name label", guidance.target == battery
		and _all_under(guidance.highlighted_meshes(), battery) and _overlay_count() == guidance.highlighted_meshes().size()
		and _markers().size() == 1, "%d meshes, %d markers" % [_overlay_count(), _markers().size()])
	var replaced: RigidBody3D = battery
	workshop._on_restock_interacted(player)
	await _ticks(0.3)
	battery = workshop.rack_stock.get_node("Slot16")
	var rack_basis: Basis = battery.global_basis
	_check("restock: the rack battery was replaced", battery != replaced and not is_instance_valid(replaced))
	_check("restock: the highlight follows the new battery, one label", guidance.target == battery
		and _all_under(guidance.highlighted_meshes(), battery) and _overlay_count() == guidance.highlighted_meshes().size()
		and _markers().size() == 1, "%d meshes, %d markers" % [_overlay_count(), _markers().size()])
	_check("restock: the step is unchanged", guidance.index == 0, _step())
	await _ticks(43.5)
	_check("stuck: no stuck hint before 45 s", overlay.stuck_label.text == "" and guidance.stuck_text() == "", "%.1f s" % guidance.stuck_time)
	await _ticks(2.0)
	_check("stuck: the stuck hint shows after 45 s", overlay.stuck_label.text.begins_with("The rack is"), overlay.stuck_label.text)
	player.global_position = rover.global_position + rover.global_basis.z * 1.2 + Vector3.UP * 0.1
	await _ticks(0.3)
	player.holder.pickup(battery)
	await _ticks(0.3)
	_check("prepared: holding a battery moves to fitting it", guidance.index == 1 and _step() == "Drop the battery into Kite's rear battery socket", _step())
	_check("stuck: the hint is cleared on the next step", guidance.stuck_text() == "" and guidance.stuck_time < 1.0)
	var capture: Node = rover.battery_socket.get_node("PartCapture")
	var names: Array = _markers().map(func(n: Node) -> String: return n.name)
	var socket_box: Node3D = guidance.get_node_or_null("GuidanceBox")
	_check("highlight: moves to the socket's box and label, the battery's glow removed", guidance.target == capture
		and _overlay_count() == 0 and socket_box != null
		and names.has("GuidanceLabel") and _markers().size() == 2, "%d overlays, markers %s" % [_overlay_count(), names])
	var shape: CollisionShape3D = capture.get_node("CollisionShape3D")
	_check("visual: the socket's box sits on the capture shape but outside Kite's tree", socket_box != null
		and not rover.is_ancestor_of(socket_box) and socket_box.global_position.distance_to(shape.global_position) < 0.001)
	var physics_found: Array = []
	var space: PhysicsDirectSpaceState3D = rover.get_world_3d().direct_space_state
	var point := PhysicsPointQueryParameters3D.new()
	point.position = socket_box.global_position
	point.collision_mask = 0xFFFFFFFF
	point.collide_with_areas = true
	for hit in space.intersect_point(point, 32):
		if guidance.is_ancestor_of(hit["collider"]):
			physics_found.append(hit["collider"].name)
	var ray := PhysicsRayQueryParameters3D.create(player.camera.global_position, socket_box.global_position, 0xFFFFFFFF)
	ray.collide_with_areas = true
	var ray_hit: Dictionary = space.intersect_ray(ray)
	var collision_nodes: Array = guidance.find_children("*", "CollisionObject3D", true, false) + guidance.find_children("*", "CollisionShape3D", true, false)
	_check("visual: no collision under Guidance, no point or ray query finds a marker", collision_nodes.is_empty()
		and physics_found.is_empty() and not (ray_hit and guidance.is_ancestor_of(ray_hit["collider"])),
		"%d collision nodes, %s, ray %s" % [collision_nodes.size(), physics_found, ray_hit.get("collider")])
	player.holder.release()
	await _ticks(1.0)
	_check("prepared: dropping the battery steps back to picking it up", guidance.index == 0 and guidance.target == battery, _step())
	player.holder.pickup(battery)
	await _ticks(0.3)
	player.holder.release()
	# Dropped the way it sits on the rack: the light battery jams on the chassis upside down
	battery.global_basis = rack_basis
	battery.global_position = rover.battery_socket.global_position + Vector3.UP * 0.05
	battery.linear_velocity = Vector3.ZERO
	await _ticks(1.5)
	_expect("m1.kite_prepared")

	# 3. iris_scanned
	_check("scanned: step 1 is the console, highlighted", guidance.objective == "m1.iris_scanned" and guidance.index == 0
		and guidance.target == workshop.get_node("Parts/ws_console_01") and _overlay_count() > 0, _step())
	workshop._on_console_used(player)
	await _ticks(0.3)
	_check("scanned: the console open moves to Control Kite", guidance.index == 1, _step())
	console._on_control_kite_pressed()
	await _ticks(0.5)
	_check("scanned: driving moves to 'drive to IRIS', not back to the console", guidance.index == 2
		and _step() == "Drive Kite to IRIS", _step())
	_check("hud: the robot HUD shows the step", hint.step_label.visible and hint.step_label.text == "Drive Kite to IRIS", hint.step_label.text)
	_check("tracker: the on-foot tracker hides while driving", not overlay.tracker.visible)
	_check("waypoint: shown while driving to IRIS, placed in the viewport", overlay.marker.visible and overlay.place_marker()
		and Rect2(Vector2.ZERO, overlay.marker.get_viewport_rect().size).has_point(overlay.marker_position)
		and overlay.marker_text().begins_with("IRIS"), "%s %s" % [overlay.marker_position, overlay.marker_text()])
	rover.get_node("CameraRig")._switch(CHASE)
	var iris: Node3D = level.get_node("Iris")
	var front: Vector3 = -iris.global_basis.z
	front.y = 0.0
	front = front.normalized()
	await _place(panel.global_position + front * 12.0, -front)
	_check("scanned: near IRIS asks for the mast camera", guidance.index == 3 and _step() == "Switch to the mast camera", _step())
	rover.get_node("CameraRig")._switch(MAST)
	await _ticks(0.3)
	_check("scanned: in the mast view, hold on the panel; the model's panel glows", guidance.index == 4
		and guidance.target == panel and _all_under(guidance.highlighted_meshes(), panel.highlight_node)
		and guidance.get_node_or_null("GuidanceBox") == null, _step())
	_check("never completes: the scan step doesn't complete m1.iris_scanned", not CS.is_objective_done("m1.iris_scanned"))
	await _place(panel.global_position + front * 60.0, -front)
	_check("scanned: driving away from IRIS before the scan steps back to 'drive to IRIS'", guidance.index == 2, _step())
	await _place(panel.global_position + front * 12.0, -front)
	var cam: Camera3D = rover.camera
	var local: Vector3 = rover.to_local(panel.global_position)
	var d: Vector3 = local - rover.to_local(cam.global_position)
	rover.controller.camera_azimuth = atan2(-d.x, -d.z)
	rover.controller.camera_altitude = atan2(d.y, Vector2(d.x, d.z).length())
	await _ticks(2.0)
	_expect("m1.iris_scanned")
	rover.controller.camera_azimuth = 0.0
	rover.controller.camera_altitude = 0.0
	rover.get_node("CameraRig")._switch(CHASE)

	# 4. kite_docked
	var pad: Node3D = workshop.get_node("Parts/ws_pad_01")
	_check("docked: after the scan, drive back onto the pad", guidance.objective == "m1.kite_docked" and guidance.index == 2
		and guidance.target == pad, _step())
	var to_pad: Vector3 = pad.global_position - panel.global_position
	to_pad.y = 0.0
	await _place(panel.global_position + to_pad * 0.5, to_pad.normalized())
	_check("docked: half way back, far from IRIS, the step is still 'drive back onto the pad'", guidance.index == 2
		and _step() == "Drive back onto the charging pad and stop", _step())
	await _ticks(0.2)
	_check("waypoint: on screen while facing the pad", overlay.place_marker() and overlay.marker_on_screen, str(overlay.marker_position))
	var pad_label: Node3D = guidance.get_node_or_null("GuidanceLabel")
	_check("waypoint: the world label is hidden while the screen marker names the pad", pad_label != null and not pad_label.visible
		and guidance.waypoint_marker_shown())
	await _place(rover.global_position, -to_pad.normalized())
	await _ticks(0.2)
	var size: Vector2 = overlay.marker.get_viewport_rect().size
	var edge: float = overlay.EDGE_MARGIN
	var p: Vector2 = overlay.marker_position if overlay.place_marker() else Vector2(-1, -1)
	var on_edge: bool = absf(p.x - edge) < 1.0 or absf(p.x - (size.x - edge)) < 1.0 or absf(p.y - edge) < 1.0 or absf(p.y - (size.y - edge)) < 1.0
	_check("waypoint: facing away it clamps to the screen edge", not overlay.marker_on_screen and on_edge, "%s in %s" % [p, size])
	_check("never completes: driving back alone doesn't dock", not CS.is_objective_done("m1.kite_docked"))
	var dock: Transform3D = workshop.get_dock_transform()
	dock.origin += Vector3.UP * 0.3
	rover.global_transform = dock
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(4.0)
	_expect("m1.kite_docked")

	# 5. inspection_sent
	_check("downlink: step 1 is leaving Kite", guidance.objective == "m1.inspection_sent" and guidance.index == 0, _step())
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.3)
	_check("downlink: on foot, open the console", guidance.index == 1, _step())
	workshop._on_console_used(player)
	await _ticks(0.3)
	console.select_section(console.Section.MISSION)
	await _ticks(0.1)
	_check("downlink: console open, open the Downlink tab", guidance.index == 2, _step())
	console.select_section(console.Section.DOWNLINK)
	await _ticks(0.1)
	_check("downlink: on the Downlink tab, press Send inspection", guidance.index == 3 and _step() == "Press Send inspection", _step())
	_check("never completes: only the real actions completed objectives", completed == expected, "%s vs %s" % [completed, expected])

	# 6. Off switch
	GS.return_to_game()
	await _ticks(0.3)
	workshop._on_console_used(player)
	GS.return_to_game()
	await _ticks(0.3)
	_check("downlink: closing the console steps back to opening it, the console highlighted", guidance.index == 1 and _overlay_count() > 0, _step())
	DBG.parse_command("guidance off")
	await _ticks(0.3)
	_check("off: no step, highlight or label; the objective stays", overlay.step_label.text == "" and _overlay_count() == 0
		and _markers().is_empty() and overlay.objective_label.text == "OBJECTIVE  Downlink the inspection from the console",
		"%s / %d / %d" % [overlay.step_label.text, _overlay_count(), _markers().size()])
	DBG.parse_command("guidance on")
	await _ticks(0.3)
	_check("on again: the step and highlight come back", overlay.step_label.text.ends_with("Open the mission console") and _overlay_count() > 0,
		overlay.step_label.text)

	# 7. Freed targets and hint_from
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var objective: String = CS.current_objective()
	var saved_steps: Array = guidance.steps(objective)
	guidance._steps[objective] = [{"text": "Test step", "label": "Test", "target": "group:test_guidance_target",
		"hint_from": "group:test_guidance_hint"}]
	var hinter := Node3D.new()
	var hinter_script := GDScript.new()
	hinter_script.source_code = "extends Node3D\nfunc get_hint(_rover) -> String:\n\treturn 'hint from elsewhere'\n"
	hinter_script.reload()
	hinter.set_script(hinter_script)
	hinter.add_to_group(&"test_guidance_hint")
	level.add_child(hinter)
	var first: Node3D = _test_target()
	await _ticks(0.3)
	_check("freed: the target in the step data is highlighted", guidance.target == first and not guidance.highlighted_meshes().is_empty()
		and not _markers().is_empty(), str(guidance.target))
	GS.change_state_to(GS.State.IN_GAME_ROBOT)
	await _ticks(0.2)
	_check("hint_from: the hint comes from that node, the target keeps the highlight", guidance.step_text() == "hint from elsewhere"
		and guidance.target == first, guidance.step_text())
	first.free()
	await _ticks(0.5)
	_check("freed: no script errors, nothing left highlighted, target cleared", errors.count == 0 and guidance.target == null
		and guidance.highlighted_meshes().is_empty() and _markers().is_empty() and not guidance.is_waypoint(),
		"%d errors, target %s, %d meshes, %d markers" % [errors.count, guidance.target, guidance.highlighted_meshes().size(), _markers().size()])
	var second: Node3D = _test_target()
	await _ticks(0.5)
	_check("freed: a replacement node gets highlighted", guidance.target == second and not guidance.highlighted_meshes().is_empty()
		and _all_under(guidance.highlighted_meshes(), second) and not _markers().is_empty() and errors.count == 0, "%d errors" % errors.count)
	hinter.free()
	await _ticks(0.3)
	_check("hint_from: a freed hint node: the step's own text, no errors", guidance.step_text() == "Test step" and errors.count == 0,
		"%s, %d errors" % [guidance.step_text(), errors.count])
	second.free()
	await _ticks(0.3)
	OS.remove_logger(errors)
	_check("freed: freeing the replacement also raises no errors", errors.count == 0 and guidance.target == null, "%d errors" % errors.count)
	guidance._steps[objective] = saved_steps
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.3)

	# 7b. M2 and M3: the objective and the waypoint; a step's text only as the stuck hint
	var m1_objective: String = CS.current_objective()
	var m1_step: String = guidance.hud_step_text()
	_check("m1: the step text is on the HUD", m1_step != "" and hint.step_label.text == m1_step and overlay.step_label.text == m1_step, m1_step)
	for mission_id in ["m2", "m3"]:
		CS._current = mission_id
		guidance.stuck_time = 0.0
		await _ticks(0.4)
		var first_step: Dictionary = guidance.current_step()
		_check("%s: objective shown, no step text (HUD and tracker)" % mission_id, CS.current_objective() != ""
			and not first_step.is_empty() and guidance.step_text() != "" and hint.objective_label.text.begins_with("OBJECTIVE")
			and hint.step_label.text == "" and overlay.step_label.text == "" and hint.stuck_label.text == "",
			"%s / %s / %s" % [hint.step_label.text, overlay.step_label.text, hint.stuck_label.text])
		guidance.stuck_time = guidance.STUCK_TIME + 1.0
		await _ticks(0.2)
		_check("%s: when stuck, the step's stuck text shows" % mission_id, first_step.get("stuck", "") != ""
			and hint.stuck_label.text == first_step["stuck"] and hint.step_label.text == "", hint.stuck_label.text)
	CS._current = "m1"
	await _ticks(0.3)
	_check("m1 again: the step text is back", CS.current_objective() == m1_objective and hint.step_label.text != "", hint.step_label.text)

	# 8. No mission
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	CS.reset()
	await _ticks(0.2)
	_check("idle: clearing the mission stops Guidance and clears its highlight", not guidance.is_physics_processing()
		and not overlay.is_processing() and not overlay.visible and _overlay_count() == 0 and _markers().is_empty())
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level" and SL.current_scene != level):
		await physics_frame
	level = SL.current_scene
	guidance = level.get_node("Guidance")
	await _ticks(2.0)
	_check("idle: a level loaded without a mission: no processing, no highlight, labels or boxes",
		CS.current_mission().is_empty() and not guidance.is_physics_processing() and not guidance.overlay.is_processing()
		and not guidance.overlay.visible and _overlay_count() == 0 and _markers().is_empty()
		and guidance.find_children("*", "Node3D", true, false).is_empty())

	print("RESULT test_guidance %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
