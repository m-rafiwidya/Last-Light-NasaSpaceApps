extends SceneTree
## Headless test: the Moon level's real terrain (MoonTerrain, data from tools/terrain/: the Apollo
## 12 site, LROC NAC DTM).
##   1. Data and layout: the terrain is ready before the player spawns, its collision is the play
##      tier's measured 2 m posts (at either Terrain Detail: Low never thins a measured tier) and
##      equals the pipeline's play.f32, which is the untouched DTM (play_measured.f32) everywhere but
##      the graded base; the spawn, the rover and the parts pile stand on flat ground (under 3
##      degrees) and nothing fell through after 4 s.
##   2. What you see is what the wheels stand on: play-tier chunk meshes (at the base, near the LM,
##      Surveyor crater, Head crater, the centre) agree with the collision to 1 mm at every
##      triangle's centre.
##   3. Light: the horizon maps start at the sun's azimuth (the EVA 2 sun from terrain.json), the
##      base is in sunlight, and the share of the play area in sunlight is the pipeline's.
##   4. The boundary: the rover at full throttle and the player walking towards it are stopped
##      inside the play area, and the HUD warns them.
##   5. A drive over the real ground: from the base along the EVA 2 route in reverse (past Bench
##      crater, south of Surveyor crater, its west rim), down into Head crater and out to the
##      west, never within 75 m of the LM, the ALSEP or Surveyor 3, holding about 2.4 m/s, steering
##      for each waypoint, checking the wheel contact every tick and the visible wheels every frame
##      as test_wheel_contact.gd does (no wheel airborne within 5 mm of the ground, none in contact
##      inside it, no wheel mesh over 1 cm in it). It must reach every waypoint.
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_terrain.gd
##     (append `-- terrain_detail=low` for the 1 m ground)

const TICKS: int = 240
const DATA: String = "res://res/terrain/moon_apollo12/"
const GROUND_MASK: int = 1 | 4
const WHEEL_RADIUS: float = 0.15
const WHEEL_WIDTH: float = 0.24
const TOUCH_MARGIN: float = 0.005
const MESH_MARGIN: float = 0.01
# Waypoints (x, z, play coordinates): north-east from the base, west of Bench crater, south of
# Surveyor crater (towards Halo), Surveyor crater's west rim, Head crater's floor, out to the west.
# The straight lines between them keep 96 m from the LM, 134 m from the ALSEP, 162 m from Surveyor 3
const ROUTE: Array = [Vector2(-230, 90), Vector2(-150, 115), Vector2(57, 140), Vector2(57, 5), Vector2(-37, -42), Vector2(-125, -60)]
const HEAD_CRATER_FLOOR := Vector2(-37, -42)
const KEEP_OUT: float = 75.0
const BOUNDARY_Z: float = 50.0
const WAYPOINT_RADIUS: float = 12.0
const STUCK_SECONDS: float = 25.0
# Throttle: held to drive_speed like a driver would (more when slower, uphill; less when faster),
# between 10% and full. Flooring it whenever the nose is up launched it over a crest and rolled it.
# The Apollo rover's top speed was 3.6 m/s. `-- drive_speed=5` drives the route at 5 m/s instead:
# over crater rims the rover then leaves the ground and lands at 2-3 m/s, which the Moon level's
# suspension (RoverLevel.rover_suspension) takes without bottoming (test_rover_landing.gd); at
# that speed a wheel's side can still rub into a rock's flank (README 13)
const DRIVE_SPEED: float = 2.4
const DRIVE_GAIN: float = 0.5

var drive_speed: float = DRIVE_SPEED
var GS: Node
var SL: Node
var failures: int = 0
var level: Node
var terrain: Node
var rover: RigidBody3D
var meta: Dictionary
var _shape := CylinderShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var drive_stats: Dictionary = {}
var driving: bool = false


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
	print("RESULT %-64s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _ray_down(x: float, z: float, mask: int = GROUND_MASK) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 2000.0, z), Vector3(x, -2000.0, z), mask)
	q.exclude = [rover.get_rid(), terrain.get_node("Rocks/RockCollision").get_rid()]
	return root.world_3d.direct_space_state.intersect_ray(q)


func _slope_at(x: float, z: float) -> float:
	var e: float = 1.0
	var dx: float = terrain.height_at(x + e, z) - terrain.height_at(x - e, z)
	var dz: float = terrain.height_at(x, z + e) - terrain.height_at(x, z - e)
	return rad_to_deg(atan(Vector2(dx, dz).length() / (2.0 * e)))


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	meta = JSON.parse_string(FileAccess.get_file_as_string(DATA + "terrain.json"))
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	terrain = level.get_node("Terrain")
	rover = level.get_node("ReadyRover")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("drive_speed="):
			drive_speed = arg.trim_prefix("drive_speed=").to_float()
	var settings: GDScript = load("res://src/settings/graphics_settings.gd")
	var low: bool = settings.get_terrain_detail() == 1
	print("INFO terrain detail %s; %d rocks, %d with collision; driving at %.1f m/s" % ["low" if low else "high", terrain.get_node("Rocks").count, terrain.get_node("Rocks").with_collision, drive_speed])

	# 1. Data and layout
	_check("terrain ready before the player spawned", terrain.is_content_ready and GS.player != null)
	var heightmap: HeightMapShape3D = terrain.get_node("Ground").get_child(0).shape
	var play_meta: Dictionary = meta["tiers"][0]
	var expected: int = play_meta["size"]
	_check("collision: the play tier's measured 2 m posts at either detail", heightmap.map_width == expected and heightmap.map_depth == expected
		and is_equal_approx(terrain.get_node("Ground").get_child(0).scale.x, 2.0), "%d x %d" % [heightmap.map_width, heightmap.map_depth])
	var stored: PackedFloat32Array = FileAccess.get_file_as_bytes(DATA + play_meta["file"]).to_float32_array()
	var measured: PackedFloat32Array = FileAccess.get_file_as_bytes(DATA + meta["provenance"]["measured_file"]).to_float32_array()
	_check("collision heights are the pipeline's play tier, bit for bit", heightmap.map_data == stored)
	var changed: int = 0
	var outside_base: int = 0
	var base: Dictionary = meta["protected"][0]
	for i in measured.size():
		if measured[i] != stored[i]:
			changed += 1
			var x: float = -512.0 + (i % expected) * 2.0
			var z: float = -512.0 + (i / expected) * 2.0
			if absf(x - base["centre"][0]) > base["size"][0] / 2.0 + base["blend"] or absf(z - base["centre"][1]) > base["size"][1] / 2.0 + base["blend"]:
				outside_base += 1
	_check("the measured DTM is untouched outside the graded base", outside_base == 0 and changed == meta["authored_changes"][0]["posts_changed"],
		"%d posts changed, %d outside the base" % [changed, outside_base])
	# Headless runs build no materials: build them as a window would, to check the setting
	if terrain.materials.is_empty():
		terrain._make_materials()
	var detail_shadows: bool = terrain.materials["play"].get_shader_parameter("detail_shadows")
	_check("the ground detail's own shadows off at Low, on otherwise", detail_shadows == not low, "detail_shadows %s" % detail_shadows)
	await _ticks(4.0)
	for item in [["player", GS.player, 0.0, 1.2], ["rover", rover, 0.0, 0.35]]:
		var body: Node3D = item[1]
		var ground: float = terrain.height_at(body.global_position.x, body.global_position.z)
		var above: float = body.global_position.y - ground
		_check("%s stands on the ground" % item[0], above > item[2] and above < item[3], "%.2f m above it" % above)
		var slope: float = _slope_at(body.global_position.x, body.global_position.z)
		_check("%s's spot is flat" % item[0], slope < 3.0, "%.1f deg" % slope)
	var pile: Node3D = level.get_node("PartsPile")
	var worst: float = -INF
	var steepest: float = 0.0
	for part in pile.get_children():
		var p: Vector3 = part.global_position
		worst = maxf(worst, absf(p.y - terrain.height_at(p.x, p.z)))
		steepest = maxf(steepest, _slope_at(p.x, p.z))
	_check("parts pile resting on the ground", worst < 0.4, "highest part centre %.2f m from the ground" % worst)
	_check("parts pile's spot is flat", steepest < 3.0, "%.1f deg" % steepest)

	# 2. Mesh = collision
	var lm: Array = meta["artifacts"]["lm"]["position"]
	var spots: Array = [Vector2(-300, 252), Vector2(lm[0] - 30.0, lm[2]), Vector2(155, 23), HEAD_CRATER_FLOOR, Vector2(0, 0)]
	var play: Dictionary = terrain.tiers[0]
	var worst_diff: float = 0.0
	var samples: int = 0
	for spot in spots:
		var cell: int = int((spot.y + play["half"]) / play["spacing"]) / terrain.CHUNK_CELLS
		var col: int = int((spot.x + play["half"]) / play["spacing"]) / terrain.CHUNK_CELLS
		var mesh: Mesh = terrain.build_chunk(0, cell, col)
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for k in range(0, indices.size(), 3 * 7):   # every 7th triangle
			var a: Vector3 = verts[indices[k]]
			var b: Vector3 = verts[indices[k + 1]]
			var c: Vector3 = verts[indices[k + 2]]
			if absf(a.y - b.y) > 1.0 or absf(a.y - c.y) > 1.0:
				continue   # a skirt
			var centre: Vector3 = (a + b + c) / 3.0
			var hit: Dictionary = _ray_down(centre.x, centre.z, 1)
			if hit:
				worst_diff = maxf(worst_diff, absf(hit["position"].y - centre.y))
				samples += 1
	_check("the play mesh's triangles are the collision's", worst_diff < 0.001 and samples > 1000, "worst %.2f mm over %d triangles" % [worst_diff * 1000.0, samples])

	# 3. Light
	var horizons: Dictionary = meta["horizons"]
	var play_h: Dictionary = horizons["tiers"]["play"]
	var image := Image.load_from_file(ProjectSettings.globalize_path(DATA + play_h["files"][0]))
	var sun: Dictionary = meta["sun"]
	var horizon_at := func(x: float, z: float) -> float:
		var size: int = play_h["size"]
		var i: int = clampi(roundi((z + play_h["half_size"]) / play_h["metres_per_pixel"]), 0, size - 1)
		var j: int = clampi(roundi((x + play_h["half_size"]) / play_h["metres_per_pixel"]), 0, size - 1)
		return -10.0 + image.get_pixel(j, i).r * 60.0
	_check("the horizon maps start at the sun's azimuth", is_equal_approx(horizons["first_azimuth"], sun["azimuth"]))
	var base_highest: float = -90.0
	for dx in range(-23, 24, 4):
		for dz in range(-16, 17, 4):
			base_highest = maxf(base_highest, horizon_at.call(base["centre"][0] + dx, base["centre"][1] + dz))
	_check("the base is in sunlight", base_highest < sun["elevation"] - 0.27, "highest horizon %.2f deg, sun %.2f" % [base_highest, sun["elevation"]])
	var lit: int = 0
	var points: int = 0
	var limit: int = int(meta["boundary_half_size"])
	for x in range(-limit + 8, limit, 16):
		for z in range(-limit + 8, limit, 16):
			points += 1
			if horizon_at.call(x, z) < sun["elevation"]:
				lit += 1
	var lit_share: float = float(lit) / points
	_check("the play area's sunlit share is the pipeline's", absf(lit_share - sun["play_area_lit_fraction"]) < 0.02,
		"%.3f (pipeline %.3f)" % [lit_share, sun["play_area_lit_fraction"]])

	# 4. Boundary
	await _boundary_checks()

	# 5. The drive
	await _drive()

	print("DONE %d failures" % failures)
	quit(1 if failures else 0)


func _place(body: RigidBody3D, x: float, z: float, yaw_degrees: float, lift: float) -> void:
	body.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), Vector3(x, terrain.height_at(x, z) + lift, z))
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	if body == rover:
		for wheel in rover.running_gear.wheel_states:
			rover.running_gear.wheel_states[wheel][0] = 0.0


func _hint_text() -> String:
	var hint := root.find_child("BoundaryHint", true, false) as Label
	var visible: bool = false
	for h in root.find_children("BoundaryHint", "Label", true, false):
		if h.is_visible_in_tree():
			return h.text
	return ""


func _boundary_checks() -> void:
	var limit: float = meta["boundary_half_size"]
	# The player, walking west from 15 m inside, on flat ground (under 3 degrees out to the wall at
	# z = 50; further south the west wall cuts a big subdued crater)
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	_place(GS.player, -limit + 15.0, BOUNDARY_Z, 90.0, 1.0)
	await _ticks(1.0)
	var hint: String = _hint_text()
	Input.action_press("move_forward")
	await _ticks(15.0)
	Input.action_release("move_forward")
	var x: float = GS.player.global_position.x
	_check("the boundary stops the player", x > -limit, "x %.2f (boundary at %.0f)" % [x, -limit])
	_check("the HUD warns the player near the boundary", hint.begins_with("Survey area boundary"), "\"%s\"" % hint)
	# The rover at full throttle, from 15 m inside
	_place(rover, -limit + 15.0, BOUNDARY_Z, 90.0, 0.4)
	GS.drive(rover)
	await _ticks(1.0)
	Input.action_press("move_forward")
	await _ticks(20.0)
	Input.action_release("move_forward")
	var rover_x: float = rover.global_position.x
	_check("the boundary stops the rover at full throttle", rover_x > -limit and rover_x < -limit + 5.0, "x %.2f, upright %s" % [rover_x, rover.global_basis.y.y > 0.7])
	_check("the HUD warns the driver near the boundary", _hint_text().begins_with("Survey area boundary"), "\"%s\"" % _hint_text())


func _drive() -> void:
	_place(rover, -299.0, 247.6, 30.0, 0.4)
	GS.drive(rover)
	await _ticks(2.0)
	drive_stats = {"ticks": 0, "frames": 0, "touching_airborne": 0, "inside_terrain": 0, "mesh_in_ground": 0, "worst_mesh": 0.0, "lowest": INF}
	driving = true
	var reached: int = 0
	var t: float = 0.0
	Input.action_press("move_forward", 0.25)
	for target in ROUTE:
		var best: float = INF
		var last_progress: float = t
		while true:
			await physics_frame
			t += 1.0 / TICKS
			var to: Vector2 = target - Vector2(rover.global_position.x, rover.global_position.z)
			var distance: float = to.length()
			if distance < best - 1.0:
				best = distance
				last_progress = t
			if distance < WAYPOINT_RADIUS:
				reached += 1
				break
			if t - last_progress > STUCK_SECONDS:
				break
			# Steer for the target: the angle between the heading and the target, right positive
			var forward: Vector3 = -rover.global_basis.z
			var heading := Vector2(forward.x, forward.z).normalized()
			var angle: float = heading.angle_to(to.normalized())
			var steer: float = clampf(angle / 0.5, -1.0, 1.0)
			var speed: float = rover.linear_velocity.dot(forward)
			Input.action_press("move_forward", clampf(0.25 + (drive_speed - speed) * DRIVE_GAIN, 0.1, 1.0))
			Input.action_release("move_left")
			Input.action_release("move_right")
			if steer > 0.05:
				Input.action_press("move_right", steer)
			elif steer < -0.05:
				Input.action_press("move_left", -steer)
			drive_stats["lowest"] = minf(drive_stats["lowest"], rover.global_position.y)
			for hardware in meta["artifacts"].values():
				var at: Array = hardware["position"]
				drive_stats["closest_hardware"] = minf(drive_stats.get("closest_hardware", INF), Vector2(at[0] - rover.global_position.x, at[2] - rover.global_position.z).length())
		print("INFO waypoint %s: %s after %.0f s, rover at %s" % [target, "reached" if distance_ok(target) else "NOT reached", t, rover.global_position.snapped(Vector3.ONE * 0.1)])
		if not distance_ok(target):
			break
	for a in ["move_forward", "move_left", "move_right"]:
		Input.action_release(a)
	driving = false
	var floor_y: float = terrain.height_at(HEAD_CRATER_FLOOR.x, HEAD_CRATER_FLOOR.y)
	_check("the drive reaches every waypoint (EVA 2 route, Head crater, out again)", reached == ROUTE.size(), "%d of %d in %.0f s" % [reached, ROUTE.size(), t])
	_check("the drive gets down to Head crater's floor", drive_stats["lowest"] < floor_y + 5.0, "lowest %.1f m, floor %.1f m" % [drive_stats["lowest"], floor_y])
	_check("the drive keeps 75 m from the LM, the ALSEP and Surveyor 3", drive_stats.get("closest_hardware", INF) >= KEEP_OUT,
		"closest %.0f m" % drive_stats.get("closest_hardware", INF))
	_check("wheels: none airborne within 5 mm of the ground", drive_stats["touching_airborne"] == 0, "%d of %d wheel-ticks" % [drive_stats["touching_airborne"], drive_stats["ticks"] * 6])
	_check("wheels: none in contact inside the ground", drive_stats["inside_terrain"] == 0, "%d" % drive_stats["inside_terrain"])
	_check("wheels: no visible wheel over 1 cm in the ground", drive_stats["mesh_in_ground"] == 0,
		"%d of %d frames, deepest %.0f mm" % [drive_stats["mesh_in_ground"], drive_stats["frames"], drive_stats["worst_mesh"] * 1000.0])
	for e in drive_stats.get("examples", []):
		print("        e.g. " + e)


# Where a wheel check failed, and the nearest rock with collision (size, distance)
func _example(kind: String, at: Vector3) -> void:
	var examples: Array = drive_stats.get("examples", [])
	if examples.size() >= 12:
		return
	var nearest := ""
	var best: float = INF
	for shape in terrain.get_node("Rocks/RockCollision").get_children():
		var d: float = Vector2(shape.global_position.x - at.x, shape.global_position.z - at.z).length()
		if d < best:
			best = d
			nearest = "rock %.2f m across, %.2f m away" % [shape.transform.basis.get_scale().x, d]
	var gear = rover.running_gear
	var wheels := ""
	for w in gear.wheel_states:
		var st: Dictionary = gear.wheel_states[w]
		wheels += " %d:%s%.3f" % [w, "C" if st[3] else "-", st[7] - gear.full_extension_height(w)]
	examples.append("%s at %s; %s; ground slope %.0f deg; speed %.1f m/s, vertical %.2f m/s; wheel compression (C = in contact):%s" % [
		kind, at.snapped(Vector3.ONE * 0.01), nearest, _slope_at(at.x, at.z), rover.linear_velocity.length(), rover.linear_velocity.y, wheels])
	drive_stats["examples"] = examples


func distance_ok(target: Vector2) -> bool:
	return (target - Vector2(rover.global_position.x, rover.global_position.z)).length() < WAYPOINT_RADIUS


# --- Wheel checks, as test_wheel_contact.gd --------------------------------------------------------

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
	if not driving:
		return
	var space := rover.get_world_3d().direct_space_state
	var gear = rover.running_gear
	drive_stats["ticks"] += 1
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
		# (checked after the step, from the contact found before it: a wheel coming down fast has
		# moved one tick further)
		if state[3] and _depth_below_terrain(space, centre, WHEEL_RADIUS) > MESH_MARGIN + absf(rover.linear_velocity.y) / TICKS:
			drive_stats["inside_terrain"] += 1
			_example("inside", centre)
		if touching and not state[3]:
			drive_stats["touching_airborne"] += 1
			_example("airborne", centre)


func _check_frame() -> void:
	if not driving or not is_instance_valid(rover):
		return
	var space := rover.get_world_3d().direct_space_state
	drive_stats["frames"] += 1
	for wheel in rover.wheel_sockets:
		var socket = rover.wheel_sockets[wheel]
		if socket and socket.part:
			var part: Node3D = socket.part
			var part_axle: Vector3 = (part.global_basis * Vector3.RIGHT).normalized()
			var hits := _wheel_shape_hits(space, part.global_position, part_axle, WHEEL_RADIUS - MESH_MARGIN, WHEEL_WIDTH - 2.0 * MESH_MARGIN)
			var sunk: float = _depth_below_terrain(space, part.global_position, WHEEL_RADIUS)
			if not hits.is_empty() or sunk > MESH_MARGIN:
				drive_stats["mesh_in_ground"] += 1
				drive_stats["worst_mesh"] = maxf(drive_stats["worst_mesh"], sunk)
				_example("mesh %.0f mm" % (sunk * 1000.0), part.global_position)
