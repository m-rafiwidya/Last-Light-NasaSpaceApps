extends SceneTree
## Headless test: the arm by hand (ManualClaw), aimed with the mast camera like a player.
##   1. R deploys the arm and the claw takes over (active, marker shown).
##   2. Following: looking at a spot 0.5 m ahead, the grip goes there (within 3 cm).
##   3. Grab: lowered onto a sample container on the ground, a click grabs it.
##   4. Place: looking at the storage tray, a click lets go and it drops into the tray.
##   5. Out of reach: looking 3 m ahead says so and the arm stays put.
##   6. Stow: R stows the arm; deployed again with a part held, driving off stows it and the part drops.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_manual_claw.gd

const TICKS: int = 240
const MAST: int = 1

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D
var claw: Node
var latch_of: Callable


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


func _press(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame


## Points the mast camera at `world_point` (twice: the camera moves as the mast pans)
func _look_at(world_point: Vector3) -> void:
	for i in 3:
		var local: Vector3 = rover.to_local(world_point)
		var cam: Vector3 = rover.to_local(rover.camera.global_position)
		var d: Vector3 = local - cam
		rover.controller.camera_azimuth = atan2(-d.x, -d.z)
		rover.controller.camera_altitude = atan2(d.y, Vector2(d.x, d.z).length())
		await _ticks(0.3)


func _latch() -> Node3D:
	return rover.find_child("ArmToolSocket", true, false).part.find_child("pivot_latch", true, false)


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
	claw = rover.get_node("ManualClaw")
	var tray: Node3D = rover.get_node("StorageBox")
	var start: Vector2 = level.get_node("RouteMarkers").start()
	rover.global_transform = Transform3D(rover.global_basis, _ground(Vector3(start.x, 0.0, start.y)) + Vector3.UP * 0.4)
	rover.linear_velocity = Vector3.ZERO
	await _ticks(2.0)
	var battery: Node = (load("res://src/robot/socket/battery_part.tscn") as PackedScene).instantiate()
	level.add_child(battery)
	battery.global_position = rover.battery_socket.global_position
	rover.battery_socket.mount(battery)
	GS.drive(rover)
	await _ticks(0.5)
	rover.get_node("CameraRig")._switch(MAST)
	await _ticks(0.3)

	# 1. Deploy
	await _press(&"arm_toggle")
	for i in 6 * TICKS:
		if claw.active:
			break
		await physics_frame
	_check("deploy: R deploys the arm and the claw takes over", claw.active and claw._marker.visible)

	# 2. Following
	var spot: Vector3 = _ground(rover.to_global(Vector3(-0.12, 0.0, -(0.53 + 0.5))))
	claw.hover = 0.15
	await _look_at(spot)
	await _ticks(2.0)
	var want: Vector3 = claw.target
	_check("follow: the grip goes where the crosshair looks (+ hover)", claw.reachable
		and _latch().global_position.distance_to(want) < 0.03 and want.distance_to(spot + Vector3.UP * 0.15) < 0.1,
		"grip %.3f m from target; target %.3f m from the spot + hover" % [_latch().global_position.distance_to(want),
		want.distance_to(spot + Vector3.UP * 0.15)])

	# 3. Grab
	var jar: RigidBody3D = (load("res://src/robot/socket/sample_container_part.tscn") as PackedScene).instantiate()
	level.add_child(jar)
	jar.global_transform = Transform3D(rover.global_basis, spot + Vector3.UP * 0.05)
	await _ticks(1.0)
	await _look_at(jar.global_position)
	claw.hover = 0.0
	await _ticks(2.0)
	_check("grab: lowered onto the jar, it's under the claw", claw.part_under_claw() == jar,
		"%.3f m from the jar's top" % _latch().global_position.distance_to(rover.get_node("ClawPick").top_of(jar)))
	Input.action_press(&"interact_primary")
	await physics_frame
	await physics_frame
	Input.action_release(&"interact_primary")
	await physics_frame
	_check("grab: a click grabs it", claw.held == jar and jar.freeze)

	# 4. Place in the tray
	claw.hover = 0.05
	await _look_at(tray.global_position)
	await _ticks(3.0)
	_check("place: the claw reaches back over the tray", claw.reachable and _latch().global_position.distance_to(claw.target) < 0.05,
		"%s; grip %.3f m from its target, clearance %.3f" % [claw.get_hint(), _latch().global_position.distance_to(claw.target),
		rover.get_node("Visuals").arm_ground_clearance()])
	claw.toggle_grab()
	await _ticks(1.5)
	_check("place: let go over the tray, the jar drops into it", claw.held == null and tray.holds(jar),
		"jar at %s in the tray's frame; %s" % [tray.to_local(jar.global_position), str(tray.items())])

	# 5. Out of reach
	var joints: Dictionary = rover.get_node("Visuals").arm_joints.duplicate()
	await _look_at(_ground(rover.to_global(Vector3(-0.12, 0.0, -3.5))))
	await _ticks(0.5)
	_check("reach: 3 m ahead is out of reach, and the hint says so", not claw.reachable and claw.get_hint().contains("out of"),
		claw.get_hint())

	# 6. Stow
	await _press(&"arm_toggle")
	await _ticks(3.0)
	_check("stow: R stows the arm and the claw lets go", not claw.active and not rover.get_node("Visuals").arm_scripted
		and not claw._marker.visible)
	await _press(&"arm_toggle")
	for i in 6 * TICKS:
		if claw.active:
			break
		await physics_frame
	await _look_at(tray.global_position)
	await _ticks(2.0)
	claw.hover = 0.0
	await _ticks(1.5)
	var grabbed: bool = claw.toggle_grab()
	Input.action_press(&"move_forward", 0.6)
	await _ticks(0.5)
	Input.action_release(&"move_forward")
	await _ticks(1.0)
	_check("stow: driving off stows the arm and drops what it held", grabbed and not claw.active and claw.held == null
		and not jar.freeze, "grabbed %s, active %s, held %s, jar frozen %s, mounted %s, parent %s, desired %.2f" % [grabbed, claw.active, claw.held,
		jar.freeze, jar.is_mounted(), jar.get_parent().name, rover.controller.desired_speed])

	print("RESULT test_manual_claw %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
