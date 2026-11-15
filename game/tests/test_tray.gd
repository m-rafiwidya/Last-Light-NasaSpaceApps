extends SceneTree
## Headless test: Kite's physical storage tray (loose parts ride in it with real physics).
##   1. Settle: two sample containers dropped in the tray come to rest inside it, no jitter.
##   2. Careful: driving off gently, cruising at 1.2 m/s and stopping gently keeps both in.
##   3. Normal: 2.4 m/s with turns, then a normal stop, keeps both in.
##   4. Reckless: full throttle straight across the boulder field (not its cleared lane) and a
##      full-reverse stop throw at least one out (bumps do it: in lunar gravity Kite can't brake
##      harder than the parts' own friction holds them on flat ground).
##   5. Secured (set_secured, for a human carrying Kite): tilted 70 degrees the jars stay; released
##      they ride loose again.
## Prints how far the parts moved in the tray, for tuning the rim, friction and bounce.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_tray.gd

const TICKS: int = 240
const JAR: String = "res://src/robot/socket/sample_container_part.tscn"

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D
var tray: Node3D
var jars: Array = []


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


func _release_all() -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(a)


func _inside() -> int:
	var n: int = 0
	for jar in jars:
		if tray.holds(jar):
			n += 1
	return n


## Jars' positions in the tray's frame, for "how far did they move"
func _local() -> Array:
	return jars.map(func(j: Node3D) -> Vector3: return tray.to_local(j.global_position))


func _moved(before: Array) -> String:
	var after: Array = _local()
	var parts: Array = []
	for i in jars.size():
		parts.append("%.0f mm" % ((after[i] - before[i]).length() * 1000.0))
	return ", ".join(parts)


## Holds forward throttle `throttle` and steering `steer` (-1 left .. 1 right) for `seconds`
func _drive(throttle: float, steer: float, seconds: float) -> void:
	_release_all()
	if throttle > 0.0:
		Input.action_press("move_forward", throttle)
	elif throttle < 0.0:
		Input.action_press("move_backward", -throttle)
	if steer > 0.0:
		Input.action_press("move_right", steer)
	elif steer < 0.0:
		Input.action_press("move_left", -steer)
	await _ticks(seconds)
	_release_all()


## Throttle that holds about `speed` m/s for `seconds`
func _cruise(speed: float, steer: float, seconds: float) -> void:
	for i in int(seconds * TICKS):
		var v: float = rover.linear_velocity.dot(-rover.global_basis.z)
		_release_all()
		if v < speed:
			Input.action_press("move_forward", clampf(0.06 + (speed - v) * 0.3, 0.05, 0.5))
		if steer > 0.0:
			Input.action_press("move_right", steer)
		elif steer < 0.0:
			Input.action_press("move_left", -steer)
		await physics_frame
	_release_all()


func _stop_gently() -> void:
	_release_all()
	for i in 10 * TICKS:
		if rover.linear_velocity.length() < 0.05:
			break
		await physics_frame
	await _ticks(1.0)


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
	tray = rover.get_node("StorageBox")
	# Kite out on the apron, heading down the long route
	var routes: Node = level.get_node("RouteMarkers")
	var start: Vector2 = routes.start()
	var first: Vector2 = routes.route("long")[0]
	var look := Vector3(first.x - start.x, 0.0, first.y - start.y).normalized()
	rover.global_transform = Transform3D(Basis.looking_at(look), _ground(Vector3(start.x, 0.0, start.y)) + Vector3.UP * 0.4)
	rover.linear_velocity = Vector3.ZERO
	await _ticks(2.0)
	# Fitted after M1's start, which takes Kite's battery out (fitting it is the player's first task)
	var battery: Node = (load("res://src/robot/socket/battery_part.tscn") as PackedScene).instantiate()
	level.add_child(battery)
	battery.global_position = rover.battery_socket.global_position
	rover.battery_socket.mount(battery)
	GS.drive(rover)
	await _ticks(0.5)

	# 1. Settle
	for x in [-0.05, 0.05]:
		var jar: RigidBody3D = (load(JAR) as PackedScene).instantiate()
		level.add_child(jar)
		jar.global_transform = Transform3D(rover.global_basis, tray.drop_point() + rover.global_basis.x * x)
		jars.append(jar)
	await _ticks(2.0)
	var rest: Array = _local()
	await _ticks(1.0)
	var still: bool = jars.all(func(j: RigidBody3D) -> bool: return j.linear_velocity.length() < 0.02)
	_check("settle: both jars rest inside the tray", _inside() == 2, "%d inside" % _inside())
	_check("settle: no jitter (still, no creep)", still, "moved %s in 1 s" % _moved(rest))

	# 2. Careful
	var before: Array = _local()
	await _cruise(1.2, 0.0, 12.0)
	await _stop_gently()
	_check("careful: 1.2 m/s and a gentle stop keep both in", _inside() == 2, "%d inside, moved %s" % [_inside(), _moved(before)])

	# 3. Normal
	before = _local()

	await _cruise(2.4, 0.0, 6.0)
	await _cruise(2.4, 0.4, 3.0)
	await _cruise(2.4, -0.4, 3.0)
	await _stop_gently()
	_check("normal: 2.4 m/s with turns keeps both in", _inside() == 2, "%d inside, moved %s" % [_inside(), _moved(before)])

	# 4. Reckless: full throttle down the short route's lane through the boulder field, then a hard stop
	# Straight across the boulder field (not its cleared lane): from 35 m out, through its centre
	var field: Node3D = level.get_node("BoulderField")
	var centre := Vector2(field.global_position.x, field.global_position.z)
	var lane: Array = [centre + Vector2(0.0, 35.0), centre, centre + Vector2(0.0, -30.0)]
	var a: Vector2 = lane[0]
	var b: Vector2 = lane[1]
	rover.global_transform = Transform3D(Basis.looking_at(Vector3(b.x - a.x, 0.0, b.y - a.y).normalized()),
		_ground(Vector3(a.x, 0.0, a.y)) + Vector3.UP * 0.4)
	rover.linear_velocity = Vector3.ZERO
	await _ticks(2.0)
	for k in jars.size():                                 # the jars come along: back in the tray
		jars[k].global_transform = Transform3D(rover.global_basis, tray.drop_point() + rover.global_basis.x * (0.05 if k else -0.05))
		jars[k].linear_velocity = Vector3.ZERO
		jars[k].angular_velocity = Vector3.ZERO
		jars[k].sleeping = false
	await _ticks(2.0)
	_check("reckless: both jars back in the tray at the lane's start", _inside() == 2, "%d inside" % _inside())
	before = _local()
	for target: Vector2 in lane.slice(1):
		for i in 30 * TICKS:
			var to := Vector2(target.x - rover.global_position.x, target.y - rover.global_position.z)
			if to.length() < 3.0:
				break
			var fwd: Vector3 = -rover.global_basis.z
			var steer: float = clampf(Vector2(fwd.x, fwd.z).normalized().angle_to(to.normalized()) / 0.25, -1.0, 1.0)
			_release_all()
			Input.action_press("move_forward", 1.0)
			if steer > 0.05:
				Input.action_press("move_right", steer)
			elif steer < -0.05:
				Input.action_press("move_left", -steer)
			await physics_frame
	await _drive(-1.0, 0.0, 1.5)
	await _ticks(2.0)
	print("INFO reckless: %d of 2 still inside, moved %s; mounted %s, frozen %s" % [_inside(), _moved(before),
		jars.map(func(j: RigidBody3D) -> bool: return j.is_mounted()), jars.map(func(j: RigidBody3D) -> bool: return j.freeze)])
	_check("reckless: full speed through the boulders and a hard stop throw something out", _inside() < 2, "%d inside" % _inside())

	# 5. Secured (a human carrying Kite home): tilted on its side the jars stay; released, they ride loose
	rover.global_transform = Transform3D(Basis.IDENTITY, _ground(rover.global_position) + Vector3.UP * 0.4)
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(2.0)
	for k in jars.size():
		jars[k].global_transform = Transform3D(rover.global_basis, tray.drop_point() + rover.global_basis.x * (0.05 if k else -0.05))
		jars[k].linear_velocity = Vector3.ZERO
		jars[k].angular_velocity = Vector3.ZERO
		jars[k].sleeping = false                           # moving a sleeping body doesn't wake it
	await _ticks(2.0)
	_check("secured: both jars in the tray before lifting", _inside() == 2, "%d inside, at %s" % [_inside(), _local()])
	tray.set_secured(true)
	var lifted: Transform3D = rover.global_transform
	rover.freeze = true
	for i in 2 * TICKS:                                   # held up and rolled 70 degrees over
		var t: float = minf(i / float(TICKS), 1.0)
		rover.global_transform = Transform3D(lifted.basis.rotated(lifted.basis.z, deg_to_rad(70.0) * t),
			lifted.origin + Vector3.UP * (0.6 * t))
		await physics_frame
	_check("secured: tilted 70 degrees in the air, both jars stay in the tray", _inside() == 2, "%d inside" % _inside())
	rover.global_transform = lifted
	rover.freeze = false
	await _ticks(1.0)
	tray.set_secured(false)
	await _ticks(1.0)
	_check("secured: released again, they ride loose in the tray", _inside() == 2
		and jars.all(func(j: RigidBody3D) -> bool: return not j.freeze and j.get_parent() == level), "%d inside" % _inside())

	print("RESULT test_tray %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
