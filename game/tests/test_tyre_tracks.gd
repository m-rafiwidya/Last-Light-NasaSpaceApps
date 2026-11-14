extends SceneTree
## Headless test of the tyre tracks (TyreTracks, TrackLog, TrackMap, TrackRaster): what is printed,
## where, and that it lasts. How it looks needs a window (tools/render_tracks_previews.gd).
##   - Moon, open ground, 30% for 8 s: prints under both wheel lines (pressed down, compacted, in the
##     fine tiles and the coarse map) and none between them;
##   - parked: no new prints; driving in the workshop's bay (not dusty ground): none;
##   - airborne (dropped from 2 m while driving): no prints in the air, each wheel starts a new run
##     on landing and no segment spans the jump;
##   - a 200 m drive at full throttle: the near tiles stay within their cap and range, the coarse map
##     still has the first prints, and the log's size per km;
##   - tiles drawn again from the log come out byte for byte as drawn live (every tile both hold);
##   - test level: the floor takes prints, its material is the one bound; the Moon's tracks are all
##     there again (same log, same tiles, same coarse map) after test level -> Moon;
##   - texture memory at High and Low; Off: no tracks.
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_tyre_tracks.gd

const TICKS: int = 240
# RunningGear.WheelState (this script compiles before the game's autoloads exist)
const IN_CONTACT: int = 3
const UNDISTURBED: int = 170

var GS: Node
var SL: Node
var failures: int = 0
var level: Node


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


func _load(level_id: String) -> void:
	SL.load_scene(level_id)
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == level_id and SL.current_scene):
		await physics_frame
	level = SL.current_scene
	await _ticks(0.5)


func _place(rover: Node, xform: Transform3D) -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(a)
	rover.global_transform = xform
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	for wheel in rover.running_gear.wheel_states:
		rover.running_gear.wheel_states[wheel][0] = 0.0


# Drives at `throttle` for `seconds`; returns the rover's transforms every 0.25 s
func _drive(rover: Node, throttle: float, seconds: float) -> Array:
	Input.action_press("move_forward", throttle)
	var poses: Array = []
	for i in int(seconds * 4):
		await _ticks(0.25)
		poses.append(rover.global_transform)
	Input.action_release("move_forward")
	return poses


# Prints under the wheel lines (x +-0.5 under the rover) and none on its centre line, at the poses
# the rover passed with at least `settle` m behind it; [wheel-line texels pressed, of, centre texels
# untouched, of, coarse covered, of]
func _prints_along(tracks: Node, poses: Array) -> Array:
	tracks.map.update_residency(Vector2(poses[-1].origin.x, poses[-1].origin.z))
	tracks.map.flush()
	var counts: Array = [0, 0, 0, 0, 0, 0]
	for k in range(4, poses.size() - 2):
		var pose: Transform3D = poses[k]
		for side in [-0.5, 0.5]:
			var p: Vector3 = pose * Vector3(side, 0.0, 0.0)
			var texel: PackedByteArray = tracks.map.fine_texel_at(p.x, p.z)
			counts[1] += 1
			if texel.size() == 2 and texel[1] > 200 and texel[0] < UNDISTURBED:
				counts[0] += 1
			counts[5] += 1
			# (the nearest coarse texel: up to 18 cm off the line at 25 cm texels)
			if tracks.map.coarse_at(p.x, p.z) > 50:
				counts[4] += 1
		var c: Vector3 = pose.origin
		var middle: PackedByteArray = tracks.map.fine_texel_at(c.x, c.z)
		counts[3] += 1
		if middle.size() == 2 and middle[1] == 0 and middle[0] == UNDISTURBED:
			counts[2] += 1
	return counts


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	load("res://src/effects/tyre_tracks/track_log.gd").clear_all()

	# --- Moon ---
	await _load("moon_level")
	var tracks: Node = level.get_node_or_null("TyreTracks")
	_check("Moon: the level has its tracks", tracks != null and tracks.map != null)
	var rover: Node = level.get_node("ReadyRover")
	var workshop: Node3D = level.get_node("Workshop")
	var terrain: Node = level.get_node("Terrain")
	_check("Moon: tracks cover the play area", tracks.map.area == Rect2(-512, -512, 1024, 1024), "%s" % tracks.map.area)
	GS.drive(rover)
	var out: Vector3 = workshop.to_global(Vector3(0.0, 0.0, -30.0))
	out.y = terrain.height_at(out.x, out.z) + 0.3
	var start := Transform3D(workshop.global_basis, out)
	_place(rover, start)
	await _ticks(3.0)
	var parked_points: int = tracks.track_log.point_count()
	await _ticks(3.0)
	_check("Moon: parked: no new prints", tracks.track_log.point_count() == parked_points,
		"%d points before, %d after 3 s" % [parked_points, tracks.track_log.point_count()])

	var poses: Array = await _drive(rover, 0.3, 8.0)
	var counts: Array = _prints_along(tracks, poses)
	_check("Moon 30%: prints under both wheel lines", counts[0] == counts[1], "%d of %d texels pressed and compacted" % [counts[0], counts[1]])
	_check("Moon 30%: none between them", counts[2] == counts[3], "%d of %d centre-line texels untouched" % [counts[2], counts[3]])
	_check("Moon 30%: the coarse map has them", counts[4] == counts[5], "%d of %d" % [counts[4], counts[5]])
	var runs: int = tracks.track_log.point_count() - tracks.track_log.segment_count()
	print("INFO Moon 30%%: %d points in %d runs" % [tracks.track_log.point_count(), runs])

	# A tile drawn live (as the rover drove) against the same tile drawn from the log: the same bytes
	var map_script: GDScript = load("res://src/effects/tyre_tracks/track_map.gd")
	var key: Vector2i = tracks.map.tile_at(poses[10].origin.x, poses[10].origin.z)
	var live_focus := Vector2(poses[10].origin.x, poses[10].origin.z)
	tracks.map.update_residency(live_focus)
	tracks.map.flush()
	var fresh = map_script.new(tracks.track_log, tracks.map.area, tracks.map.fine_n, tracks.map.fine_cap, tracks.map.coarse_n, tracks.map.radius, false)
	fresh.update_residency(live_focus)
	fresh.flush()
	var compared: Array = _compare_tiles(tracks.map, fresh)
	_check("Tiles drawn live and drawn again from the log: byte for byte", compared[0] > 1 and compared[1] == 0,
		"%d tiles compared, %d differ" % [compared[0], compared[1]])
	_check("The coarse map drawn again from the log: byte for byte", tracks.map.coarse_data == fresh.coarse_data)

	# Driving in the bay: the workshop's floor isn't dusty ground
	await _ticks(3.0)
	_place(rover, workshop.get_dock_transform().translated(Vector3.UP * 0.05))
	await _ticks(2.0)
	var bay_points: int = tracks.track_log.point_count()
	Input.action_press("move_backward", 0.25)
	await _ticks(1.5)
	Input.action_release("move_backward")
	_check("Moon: driving in the bay: no prints", tracks.track_log.point_count() == bay_points, "%d new points" % (tracks.track_log.point_count() - bay_points))
	await _ticks(2.0)

	# Airborne
	_place(rover, start.translated(Vector3(3.0, 0.0, 0.0)))
	await _ticks(2.0)
	Input.action_press("move_forward", 0.5)
	await _ticks(2.0)
	var before_jump: int = tracks.track_log.point_count()
	var starts_before: int = before_jump - tracks.track_log.segment_count()
	rover.global_position += Vector3.UP * 2.0
	await physics_frame
	await physics_frame
	var in_air_points: int = -1
	for i in TICKS * 3:
		await physics_frame
		var any_contact: bool = false
		for wheel in rover.running_gear.wheel_states:
			if rover.running_gear.wheel_states[wheel][IN_CONTACT]:
				any_contact = true
		if any_contact:
			in_air_points = tracks.track_log.point_count() - before_jump
			break
	await _ticks(1.0)
	Input.action_release("move_forward")
	var starts_after: int = tracks.track_log.point_count() - tracks.track_log.segment_count()
	var longest: float = 0.0
	var pts: PackedFloat32Array = tracks.track_log.points
	for i in range(before_jump, tracks.track_log.point_count()):
		var j: int = tracks.track_log.previous[i]
		if j >= 0:
			longest = maxf(longest, Vector2(pts[i * 5] - pts[j * 5], pts[i * 5 + 1] - pts[j * 5 + 1]).length())
	_check("Moon: airborne: no prints in the air", in_air_points == 0, "%d points while in the air" % in_air_points)
	_check("Moon: landing: every wheel starts a new run", starts_after - starts_before == 6, "%d new runs" % (starts_after - starts_before))
	_check("Moon: no segment spans the jump", longest < 0.3, "longest %.2f m" % longest)
	await _ticks(3.0)

	# A long drive: 200 m at full throttle
	_place(rover, start.translated(Vector3(-3.0, 0.0, 0.0)))
	await _ticks(2.0)
	var log_bytes_before: int = tracks.track_log.memory_bytes()
	var long_start: Vector3 = rover.global_position
	Input.action_press("move_forward", 1.0)
	var driven: float = 0.0
	var peak_tiles: int = 0
	var far_tiles: int = 0
	for i in TICKS * 90:
		await physics_frame
		if i % 60 == 0:
			await process_frame
			peak_tiles = maxi(peak_tiles, tracks.map.tiles.size())
		driven = Vector2(rover.global_position.x - long_start.x, rover.global_position.z - long_start.z).length()
		if driven > 200.0:
			break
	Input.action_release("move_forward")
	await _ticks(4.0)
	var focus := Vector2(rover.global_position.x, rover.global_position.z)
	tracks.map.update_residency(focus)
	tracks.map.flush()
	for tile_key in tracks.map.tiles:
		var centre: Vector2 = tracks.map.area.position + (Vector2(tile_key) + Vector2(0.5, 0.5)) * 8.0
		if centre.distance_to(focus) > tracks.map.radius + 8.0 and tracks.map.tiles.size() >= tracks.map.fine_cap:
			far_tiles += 1
	var first: Vector3 = poses[6] * Vector3(0.5, 0.0, 0.0)
	_check("Long drive: 200 m", driven > 200.0, "%.0f m" % driven)
	_check("Long drive: near tiles within their cap", peak_tiles <= tracks.map.fine_cap, "at most %d held of %d" % [peak_tiles, tracks.map.fine_cap])
	_check("Long drive: the first prints are still in the coarse map", tracks.map.coarse_at(first.x, first.z) > 50, "%d" % tracks.map.coarse_at(first.x, first.z))
	var per_km: float = (tracks.track_log.memory_bytes() - log_bytes_before) / maxf(driven / 1000.0, 0.001) / 1048576.0
	print("MEASURE log: %.1f MB per km driven (all six wheels), %d points in all" % [per_km, tracks.track_log.point_count()])

	# Stopped dead (it would still be coasting from 200 m at full throttle), then the snapshot
	_place(rover, rover.global_transform)
	await _ticks(2.0)
	var moon_points: int = tracks.track_log.point_count()
	tracks.map.update_residency(live_focus)
	tracks.map.flush()
	var moon_map = tracks.map

	# --- Test level ---
	await _load("test_level")
	tracks = level.get_node_or_null("TyreTracks")
	var floor_node: Node = level.get_node("NavigationRegion3D/CSGBox3D")
	_check("Test level: tracks cover the floor", tracks != null and tracks.map.area == Rect2(-64, -64, 128, 128), "%s" % (tracks.map.area if tracks else "none"))
	_check("Test level: the floor's material is the one bound", tracks.materials == [floor_node.material_override]
		and floor_node.material_override.get_shader_parameter("tracks_area") == Vector3(-64, -64, 128))
	rover = level.get_node("ReadyRover")
	GS.drive(rover)
	_place(rover, Transform3D(Basis.IDENTITY, Vector3(30.0, 0.3, 40.0)))
	await _ticks(2.0)
	poses = await _drive(rover, 0.3, 6.0)
	counts = _prints_along(tracks, poses)
	_check("Test level 30%: prints under both wheel lines", counts[0] == counts[1], "%d of %d" % [counts[0], counts[1]])
	_check("Test level 30%: none between them", counts[2] == counts[3], "%d of %d" % [counts[2], counts[3]])
	await _ticks(3.0)

	# --- The Moon again: its tracks are all there ---
	await _load("moon_level")
	tracks = level.get_node("TyreTracks")
	tracks.map.update_residency(live_focus)
	tracks.map.flush()
	_check("Moon again: the same log", tracks.track_log.point_count() == moon_points, "%d points (%d before)" % [tracks.track_log.point_count(), moon_points])
	var reloaded: Array = _compare_tiles(tracks.map, moon_map)
	_check("Moon again: the same tiles", reloaded[0] > 1 and reloaded[1] == 0, "%d tiles compared, %d differ" % [reloaded[0], reloaded[1]])
	_check("Moon again: the same coarse map", tracks.map.coarse_data == moon_map.coarse_data)
	_check("Moon again: the coarse map has the first prints", tracks.map.coarse_at(first.x, first.z) > 50)

	# --- Memory ---
	print("MEASURE texture memory: High %.1f MB, Low %.1f MB on the Moon (fine %d / %d tiles of %d texels, coarse %d x %d of %d)" % [
		_bytes_for(map_script, tracks, 512, 48, 258) / 1048576.0, _bytes_for(map_script, tracks, 256, 32, 130) / 1048576.0,
		48, 32, 512, tracks.map.coarse_per_side, tracks.map.coarse_per_side, 258])

	# --- Off ---
	GraphicsSettings.surface_effects = GraphicsSettings.SurfaceEffects.OFF
	await _load("test_level")
	_check("Off: no tracks", level.get_node_or_null("TyreTracks") == null)
	GraphicsSettings.surface_effects = GraphicsSettings.SurfaceEffects.HIGH

	print("DONE %d failures" % failures)
	quit(1 if failures else 0)


# Every fine tile both maps hold, byte for byte: [compared, differing]
func _compare_tiles(a, b) -> Array:
	var compared: int = 0
	var differing: int = 0
	for tile_key in a.tiles:
		if a.tiles[tile_key]["ready"] and b.tiles.has(tile_key) and b.tiles[tile_key]["ready"]:
			compared += 1
			if a.fine_data[a.tiles[tile_key]["layer"]] != b.fine_data[b.tiles[tile_key]["layer"]]:
				differing += 1
	return [compared, differing]


func _bytes_for(map_script: GDScript, tracks: Node, fine_n: int, cap: int, coarse_n: int) -> int:
	var m = map_script.new(tracks.track_log, tracks.map.area, fine_n, cap, coarse_n, 40.0, false)
	return m.texture_bytes()
