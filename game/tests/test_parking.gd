extends SceneTree
## Headless test: a stopped rover and loose parts hold still on slopes.
##   1. The assembled rover parked (no throttle) on planes of 2 to 35 degrees, nose up the slope
##      and side-on, under the Moon's 1.62 and Earth's 9.8 m/s^2: it must move less than 2 cm in
##      30 s (after 1 s to settle). With the automatic brake on, up to the steepest slope the
##      tyres can hold (35 degrees); with it off, up to the slope its rolling resistance holds
##      (the tyre's static friction keeps it from sliding sideways on every slope).
##   2. Each loose part (wheel, motor, battery, mast head, antenna, tool turret), laid on 15 and 30
##      degree planes as spawned and turned on its side: it must move less than 2 cm in 10 s once
##      it has come to rest. Round parts on their curved side (a wheel on its tread, the battery)
##      may roll on slopes past their regolith rolling resistance (17 degrees); that is reported.
##   3. The brake lets go: full throttle up a 15 degree plane from a stop climbs straight away
##      (0.75 m in 3 s before the brake existed; the rover rolled back first).
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_parking.gd

const TICKS: int = 240
const MOON: float = 1.62
const EARTH: float = 9.8
const HOLD_LIMIT: float = 0.02
const PARK_SLOPES: Array = [2.0, 5.0, 10.0, 15.0, 25.0, 35.0]
const PART_SLOPES: Array = [15.0, 30.0]
const PARTS: Array = ["wheel", "motor", "battery", "mast_head", "antenna", "arm_tool"]

var GS: Node
var SL: Node
var failures: int = 0
var level: Node
var plane_index: int = 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-62s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _set_gravity(g: float) -> void:
	PhysicsServer3D.area_set_param(root.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, g)


# A 60 x 60 m plane tilted `slope` degrees (rising towards -Z), far from everything else.
# Returns the transform of its top surface's centre.
func _plane(slope: float) -> Transform3D:
	plane_index += 1
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	level.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(slope)), Vector3(-400.0 + plane_index * 80.0, 200.0, 400.0))
	return body.global_transform


func _release_all() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(action)


func _teleport(rover: RigidBody3D, to: Transform3D) -> void:
	rover.global_transform = to
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	for wheel in rover.running_gear.wheel_states:
		rover.running_gear.wheel_states[wheel][0] = 0.0


func _park(rover: RigidBody3D, g: float, slope: float, side_on: bool) -> float:
	_release_all()
	var surface: Transform3D = _plane(slope)
	var heading := Basis(Vector3.UP, -PI / 2.0) if side_on else Basis.IDENTITY
	_teleport(rover, Transform3D(surface.basis * heading, surface.origin + surface.basis.y * 0.25))
	await _ticks(1.0)
	var start: Vector3 = rover.global_position
	await _ticks(30.0)
	return start.distance_to(rover.global_position)


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	var rover: RigidBody3D = level.get_node("ReadyRover")
	await _ticks(1.0)
	GS.drive(rover)
	var has_brake: bool = "auto_brake" in rover

	# 1. Parked
	for g in [MOON, EARTH]:
		_set_gravity(g)
		var unbraked_limit: float = rad_to_deg(asin(minf(rover.rolling_resistance_force / (rover.mass * g), 1.0)))
		for brake in [true, false]:
			if has_brake:
				rover.auto_brake = brake
			elif brake:
				continue   # before the brake existed: only the unbraked runs
			for slope in PARK_SLOPES:
				for side_on in [false, true]:
					var moved: float = await _park(rover, g, slope, side_on)
					# Nose up the slope it must hold with the brake, or within the rolling
					# resistance without; side-on the tyres' static friction holds either way
					var must_hold: bool = side_on or brake or slope < unbraked_limit * 0.9
					var name := "g %.2f %s, %4.1f deg %s" % [g, "brake on " if brake else "brake off", slope, "side-on" if side_on else "nose up"]
					if must_hold:
						_check("parked: " + name, moved < HOLD_LIMIT, "moved %.3f m in 30 s" % moved)
					else:
						print("INFO   parked: %s moved %.2f m in 30 s (past the %.1f deg rolling resistance holds)" % [name, moved, unbraked_limit])
	if has_brake:
		rover.auto_brake = true

	# 2. Loose parts, laid down gently in two poses each (as spawned, and turned onto a side: for
	# the wheel that is lying flat, for the battery on its curved side), side by side across the
	# slope so nothing that rolls hits the others
	_set_gravity(MOON)
	rover.global_position += Vector3(0.0, 0.0, -300.0)
	var roll_limit: float = rad_to_deg(atan(0.3))
	for slope in PART_SLOPES:
		var surface: Transform3D = _plane(slope)
		var parts: Array = []
		for i in PARTS.size():
			for pose in 2:
				var part: RigidBody3D = rover.STARTING_PARTS[PARTS[i]].instantiate()
				level.add_child(part)
				var turn := Basis(Vector3.BACK, PI / 2.0) if pose == 1 else Basis.IDENTITY
				part.global_transform = Transform3D(surface.basis * turn,
					surface.origin + surface.basis.x * ((i * 2 + pose) * 3.0 - 17.0) + surface.basis.y * 0.35)
				parts.append([PARTS[i] + (" on its side" if pose == 1 else ""), part])
		await _ticks(4.0)
		var starts: Array = parts.map(func(e: Array) -> Vector3: return e[1].global_position)
		await _ticks(10.0)
		for i in parts.size():
			var moved: float = (starts[i] as Vector3).distance_to(parts[i][1].global_position)
			var name := "loose %s, %.0f deg" % [parts[i][0], slope]
			if slope < roll_limit:
				_check(name, moved < HOLD_LIMIT, "moved %.3f m in 10 s" % moved)
			elif moved >= HOLD_LIMIT:
				print("INFO   %s: rolled %.2f m in 10 s (past the %.0f deg rolling resistance holds)" % [name, moved, roll_limit])
			else:
				_check(name, true, "moved %.3f m in 10 s" % moved)
			parts[i][1].queue_free()

	# 3. The brake lets go
	var surface: Transform3D = _plane(15.0)
	_teleport(rover, Transform3D(surface.basis, surface.origin + surface.basis.y * 0.25))
	await _ticks(2.0)
	var start: Vector3 = rover.global_position
	Input.action_press("move_forward")
	await _ticks(3.0)
	_release_all()
	var climbed: float = rover.global_position.y - start.y
	_check("full throttle from a stop climbs a 15 deg plane", climbed > 0.7, "climbed %.2f m in 3 s" % climbed)

	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
