extends SceneTree
## Headless test: the crew lander (src/field/lander.tscn, tools/blender/LANDER_KIT.md) in the Moon level.
##   1. Model: the markers, the moving pieces, under 6,000 triangles.
##   2. Placement: 40-50 m from the bay door, the footprint under 3 degrees, clear of the IRIS lane
##      and both M3 routes; ramp down at load with its foot on the ground.
##   3. Walk-out: the opening, skipped, leaves the player on the porch with the ramp down; from
##      the Hatch marker the player walks (move_forward, the body animating) down
##      the ramp, over the ground to the bay door and in: boots on the ramp, no fall, the walk
##      blend on, m1.workshop_entered completed.
##   4. Flight: away from its spot the ramp folds up and the hatch shuts; back, the hatch light
##      lowers the ramp and opens the hatch.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_lander.gd

const TICKS: int = 240
const RAMP_SLOPE_DEG: float = 30.0

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-66s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _wait(condition: Callable, seconds: float = 120.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if condition.call():
			return true
		await process_frame
	return false


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t: float = clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return p.distance_to(a + (b - a) * t)


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	var SI: GDScript = load("res://src/save/save_index.gd")
	load("res://src/cutscene/cutscene_director.gd").autoplay = true
	await _wait(func() -> bool: return GS.state == GS.State.MAIN_MENU)
	CS.reset()
	SI.start_new_campaign("slot_3")
	if not await _wait(func() -> bool: return SL.current_level_id == "moon_level" and SL.loading_scene_id.is_empty() and GS.state == GS.State.CUTSCENE):
		_check("the Moon level comes up with the opening", false)
		_finish()
		return
	var level: Node = SL.current_scene
	var cutscenes: Node = level.get_node("MissionDirector/Cutscenes")
	await _ticks(1.0)
	cutscenes.skip()
	await _wait(func() -> bool: return GS.state == GS.State.IN_GAME_PLAYER, 10.0)
	await _ticks(0.5)
	var lander = level.get_node("Lander")
	var workshop: Node3D = level.get_node("Workshop")
	var terrain: Node = level.get_node("Terrain")

	# 1. Model
	var markers: bool = ["Hatch", "EngineGlow", "PlumePoint", "RampFoot", "HatchLight", "RampHinge"].all(
		func(n: String) -> bool: return lander.has_node(n))
	var pieces: bool = ["lander_ramp_upper", "lander_ramp_lower", "lander_hatch_leaf"].all(
		func(n: String) -> bool: return lander.get_node("Model").find_child(n, true, false) != null)
	_check("[model] markers and moving pieces", markers and pieces)
	var triangles: int = 0
	for m in lander.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		for s in m.mesh.get_surface_count():
			triangles += m.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	_check("[model] under 6,000 triangles", triangles > 1000 and triangles < 6000, str(triangles))
	_check("[model] after the opening: engine off, hatch light on", not lander.engine_glow.visible and lander.hatch_light.visible)

	# 2. Placement
	var door: Vector3 = workshop.to_global(Vector3(-1.0, 0.0, -4.0))
	var at := Vector2(lander.global_position.x, lander.global_position.z)
	var door_distance: float = at.distance_to(Vector2(door.x, door.z))
	_check("[place] 40-50 m from the bay door", door_distance >= 40.0 and door_distance <= 50.0, "%.1f m" % door_distance)
	var samples: Array[Vector3] = []
	for r in [0.0, 2.0, 4.3]:
		for k in 12:
			var p: Vector3 = lander.to_global(Vector3(r * cos(k * TAU / 12.0), 0.0, r * sin(k * TAU / 12.0)))
			samples.append(Vector3(p.x, terrain.height_at(p.x, p.z), p.z))
	var slope: float = _plane_slope(samples)
	_check("[place] footprint under 3 degrees", slope < 3.0, "%.2f deg" % slope)
	var iris: Vector3 = level.get_node("Iris").global_position
	var lanes: Array = [[Vector2(door.x, door.z), Vector2(iris.x, iris.z)]]
	var routes: Node = level.get_node("RouteMarkers")
	for route in [routes.short_route, routes.long_route]:
		lanes.append([Vector2(door.x, door.z), route[0]])
		for i in route.size() - 1:
			lanes.append([route[i], route[i + 1]])
	var clearance: float = INF
	for lane in lanes:
		clearance = minf(clearance, _segment_distance(at, lane[0], lane[1]))
	_check("[place] clear of the IRIS lane and the M3 routes", clearance > 15.0, "%.1f m" % clearance)
	var foot: Vector3 = lander.get_node("RampFoot").global_position
	_check("[place] ramp down at load, its foot on the ground", lander.is_deployed()
		and absf(foot.y - terrain.height_at(foot.x, foot.z)) < 0.1, "%.3f m" % (foot.y - terrain.height_at(foot.x, foot.z)))

	# 3. Walk-out
	var player = GS.player
	var body = player.get_node("Body")
	var hatch: Node3D = lander.hatch
	_check("[walk] after the skipped opening: on the porch at the hatch, m1.workshop_entered current",
		player.global_position.distance_to(hatch.global_position) < 0.3 and player.is_on_floor
		and CS.current_objective() == "m1.workshop_entered", "%.2f m" % player.global_position.distance_to(hatch.global_position))
	var out: Vector3 = -lander.global_basis.z
	var waypoints: Array[Vector3] = [lander.to_global(Vector3(0.0, 0.0, -8.5)), workshop.to_global(Vector3(-1.0, 0.0, -6.0)),
		workshop.to_global(Vector3(-1.0, 0.0, 0.0))]
	var ramp_samples: int = 0
	var ramp_worst: float = 0.0
	var descent_samples: int = 0
	var descent_floor: int = 0
	var walk_blend: float = 0.0
	var walk_frames: int = 0
	var lowest_vy: float = 0.0
	var reached_ground: bool = false
	var arrived: bool = false
	var hinge: Vector3 = lander.get_node("RampHinge").global_position
	var run: float = (lander.get_node("RampFoot").global_position - hinge).dot(out)
	var start: float = (hatch.global_position - hinge).dot(out)
	Input.action_press(&"move_forward")
	for i in 90 * TICKS:
		var target: Vector3 = waypoints[0]
		var to: Vector3 = target - player.global_position
		to.y = 0.0
		if to.length() < 1.0:
			waypoints.pop_front()
			if waypoints.is_empty():
				break
			continue
		player.controller.camera_azimuth = atan2(-to.x, -to.z)
		await physics_frame
		var along: float = (player.global_position - hinge).dot(out)
		if along > start + 0.2 and along < run - 0.3:
			descent_samples += 1
			descent_floor += 1 if player.is_on_floor else 0
		if along > 0.3 and along < run - 0.3:
			var surface: float = hinge.y - along * tan(deg_to_rad(RAMP_SLOPE_DEG))
			ramp_worst = maxf(ramp_worst, maxf(absf(body.suit.global_position.y - surface), absf(player.global_position.y - surface)))
			ramp_samples += 1
		if along > run + 1.0:
			reached_ground = true
		if i > TICKS:
			walk_blend += float(body.tree.get("parameters/move/blend_amount"))
			walk_frames += 1
			lowest_vy = minf(lowest_vy, player.linear_velocity.y)
		if CS.is_objective_done("m1.workshop_entered"):
			arrived = true
			break
	Input.action_release(&"move_forward")
	_check("[walk] porch to ramp foot: on the floor, boots and body on the ramp", ramp_samples > 100 and ramp_worst < 0.08
		and descent_floor >= descent_samples * 0.95, "worst %.3f m, on the floor %d of %d" % [ramp_worst, descent_floor, descent_samples])
	_check("[walk] onto the ground past the ramp's foot, no fall", reached_ground and lowest_vy > -2.5, "lowest %.2f m/s" % lowest_vy)
	_check("[walk] the body walks (move blend)", walk_frames > 0 and walk_blend / walk_frames > 0.7,
		"%.2f" % (walk_blend / maxf(walk_frames, 1)))
	_check("[walk] to the bay door and in: m1.workshop_entered", arrived, "%.1f m from the last waypoint" % (
		player.global_position.distance_to(workshop.to_global(Vector3(-1.0, 0.0, 0.0)))))

	# 4. Flight
	var rest: Vector3 = lander.global_position
	lander.global_position = rest + Vector3(0.0, 200.0, 0.0)
	await _ticks(0.1)
	_check("[flight] away from its spot: ramp folded, hatch shut", lander.deployed == 0.0
		and absf(lander.get_node("RampHinge").rotation_degrees.x - 90.0) < 0.5)
	lander.global_position = rest
	await _ticks(0.5)
	_check("[flight] landed, it stays folded until the hatch light", lander.deployed == 0.0)
	lander.set_hatch_light(true)
	await _ticks(2.0)
	_check("[flight] the ramp is coming down, the hatch still shut", lander.deployed > 0.2 and lander.deployed < 0.7
		and lander.get_node("Model").find_child("lander_hatch_leaf", true, false).rotation.y == 0.0)
	await _ticks(3.0)
	_check("[flight] the ramp down, the hatch open", lander.is_deployed()
		and absf(lander.get_node("RampHinge").rotation_degrees.x + RAMP_SLOPE_DEG) < 0.5)
	_finish()


## Steepest slope (degrees) of the least-squares plane through `points`
func _plane_slope(points: Array[Vector3]) -> float:
	var n: float = points.size()
	var sx: float = 0.0
	var sz: float = 0.0
	var sy: float = 0.0
	for p in points:
		sx += p.x
		sz += p.z
		sy += p.y
	var cx: float = sx / n
	var cz: float = sz / n
	var cy: float = sy / n
	var xx: float = 0.0
	var xz: float = 0.0
	var zz: float = 0.0
	var xy: float = 0.0
	var zy: float = 0.0
	for p in points:
		var dx: float = p.x - cx
		var dz: float = p.z - cz
		var dy: float = p.y - cy
		xx += dx * dx
		xz += dx * dz
		zz += dz * dz
		xy += dx * dy
		zy += dz * dy
	var det: float = xx * zz - xz * xz
	var a: float = (xy * zz - zy * xz) / det
	var b: float = (zy * xx - xy * xz) / det
	return rad_to_deg(atan(Vector2(a, b).length()))


func _finish() -> void:
	var path: String = load("res://src/save/save_index.gd").slot_path("slot_3")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	print("RESULT test_lander %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
