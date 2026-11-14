extends SceneTree
## Headless test: the rover driving off a crater rim on the Moon, at 4, 5 and 6 m/s.
## The rim (built in the air over the Moon level, so the level's gravity and rover suspension apply):
## flat ground, a 12 degree rise to a crest 0.85 m up, then the crater side: ground 1.0 m below
## the approach. The rover leaves the crest and lands about 1.9 m lower, at 2.4-2.7 m/s
## downwards: what the real terrain did at 4-6 m/s (README 7, Level gravity). Each run is checked as
## test_wheel_contact.gd checks wheels, plus:
##   - no bottoming: no wheel's suspension within 5 mm of the top of its travel, and nothing on the
##     rover's body (chassis, bump stops) touching the ground;
##   - no visible wheel over 1 cm in the ground, no wheel airborne within 5 mm of the ground, none in
##     contact inside it (by over 1 cm plus one tick of the rover's vertical travel: the check runs
##     after the step, from the contact found before it);
##   - no bounce: after touching down, under 0.1 s with no wheel loaded (Earth's springs at lunar
##     gravity sent it back into the air for 0.5-0.9 s);
##   - upright and settled 4 s after landing.
## Also: at rest on flat ground the Moon rover sits at Earth's ride height and sag (the level's
## suspension), and with the default suspension under Earth gravity it is unchanged.
## Prints one line per check and PASS / FAIL; MEASURE lines for the landings.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_rover_landing.gd

const TICKS: int = 240
const MOON: float = 1.62
const EARTH: float = 9.8
const RAMP_RUN: float = 4.0
const RAMP_RISE: float = 0.85     # tan(12 degrees) * 4
const DROP: float = 1.0           # the crater side, below the approach
const SPEEDS: Array = [4.0, 5.0, 6.0]
const GROUND_MASK: int = 1 | 4
const WHEEL_RADIUS: float = 0.15
const WHEEL_WIDTH: float = 0.24
const TOUCH_MARGIN: float = 0.005
const MESH_MARGIN: float = 0.01
# Earth's values on flat ground with the default suspension (README Level gravity)
const EARTH_RIDE_HEIGHT: float = 0.1006
const EARTH_SAG: float = 0.049

var GS: Node
var SL: Node
var failures: int = 0
var level: Node
# The rim's approach ground: 150 m over the terrain at the level's origin (not kilometres away: a
# float position 5 km out moves in 0.5 mm steps, and a rover settling slower than 0.06 m/s stalls)
var ground_at := Vector3.ZERO
var rover: RigidBody3D
var grounds: Array[RID] = []
var _shape := CylinderShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var stats: Dictionary = {}
var watching: bool = false


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	var checker_script := GDScript.new()
	checker_script.source_code = "extends Node\nvar callback: Callable\nfunc _process(_delta: float) -> void:\n\tcallback.call()\n"
	checker_script.reload()
	var checker := Node.new()
	checker.set_script(checker_script)
	checker.set("callback", _check_frame)
	checker.process_priority = 1000
	root.add_child.call_deferred(checker)
	physics_frame.connect(_check_tick)
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


func _box(size: Vector3, centre: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	level.add_child(body)
	body.global_position = centre
	grounds.append(body.get_rid())


# Approach ground (y 0) for z > 0, the 12 degree rise from z 0 to z -RAMP_RUN, the crater side
# (y -DROP) beyond it; 30 m wide
func _build_rim() -> void:
	_box(Vector3(30.0, 1.0, 120.0), ground_at + Vector3(0.0, -0.5, 60.0))
	_box(Vector3(30.0, 1.0, 120.0), ground_at + Vector3(0.0, -DROP - 0.5, -RAMP_RUN - 60.0))
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var wedge := ConvexPolygonShape3D.new()
	wedge.points = PackedVector3Array([
		Vector3(-15, 0, 0), Vector3(15, 0, 0), Vector3(-15, 0, -RAMP_RUN), Vector3(15, 0, -RAMP_RUN),
		Vector3(-15, RAMP_RISE, -RAMP_RUN), Vector3(15, RAMP_RISE, -RAMP_RUN),
		Vector3(-15, -DROP, -RAMP_RUN), Vector3(15, -DROP, -RAMP_RUN)])
	shape.shape = wedge
	body.add_child(shape)
	level.add_child(body)
	body.global_position = ground_at
	grounds.append(body.get_rid())


func _teleport(at: Vector3, speed: float) -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(a)
	rover.global_transform = Transform3D(Basis.IDENTITY, at)
	rover.linear_velocity = Vector3(0.0, 0.0, -speed)
	rover.angular_velocity = Vector3.ZERO
	for wheel in rover.running_gear.wheel_states:
		rover.running_gear.wheel_states[wheel][0] = speed / WHEEL_RADIUS


func _compressions() -> Array:
	var gear = rover.running_gear
	var out: Array = []
	for wheel in gear.wheel_states:
		if gear.wheel_states[wheel][3]:
			out.append(gear.wheel_states[wheel][7] - gear.full_extension_height(wheel))
	return out


# Wheels pushing on the ground (in contact and loaded)
func _loaded_wheels() -> int:
	var count: int = 0
	for wheel in rover.running_gear.wheel_states:
		var state: Dictionary = rover.running_gear.wheel_states[wheel]
		if state[3] and (state[1] as Vector3).length() > 0.0:
			count += 1
	return count


func _travel() -> float:
	var gear = rover.running_gear
	return maxf(gear.suspension_top, gear.full_extension_height(0)) - gear.full_extension_height(0)


func _at_rest(g: float, suspension: Dictionary) -> Array:
	_set_gravity(g)
	rover.apply_suspension(suspension)
	_teleport(ground_at + Vector3(0.0, 0.11, 40.0), 0.0)
	await _ticks(6.0)
	var c: Array = _compressions()
	var sag: float = 0.0
	for v in c:
		sag += v / maxf(c.size(), 1)
	return [rover.global_position.y - ground_at.y, sag]


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	var terrain: Node = level.get_node("Terrain")
	ground_at = Vector3(0.0, ceilf(terrain.height_at(0.0, 0.0)) + 150.0, 0.0)
	_build_rim()
	await _ticks(1.0)
	GS.drive(rover)
	var moon_suspension: Dictionary = level.get("rover_suspension") if level.get("rover_suspension") is Dictionary else {}
	print("INFO the Moon level's rover suspension: %s" % moon_suspension)

	# Ride height and sag
	var earth: Array = await _at_rest(EARTH, {})
	var moon: Array = await _at_rest(MOON, moon_suspension)
	print("MEASURE ride height (body origin) / sag: Earth default %.1f cm / %.1f mm, Moon %.1f cm / %.1f mm" % [earth[0] * 100.0, earth[1] * 1000.0, moon[0] * 100.0, moon[1] * 1000.0])
	_check("Earth, default suspension: ride height unchanged", absf(earth[0] - EARTH_RIDE_HEIGHT) < 0.003, "%.1f cm" % (earth[0] * 100.0))
	_check("Moon: Earth's ride height", absf(moon[0] - earth[0]) < 0.005, "%.1f cm (Earth %.1f)" % [moon[0] * 100.0, earth[0] * 100.0])
	_check("Moon: Earth's sag", absf(moon[1] - earth[1]) < 0.005, "%.1f mm (Earth %.1f)" % [moon[1] * 1000.0, earth[1] * 1000.0])

	# Off the rim
	_set_gravity(MOON)
	rover.apply_suspension(moon_suspension)
	for speed in SPEEDS:
		await _land(speed)

	print("DONE %d failures" % failures)
	quit(1 if failures else 0)


func _land(speed: float) -> void:
	_teleport(ground_at + Vector3(0.0, 0.25, 30.0), speed)
	stats = {"ticks": 0, "frames": 0, "bottomed": 0, "body_contacts": 0, "touching_airborne": 0, "inside": 0,
		"mesh_in_ground": 0, "worst_mesh": 0.0, "max_compression": 0.0, "landing_speed": 0.0, "airborne": 0.0,
		"rebound_speed": 0.0, "bounced": 0.0, "max_tilt": 0.0}
	var t: float = 0.0
	var left_crest: bool = false
	var flying: bool = false
	var landed: bool = false
	while t < 14.0:
		await physics_frame
		t += 1.0 / TICKS
		var forward: float = -rover.linear_velocity.z
		var z: float = rover.global_position.z - ground_at.z
		if z > -RAMP_RUN:
			# Hold the speed up to the crest (the throttle is the motor voltage, about 9.6 m/s full)
			Input.action_press("move_forward", clampf(speed / 9.6 + (speed - forward) * 0.5, 0.05, 1.0))
		else:
			Input.action_release("move_forward")
		watching = z < 2.0
		if z < -RAMP_RUN:
			left_crest = true
		var loaded: int = _loaded_wheels()
		if left_crest and not landed and loaded == 0:
			flying = true
			stats["airborne"] += 1.0 / TICKS
			stats["landing_speed"] = maxf(stats["landing_speed"], -rover.linear_velocity.y)
		elif flying and not landed:
			landed = true
		if landed:
			# The rebound: how fast the body comes back up, and time with no wheel holding it
			stats["rebound_speed"] = maxf(stats["rebound_speed"], rover.linear_velocity.y)
			stats["max_tilt"] = maxf(stats["max_tilt"], rad_to_deg(rover.global_basis.y.angle_to(Vector3.UP)))
			if loaded == 0:
				stats["bounced"] += 1.0 / TICKS
		if left_crest and z < -RAMP_RUN - 30.0:
			break
	Input.action_release("move_forward")
	watching = false
	await _ticks(4.0)
	var upright: bool = rover.global_basis.y.y > 0.95
	print("MEASURE %.0f m/s off the rim: %.2f s in the air, landing at %.2f m/s down, deepest compression %.0f of %.0f mm; rebound %.2f m/s up, %.2f s off the ground again, tilting up to %.0f deg" % [
		speed, stats["airborne"], stats["landing_speed"], stats["max_compression"] * 1000.0, _travel() * 1000.0,
		stats["rebound_speed"], stats["bounced"], stats["max_tilt"]])
	var tag := "%.0f m/s off the rim: " % speed
	_check(tag + "it flies and lands hard", stats["airborne"] > 0.3 and stats["landing_speed"] > 2.0, "%.2f s, %.2f m/s" % [stats["airborne"], stats["landing_speed"]])
	_check(tag + "no bottoming (travel)", stats["bottomed"] == 0, "%d ticks within 5 mm of the top; deepest %.0f mm of %.0f" % [stats["bottomed"], stats["max_compression"] * 1000.0, _travel() * 1000.0])
	_check(tag + "no bottoming (body on the ground)", stats["body_contacts"] == 0, "%d ticks" % stats["body_contacts"])
	_check(tag + "no visible wheel in the ground", stats["mesh_in_ground"] == 0, "%d frames, deepest %.0f mm" % [stats["mesh_in_ground"], stats["worst_mesh"] * 1000.0])
	_check(tag + "wheel contact right (no airborne / inside)", stats["touching_airborne"] == 0 and stats["inside"] == 0,
		"airborne %d, inside %d of %d wheel-ticks" % [stats["touching_airborne"], stats["inside"], stats["ticks"] * 6])
	_check(tag + "doesn't bounce back into the air", stats["bounced"] < 0.1, "%.2f s with no wheel loaded, rebound %.2f m/s" % [stats["bounced"], stats["rebound_speed"]])
	_check(tag + "upright and settled", upright and rover.linear_velocity.length() < 0.5, "up %.2f, %.2f m/s" % [rover.global_basis.y.y, rover.linear_velocity.length()])


# --- Per tick and per frame (as test_wheel_contact.gd) -------------------------------------------

func _wheel_shape_hits(space: PhysicsDirectSpaceState3D, centre: Vector3, axle: Vector3, radius: float, width: float) -> Array:
	_shape.radius = radius
	_shape.height = width
	var forward := axle.cross(Vector3.UP)
	if forward.length() < 0.1:
		forward = axle.cross(Vector3.FORWARD)
	forward = forward.normalized()
	var up := forward.cross(axle).normalized()
	_query.shape = _shape
	_query.transform = Transform3D(Basis(forward, axle.normalized(), up), centre)
	_query.collision_mask = GROUND_MASK
	_query.exclude = [rover.get_rid()]
	return space.intersect_shape(_query, 4)


func _depth_below_terrain(space: PhysicsDirectSpaceState3D, centre: Vector3, radius: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(centre + Vector3.UP * 0.5, centre + Vector3.DOWN * 1.0, GROUND_MASK)
	q.exclude = [rover.get_rid()]
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y - (centre.y - radius) if hit else -INF


func _check_tick() -> void:
	if not watching:
		return
	var space := rover.get_world_3d().direct_space_state
	var gear = rover.running_gear
	stats["ticks"] += 1
	# Checked after the step, from the contact found before it: a wheel coming down at landing
	# speed has moved one tick further (12 mm at 2.8 m/s)
	var inside_margin: float = MESH_MARGIN + absf(rover.linear_velocity.y) / TICKS
	var travel: float = _travel()
	for c in _compressions():
		stats["max_compression"] = maxf(stats["max_compression"], c)
		if c > travel - 0.005:
			stats["bottomed"] += 1
	var direct := PhysicsServer3D.body_get_direct_state(rover.get_rid())
	for k in direct.get_contact_count():
		if direct.get_contact_collider(k) in grounds:
			stats["body_contacts"] += 1
			break
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
		if state[3] and _depth_below_terrain(space, centre, WHEEL_RADIUS) > inside_margin:
			stats["inside"] += 1
		if touching and not state[3]:
			stats["touching_airborne"] += 1


func _check_frame() -> void:
	if not watching or not is_instance_valid(rover):
		return
	var space := rover.get_world_3d().direct_space_state
	stats["frames"] += 1
	for wheel in rover.wheel_sockets:
		var socket = rover.wheel_sockets[wheel]
		if socket and socket.part:
			var part: Node3D = socket.part
			var part_axle: Vector3 = (part.global_basis * Vector3.RIGHT).normalized()
			var hits := _wheel_shape_hits(space, part.global_position, part_axle, WHEEL_RADIUS - MESH_MARGIN, WHEEL_WIDTH - 2.0 * MESH_MARGIN)
			var sunk: float = _depth_below_terrain(space, part.global_position, WHEEL_RADIUS)
			if not hits.is_empty() or sunk > MESH_MARGIN:
				stats["mesh_in_ground"] += 1
				stats["worst_mesh"] = maxf(stats["worst_mesh"], sunk)
