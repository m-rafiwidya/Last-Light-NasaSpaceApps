extends SceneTree
## Headless test: the Kite delivery from start to end (tools/blender/KITE_KIT.md 14).
##   1. Load (Moon): the player takes the cartridge off the rack and lets go of it over the docked
##      rover's deck; the cargo mount takes it and the robot HUD's CARGO line names it.
##   2. Rules (Moon): the player can't pick up the rover; the driven rover's mast camera picks
##      nothing up.
##   3. Drive: from the console, out of the bay, along the route to Kite. The rover never touches
##      Kite and stays upright.
##   4. Scan: the mast camera held on Kite from about 12 m. Kite.scanned fires once.
##   5. Park: into the delivery window; the hint says "In position".
##   6. Interrupted insert: E, then throttle while the arm carries the cartridge. The delivery
##      aborts and the cartridge is back on the mount, the arm stowed.
##   7. Insert: E again. The cartridge ends on Kite's seat (within 5 mm), cargo_inserted and then
##      Kite.cartridge_inserted fire once, Kite's light goes green, the arm stows. Throughout: the
##      arm stays 20 mm or more above the terrain and never inside Kite.
##   8. Test level: the player can still lift a rover, and the rover's mast camera can still pick
##      a part up.
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_kite.gd   (add `-- trace`)

const TICKS: int = 240
const MAST: int = 1                  # RoverCamera.View.MAST
const APPROACH := Vector2(0.637, -0.771)     # the heading into Kite (azimuth 39.6)
const YAW_AXIS := Vector2(-0.12, 0.53)       # the arm's yaw axis (right, forward) from the rover's origin
const PARK_D: float = 0.51                   # the middle of the delivery window
const SEAT_GAP: float = 0.006                # the port's seat over its floor

var GS: Node
var SL: Node
var failures: int = 0
var level: Node3D
var workshop: Node3D
var rover: RigidBody3D
var kite: Node3D
var delivery: Node
var trace: bool = "trace" in OS.get_cmdline_user_args()
var events: Dictionary = {}
var touched_kite: bool = false
var tilted: float = 0.0
var arm_lowest: float = INF
var arm_in_kite: int = 0
var inside_where: Array = []
var watching_arm: bool = false


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-72s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _release_all() -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(a)


func _count(name: String) -> Callable:
	return func(_a = null, _b = null, _c = null) -> void: events[name] = events.get(name, 0) + 1


func _physics_process(_delta: float) -> bool:
	if not is_instance_valid(rover) or not is_instance_valid(kite):
		return false
	for body in rover.get_colliding_bodies():
		if kite.is_ancestor_of(body):
			touched_kite = true
	tilted = maxf(tilted, rad_to_deg(acos(clampf(rover.global_basis.y.y, -1.0, 1.0))))
	if watching_arm and Engine.get_physics_frames() % 24 == 0:
		var visuals = rover.get_node("Visuals")
		arm_lowest = minf(arm_lowest, visuals.arm_ground_clearance())
		arm_in_kite += _arm_points_in_kite(visuals)
	return false


# Arm vertices (forearm, wrist, turret and the cartridge on it) inside Kite's collision (small sphere queries, layer 2)
func _arm_points_in_kite(visuals) -> int:
	var meshes: Array = []
	for joint in ["J3", "J4"]:
		meshes += (visuals._arm_nodes[joint] as Node).find_children("*", "MeshInstance3D", true, false)
	var tool = visuals._arm_tool()
	if tool:
		meshes += tool.find_children("*", "MeshInstance3D", true, false)
	var space := rover.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 0.005
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 2
	query.exclude = [rover.get_rid()]
	var inside: int = 0
	for mesh in meshes:
		var verts: Array = visuals._vertices(mesh)
		for k in range(0, verts.size(), 4):
			query.transform = Transform3D(Basis.IDENTITY, (mesh as MeshInstance3D).global_transform * verts[k])
			var p: Vector3 = query.transform.origin
			for hit in space.intersect_shape(query, 4):
				if kite.is_ancestor_of(hit["collider"]) and not _in_port_opening(p):
					inside += 1
					if inside_where.size() < 6:
						var lp: Vector3 = kite.port.global_transform.affine_inverse() * p
						inside_where.append("%s on %s phase %d at port (%.3f, %.3f, %.3f)" % [mesh.name, hit["collider"].name,
							delivery.phase, lp.x, lp.y, lp.z])
	return inside


# The port's collider is one box over the whole port: its opening (0.28 x 0.17 m, down to its floor,
# SEAT_GAP under the seat) is empty in the model
func _in_port_opening(world_point: Vector3) -> bool:
	var p: Vector3 = kite.port.global_transform.affine_inverse() * world_point
	var floor_y: float = (kite.port.global_transform.affine_inverse() * kite.port.seat.global_position).y - SEAT_GAP
	return absf(p.x) < 0.14 and absf(p.z) < 0.085 and p.y > floor_y


## Drives through world waypoints (x, z), steering like a driver; the last one stops if `stop`
func _drive_to(points: Array, speed: float, timeout: float, stop: bool) -> bool:
	var t: float = 0.0
	for i in points.size():
		var target: Vector2 = points[i]
		var last: bool = stop and i == points.size() - 1
		while true:
			await physics_frame
			t += 1.0 / TICKS
			var forward: Vector3 = -rover.global_basis.z
			var v: float = rover.linear_velocity.dot(forward)
			var to := Vector2(target.x - rover.global_position.x, target.y - rover.global_position.z)
			var passed: bool = Vector2(forward.x, forward.z).dot(to) < 0.0 and to.length() < 1.5
			if (not last and (to.length() < 0.6 or passed)) or (last and (to.length() < 0.08 or passed) and absf(v) < 0.05):
				break
			if t > timeout:
				_release_all()
				return false
			if trace and int(t * TICKS) % TICKS == 0:
				print("TRACE t %.0f wp %d at (%.1f, %.1f) %.1f m to go, %.2f m/s" % [t, i, rover.global_position.x, rover.global_position.z, to.length(), v])
			var heading := Vector2(forward.x, forward.z).normalized()
			var steer: float = clampf(heading.angle_to(to.normalized()) / 0.25, -1.0, 1.0)
			var want: float = clampf(to.length() * 0.8, 0.0, speed) if last else speed
			_release_all()
			if v > want + 0.15:
				Input.action_press("move_backward", clampf((v - want) * 0.6, 0.05, 0.6))
			elif v < want:
				Input.action_press("move_forward", clampf(0.06 + (want - v) * 0.3, 0.05, 0.5))
			if steer > 0.05:
				Input.action_press("move_right", steer)
			elif steer < -0.05:
				Input.action_press("move_left", -steer)
	_release_all()
	# Brake to a stop
	while rover.linear_velocity.length() > 0.03 and t < timeout:
		await physics_frame
		t += 1.0 / TICKS
		_release_all()
		if rover.linear_velocity.dot(-rover.global_basis.z) > 0.05:
			Input.action_press("move_backward", 0.3)
		elif rover.linear_velocity.dot(-rover.global_basis.z) < -0.05:
			Input.action_press("move_forward", 0.3)
	_release_all()
	return true


## Where the rover's origin stops, heading APPROACH, for the port to sit PARK_D ahead of the arm's
## yaw axis
func _park_point() -> Vector2:
	var port := Vector2(kite.port.global_position.x, kite.port.global_position.z)
	var right := Vector2(-APPROACH.y, APPROACH.x)
	return port - APPROACH * (PARK_D + YAW_AXIS.y) - right * YAW_AXIS.x


## Like a driver reading the hint: forward or back by the distance it asks for, until in the window
func _creep_into_window() -> void:
	for attempt in 4:
		if delivery.ready_for(kite.port):
			return
		var error: float = delivery.measure(kite.port)["d"] - PARK_D
		if trace:
			print("TRACE creep %+.3f m (d %.3f)" % [error, error + PARK_D])
		await _nudge(error)
		await _ticks(0.5)


## Straight forward (or back, if negative) by `distance` at a crawl, then stopped
func _nudge(distance: float) -> void:
	var start: Vector3 = rover.global_position
	var t: float = 0.0
	var go: String = "move_forward" if distance > 0.0 else "move_backward"
	var stop: String = "move_backward" if distance > 0.0 else "move_forward"
	while rover.global_position.distance_to(start) < absf(distance) - 0.015 and t < 10.0:
		_release_all()
		Input.action_press(go, 0.12 if rover.linear_velocity.length() < 0.1 else 0.0)
		await physics_frame
		t += 1.0 / TICKS
	_release_all()
	while rover.linear_velocity.length() > 0.02 and t < 15.0:
		Input.action_press(stop, 0.2)
		await physics_frame
		t += 1.0 / TICKS
	_release_all()


func _press_e() -> void:
	rover.controller.interact.emit(true)
	rover.controller.interact.emit(false)


func _aim_mast_at(world_point: Vector3) -> void:
	var local: Vector3 = rover.to_local(world_point)
	var cam: Vector3 = rover.to_local(rover.camera.global_position)
	var d: Vector3 = local - cam
	rover.controller.camera_azimuth = atan2(-d.x, -d.z)
	rover.controller.camera_altitude = atan2(d.y, Vector2(d.x, d.z).length())


## Stands the player 1.8 m in front of the rover, looking at its body (between the front wheels)
func _aim_player_at_rover(player) -> void:
	var ahead: Vector3 = -rover.global_basis.z
	ahead.y = 0.0
	player.global_position = rover.global_position + ahead.normalized() * 1.8 + Vector3.UP * 0.05
	player.linear_velocity = Vector3.ZERO
	await _ticks(0.3)
	var d: Vector3 = rover.global_position + Vector3.UP * 0.3 - player.camera.global_position
	player.controller.camera_azimuth = atan2(-d.x, -d.z)
	player.controller.camera_altitude = atan2(d.y, Vector2(d.x, d.z).length())
	await _ticks(0.3)


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	workshop = level.get_node("Workshop")
	rover = level.get_node("ReadyRover")
	kite = level.get_node("Kite")
	delivery = rover.get_node("CargoDelivery")
	kite.scanned.connect(_count("scanned"))
	kite.cartridge_inserted.connect(_count("kite_inserted"))
	kite.port.cargo_inserted.connect(_count("cargo_inserted"))
	delivery.delivery_aborted.connect(_count("aborted"))
	delivery.delivery_finished.connect(_count("finished"))
	await _ticks(3.0)

	# 1. Load
	var player = GS.player
	var cartridge: RigidBody3D = workshop.rack_stock.get_node("Slot17")
	var socket = rover.get_node("CargoSocket")
	player.global_position = rover.global_position + rover.global_basis.x * 1.4 + Vector3.UP * 0.1
	await _ticks(0.3)
	player.holder.pickup(cartridge)
	await _ticks(0.5)
	_check("load: the player picks the cartridge off the rack", player.holder.held_object == cartridge)
	player.holder.release()
	cartridge.global_position = socket.global_position + Vector3.UP * 0.12
	cartridge.linear_velocity = Vector3.ZERO
	await _ticks(1.0)
	_check("load: let go over the deck, the cargo mount takes it", socket.part == cartridge)

	# 2. Rules on the Moon
	await _aim_player_at_rover(player)
	var aimed_at_rover: bool = player.looking_at_object == rover
	player._on_controller_interact(true)
	await _ticks(0.2)
	_check("rules: the player can't pick up the rover on the Moon", aimed_at_rover and player.holder.held_object == null,
		"aimed at it: %s, holding %s" % [aimed_at_rover, player.holder.held_object])

	# 3. Drive out (from the console) and to Kite
	workshop._on_console_interacted(player)
	await _ticks(0.5)
	var hud := root.get_node("Main").find_child("RobotHUD", true, false)
	var cargo_line: Label = hud.find_child("Cargo", true, false)
	_check("load: the robot HUD's CARGO line names it", cargo_line != null and cargo_line.text == "CARGO  Diagnostic cartridge",
		cargo_line.text if cargo_line else "no label")
	var door: Vector3 = workshop.to_global(Vector3(-0.5, 0.0, -6.0))
	var apron: Vector3 = workshop.to_global(Vector3(1.5, 0.0, -12.0))     # right of the base sign
	var ok: bool = await _drive_to([Vector2(door.x, door.z), Vector2(apron.x, apron.z)], 1.0, 60.0, false)
	var scan_spot: Vector2 = _park_point() - APPROACH * 12.0
	ok = ok and await _drive_to([scan_spot], 2.4, 150.0, true)
	_check("drive: out of the bay and to 12 m from Kite", ok, "at (%.1f, %.1f)" % [rover.global_position.x, rover.global_position.z])

	# 4. Scan
	rover.get_node("CameraRig")._switch(MAST)
	_aim_mast_at(kite.global_position + Vector3.UP * 0.35)
	await _ticks(0.2)
	var e_picked: bool = false
	# Rules: E in the mast view does nothing to loose things on the Moon
	var loose: RigidBody3D = load("res://src/robot/socket/motor_part.tscn").instantiate()
	level.add_child(loose)
	loose.global_position = rover.camera.global_position - rover.camera.global_basis.z * 1.2
	await _ticks(0.1)
	_press_e()
	await _ticks(0.2)
	e_picked = rover.holder.held_object != null
	loose.queue_free()
	_check("rules: the rover's mast camera picks nothing up on the Moon", not e_picked and not rover.pickup_enabled)
	_aim_mast_at(kite.global_position + Vector3.UP * 0.35)
	await _ticks(2.0)
	_check("scan: the mast camera held on Kite scans it, once", kite.is_scanned and events.get("scanned", 0) == 1,
		"scanned %s, %d events" % [kite.is_scanned, events.get("scanned", 0)])
	rover.controller.camera_azimuth = 0.0
	rover.controller.camera_altitude = 0.0

	# 5. Park
	var park: Vector2 = _park_point()
	ok = await _drive_to([park - APPROACH * 3.0, park], 0.6, 60.0, true)
	await _ticks(1.0)
	await _creep_into_window()
	var m: Dictionary = delivery.measure(kite.port)
	_check("park: in the delivery window, the hint says so", ok and delivery.ready_for(kite.port)
		and delivery.get_hint().begins_with("In position"), "d %.2f m, bearing %+.1f, hint \"%s\"" % [m["d"], m["bearing"], delivery.get_hint()])

	# 6. Interrupted insert
	watching_arm = true
	_press_e()
	await _ticks(2.5)
	var started: bool = delivery.is_busy()
	Input.action_press("move_forward", 0.4)
	await _ticks(0.3)
	Input.action_release("move_forward")
	for k in 60:
		if not delivery.is_busy():
			break
		await _ticks(0.25)
	await _ticks(0.5)
	_check("interrupted: throttle mid-delivery aborts it, the cartridge is back on the mount",
		started and events.get("aborted", 0) == 1 and socket.part == cartridge and not delivery.is_busy(),
		"started %s, aborted %d, on the mount %s" % [started, events.get("aborted", 0), socket.part == cartridge])
	_check("interrupted: the arm is stowed again", rover.get_node("Visuals").arm_joints == rover.get_node("Visuals").ARM_STOWED)

	# Back into the window if the nudge moved it out
	await _creep_into_window()

	# 7. Insert
	_press_e()
	var waited: float = 0.0
	while events.get("kite_inserted", 0) == 0 and waited < 30.0:
		await _ticks(0.25)
		waited += 0.25
	for k in 60:
		if not delivery.is_busy():
			break
		await _ticks(0.25)
	watching_arm = false
	var seat: Node3D = kite.port.seat
	var seated: float = cartridge.global_position.distance_to(seat.global_position) if is_instance_valid(cartridge) else INF
	_check("insert: the cartridge sits on Kite's seat", kite.port.occupant == cartridge and seated < 0.005, "%.1f mm off" % (seated * 1000.0))
	_check("insert: cargo_inserted, then Kite's cartridge_inserted, once each",
		events.get("cargo_inserted", 0) == 1 and events.get("kite_inserted", 0) == 1 and events.get("finished", 0) == 1,
		"%s" % events)
	_check("insert: Kite's light is green, the cargo mount empty, the arm stowed", kite.has_cartridge and socket.part == null
		and rover.get_node("Visuals").arm_joints == rover.get_node("Visuals").ARM_STOWED)
	_check("arm: 20 mm or more above the terrain throughout", arm_lowest >= 0.02, "lowest %.0f mm" % (arm_lowest * 1000.0))
	_check("arm: never inside Kite", arm_in_kite == 0, "%d sampled points inside %s" % [arm_in_kite, inside_where])
	_check("the rover never touched Kite and stayed upright", not touched_kite and tilted < 15.0, "touched %s, tilt up to %.1f deg" % [touched_kite, tilted])

	# 8. The test level keeps its sandbox rules
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.5)
	kite = null
	SL.load_scene("test_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "test_level"):
		await physics_frame
	await _ticks(2.0)
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	player = GS.player
	await _aim_player_at_rover(player)
	player._on_controller_interact(true)
	await _ticks(0.3)
	_check("test level: the player can still lift a rover", player.holder.held_object == rover)
	player.holder.release()
	await _ticks(1.5)
	level._on_robot_trigger_interacted(player, rover)
	await _ticks(0.3)
	rover.get_node("CameraRig")._switch(MAST)
	# Look away from the level's "Drive Robot" trigger box (the mast ray sees areas)
	var away: Vector3 = rover.global_position - level.get_node("ReadyRoverTrigger").global_position
	away.y = 0.0
	_aim_mast_at(rover.camera.global_position + away.normalized() + Vector3.DOWN * 0.35)
	await _ticks(0.3)
	loose = load("res://src/robot/socket/motor_part.tscn").instantiate()
	level.add_child(loose)
	loose.global_position = rover.camera.global_position - rover.camera.global_basis.z * 1.0
	await _ticks(0.1)
	_press_e()
	await _ticks(0.3)
	_check("test level: the rover's mast camera still picks a part up", rover.holder.held_object == loose,
		"driven %s, aiming %s, ray hits %s, holding %s" % [rover.is_driven(), rover.is_aiming(),
		rover.raycast.get_collider() if rover.raycast.is_colliding() else null, rover.holder.held_object])
	print("RESULT %s" % ("ALL PASS" if failures == 0 else "%d CHECKS FAILED" % failures))
	quit(1 if failures else 0)
