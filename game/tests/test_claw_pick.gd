extends SceneTree
## Headless test (plan v2 G3): the arm's assisted pick (ClawPick).
##   1. Hints: a delivery crate 2 m ahead says to come closer; one in the arm's reach says "In
##      position".
##   2. Pick: E has the arm pick the crate up; it ends on the cargo mount (the box refuses it), the
##      arm stowed high over it (turret clear of the crate) and free again.
##   3. Short parts: a sample container on the ground is too low for the turret (hint says so);
##      the storage tray would be its destination.
##   4. Interrupted before the latch: the rover moving stops the pick; nothing is taken.
##   5. Interrupted while carrying: the part drops where it is.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_claw_pick.gd

const TICKS: int = 240

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D
var claw: Node


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


func _ground(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0, 1)
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if hit else at


## Puts `part` on the ground `ahead` m in front of the arm's yaw axis, `left` m to its left
func _place(part: RigidBody3D, ahead: float, left: float = 0.0) -> void:
	var yaw := Vector2(-0.12 - left, 0.53 + ahead)               # kit frame (x right, y forward)
	var at: Vector3 = rover.to_global(Vector3(yaw.x, 0.0, -yaw.y))
	part.freeze = false
	part.global_transform = Transform3D(rover.global_basis, _ground(at) + Vector3.UP * 0.05)
	part.linear_velocity = Vector3.ZERO
	part.angular_velocity = Vector3.ZERO
	await _ticks(1.0)


func _wait_idle(seconds: float) -> bool:
	for i in int(seconds * TICKS):
		if not claw.is_busy():
			return true
		await physics_frame
	return false


func _stowed() -> bool:
	var visuals: Node = rover.get_node("Visuals")
	var stow: Dictionary = visuals.stow_pose()
	for j in ["J1", "J2", "J3", "J4"]:
		if absf(visuals.arm_joints[j] - stow[j]) > 0.5:
			return false
	return not visuals.arm_scripted


## The world box around a node's visible meshes
func _aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh and mesh.is_visible_in_tree():
			var b: AABB = mesh.global_transform * mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box


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
	rover = level.get_node("ReadyRover")
	claw = rover.get_node("ClawPick")
	var cargo: Node = rover.get_node("CargoSocket")
	var tray: Node = rover.get_node("StorageBox")
	# Kite out on the apron, on open ground
	var start: Vector2 = level.get_node("RouteMarkers").start()
	rover.global_transform = Transform3D(rover.global_basis, _ground(Vector3(start.x, 0.0, start.y)) + Vector3.UP * 0.4)
	rover.linear_velocity = Vector3.ZERO
	await _ticks(2.0)
	GS.drive(rover)
	await _ticks(0.3)

	# 1. Hints
	var crate: RigidBody3D = (load("res://src/field/cargo_crate_part.tscn") as PackedScene).instantiate()
	level.add_child(crate)
	await _place(crate, 2.0)
	_check("hint: a crate 2 m ahead: come closer", claw.get_hint().contains("closer"), claw.get_hint())
	var reach := -1.0
	for d in [0.40, 0.45, 0.50, 0.55, 0.60, 0.35, 0.65, 0.70]:
		await _place(crate, d)
		if claw.ready_for(crate):
			reach = d
			break
	_check("hint: there is a spot in the arm's reach", reach > 0.0, "%.2f m ahead of the arm" % reach)
	_check("hint: in reach it says In position", claw.get_hint().begins_with("In position"), claw.get_hint())

	# 2. Pick
	var finished: Array = []
	var aborted: Array = []
	claw.pick_finished.connect(func(p: Node, s: Node) -> void: finished.append([p, s]))
	claw.pick_aborted.connect(func(p: Node, reason: String) -> void: aborted.append(reason))
	_check("pick: E starts it", claw.handle_interact() and claw.is_busy())
	_check("pick: it finishes", await _wait_idle(40.0))
	_check("pick: not interrupted", aborted.is_empty(), str(aborted))
	_check("pick: the crate is on the cargo mount (the box refuses it)", cargo.part == crate and crate.is_mounted()
		and finished.size() == 1 and finished[0][1] == cargo, str(cargo.part))
	_check("pick: the arm is stowed and free again", _stowed())
	var turret: Node = rover.find_child("ArmToolSocket", true, false).part.get_node("Model")
	_check("pick: over the tall crate the arm stows high, its turret clear of the crate",
		rover.get_node("Visuals").stow_pose() == rover.get_node("Visuals").ARM_STOWED_HIGH
		and not _aabb(turret).intersects(_aabb(crate)), "turret %s, crate %s" % [_aabb(turret), _aabb(crate)])

	# 3. Short parts: too low for the turret, but the box would take them
	var jar: RigidBody3D = (load("res://src/robot/socket/sample_container_part.tscn") as PackedScene).instantiate()
	level.add_child(jar)
	jar.add_to_group(&"claw_target")
	await _place(jar, reach)
	_check("short: a sample container on the ground is too low to grab", not claw.ready_for(jar)
		and claw.get_hint().contains("too low"), claw.get_hint())
	_check("short: the storage tray would take it first", claw.destination_for(jar) == tray)
	jar.queue_free()

	# 4. Interrupted before the latch (a second crate; the first leaves the cargo mount)
	cargo.unmount().global_position = rover.global_position + Vector3(0.0, 1.0, 30.0)
	var crate2: RigidBody3D = (load("res://src/field/cargo_crate_part.tscn") as PackedScene).instantiate()
	level.add_child(crate2)
	await _place(crate2, reach)
	aborted.clear()
	_check("abort: E starts a pick", claw.handle_interact(), claw.get_hint())
	await _ticks(0.3)
	rover.global_position += rover.global_basis.x * 0.1
	await _wait_idle(30.0)
	_check("abort: moving before the latch stops it, nothing taken", aborted == ["the rover moved"] and not crate2.is_mounted()
		and crate2.get_parent() == level, str(aborted))
	_check("abort: the arm stows", _stowed())

	# 5. Interrupted while carrying
	await _place(crate2, reach)
	_check("drop: E starts a pick", claw.handle_interact(), claw.get_hint())
	for i in 30 * TICKS:
		if claw.phase == claw.Phase.UP:
			break
		await physics_frame
	await _ticks(0.3)
	rover.global_position += rover.global_basis.x * 0.1
	await _wait_idle(30.0)
	_check("drop: moving while carrying drops the part where it is", aborted.size() == 2 and aborted[1] == "the rover moved"
		and not crate2.is_mounted() and crate2.get_parent() == level and not crate2.freeze, str(aborted))

	print("RESULT test_claw_pick %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
