extends SceneTree
## Headless test: the M3 routes (RouteMarkers), Head crater's shade and the boulder field.
##   1. Routes: both end at the far-rim logger, the long one clearly longer, flags staked.
##   2. Boulders: up to 3 m, with collision, none big in the short route's lane.
##   3. Shade (ColdZone dtm_shade): M3 shows the timeline's sun. Courier (high sun): nothing cold.
##      Freighter (dusk, west): Head's west wall is cold on the short route, the long route and the
##      logger aren't. Before M3 the level keeps its own sun.
##   4. Climbing: Kite's limit (ramps of regolith, from rest, thermal kit + logger) is well above
##      the short route's steepest slope, with standard and grip wheels.
##   5. Drivable: Kite drives the short route out and back (logger on the way back) with standard
##      and with grip wheels, and the long route with standard wheels.
##   6. No soft-lock in Head: F rights Kite on the crater floor; Kite still there for STILL_FOR s
##      lets the console request the emergency recovery, which docks it.
##   `-- climb` only measures the climbing limit.

const TICKS: int = 240
const FLOOR := Vector3(0.0, 300.0, 0.0)
const GRIP_WHEEL: String = "res://src/robot/socket/wheel_high_grip_part.tscn"
const LOGGER_PART: String = "res://src/robot/socket/field_logger_part.tscn"
const CAPTURE: float = 5.0
const ROUTE_SPEED: float = 3.0
const THERMAL: Dictionary = {"ThermalCoverSocket": "res://src/robot/socket/thermal_cover_part.tscn",
	"HeaterSocket": "res://src/robot/socket/thermal_heater_part.tscn"}

var GS: Node
var SL: Node
var CS: Node
var failures := 0
var level: Node
var rover: RigidBody3D
var director: Node
var _spare_wheels: Array = []
const M1_DONE: Array = ["m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]
const M2_DONE: Array = ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed", "m2.iris_activated",
	"m2.kite_docked", "m2.telemetry_received"]
var markers: Node
var terrain: Node
var max_pitch := 0.0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-70s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _release() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(action)


func _mount_in(socket_name: String, path: String) -> void:
	var socket: Node = rover.find_child(socket_name, true, false)
	if socket.part:
		socket.unmount().queue_free()
	if path:
		var part: RigidBody3D = load(path).instantiate()
		level.add_child(part)
		part.global_position = socket.global_position
		socket.mount(part)
	await _ticks(0.2)


func _set_grip_wheels() -> void:
	var sockets: Array = [rover.front_left_socket, rover.front_right_socket, rover.rear_left_socket, rover.rear_right_socket]
	if _spare_wheels.is_empty():
		for i in 4:
			var part: RigidBody3D = load(GRIP_WHEEL).instantiate()
			level.add_child(part)
			_spare_wheels.append(part)
	for i in 4:
		var socket: Node = sockets[i]
		var old: RigidBody3D = socket.unmount()
		var new: RigidBody3D = _spare_wheels[i]
		new.global_position = socket.global_position
		socket.mount(new)
		_spare_wheels[i] = old
		old.global_position = FLOOR + Vector3(-40.0 + 2.0 * i, 1.0, -40.0)
	await _ticks(0.2)


# --- Climbing limit -------------------------------------------------------------------------------

var _ramp: StaticBody3D = null


# A 40 m wide, 80 m long ramp of `degrees` rising towards -Z, its foot at FLOOR
func _build_ramp(degrees: float) -> void:
	if _ramp == null:
		_ramp = StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(40.0, 1.0, 80.0)
		shape.shape = box
		_ramp.add_child(shape)
		level.add_child(_ramp)
	var basis := Basis(Vector3.RIGHT, deg_to_rad(degrees))
	_ramp.global_transform = Transform3D(basis, FLOOR + basis * Vector3(0.0, -0.5, -40.0))


# From rest on the ramp, full throttle for 20 s: metres gained along the slope
func _climb(degrees: float) -> float:
	await _build_ramp(degrees)
	var basis := Basis(Vector3.RIGHT, deg_to_rad(degrees))
	var start: Vector3 = FLOOR + basis * Vector3(0.0, 0.45, -15.0)
	_release()
	rover.global_transform = Transform3D(basis, start)
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	rover.battery.charge = rover.battery.capacity
	await _ticks(1.0)
	var settled: Vector3 = rover.global_position
	Input.action_press("move_forward", 1.0)
	await _ticks(20.0)
	_release()
	return (rover.global_position - settled).dot(basis * Vector3.FORWARD)


func climb_limit() -> float:
	var best := 0.0
	for degrees in range(20, 50, 2):
		var gained: float = await _climb(degrees)
		print("INFO climb %2d deg: %+.1f m along the slope in 20 s" % [degrees, gained])
		if gained > 15.0:
			best = degrees
		else:
			break
	return best


func _climb_report() -> Vector2:
	for socket_name in THERMAL:
		await _mount_in(socket_name, THERMAL[socket_name])
	await _mount_in("CargoSocket", LOGGER_PART)
	var standard: float = await climb_limit()
	await _set_grip_wheels()
	var grip: float = await climb_limit()
	await _set_grip_wheels()
	await _mount_in("CargoSocket", "")
	_ramp.global_position = FLOOR + Vector3(0.0, -200.0, 0.0)
	print("CLIMB limit from rest, thermal kit + logger (%.0f kg): standard wheels %.0f deg, grip wheels %.0f deg" % [rover.mass, standard, grip])
	return Vector2(standard, grip)


# --- Routes ---------------------------------------------------------------------------------------

func _polyline(id: String) -> PackedVector2Array:
	var points := PackedVector2Array([markers.start()])
	points.append_array(markers.route(id))
	return points


# Every metre along a route (x, z)
func _samples(id: String) -> Array[Vector2]:
	var points := _polyline(id)
	var out: Array[Vector2] = []
	for i in points.size() - 1:
		var n: int = maxi(1, int(points[i].distance_to(points[i + 1])))
		for k in n:
			out.append(points[i].lerp(points[i + 1], float(k) / n))
	return out


# Steepest along-track slope (degrees, 4 m baseline, DTM heights)
func _steepest(id: String) -> float:
	var points := _polyline(id)
	var worst := 0.0
	for i in points.size() - 1:
		var n: int = maxi(1, int(points[i].distance_to(points[i + 1]) / 4.0))
		var step: float = points[i].distance_to(points[i + 1]) / n
		for k in n:
			var a: Vector2 = points[i].lerp(points[i + 1], float(k) / n)
			var b: Vector2 = points[i].lerp(points[i + 1], float(k + 1) / n)
			worst = maxf(worst, rad_to_deg(atan(absf(terrain.height_at(b.x, b.y) - terrain.height_at(a.x, a.y)) / step)))
	return worst


func _cold_metres(id: String) -> float:
	var metres := 0.0
	for p in _samples(id):
		if director.cold_zone_at(Vector3(p.x, terrain.height_at(p.x, p.y), p.y)):
			metres += 1.0
	return metres


func _set_m3(service: String) -> void:
	CS.load_state({"current": "m3", "objectives": M1_DONE + M2_DONE, "missions_done": ["m1", "m2"],
		"flags": ["iris_online", "cargo_delivered"], "items": {"cargo.service." + service: 1, "cargo.thermal_kit": 1}})
	director.apply_mission_sun()


func _drive_route(points: Array) -> bool:
	var reached := 0
	for target in points:
		var t := 0.0
		var best := INF
		var last_progress := 0.0
		while true:
			await physics_frame
			t += 1.0 / TICKS
			max_pitch = maxf(max_pitch, rad_to_deg(acos(clampf(rover.global_basis.y.dot(Vector3.UP), -1.0, 1.0))))
			var to: Vector2 = target - Vector2(rover.global_position.x, rover.global_position.z)
			if to.length() < best - 1.0:
				best = to.length()
				last_progress = t
			if to.length() < CAPTURE:
				reached += 1
				break
			if t - last_progress > 25.0:
				print("INFO stuck short of %s at %s" % [target, rover.global_position.snapped(Vector3.ONE * 0.1)])
				break
			var forward: Vector3 = -rover.global_basis.z
			var steer: float = clampf(Vector2(forward.x, forward.z).normalized().angle_to(to.normalized()) / 0.5, -1.0, 1.0)
			var speed: float = rover.linear_velocity.dot(forward)
			Input.action_press("move_forward", clampf(0.25 + (ROUTE_SPEED - speed) * 0.5, 0.1, 1.0))
			Input.action_release("move_left")
			Input.action_release("move_right")
			if steer > 0.05:
				Input.action_press("move_right", steer)
			elif steer < -0.05:
				Input.action_press("move_left", -steer)
	_release()
	await _ticks(1.0)
	return reached == points.size()


# Apron to the logger, logger mounted, and back to the apron
func _round_trip(id: String) -> Dictionary:
	var start: Vector2 = markers.start()
	var first: Vector2 = markers.route(id)[0]
	var heading: Vector2 = first - start
	rover.global_transform = Transform3D(Basis(Vector3.UP, atan2(-heading.x, -heading.y)),
		Vector3(start.x, terrain.height_at(start.x, start.y) + 0.4, start.y))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	rover.battery.charge = rover.battery.capacity
	await _mount_in("CargoSocket", "")
	max_pitch = 0.0
	var out: Array = Array(markers.route(id))
	var back: Array = out.slice(0, out.size() - 1)
	back.reverse()
	back.append(start)
	var there: bool = await _drive_route(out)
	await _mount_in("CargoSocket", LOGGER_PART)
	var home: bool = there and await _drive_route(back)
	return {"there": there, "home": home, "pitch": max_pitch}


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	director = level.get_tree().get_first_node_in_group("mission_director")
	await physics_frame
	await physics_frame
	GS.drive(rover)
	await _ticks(1.0)
	terrain = level.get_node("Terrain")
	markers = level.get_node("RouteMarkers")
	if "climb" in OS.get_cmdline_user_args():
		await _climb_report()
		quit(0)
		return

	# 1. Routes
	var logger: Vector3 = level.get_node("FarLogger").global_position
	for id in ["short", "long"]:
		var end: Vector2 = markers.route(id)[-1]
		_check("[route] %s ends at the far-rim logger" % id, end.distance_to(Vector2(logger.x, logger.z)) < 3.0, str(end))
	var short_m: float = markers.round_trip("short")
	var long_m: float = markers.round_trip("long")
	_check("[route] the long route is clearly longer", long_m > 1.15 * short_m, "%.0f m vs %.0f m" % [long_m, short_m])
	var stakes: int = markers.get_child_count()
	_check("[route] flags along both routes and a sign for each", stakes == markers.route("short").size() + markers.route("long").size(), str(stakes))

	# 2. Boulders
	var field: Node = level.get_node("BoulderField")
	_check("[rocks] a boulder field up to 3 m", field.rocks.count >= 80 and field.largest() > 2.5 and field.largest() <= 3.0,
		"%d rocks, largest %.2f m" % [field.rocks.count, field.largest()])
	var biggest := -1
	for i in field.values.size() / 6:
		if biggest < 0 or field.values[i * 6 + 3] > field.values[biggest * 6 + 3]:
			biggest = i
	var top := Vector3(field.values[biggest * 6], field.values[biggest * 6 + 1] + 10.0, field.values[biggest * 6 + 2])
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 20.0, 1))
	_check("[rocks] the biggest boulder has collision", hit and hit["collider"].get_parent() == field.rocks
		and hit["position"].y > field.values[biggest * 6 + 1] + 0.8, str(hit.get("position", "no hit")))
	var in_lane := 0
	for i in field.values.size() / 6:
		var p := Vector2(field.values[i * 6], field.values[i * 6 + 2])
		if field.values[i * 6 + 3] > field.lane_max_size and field._distance_to_path(p, _polyline("short")) < field.lane_half_width:
			in_lane += 1
	_check("[rocks] the short route's marked lane is clear of big rocks", in_lane == 0, str(in_lane))
	var on_line := 0
	var chord := PackedVector2Array([markers.route("short")[0], markers.route("short")[3]])
	for i in field.values.size() / 6:
		var p := Vector2(field.values[i * 6], field.values[i * 6 + 2])
		if field.values[i * 6 + 3] >= 1.0 and field._distance_to_path(p, chord) < 1.0 + field.values[i * 6 + 3] * 0.5:
			on_line += 1
	_check("[rocks] cutting straight across the field instead of following the flags hits boulders", on_line >= 2,
		"%d rocks of 1 m+ on the straight line" % on_line)

	# 3. Shade
	var sky: Node = level.get_node("WorldEnvironment")
	var zone: Node = level.get_node("ColdZones/HeadShade")
	_check("[sun] before M3 the level keeps its own sun", is_equal_approx(sky.sun_azimuth, 90.6247) and is_equal_approx(sky.sun_elevation, 16.7229),
		"%.1f / %.1f" % [sky.sun_azimuth, sky.sun_elevation])
	_set_m3("courier")
	_check("[sun] Courier M3: high sun", sky.sun_elevation > 75.0 and sky.sun_azimuth < 180.0, "%.1f / %.1f" % [sky.sun_azimuth, sky.sun_elevation])
	_check("[cold] Courier M3: no shade in Head", zone.shaded_area() < 10.0, "%.0f m2" % zone.shaded_area())
	_check("[cold] Courier M3: neither route is cold", _cold_metres("short") == 0.0 and _cold_metres("long") == 0.0)
	_set_m3("freighter")
	_check("[sun] Freighter M3: dusk sun in the west", absf(sky.sun_azimuth - 269.3753) < 0.01 and absf(sky.sun_elevation - 16.7) < 0.2,
		"%.1f / %.1f" % [sky.sun_azimuth, sky.sun_elevation])
	var short_cold: float = _cold_metres("short")
	_check("[cold] Freighter M3: Head's west wall is in shade", zone.shaded_area() > 300.0, "%.0f m2" % zone.shaded_area())
	_check("[cold] Freighter M3: the short route crosses it", short_cold >= 20.0, "%.0f m" % short_cold)
	_check("[cold] Freighter M3: the long route stays sunlit", _cold_metres("long") == 0.0)
	_check("[cold] Freighter M3: the logger stop is sunlit", director.cold_zone_at(logger) == null)
	var west_wall := Vector3(-76.0, terrain.height_at(-76.0, -50.0), -50.0)
	_check("[cold] the cold is on the west wall", director.cold_zone_at(west_wall) != null)

	# 4. Climbing
	var limits: Vector2 = await _climb_report()
	var steepest: float = _steepest("short")
	print("INFO steepest along-track slope: short route %.1f deg, long route %.1f deg" % [steepest, _steepest("long")])
	_check("[climb] standard wheels climb well past the short route's steepest slope", limits.x >= steepest + 8.0, "%.0f vs %.1f deg" % [limits.x, steepest])
	_check("[climb] grip wheels climb at least as steep", limits.y >= limits.x, "%.0f deg" % limits.y)

	# 5. Drivable, thermal kit fitted (Freighter M3)
	var trip: Dictionary = await _round_trip("short")
	_check("[drive] short route out and back, standard wheels", trip["there"] and trip["home"], "steepest tilt %.0f deg" % trip["pitch"])
	trip = await _round_trip("long")
	_check("[drive] long route out and back, standard wheels", trip["there"] and trip["home"], "steepest tilt %.0f deg" % trip["pitch"])
	await _set_grip_wheels()
	trip = await _round_trip("short")
	_check("[drive] short route out and back, grip wheels", trip["there"] and trip["home"], "steepest tilt %.0f deg" % trip["pitch"])
	await _set_grip_wheels()

	# 6. No soft-lock on Head's floor
	var floor_point := Vector3(-40.0, terrain.height_at(-40.0, -45.0), -45.0)
	rover.global_transform = Transform3D(Basis(Vector3.RIGHT, PI), floor_point + Vector3.UP * 1.0)
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(3.0)
	rover.controller.reset_requested.emit()
	await _ticks(2.0)
	_check("[stuck] F rights Kite on the crater floor", rover.global_basis.y.dot(Vector3.UP) > 0.95, "up %.2f" % rover.global_basis.y.dot(Vector3.UP))
	await _ticks(director.STILL_FOR + 1.0)
	_check("[stuck] Kite still in the crater: recovery can be requested", director.can_request_recovery(), "still %.0f s" % director.still_time)
	_check("[stuck] the request starts the recovery", director.request_recovery() and director.recovering)
	await _ticks(director.RECOVERY_DELAY + 1.0)
	_check("[stuck] Kite is back on the pad", not director.recovering and director.pad.is_in_zone(rover))
	CS.reset()
	print("RESULT %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
