extends SceneTree
## Measurement (not a pass / fail test): how long the suit's oxygen has to last (EvaRescue.capacity_s).
##   oxygen >= walk out + pickup and alignment + carry home + airlock entry, plus a 30% margin,
## to the farthest place Kite can strand: the far-rim logger by the long route (M3), and the landing zone (M2).
## Walking and carrying speeds are measured on the real terrain along the long route (three 40 s legs at
## 15%, 50% and 85% of it, standing start included), the path lengths are the route's own polyline.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/measure_eva_oxygen.gd

const TICKS: int = 240
var PLAYER: GDScript
var GUIDANCE: GDScript
var SAVE_GATE: GDScript
const LEG_SECONDS: float = 40.0
const PICKUP_SECONDS: float = 10.0
const ENTRY_SECONDS: float = 15.0
const MARGIN: float = 1.30

var GS: Node
var SL: Node
var CS: Node
var level: Node3D
var player: RigidBody3D
var rover: RigidBody3D
var workshop: Node3D


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _ground(at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 30.0, 1)
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if hit else at.y


func _length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


func _point_at(points: PackedVector2Array, distance: float) -> Array:
	var walked: float = 0.0
	for i in range(1, points.size()):
		var seg: float = points[i].distance_to(points[i - 1])
		if walked + seg >= distance:
			var t: float = (distance - walked) / seg
			return [points[i - 1].lerp(points[i], t), (points[i] - points[i - 1]).normalized()]
		walked += seg
	return [points[points.size() - 1], Vector2.RIGHT]


## Walks (or carries Kite) for LEG_SECONDS from `at` along `dir` (xz), returns the speed over the ground (m/s)
func _leg(at: Vector2, dir: Vector2, carry: bool) -> float:
	var start := Vector3(at.x, 0.0, at.y)
	start.y = _ground(start)
	player.global_position = start + Vector3.UP * 1.1
	player.linear_velocity = Vector3.ZERO
	player.controller.camera_azimuth = atan2(-dir.x, -dir.y)
	player.controller.camera_altitude = 0.0
	if carry:
		var ahead: Vector3 = start + Vector3(dir.x, 0.0, dir.y) * 2.0
		rover.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(ahead.x, _ground(ahead) + 0.4, ahead.z))
		rover.linear_velocity = Vector3.ZERO
		await _ticks(1.0)
		player.holder.pickup(rover)
	await _ticks(1.0)
	var from: Vector3 = player.global_position
	Input.action_press(&"move_forward")
	await _ticks(LEG_SECONDS)
	Input.action_release(&"move_forward")
	var to: Vector3 = player.global_position
	if carry:
		player.holder.release()
		await _ticks(0.5)
	return Vector2(to.x - from.x, to.z - from.z).length() / LEG_SECONDS


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	PLAYER = load("res://src/player/player.gd")
	GUIDANCE = load("res://src/levels/guidance.gd")
	SAVE_GATE = load("res://src/save/save_gate.gd")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	CS.reset()
	load("res://src/save/save_index.gd").start_new_campaign()
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	player = GS.player
	rover = level.get_node("ReadyRover")
	workshop = level.get_node("Workshop")
	await _ticks(2.0)
	var markers: Node = level.get_node("RouteMarkers")
	var pad := Vector2(workshop.global_position.x, workshop.global_position.z)
	var logger := Vector2(level.get_node("FarLogger").global_position.x, level.get_node("FarLogger").global_position.z)
	var lz := Vector2(level.get_node("LandingZone").global_position.x, level.get_node("LandingZone").global_position.z)
	var walk: Array[float] = []
	var carry: Array[float] = []
	var long_route: PackedVector2Array = markers.route("long")
	var total_long: float = _length(long_route)
	for share in [0.15, 0.5, 0.85]:
		var at: Array = _point_at(long_route, total_long * share)
		var w: float = await _leg(at[0], at[1], false)
		var c: float = await _leg(at[0], at[1], true)
		walk.append(w)
		carry.append(c)
		print("LEG  at %d%% of the long route: walk %.2f m/s, carry %.2f m/s" % [roundi(share * 100.0), w, c])
	var v_walk: float = walk.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / walk.size()
	var v_carry: float = carry.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / carry.size()
	print("MEAN walk %.2f m/s (nominal %.1f), carry %.2f m/s (nominal %.1f)" % [v_walk, PLAYER.SPEED_WALK, v_carry, PLAYER.SPEED_CARRY])
	var worst: float = 0.0
	for item in [["far-rim logger, long route", pad.distance_to(long_route[0]) + total_long + long_route[long_route.size() - 1].distance_to(logger)],
			["far-rim logger, short route", pad.distance_to(markers.route("short")[0]) + _length(markers.route("short")) + markers.route("short")[markers.route("short").size() - 1].distance_to(logger)],
			["far-rim logger, straight line", pad.distance_to(logger)],
			["landing zone, straight line", pad.distance_to(lz)]]:
		var path: float = item[1]
		var seconds: float = path / v_walk + PICKUP_SECONDS + path / v_carry + ENTRY_SECONDS
		print("SITE %-32s %5.0f m  walk %4.0f s + pickup %.0f s + carry %4.0f s + entry %.0f s = %4.0f s (%.1f min), with margin %.0f s (%.1f min)" % [
			item[0], path, path / v_walk, PICKUP_SECONDS, path / v_carry, ENTRY_SECONDS, seconds, seconds / 60.0, seconds * MARGIN, seconds * MARGIN / 60.0])
		worst = maxf(worst, seconds)
	print("RESULT oxygen: farthest rescue %.0f s (%.1f min); capacity with %.0f%% margin = %.0f s (%.1f min); EvaRescue.capacity_s is %.0f" % [
		worst, worst / 60.0, (MARGIN - 1.0) * 100.0, worst * MARGIN, worst * MARGIN / 60.0, level.get_node("EvaRescue").capacity_s])
	quit()
