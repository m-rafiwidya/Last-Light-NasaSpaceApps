extends SceneTree
## Headless test (plan v2 G1): part values that make the loadout matter.
##   1. Batteries: the light pack is 40 Wh (its catalog text says so), the standard 100 Wh.
##   2. Range: with the standard battery Kite's range covers both M3 round trips with margin; with
##      the light one it covers neither (the plan's "default fails both routes").
##   3. Tread: high-grip (lugged) wheels cost more energy per metre, so less range.
##   4. Ground traction: Robot.ground_traction scales every wheel's friction, and on loose ground
##      (0.25) the same full throttle gets Kite less far in a second than on normal ground.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_part_values.gd

const TICKS: int = 240
const PARTS: String = "res://src/robot/socket/%s.tscn"

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D


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


## Takes a part off and parks it out of the way (not freed: RoverVisuals remembers the last wheel)
func _remove(socket: Node) -> void:
	var old: RigidBody3D = socket.unmount()
	if old:
		old.freeze = true
		old.global_position = Vector3(0.0, 500.0 + old.get_index(), 0.0)


func _swap(socket: Node, scene: String) -> Node:
	_remove(socket)
	var part: Node3D = (load(PARTS % scene) as PackedScene).instantiate()
	level.add_child(part)
	part.global_position = socket.global_position
	socket.mount(part)
	return part


func _battery(scene: String) -> void:
	var battery: Node = _swap(rover.battery_socket, scene)
	battery.charge = battery.capacity


func _wheels(scene: String) -> void:
	for socket in rover.wheel_sockets.values():
		_swap(socket, scene)


## Metres Kite covers from a standstill in `seconds` of full throttle, straight ahead
func _launch(seconds: float) -> float:
	var at := Vector3(rover.global_position.x, 0.0, rover.global_position.z)
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 50.0, at + Vector3.DOWN * 50.0, 1)
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	rover.global_transform = Transform3D(rover.global_basis, (hit["position"] if hit else at) + Vector3.UP * 0.4)
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(1.5)
	var start: Vector3 = rover.global_position
	Input.action_press("move_forward", 1.0)
	await _ticks(seconds)
	Input.action_release("move_forward")
	var moved: float = Vector2(rover.global_position.x - start.x, rover.global_position.z - start.z).length()
	await _ticks(2.0)
	return moved


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
	var routes: Node = level.get_node("RouteMarkers")
	var short_trip: float = routes.round_trip("short")
	var long_trip: float = routes.round_trip("long")
	await _ticks(0.5)

	# 1. Batteries
	var light: Node = (load(PARTS % "battery_light_part") as PackedScene).instantiate()
	var standard: Node = (load(PARTS % "battery_part") as PackedScene).instantiate()
	_check("batteries: light 40 Wh, standard 100 Wh", is_equal_approx(light.capacity, 40.0) and is_equal_approx(standard.capacity, 100.0),
		"%.0f / %.0f" % [light.capacity, standard.capacity])
	_check("batteries: the light pack's description says 40 Wh", light.get_description().contains("40 Wh"), light.get_description())
	light.free()
	standard.free()

	# 2. Range (Kite picks up a new battery on its next physics step)
	_battery("battery_part")
	await _ticks(0.1)
	var standard_range: float = rover.range_estimate()
	_check("range: the standard battery covers both M3 round trips with 50% to spare",
		standard_range > 1.5 * maxf(short_trip, long_trip),
		"range %.0f m, short %.0f m, long %.0f m" % [standard_range, short_trip, long_trip])
	_battery("battery_light_part")
	await _ticks(0.1)
	var light_range: float = rover.range_estimate()
	_check("range: the light battery covers neither M3 round trip", light_range < minf(short_trip, long_trip),
		"range %.0f m" % light_range)
	rover.battery.charge = rover.battery.capacity * 0.5
	_check("range: half the charge, half the range", is_equal_approx(rover.range_estimate(), light_range * 0.5))
	_battery("battery_part")
	await _ticks(0.1)

	# 3. Tread
	var standard_cost: float = rover.planned_wh_per_metre()
	_wheels("wheel_high_grip_part")
	await _ticks(0.2)
	_check("tread: high-grip wheels cost more per metre", rover.planned_wh_per_metre() > standard_cost * 1.1,
		"%.4f vs %.4f Wh/m" % [rover.planned_wh_per_metre(), standard_cost])
	_check("tread: so less range on the same battery", rover.range_estimate() < standard_range,
		"%.0f m vs %.0f m" % [rover.range_estimate(), standard_range])
	_wheels("wheel_part")
	await _ticks(0.2)

	# 4. Ground traction
	var gear: Object = rover.running_gear
	var wheel: Variant = gear.wheel_properties.keys()[0]
	var normal_friction: float = gear.get_longitudinal_friction(wheel)
	var normal_lateral: float = gear.get_lateral_friction(wheel)
	rover.ground_traction = 0.5
	_check("traction: 0.5 halves every wheel's friction", is_equal_approx(gear.get_longitudinal_friction(wheel), normal_friction * 0.5)
		and is_equal_approx(gear.get_lateral_friction(wheel), normal_lateral * 0.5))
	rover.ground_traction = 1.0
	_check("traction: back to 1.0 restores it", is_equal_approx(gear.get_longitudinal_friction(wheel), normal_friction))
	GS.drive(rover)
	await _ticks(0.3)
	var firm: float = await _launch(1.5)
	rover.ground_traction = 0.25
	var loose: float = await _launch(1.5)
	rover.ground_traction = 1.0
	_check("traction: on loose ground the same throttle gets Kite less far", loose < firm * 0.9,
		"%.2f m firm, %.2f m loose" % [firm, loose])

	print("RESULT test_part_values %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
