extends SceneTree
## The level's CSG collision is a surface mesh, so a shape wholly inside it doesn't overlap
## it; each check therefore also compares the wheel's bottom with the terrain top under it.
##
## Headless test: drives the assembled rover in the test level onto the ramp (from the front
## and onto its side edge), over a 20 cm kerb and across the see-saw, and checks every wheel on
## every physics tick:
##   - "touching but airborne": a cylinder the size of the wheel, 5 mm below the physics wheel
##     position, overlaps the ground (the wheel is within 5 mm of standing on something), but
##     the wheel is reported out of contact
##   - "inside terrain": a wheel reported in contact whose physics position is more than 1 cm
##     inside the terrain (it found a surface below the one it is actually on)
##   - "mesh in ground": the visible wheel (1 cm smaller) overlaps the ground
## Prints one line per scenario and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_wheel_contact.gd

const GROUND_MASK: int = 1 | 4
const WHEEL_RADIUS: float = 0.15
const WHEEL_WIDTH: float = 0.24
const TOUCH_MARGIN: float = 0.005
const MESH_MARGIN: float = 0.01
const WHEEL_NAMES: Array[String] = ["FL", "FR", "RL", "RR", "ML", "MR"]

var level: Node
var rover: RigidBody3D
var GS: Node
var t := 0.0
var scenario := -1
var scenario_t := 0.0
var stats := {}
var failures := 0
var scenarios: Array = []
var _shape := CylinderShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())


func _ground_height(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 10.0, z), Vector3(x, -1.0, z), GROUND_MASK)
	q.exclude = [rover.get_rid()]
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y if hit else 0.0


func _setup_scenarios() -> void:
	var space := rover.get_world_3d().direct_space_state
	# The ramp: highest at x 0, ground at x 6; find which way its depth runs from z -5
	var z_mid: float = -6.5 if _ground_height(space, 3.0, -6.5) > 1.0 else -3.5
	var side_z: float = -5.0
	var approach_from: float = 1.0 if z_mid < -5.0 else -1.0   # approach the side face from outside
	# See-saw: the plank (6 m along X, hinge 1 m up) rests level; tip it so its +X end is on
	# the ground, like a ramp, then find where it is 12 cm up
	var plank := level.get_node("SeeSaw/RigidBody3D6") as RigidBody3D
	var tip := asin(1.0 / 3.0)
	plank.global_transform = Transform3D(Basis(Vector3.BACK, -tip), Vector3(0.0, 1.0, 0.0))
	plank.linear_velocity = Vector3.ZERO
	plank.angular_velocity = Vector3.ZERO
	var plank_h_left := _ground_height(space, -2.6, 0.0)
	var plank_h_right := _ground_height(space, 2.6, 0.0)
	var low_sign: float = -1.0 if plank_h_left < plank_h_right else 1.0
	var cross_x: float = 0.0
	for i in 60:
		var x := low_sign * (3.0 - i * 0.05)
		if _ground_height(space, x, 0.0) >= 0.12:
			cross_x = x
			break
	scenarios = [
		# name, start position, yaw (degrees; 0 = facing -Z, 90 = facing -X), throttle, seconds, extra setup
		["ramp, front (up the slope)", Vector3(9.0, 0.3, z_mid), 90.0, 1.0, 6.0, ""],
		["ramp, side edge (left wheels)", Vector3(6.0, 0.3, side_z + approach_from * 2.0), 0.0 if approach_from > 0.0 else 180.0, 0.6, 5.0, ""],
		["20 cm kerb", Vector3(30.0, 0.3, 8.0), 0.0, 0.7, 5.0, "kerb"],
		["see-saw, across the low end", Vector3(cross_x, 0.3, 2.5), 0.0, 0.6, 5.0, ""],
	]
	print("INFO ramp depth runs to z %.1f; side face at z %.1f; see-saw low end at x %+.0f, crossing at x %.2f (plank %.2f m up)" % [
		z_mid, side_z, low_sign * 3.0, cross_x, _ground_height(space, cross_x, 0.0)])


func _start_scenario(index: int) -> void:
	scenario = index
	scenario_t = 0.0
	stats = {"ticks": 0, "touching_airborne": 0, "inside_terrain": 0, "mesh_in_ground": 0, "worst_mesh": 0.0, "examples": [], "max_compression_seen": 0.0}
	var s: Array = scenarios[index]
	if s[5] == "kerb":
		var kerb := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 0.2, 0.6)
		shape.shape = box
		kerb.add_child(shape)
		level.add_child(kerb)
		kerb.global_position = Vector3(s[1].x, 0.1, s[1].z - 3.0)
	for a in ["move_forward", "move_left", "move_right"]:
		Input.action_release(a)
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	rover.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(s[2])), s[1])
	Input.action_press("move_forward", s[3])


func _wheel_shape_hits(space: PhysicsDirectSpaceState3D, centre: Vector3, axle: Vector3, radius: float, width: float) -> Array:
	_shape.radius = radius
	_shape.height = width
	var forward := axle.cross(Vector3.UP)
	if forward.length() < 0.1:
		forward = axle.cross(Vector3.FORWARD)
	forward = forward.normalized()
	var up := forward.cross(axle).normalized()
	_query.shape = _shape
	# Columns: X = forward, Y = axle (the cylinder's axis), Z = up (right-handed)
	_query.transform = Transform3D(Basis(forward, axle.normalized(), up), centre)
	_query.collision_mask = GROUND_MASK
	_query.exclude = [rover.get_rid()]
	return space.intersect_shape(_query, 4)


# How far the lowest point of a wheel is below the terrain top under its centre (positive =
# into the terrain), from a ray down from 0.5 m above the wheel (so overhangs don't count)
func _depth_below_terrain(space: PhysicsDirectSpaceState3D, centre: Vector3, radius: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(centre + Vector3.UP * 0.5, centre + Vector3.DOWN * 1.0, GROUND_MASK)
	q.exclude = [rover.get_rid()]
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y - (centre.y - radius) if hit else -INF


func _check_tick() -> void:
	var space := rover.get_world_3d().direct_space_state
	var gear = rover.running_gear
	stats["ticks"] += 1
	for wheel in gear.wheel_states:
		var state: Dictionary = gear.wheel_states[wheel]
		var steer: float = gear.get_steer_angle(wheel, rover.controller.steer)
		var axle: Vector3 = (rover.global_basis * Vector3.RIGHT.rotated(Vector3.UP, steer)).normalized()
		var centre: Vector3 = rover.to_global(rover.wheel_centers[wheel])
		var below: Vector3 = centre - rover.global_basis.y * TOUCH_MARGIN
		var touching: bool = (
			not _wheel_shape_hits(space, below, axle, WHEEL_RADIUS, WHEEL_WIDTH).is_empty()
			or _depth_below_terrain(space, centre, WHEEL_RADIUS) > -TOUCH_MARGIN
		)
		if state[3] and _depth_below_terrain(space, centre, WHEEL_RADIUS) > MESH_MARGIN:
			stats["inside_terrain"] += 1
		if touching and not state[3]:
			stats["touching_airborne"] += 1
			if stats["examples"].size() < 3:
				# Where would the old suspension ray (4 cm above the attachment point) have started?
				var attach: Vector3 = rover.to_global(gear.wheel_properties[wheel][0])
				var ray_start: Vector3 = attach + rover.global_basis.y * 0.04
				var terrain: float = _ground_height(space, ray_start.x, ray_start.z)
				stats["examples"].append("%s at t %.2f: the old suspension ray would start %.0f mm %s the terrain top" % [
					WHEEL_NAMES[wheel], scenario_t, absf(ray_start.y - terrain) * 1000.0, "below (inside)" if ray_start.y < terrain else "above"])
		var socket = rover.wheel_sockets[wheel]
		if socket and socket.part:
			var part: Node3D = socket.part
			var part_axle: Vector3 = (part.global_basis * Vector3.RIGHT).normalized()
			var hits := _wheel_shape_hits(space, part.global_position, part_axle, WHEEL_RADIUS - MESH_MARGIN, WHEEL_WIDTH - 2.0 * MESH_MARGIN)
			var sunk: float = _depth_below_terrain(space, part.global_position, WHEEL_RADIUS)
			if not hits.is_empty() or sunk > MESH_MARGIN:
				stats["mesh_in_ground"] += 1
				# How deep: shrink until it no longer overlaps
				var depth := MESH_MARGIN
				while depth < 0.14 and not _wheel_shape_hits(space, part.global_position, part_axle, WHEEL_RADIUS - depth, WHEEL_WIDTH - 2.0 * MESH_MARGIN).is_empty():
					depth += 0.005
				stats["worst_mesh"] = maxf(stats["worst_mesh"], maxf(depth, sunk))


func _finish_scenario() -> void:
	var s: Array = scenarios[scenario]
	var ok: bool = stats["touching_airborne"] == 0 and stats["inside_terrain"] == 0 and stats["mesh_in_ground"] == 0
	failures += 0 if ok else 1
	print("RESULT %-30s %s  ticks %d, touching-but-airborne %d, in contact but inside terrain %d, wheel mesh in ground %d (deepest %.0f mm); rover ended at %s, upright %s" % [
		s[0], "PASS" if ok else "FAIL", stats["ticks"], stats["touching_airborne"], stats["inside_terrain"], stats["mesh_in_ground"], stats["worst_mesh"] * 1000.0,
		rover.global_position.snapped(Vector3.ONE * 0.01), rover.global_basis.y.y > 0.7])
	for e in stats["examples"]:
		print("        e.g. " + e)


func _physics_process(delta: float) -> bool:
	GS = root.get_node("GameState")
	var SL = root.get_node("SceneLoader")
	if GS.state == GS.State.MAIN_MENU and not has_meta("requested"):
		set_meta("requested", true)
		SL.load_scene("test_level")
	if level == null:
		if GS.state == GS.State.IN_GAME_PLAYER and SL.current_scene:
			level = SL.current_scene
			rover = level.get_node("ReadyRover")
		return false
	t += delta
	if t < 1.0:
		return false
	if scenario < 0:
		if not has_meta("tipped"):
			set_meta("tipped", true)
			var plank := level.get_node("SeeSaw/RigidBody3D6") as RigidBody3D
			plank.global_transform = Transform3D(Basis(Vector3.BACK, -asin(1.0 / 3.0)), Vector3(0.0, 1.0, 0.0))
			return false
		GS.drive(rover)
		_setup_scenarios()
		_start_scenario(0)
		return false
	scenario_t += delta
	if scenario_t > 0.2:  # let the teleport settle
		_check_tick()
	if scenario_t > scenarios[scenario][4]:
		_finish_scenario()
		if scenario + 1 < scenarios.size():
			_start_scenario(scenario + 1)
		else:
			Input.action_release("move_forward")
			print("RESULT %s" % ("ALL PASS" if failures == 0 else "%d SCENARIOS FAILED" % failures))
			return true
	return false
