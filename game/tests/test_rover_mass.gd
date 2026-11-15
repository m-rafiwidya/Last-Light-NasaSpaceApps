extends SceneTree
## Headless test: mounted part mass and rolling resistance change how Kite drives (Moon level,
## lunar gravity, loose regolith, on a flat floor built above the terrain).
##   1. Mass: the standard build is REFERENCE_MASS; the 12 kg radio module adds 12 kg.
##   2. Same drive (half throttle, 12 s): a loaded Kite covers less ground, tops out lower and
##      uses more Wh than an empty one.
##   3. Holding 3 m/s: loaded draws more power. Coasting from it slows Kite down.
##   4. Grip wheels (4 of them) use more Wh per metre on flat ground.
##   5. Energy: over every drive, the motors' shaft work never exceeds the electrical energy.
##   7. The heater draws only in an active cold zone with the heater fitted.
##   6. MissionDirector's learned Wh per metre (the return estimate) is higher when loaded, and
##      time stopped (the electronics still drawing) doesn't change it.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_rover_mass.gd
##   `-- routes` instead drives each mission's route over the real terrain, empty and loaded, and
##   prints the Wh and battery share each uses (balance report, no checks).

const TICKS: int = 240
const FLOOR := Vector3(0.0, 300.0, 0.0)
const START := FLOOR + Vector3(-250.0, 0.35, 120.0)
const MODULE: String = "res://src/robot/socket/radio_module_part.tscn"
const GRIP_WHEEL: String = "res://src/robot/socket/wheel_high_grip_part.tscn"
const WHEEL: String = "res://src/robot/socket/wheel_part.tscn"
const REFERENCE_MASS: float = 80.0

var GS: Node
var SL: Node
var failures := 0
var level: Node
var rover: RigidBody3D
var director: Node
var electrical_j := 0.0
var mechanical_j := 0.0
var worst_step_excess := 0.0
var cold_seconds := 0.0
var heater_wh := 0.0
var CS: Node
const M1_DONE: Array = ["m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]
const M2_DONE: Array = ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed", "m2.iris_activated",
	"m2.kite_docked", "m2.telemetry_received"]


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-70s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _tick() -> void:
	await physics_frame
	electrical_j += rover.electrical_power / TICKS
	mechanical_j += rover.mechanical_power / TICKS
	worst_step_excess = maxf(worst_step_excess, rover.mechanical_power - rover.electrical_power)
	if director and director.cold_zone_at(rover.global_position):
		cold_seconds += 1.0 / TICKS
	heater_wh += rover.heater_power / TICKS / 3600.0


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await _tick()


func _forward_speed() -> float:
	return rover.linear_velocity.dot(-rover.global_basis.z)


func _place() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(action)
	rover.global_transform = Transform3D(Basis.IDENTITY, START)
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	for wheel in rover.running_gear.wheel_states:
		rover.running_gear.wheel_states[wheel][0] = 0.0
	rover.battery.charge = rover.battery.capacity
	await _ticks(2.0)


func _set_cargo(path: String) -> void:
	var socket: Node = rover.get_node("CargoSocket")
	if socket.part:
		socket.unmount().queue_free()
	if path:
		var part: RigidBody3D = load(path).instantiate()
		level.add_child(part)
		part.global_position = socket.global_position
		socket.mount(part)
	await _ticks(0.2)


# Swaps the four corner wheels for grip wheels (true) or back to the originals (false). Parts are
# kept, not freed: the rover's visuals hold on to the wheels they placed.
var _spare_wheels: Array = []
func _set_grip_wheels(grip: bool) -> void:
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
		old.global_position = START + Vector3(10.0 + i, 0.5, 0.0)
	await _ticks(0.2)


# Fixed throttle from rest: distance, top speed and Wh
func _fixed_drive(throttle: float, seconds: float) -> Dictionary:
	await _place()
	var start: Vector3 = rover.global_position
	var charge: float = rover.battery.charge
	var top := 0.0
	Input.action_press("move_forward", throttle)
	for i in int(seconds * TICKS):
		await _tick()
		top = maxf(top, _forward_speed())
	Input.action_release("move_forward")
	return {"distance": rover.global_position.distance_to(start), "top": top, "wh": charge - rover.battery.charge}


# Drives to `speed` and holds it for `seconds`: Wh per metre and average watts while holding
func _hold_speed(speed: float, seconds: float) -> Dictionary:
	await _place()
	var throttle := 0.3
	for i in 6 * TICKS:
		throttle = clampf(throttle + (speed - _forward_speed()) * 0.002, 0.0, 1.0)
		Input.action_press("move_forward", throttle)
		await _tick()
	var start: Vector3 = rover.global_position
	var charge: float = rover.battery.charge
	for i in int(seconds * TICKS):
		throttle = clampf(throttle + (speed - _forward_speed()) * 0.002, 0.0, 1.0)
		Input.action_press("move_forward", throttle)
		await _tick()
	var wh: float = charge - rover.battery.charge
	var metres: float = rover.global_position.distance_to(start)
	return {"wh_per_m": wh / maxf(metres, 0.001), "watts": wh * 3600.0 / seconds, "speed": metres / seconds}


func _coast(seconds: float) -> Dictionary:
	var v0: float = _forward_speed()
	Input.action_release("move_forward")
	var start: Vector3 = rover.global_position
	await _ticks(seconds)
	return {"v0": v0, "v1": _forward_speed(), "distance": rover.global_position.distance_to(start)}


func _learned_wh_per_m(loaded: bool) -> float:
	await _set_cargo(MODULE if loaded else "")
	await _place()
	director._distance = 0.0
	director._energy = 0.0
	director._last_charge = -1.0
	director._last_position = rover.global_position
	var throttle := 0.3
	for i in 30 * TICKS:
		throttle = clampf(throttle + (3.0 - _forward_speed()) * 0.002, 0.0, 1.0)
		Input.action_press("move_forward", throttle)
		await _tick()
	Input.action_release("move_forward")
	return director.wh_per_metre()


# --- Route balance (`-- routes`) -----------------------------------------------------------------

# Where Kite stops for IRIS: 12 m short of the station, on the base side
const IRIS := Vector2(-212.0, 146.0)
const LOGGER := Vector2(2.0, -59.0)
const SHORT_ROUTE: Array = [Vector2(-88.0, 30.0), LOGGER]
# Sunlit and longer: wide of the short route's shade, south round to the far rim
const LONG_ROUTE: Array = [Vector2(-180.0, 120.0), Vector2(-150.0, -20.0), Vector2(-110.0, -100.0), Vector2(-30.0, -110.0), LOGGER]
# A first-time player's time stopped at the destination (scanning, installing, looking around), s
const STOP_M1: float = 90.0
const STOP_M2: float = 150.0
const STOP_M3: float = 120.0
const ROUTE_SPEED: float = 3.0
const LOGGER_PART: String = "res://src/robot/socket/field_logger_part.tscn"
const THERMAL: Dictionary = {"ThermalCoverSocket": "res://src/robot/socket/thermal_cover_part.tscn",
	"HeaterSocket": "res://src/robot/socket/thermal_heater_part.tscn"}


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


func _drive_route(points: Array) -> Dictionary:
	var metres := 0.0
	var reached := 0
	var last: Vector3 = rover.global_position
	var throttle := 0.3
	for target in points:
		var t := 0.0
		var best := INF
		var last_progress := 0.0
		while true:
			await _tick()
			t += 1.0 / TICKS
			var moved: Vector3 = rover.global_position - last
			moved.y = 0.0
			metres += moved.length()
			last = rover.global_position
			var to: Vector2 = target - Vector2(rover.global_position.x, rover.global_position.z)
			if to.length() < best - 1.0:
				best = to.length()
				last_progress = t
			if to.length() < 8.0:
				reached += 1
				break
			if t - last_progress > 25.0:
				print("INFO stuck short of %s at %s" % [target, rover.global_position.snapped(Vector3.ONE * 0.1)])
				break
			var forward: Vector3 = -rover.global_basis.z
			var steer: float = clampf(Vector2(forward.x, forward.z).normalized().angle_to(to.normalized()) / 0.5, -1.0, 1.0)
			throttle = clampf(0.25 + (ROUTE_SPEED - _forward_speed()) * 0.5, 0.1, 1.0)
			Input.action_press("move_forward", throttle)
			Input.action_release("move_left")
			Input.action_release("move_right")
			if steer > 0.05:
				Input.action_press("move_right", steer)
			elif steer < -0.05:
				Input.action_press("move_left", -steer)
	for action in ["move_forward", "move_left", "move_right"]:
		Input.action_release(action)
	await _ticks(2.0)
	return {"metres": metres, "reached": reached == points.size()}


func _route_run(name: String, out: Array, back: Array, out_cargo: String, back_cargo: String, thermal: bool, stop: float) -> void:
	var terrain: Node = level.get_node("Terrain")
	var apron: Vector3 = level.get_node("Workshop").to_global(Vector3(1.5, 0.0, -12.0))
	var heading: Vector2 = out[0] - Vector2(apron.x, apron.z)
	rover.global_transform = Transform3D(Basis(Vector3.UP, atan2(-heading.x, -heading.y)),
		Vector3(apron.x, terrain.height_at(apron.x, apron.z) + 0.4, apron.z))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	for socket_name in THERMAL:
		await _mount_in(socket_name, THERMAL[socket_name] if thermal else "")
	await _mount_in("CargoSocket", out_cargo)
	rover.battery.charge = rover.battery.capacity
	var mass_out: float = rover.mass
	cold_seconds = 0.0
	heater_wh = 0.0
	var ticks0: int = Engine.get_physics_frames()
	var a: Dictionary = await _drive_route(out)
	var wh_out: float = rover.battery.capacity - rover.battery.charge
	await _ticks(stop)
	await _mount_in("CargoSocket", back_cargo)
	var mass_back: float = rover.mass
	var b: Dictionary = await _drive_route(back + [Vector2(apron.x, apron.z)])
	var wh: float = rover.battery.capacity - rover.battery.charge
	var seconds: float = float(Engine.get_physics_frames() - ticks0) / TICKS
	print("ROUTE %-38s %3.0f/%3.0f kg  %5.0f m  %4.0f s (%3.0f stopped)  %6.2f Wh  %5.1f%% of %.0f Wh  %s" % [name, mass_out,
		mass_back, a["metres"] + b["metres"], seconds, stop, wh, 100.0 * wh / rover.battery.capacity, rover.battery.capacity,
		"" if a["reached"] and b["reached"] else "NOT ALL WAYPOINTS REACHED"])
	if cold_seconds > 0.0:
		print("      in active cold zones %.0f s, heater %.2f Wh (%.1f%%)" % [cold_seconds, heater_wh, 100.0 * heater_wh / rover.battery.capacity])


# M3 in progress after an order by `service` (the Freighter arrives late: M3 near nightfall)
func _set_m3(service: String) -> void:
	CS.load_state({"current": "m3", "objectives": M1_DONE + M2_DONE + ["m3.logger_recovered"], "missions_done": ["m1", "m2"],
		"flags": ["iris_online", "cargo_delivered"], "items": {"cargo.service." + service: 1, "cargo.thermal_kit": 1}})


func _routes() -> void:
	var cartridge: String = "res://src/robot/socket/cartridge_part.tscn"
	var short_back: Array = SHORT_ROUTE.slice(0, SHORT_ROUTE.size() - 1)
	short_back.reverse()
	var long_back: Array = LONG_ROUTE.slice(0, LONG_ROUTE.size() - 1)
	long_back.reverse()
	if "long_only" in OS.get_cmdline_user_args():
		await _route_run("M3 long, empty", LONG_ROUTE, long_back, "", "", false, STOP_M3)
		quit(0)
		return
	await _route_run("M1 IRIS, empty", [IRIS], [], "", "", false, STOP_M1)
	await _route_run("M1 IRIS, cartridge out", [IRIS], [], cartridge, "", false, STOP_M1)
	await _route_run("M2 IRIS, empty", [IRIS], [], "", "", false, STOP_M2)
	await _route_run("M2 IRIS, module out", [IRIS], [], MODULE, "", false, STOP_M2)
	await _route_run("M3 short, empty", SHORT_ROUTE, short_back, "", "", false, STOP_M3)
	await _route_run("M3 short, thermal kit + logger back", SHORT_ROUTE, short_back, "", LOGGER_PART, true, STOP_M3)
	await _route_run("M3 long, empty", LONG_ROUTE, long_back, "", "", false, STOP_M3)
	await _route_run("M3 long, thermal kit + logger back", LONG_ROUTE, long_back, "", LOGGER_PART, true, STOP_M3)
	for service in ["courier", "freighter"]:
		_set_m3(service)
		await _route_run("M3 short, kit + logger, %s" % service, SHORT_ROUTE, short_back, "", LOGGER_PART, true, STOP_M3)
		await _route_run("M3 long, kit + logger, %s" % service, LONG_ROUTE, long_back, "", LOGGER_PART, true, STOP_M3)
	CS.reset()
	await _set_grip_wheels(true)
	await _route_run("M3 short, grip wheels + kit + logger", SHORT_ROUTE, short_back, "", LOGGER_PART, true, STOP_M3)
	await _route_run("M3 long, grip wheels + kit + logger", LONG_ROUTE, long_back, "", LOGGER_PART, true, STOP_M3)
	quit(0)


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
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000.0, 1.0, 2000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	level.add_child(floor_body)
	floor_body.global_position = FLOOR
	rover = level.get_node("ReadyRover")
	director = level.get_tree().get_first_node_in_group("mission_director")
	await physics_frame
	await physics_frame
	GS.drive(rover)
	await _ticks(1.0)
	if "routes" in OS.get_cmdline_user_args():
		var pad: Node = level.get_node("Workshop").pad
		print("INFO Kite at load: on the pad's power %s, %.2f m from the dock point" % [rover.external_power, pad.offset_of(rover).length()])
		await _routes()
		return

	# 1. Mass
	await _set_cargo("")
	var empty_mass: float = rover.mass
	await _set_cargo(MODULE)
	var loaded_mass: float = rover.mass
	_check("mass: standard build %.0f kg, +12 kg with the radio module" % REFERENCE_MASS,
		is_equal_approx(empty_mass, REFERENCE_MASS) and is_equal_approx(loaded_mass - empty_mass, 12.0),
		"empty %.1f kg, loaded %.1f kg, rolling coefficient %.3f" % [empty_mass, loaded_mass, rover.rolling_resistance_coefficient])

	# 2. Same drive
	await _set_cargo("")
	var empty_drive: Dictionary = await _fixed_drive(0.5, 12.0)
	await _set_cargo(MODULE)
	var loaded_drive: Dictionary = await _fixed_drive(0.5, 12.0)
	var detail: String = "empty %.1f m, %.2f m/s, %.3f Wh; loaded %.1f m, %.2f m/s, %.3f Wh" % [empty_drive["distance"],
		empty_drive["top"], empty_drive["wh"], loaded_drive["distance"], loaded_drive["top"], loaded_drive["wh"]]
	_check("same drive: loaded Kite is slower (less distance, lower top speed)",
		loaded_drive["distance"] < empty_drive["distance"] and loaded_drive["top"] < empty_drive["top"], detail)
	_check("same drive: loaded Kite uses more Wh, and more per metre", loaded_drive["wh"] > empty_drive["wh"]
		and loaded_drive["wh"] / loaded_drive["distance"] > empty_drive["wh"] / empty_drive["distance"], detail)
	var loaded_launch: Dictionary = await _fixed_drive(1.0, 1.0)
	await _set_cargo("")
	var empty_launch: Dictionary = await _fixed_drive(1.0, 1.0)
	_check("full throttle: loaded Kite accelerates slower (distance in the first second)",
		loaded_launch["distance"] < empty_launch["distance"],
		"loaded %.2f m, empty %.2f m" % [loaded_launch["distance"], empty_launch["distance"]])

	# 3. Holding speed, then coasting
	var empty_hold: Dictionary = await _hold_speed(3.0, 10.0)
	var empty_coast: Dictionary = await _coast(1.0)
	await _set_cargo(MODULE)
	var loaded_hold: Dictionary = await _hold_speed(3.0, 10.0)
	var loaded_coast: Dictionary = await _coast(1.0)
	_check("holding 3 m/s: loaded Kite draws more power", loaded_hold["watts"] > empty_hold["watts"] * 1.05,
		"empty %.0f W (%.4f Wh/m at %.2f m/s), loaded %.0f W (%.4f Wh/m at %.2f m/s)" % [empty_hold["watts"],
		empty_hold["wh_per_m"], empty_hold["speed"], loaded_hold["watts"], loaded_hold["wh_per_m"], loaded_hold["speed"]])
	_check("coasting: off the throttle Kite slows down, empty and loaded",
		empty_coast["v1"] < empty_coast["v0"] - 0.3 and loaded_coast["v1"] < loaded_coast["v0"] - 0.3,
		"empty %.2f -> %.2f m/s, loaded %.2f -> %.2f m/s in 1 s" % [empty_coast["v0"], empty_coast["v1"],
		loaded_coast["v0"], loaded_coast["v1"]])

	# 4. Grip wheels on flat ground
	await _set_cargo("")
	var standard_hold: Dictionary = await _hold_speed(3.0, 10.0)
	await _set_grip_wheels(true)
	var grip_mass: float = rover.mass
	var grip_hold: Dictionary = await _hold_speed(3.0, 10.0)
	await _set_grip_wheels(false)
	_check("grip wheels: heavier, and more Wh per metre on flat ground",
		is_equal_approx(grip_mass - REFERENCE_MASS, 8.0) and grip_hold["wh_per_m"] > standard_hold["wh_per_m"] * 1.1,
		"standard %.4f Wh/m, 4 grip wheels %.4f Wh/m (+%.1f kg)" % [standard_hold["wh_per_m"], grip_hold["wh_per_m"], grip_mass - REFERENCE_MASS])

	# 6. The return estimate learns the loaded consumption
	var learned_empty: float = await _learned_wh_per_m(false)
	var learned_loaded: float = await _learned_wh_per_m(true)
	await _ticks(30.0)
	var learned_after_stop: float = director.wh_per_metre()
	await _set_cargo("")
	_check("return estimate: learned Wh per metre is higher when loaded", learned_loaded > learned_empty,
		"empty %.4f, loaded %.4f Wh/m" % [learned_empty, learned_loaded])
	_check("return estimate: 30 s stopped (electronics still on) doesn't change the learned Wh per metre",
		absf(learned_after_stop - learned_loaded) < learned_loaded * 0.05,
		"%.4f before, %.4f after the stop" % [learned_loaded, learned_after_stop])

	# 7. Heater: draws only in an active cold zone (M3, daylight: the short route's shade) with it fitted
	_set_m3("courier")
	for socket_name in THERMAL:
		await _mount_in(socket_name, THERMAL[socket_name])
	var shade: Vector3 = level.get_node("ColdZones/ShortRouteShade").global_position
	await _place()
	var sunlit: float = rover.heater_power
	rover.global_transform = Transform3D(Basis.IDENTITY, Vector3(shade.x, START.y, shade.z))
	await _ticks(1.0)
	var in_shade: float = rover.heater_power
	await _mount_in("HeaterSocket", "")
	await _ticks(0.5)
	var no_heater: float = rover.heater_power
	await _mount_in("ThermalCoverSocket", "")
	CS.reset()
	_check("heater: draws in the shade only, and only when fitted", sunlit == 0.0 and in_shade == rover.HEATER_POWER and no_heater == 0.0,
		"sunlit %.0f W, in shade %.0f W, unfitted %.0f W" % [sunlit, in_shade, no_heater])

	# 5. Energy
	_check("energy: shaft work never exceeds the electrical energy drawn",
		mechanical_j <= electrical_j and worst_step_excess <= 0.001,
		"shaft %.0f J, electrical %.0f J (%.0f%%), worst step excess %.4f W" % [mechanical_j, electrical_j,
		100.0 * mechanical_j / maxf(electrical_j, 0.001), worst_step_excess])

	print("RESULT test_rover_mass %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
