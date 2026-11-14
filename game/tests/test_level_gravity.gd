extends SceneTree
## Headless test: per-level gravity, and what lunar gravity does to the rover and the player.
##   1. Each level gets its own gravity: test level 9.8, Moon 1.62, back to 9.8 on the test
##      level and the main menu (the world's physics space, the player's and the rover's
##      get_gravity()).
##   2. On a flat floor over the Moon level, the same runs under 9.8 and under 1.62 m/s^2 (the
##      Earth run sets the space's gravity directly and puts the rover scene's own suspension
##      back, so only gravity and the level's rover suspension differ):
##        rover: ride height, straight runs, stops, a turn, and climbing a 26.6 degree wedge
##        (like the test level's ramp) with a 3 m run-up and from a standstill on the slope;
##        player: jump height and time in the air, walking speed and the distance to stop.
##      Full throttle and 30% throttle straight runs (top speed, heading drift with no steering);
##      from the 30% speed, coasting and full-reverse stops and a full-lock turn.
##      Prints a MEASURE line per value; the checks are what physics says must hold (speed and
##      walking speed don't depend on gravity, the jump keeps its take-off speed, the Moon
##      rover climbs the slope the Earth one can't hold from a standstill).
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_level_gravity.gd
##     (append `-- no_traction_control` to measure the rover without traction control)

const TICKS: int = 240
const MOON: float = 1.62
const EARTH: float = 9.8
# The test level's player settings (RoverLevel's defaults), used for the Earth runs on the Moon
# ground; the Moon runs use the Moon level's own
const EARTH_PLAYER: Dictionary = {"jump_height": 0.8, "ground_friction": 0.5}
# The Moon level has real terrain now: the runs use a flat floor (2 x 2 km, top at FLOOR) that the
# test builds over it (the ground within 1.1 km of the origin is under 240 m), in the same level, so
# the level's gravity and player settings apply. Not far away: a float position 5 km out moves in
# 0.5 mm steps, and a rover settling slower than 0.06 m/s stalled there, 3-4 mm off its rest height
const FLOOR := Vector3(0.0, 300.0, 0.0)
const ROVER_START := FLOOR + Vector3(-120.0, 0.35, 60.0)
const PLAYER_START := FLOOR + Vector3(-60.0, 1.0, 40.0)
const RAMP_ORIGIN := FLOOR + Vector3(-180.0, 0.0, 0.0)
const RAMP_LENGTH: float = 6.0
const RAMP_HEIGHT: float = 3.0   # atan(3 / 6) = 26.6 degrees

var GS: Node
var SL: Node
var failures := 0
var results: Dictionary = {}   # "<name>@<g>" -> value


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-60s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _measure(name: String, g: float, value: float, unit: String) -> void:
	results["%s@%s" % [name, g]] = value
	print("MEASURE g %-5.2f %-40s %8.2f %s" % [g, name, value, unit])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _space_gravity() -> float:
	return PhysicsServer3D.area_get_param(root.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY)


func _set_space_gravity(g: float) -> void:
	PhysicsServer3D.area_set_param(root.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, g)


func _load(level_id: String, state: int) -> void:
	SL.load_scene(level_id)
	while not (GS.state == state and (level_id == "main_menu" or SL.current_level_id == level_id)):
		await physics_frame
	await _ticks(0.5)


func _check_gravity(tag: String, expected: float) -> void:
	var ok: bool = absf(_space_gravity() - expected) < 0.001
	var detail: String = "space %.2f" % _space_gravity()
	if GS.player:
		ok = ok and absf(GS.player.gravity - expected) < 0.001
		detail += ", player %.2f" % GS.player.gravity
	var rovers: Array = root.find_children("*", "Robot", true, false)
	for rover in rovers:
		ok = ok and absf(rover.get_gravity().length() - expected) < 0.001
	detail += ", %d rovers" % rovers.size()
	_check("%s gravity %.2f" % [tag, expected], ok, detail)


func _release_all() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right", "move_jump"]:
		Input.action_release(action)


# --- Rover ----------------------------------------------------------------------------------

func _place_rover(rover: RigidBody3D, at: Vector3, heading: float = 0.0) -> void:
	_release_all()
	_teleport(rover, Transform3D(Basis(Vector3.UP, heading), at))
	await _ticks(2.0)   # settle


# At rest, wheels stopped too (RunningGear.WheelState.ANGULAR_VELOCITY = 0), so one run's wheel
# spin can't carry into the next
func _teleport(rover: RigidBody3D, to: Transform3D) -> void:
	rover.global_transform = to
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	for wheel in rover.running_gear.wheel_states:
		rover.running_gear.wheel_states[wheel][0] = 0.0


func _forward_speed(rover: RigidBody3D) -> float:
	return rover.linear_velocity.dot(-rover.global_basis.z)


# Straight run from rest at `throttle`: top forward speed, time to 90% of it, and how far the
# heading wanders with no steering input (wheelspin takes the tyres' sideways grip)
func _straight_run(rover: RigidBody3D, g: float, throttle: float, seconds: float) -> void:
	var tag: String = "%d%% throttle" % roundi(throttle * 100.0)
	await _place_rover(rover, ROVER_START)
	var heading0: float = rover.global_rotation.y
	Input.action_press("move_forward", throttle)
	var speeds: Array[float] = []
	var drift := 0.0
	for i in int(seconds * TICKS):
		await physics_frame
		speeds.append(_forward_speed(rover))
		drift = maxf(drift, absf(angle_difference(heading0, rover.global_rotation.y)))
	var top: float = speeds.max()
	var t90 := 0.0
	for i in speeds.size():
		if speeds[i] >= 0.9 * top:
			t90 = float(i) / TICKS
			break
	_measure(tag + ": top forward speed", g, top, "m/s")
	_measure(tag + ": time to 90% of it", g, t90, "s")
	_measure(tag + ": heading drift, no steering", g, rad_to_deg(drift), "deg")


func _measure_rover(rover: RigidBody3D, g: float) -> void:
	_set_space_gravity(g)
	await _place_rover(rover, ROVER_START)
	# Ride height: the body's origin above the ground at rest
	_measure("rover ride height (body origin)", g, (rover.global_position.y - FLOOR.y) * 100.0, "cm")

	await _straight_run(rover, g, 1.0, 12.0)
	await _straight_run(rover, g, 0.3, 8.0)   # leaves the rover at a steady 30% speed

	# From that steady speed: throttle released, coast (back-EMF, rolling drag) to a stop
	Input.action_release("move_forward")
	var start: Vector3 = rover.global_position
	var t := 0.0
	while _forward_speed(rover) > 0.05 and t < 30.0:
		await physics_frame
		t += 1.0 / TICKS
	_measure("from 30%: coast to stop, distance", g, rover.global_position.distance_to(start), "m")

	# From the same speed: full reverse until it stops
	await _straight_run(rover, g, 0.3, 8.0)
	var v0: float = _forward_speed(rover)
	Input.action_release("move_forward")
	Input.action_press("move_backward")
	start = rover.global_position
	t = 0.0
	while _forward_speed(rover) > 0.0 and t < 30.0:
		await physics_frame
		t += 1.0 / TICKS
	Input.action_release("move_backward")
	_measure("from 30%: full reverse, stop distance", g, rover.global_position.distance_to(start), "m")
	_measure("from 30%: full reverse, deceleration", g, v0 / maxf(t, 0.001), "m/s^2")

	# Full lock at 30% throttle: steady turn
	await _place_rover(rover, ROVER_START)
	Input.action_press("move_forward", 0.3)
	Input.action_press("move_right")
	await _ticks(8.0)
	var v: float = 0.0
	var w: float = 0.0
	var samples: int = TICKS * 2
	for i in samples:
		await physics_frame
		v += Vector2(rover.linear_velocity.x, rover.linear_velocity.z).length() / samples
		w += absf(rover.angular_velocity.y) / samples
	_release_all()
	_measure("30% full-lock turn: speed", g, v, "m/s")
	_measure("30% full-lock turn: radius", g, v / maxf(w, 0.001), "m")
	_measure("30% full-lock turn: lateral acceleration / g", g, v * w / g, "")

	# Ramp: 3 m run-up, full throttle, how high it gets (3.0 + ride height = on top)
	await _place_rover(rover, RAMP_ORIGIN + Vector3(0.0, 0.35, 3.0))
	Input.action_press("move_forward")
	var highest := 0.0
	for i in 12 * TICKS:
		await physics_frame
		highest = maxf(highest, rover.global_position.y - FLOOR.y)
	_release_all()
	_measure("ramp, 3 m run-up: highest (top 3.0)", g, highest, "m")

	# Ramp from a standstill 1 m up the slope, nose up: parked 1 s with no throttle, then full
	var slope: float = atan(RAMP_HEIGHT / RAMP_LENGTH)
	var up_slope := Basis(Vector3.RIGHT, slope)
	var on_slope: Vector3 = RAMP_ORIGIN + Vector3(0.0, 1.0, -1.0 / tan(slope)) + up_slope.y * 0.12
	_teleport(rover, Transform3D(up_slope, on_slope))
	await _ticks(0.3)
	var settled: Vector3 = rover.global_position
	await _ticks(1.0)
	_measure("ramp, parked 1 s without throttle: rolled back", g, settled.distance_to(rover.global_position), "m")
	Input.action_press("move_forward")
	highest = 0.0
	for i in 12 * TICKS:
		await physics_frame
		highest = maxf(highest, rover.global_position.y - FLOOR.y)
	_release_all()
	_measure("ramp from standstill 1 m up: highest (top 3.0)", g, highest, "m")


# --- Player ---------------------------------------------------------------------------------

func _measure_player(player: RigidBody3D, g: float, settings: Dictionary) -> void:
	_set_space_gravity(g)
	for property in settings:
		player.set(property, settings[property])
	_release_all()
	player.global_position = PLAYER_START
	player.linear_velocity = Vector3.ZERO
	await _ticks(3.0)
	var rest_y: float = player.global_position.y

	# Jump from rest
	Input.action_press("move_jump")
	await _ticks(0.05)
	Input.action_release("move_jump")
	var apex: float = rest_y
	var t := 0.0
	var left_ground := false
	while t < 15.0:
		await physics_frame
		t += 1.0 / TICKS
		apex = maxf(apex, player.global_position.y)
		if player.global_position.y > rest_y + 0.05:
			left_ground = true
		elif left_ground and player.is_on_floor:
			break
	_measure("player jump height", g, apex - rest_y, "m")
	_measure("player time in the air", g, t, "s")
	await _ticks(1.0)

	# Walk 3 s, then let go: speed and the distance to stop
	Input.action_press("move_forward")
	await _ticks(3.0)
	var speed: float = Vector2(player.linear_velocity.x, player.linear_velocity.z).length()
	Input.action_release("move_forward")
	var start: Vector3 = player.global_position
	t = 0.0
	while Vector2(player.linear_velocity.x, player.linear_velocity.z).length() > 0.05 and t < 15.0:
		await physics_frame
		t += 1.0 / TICKS
	_measure("player walking speed", g, speed, "m/s")
	_measure("player stop after letting go: time", g, t, "s")
	_measure("player stop after letting go: distance", g, Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length(), "m")


func _add_floor(level: Node) -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000.0, 1.0, 2000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	level.add_child(floor_body)
	floor_body.global_position = FLOOR


func _add_ramp(level: Node) -> void:
	var ramp := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var wedge := ConvexPolygonShape3D.new()
	# 10 m wide, with a 6 m flat top behind the slope
	wedge.points = PackedVector3Array([
		Vector3(-5.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0),
		Vector3(-5.0, 0.0, -RAMP_LENGTH - 6.0), Vector3(5.0, 0.0, -RAMP_LENGTH - 6.0),
		Vector3(-5.0, RAMP_HEIGHT, -RAMP_LENGTH), Vector3(5.0, RAMP_HEIGHT, -RAMP_LENGTH),
		Vector3(-5.0, RAMP_HEIGHT, -RAMP_LENGTH - 6.0), Vector3(5.0, RAMP_HEIGHT, -RAMP_LENGTH - 6.0)])
	shape.shape = wedge
	ramp.add_child(shape)
	level.add_child(ramp)
	ramp.global_position = RAMP_ORIGIN


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	_check_gravity("main menu", EARTH)
	await _load("test_level", GS.State.IN_GAME_PLAYER)
	_check_gravity("test level", EARTH)
	await _load("moon_level", GS.State.IN_GAME_PLAYER)
	_check_gravity("Moon level", MOON)

	var level: Node = SL.current_scene
	_add_floor(level)
	_add_ramp(level)
	var moon_player: Dictionary = {}
	for property in EARTH_PLAYER:
		moon_player[property] = level.get(property)
	_check("Moon level's player settings reach the player", moon_player.keys().all(func(p): return GS.player.get(p) == moon_player[p]), str(moon_player))
	await _measure_player(GS.player, EARTH, EARTH_PLAYER)
	await _measure_player(GS.player, MOON, moon_player)
	var rover: RigidBody3D = level.get_node("ReadyRover")
	# `-- no_traction_control` measures the rover without it, for comparison
	if "no_traction_control" in OS.get_cmdline_user_args():
		rover.traction_control = false
	GS.drive(rover)
	await _ticks(0.5)
	# Each run with its own suspension: the rover scene's (tuned for Earth) under Earth gravity,
	# the Moon level's (RoverLevel.rover_suspension) under the Moon's
	for g in [EARTH, MOON]:
		rover.apply_suspension({} if g == EARTH else level.rover_suspension)
		await _measure_rover(rover, g)
	_set_space_gravity(MOON)

	# What must hold whatever the tuning: speeds that don't depend on gravity, the jump's
	# take-off speed, and the slope the motors couldn't hold on Earth being easy on the Moon.
	# The rest (wheelspin, braking, cornering) is reported above as MEASURE lines.
	var r := results
	_check("Moon rover rides at Earth's height (the level's suspension, within 5 mm)",
		absf(r["rover ride height (body origin)@%s" % MOON] - r["rover ride height (body origin)@%s" % EARTH]) < 0.5,
		"%.1f cm, Earth %.1f" % [r["rover ride height (body origin)@%s" % MOON], r["rover ride height (body origin)@%s" % EARTH]])
	_check("30% throttle top speed doesn't depend on gravity (within 10%)",
		absf(r["30%% throttle: top forward speed@%s" % MOON] / r["30%% throttle: top forward speed@%s" % EARTH] - 1.0) < 0.1)
	if rover.traction_control:
		_check("Moon full throttle: traction control keeps 85% of Earth's top speed",
			r["100%% throttle: top forward speed@%s" % MOON] > 0.85 * r["100%% throttle: top forward speed@%s" % EARTH],
			"%.2f m/s" % r["100%% throttle: top forward speed@%s" % MOON])
		_check("Moon full throttle: goes straight (drift under 1 deg, as test_straight_line.gd)",
			r["100%% throttle: heading drift, no steering@%s" % MOON] < 1.0,
			"%.2f deg" % r["100%% throttle: heading drift, no steering@%s" % MOON])
		_check("Moon rover climbs the ramp with a run-up", r["ramp, 3 m run-up: highest (top 3.0)@%s" % MOON] > 3.0)
	_check("Moon rover climbs the ramp from a standstill",
		r["ramp from standstill 1 m up: highest (top 3.0)@%s" % MOON] > 3.0)
	_check("Earth jump is JUMP_HEIGHT (0.8 m)", absf(r["player jump height@%s" % EARTH] - 0.8) < 0.1,
		"%.2f m" % r["player jump height@%s" % EARTH])
	_check("Moon jump capped at the level's 1.2 m (+-0.15)",
		absf(r["player jump height@%s" % MOON] - 1.2) < 0.15, "%.2f m" % r["player jump height@%s" % MOON])
	_check("Moon jump still floaty: over 2 s in the air (Earth 0.8 s)",
		r["player time in the air@%s" % MOON] > 2.0, "%.2f s" % r["player time in the air@%s" % MOON])
	_check("Earth walk stops in 0.4 m (+-0.05)", absf(r["player stop after letting go: distance@%s" % EARTH] - 0.4) < 0.05,
		"%.2f m" % r["player stop after letting go: distance@%s" % EARTH])
	_check("Moon walk stops within 1 m (level ground friction)", r["player stop after letting go: distance@%s" % MOON] < 1.0,
		"%.2f m" % r["player stop after letting go: distance@%s" % MOON])
	_check("walking speed doesn't depend on gravity (within 5%)",
		absf(r["player walking speed@%s" % MOON] / r["player walking speed@%s" % EARTH] - 1.0) < 0.05)

	await _load("test_level", GS.State.IN_GAME_PLAYER)
	_check_gravity("test level again", EARTH)
	await _load("main_menu", GS.State.MAIN_MENU)
	_check_gravity("main menu again", EARTH)
	print("RESULT %s" % ("ALL PASS" if failures == 0 else "%d CHECKS FAILED" % failures))
	quit()
