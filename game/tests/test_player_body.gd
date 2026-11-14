extends SceneTree
## Headless test: the player's first-person spacesuit body (src/player/body/, PlayerBody;
## tools/blender/ASTRONAUT_KIT.md 13).
##   1. Structure: the suit is under the player, has no collision, the helmet is drawn as a
##      shadow only, the body casts shadows, the helmet light ignores the suit's shadows.
##   2. The body is visual: the same scripted walk, sprint, strafe, jump, crouch and turns give
##      the same player path and camera with and without the body (test level).
##   3. Planted boots: walking, sprinting, crouch-walking, backwards, strafing and diagonally on
##      flat ground, the sole points touching the ground don't slide (test level).
##   4. Jumps on Earth and on the Moon: the air poses blend in, rise -> fall, and the landing
##      plays; the camera's height over the body is untouched.
##   5. Hands (Moon workshop): the cartridge in the right hand, a wheel in both; the wrists on
##      their targets, the hands closed, the part about 0.5 m out; throwing and dropping let
##      go and the arms return to the animation; a rover (test level) keeps the floating hold.
##   6. Every socket of the docked rover still takes its part dropped from the hands, standing and
##      crouched (Moon workshop).
##   7. Driving hides the body (the console's seated operator is the player then).
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_player_body.gd

const TICKS: int = 240
# Boot sole edges from the ankle, skeleton space (character faces +Z): heel, middle, toe
const SOLE: Array[Vector3] = [Vector3(0.0, -0.11, -0.095), Vector3(0.0, -0.11, 0.06), Vector3(0.0, -0.11, 0.215)]

var GS: Node
var SL: Node
var failures: int = 0
var _inputs: Array[String] = []


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-72s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _press(actions: Array) -> void:
	for a in actions:
		Input.action_press(a)
		_inputs.append(a)


func _release_all() -> void:
	for a in _inputs:
		Input.action_release(a)
	_inputs.clear()


func _load(level: String) -> void:
	_release_all()
	SL.load_scene(level)
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == level):
		await physics_frame
	await _ticks(1.5)


func _body(player):
	var body = player.get_node_or_null("Body")
	if body and body.skeleton and not body.skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		body.skeleton.skeleton_updated.connect(_on_skeleton_updated.bind(body.skeleton))
	return body


## The pose the skin gets (after the modifiers: lower body turn, arm IK, hands), per bone name
var final_pose: Dictionary = {}


func _on_skeleton_updated(skeleton: Skeleton3D) -> void:
	for bone in ["LeftFoot", "RightFoot", "LeftHand", "RightHand"]:
		final_pose[bone] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	await _ticks(0.5)

	await _load("test_level")
	_structure_checks(GS.player)
	await _invariance_checks()
	await _feet_checks()
	await _jump_checks("test_level")
	await _oversize_checks()
	await _load("moon_level")
	await _jump_checks("moon_level")
	await _hand_checks()
	await _socket_checks()
	await _drive_checks()
	_release_all()
	print("RESULT %s" % ("ALL PASS" if failures == 0 else "%d CHECKS FAILED" % failures))
	quit(1 if failures else 0)


# 1 ---------------------------------------------------------------------------------------------
func _structure_checks(player) -> void:
	var body = _body(player)
	_check("structure: the player has a Body (PlayerBody) with the suit", body != null and body.skeleton != null)
	var colliders: Array = body.find_children("*", "CollisionObject3D", true, false) + body.find_children("*", "CollisionShape3D", true, false)
	_check("structure: no collision in the body", colliders.is_empty(), str(colliders))
	_check("structure: the helmet casts its shadow but is never drawn",
		body.helmet_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	_check("structure: the body is drawn and casts shadows",
		body.body_mesh.visible and body.body_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_check("structure: the helmet light ignores the suit's shadows (it is inside the helmet)",
		player.helmet_light.shadow_caster_mask & body.BODY_LAYER == 0 and body.body_mesh.layers == body.BODY_LAYER)
	_check("structure: the holder pulls held parts to the body's hold point",
		player.holder.hold_point == body.hold_point)
	var triangles: int = 0
	for m in [body.body_mesh, body.helmet_mesh]:
		for s in m.mesh.get_surface_count():
			triangles += m.mesh.surface_get_array_len(s) / 3 if m.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_INDEX == 0 else (m.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	_check("structure: suit triangles within the kit's cap", triangles <= 5000, "%d" % triangles)


# 2 ---------------------------------------------------------------------------------------------
## The scripted run: [seconds, actions, azimuth change (degrees), altitude (degrees), crouch]
const SCRIPT: Array = [
	[0.5, [], 0.0, 0.0, false], [1.2, ["move_forward"], 0.0, -10.0, false],
	[1.0, ["move_forward", "move_sprint"], 25.0, 0.0, false], [0.8, ["move_right"], -40.0, 20.0, false],
	[0.6, ["move_forward", "move_jump"], 0.0, 0.0, false], [1.0, [], 70.0, -50.0, false],
	[1.2, ["move_forward"], 0.0, -20.0, true], [0.8, ["move_backward"], -30.0, 0.0, true],
	[0.8, ["move_left"], 0.0, 0.0, false], [1.0, [], 0.0, 0.0, false],
]


func _record_script(player) -> Array:
	var samples: Array = []
	var controller = player.controller
	for step in SCRIPT:
		_release_all()
		_press(step[1])
		if step[4] != player.want_to_crouch:
			player._on_controller_crouch(step[4])
		var frames: int = int(step[0] * TICKS)
		var az0: float = controller.camera_azimuth
		for i in frames:
			controller.camera_azimuth = az0 + deg_to_rad(step[2]) * float(i + 1) / frames
			controller.camera_altitude = deg_to_rad(step[3])
			await physics_frame
			samples.append([player.global_position, player.camera.global_transform])
	_release_all()
	if player.want_to_crouch:
		player._on_controller_crouch(false)
	return samples


func _deviation(a: Array, b: Array) -> Array:
	var position: float = 0.0
	var camera: float = 0.0
	for i in mini(a.size(), b.size()):
		position = maxf(position, (a[i][0] - b[i][0]).length())
		var ta: Transform3D = a[i][1]
		var tb: Transform3D = b[i][1]
		camera = maxf(camera, (ta.origin - tb.origin).length() + (ta.basis.x - tb.basis.x).length()
			+ (ta.basis.y - tb.basis.y).length() + (ta.basis.z - tb.basis.z).length())
	return [position, camera]


## Puts the player back where a run starts, still, standing, looking ahead, and lets it settle
func _reset_player(player, start: Transform3D) -> void:
	_release_all()
	if player.want_to_crouch:
		player._on_controller_crouch(false)
	player.global_transform = start
	player.linear_velocity = Vector3.ZERO
	player.controller.camera_azimuth = 0.0
	player.controller.camera_altitude = 0.0
	player.controller.request_jump = false
	await _ticks(1.5)


## A spot on the floor with nothing movable within `radius` (the run mustn't push props
## around, or the next run meets them somewhere else)
func _open_floor(player, radius: float) -> Vector3:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	for ring in range(0, 40, 2):
		for k in 16:
			var at: Vector3 = player.global_position + Vector3(cos(TAU * k / 16.0), 0.0, sin(TAU * k / 16.0)) * ring
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = sphere
			query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 1.0)
			query.collision_mask = 2 | 4 | 16
			query.exclude = [player.get_rid()]
			query.collide_with_areas = true
			if not space.intersect_shape(query, 1).is_empty():
				continue
			var flat: bool = true
			for j in 8:
				var edge: Vector3 = at + Vector3(cos(TAU * j / 8.0), 0.0, sin(TAU * j / 8.0)) * radius
				var ray := PhysicsRayQueryParameters3D.create(edge + Vector3.UP, edge + Vector3.DOWN * 0.3, 1)
				var hit: Dictionary = space.intersect_ray(ray)
				flat = flat and not hit.is_empty() and absf((hit["position"] as Vector3).y - at.y) < 0.02
			if flat:
				return at
	return player.global_position


func _invariance_checks() -> void:
	# All runs in one loaded level, from the same start: twice with the body, then twice without.
	# The repeats show what is left of the physics' own run-to-run noise; without the body the
	# runs must match the ones with it as closely.
	var player = GS.player
	var start: Transform3D = player.global_transform
	start.origin = _open_floor(player, 9.0)
	var runs: Array = []
	for with_body in [true, true, false, false]:
		if not with_body and player.has_node("Body"):
			var body = player.get_node("Body")
			player.holder.hold_point = null
			player.remove_child(body)
			body.free()
		await _reset_player(player, start)
		runs.append(await _record_script(player))
	var same: float = maxf(_deviation(runs[0], runs[1])[0], _deviation(runs[2], runs[3])[0])
	var across: float = 0.0
	var camera: float = 0.0
	for a in [0, 1]:
		for b in [2, 3]:
			var d: Array = _deviation(runs[a], runs[b])
			across = maxf(across, d[0])
			camera = maxf(camera, d[1])
	_check("visual only: path and camera with and without the body (%d ticks)" % runs[2].size(),
		runs[0].size() == runs[2].size() and across <= maxf(same * 1.5, 1e-6),
		"run to run %.4f mm; with vs without the body %.4f mm (camera %.6f)" % [same * 1000, across * 1000, camera])
	await _load("test_level")


# 3 ---------------------------------------------------------------------------------------------
func _soles(body, side: String) -> Array:
	var sk: Skeleton3D = body.skeleton
	var bone: int = sk.find_bone(side + "Foot")
	if not final_pose.has(side + "Foot"):
		return []
	var pose: Transform3D = sk.global_transform.affine_inverse() * (final_pose[side + "Foot"] as Transform3D)
	var delta: Basis = pose.basis * sk.get_bone_global_rest(bone).basis.inverse()
	var out: Array = []
	for offset in SOLE:
		out.append(sk.global_transform * (pose.origin + delta * offset))
	return out


## Mean slide (m/s) of planted boots: [a flat boot (its whole sole within 1.5 mm of the ground on
## two frames in a row), a rolling one (only its heel or toe edge on the ground), flat time (s)]
func _measure_slide(player, seconds: float) -> Array:
	var body = _body(player)
	var previous: Dictionary = {}
	var slid: Array = [0.0, 0.0]
	var planted_time: Array = [0.0, 0.0]
	for i in int(seconds * TICKS):
		await physics_frame
		var shape: CapsuleShape3D = player.get_node("CollisionShape3D").shape
		var ground: float = player.global_position.y + 1.0 - shape.height / 2.0
		for side in ["Left", "Right"]:
			var pts: Array = _soles(body, side)
			if pts.is_empty():
				continue
			if previous.has(side):
				var before: Array = previous[side]
				var flat: bool = true
				for k in pts.size():
					flat = flat and before[k].y - ground < 0.0015 and pts[k].y - ground < 0.0015
				if flat:
					slid[0] += Vector2(pts[1].x - before[1].x, pts[1].z - before[1].z).length()
					planted_time[0] += 1.0 / TICKS
				else:
					for k in [0, 2]:
						if before[k].y - ground < 0.001 and pts[k].y - ground < 0.001:
							slid[1] += Vector2(pts[k].x - before[k].x, pts[k].z - before[k].z).length()
							planted_time[1] += 1.0 / TICKS
			previous[side] = pts
	return [slid[0] / maxf(planted_time[0], 1e-6), slid[1] / maxf(planted_time[1], 1e-6), planted_time[0]]


func _feet_checks() -> void:
	var player = GS.player
	# Limits: a flat boot creeps at most 3 cm/s, the edge a boot rolls over 20 cm/s (the clips are
	# keyed at 60 fps and played back interpolated; walking is 2 m/s, sprinting 3)
	var cases: Array = [
		["walk", ["move_forward"], false], ["sprint", ["move_forward", "move_sprint"], false],
		["backwards", ["move_backward"], false], ["strafe right", ["move_right"], false],
		["diagonal", ["move_forward", "move_left"], false], ["crouch walk", ["move_forward"], true],
	]
	var heading: float = 0.0
	for c in cases:
		# Walk away from the spawn and back, so the test stays on the open floor
		player.controller.camera_azimuth = heading
		heading += PI
		if c[2]:
			player._on_controller_crouch(true)
		_press(c[1])
		await _ticks(0.8)
		var r: Array = await _measure_slide(player, 1.6)
		_release_all()
		if c[2]:
			player._on_controller_crouch(false)
		await _ticks(0.8)
		_check("feet: %s, planted soles stay put" % c[0], r[0] < 0.03 and r[1] < 0.2 and r[2] > 0.3,
			"flat boot %.3f m/s, rolling heel or toe %.3f m/s, %.1f s planted" % [r[0], r[1], r[2]])


# 4 ---------------------------------------------------------------------------------------------
func _jump_checks(level: String) -> void:
	var player = GS.player
	var body = _body(player)
	var camera_height: float = player.camera.position.y
	player.controller.request_jump = true
	var max_air: float = 0.0
	var positions: Array = []
	var air_time: float = 0.0
	var landed_at: float = -1.0
	var land_peak: float = 0.0
	var t: float = 0.0
	var camera_moved: float = 0.0
	while t < 4.0:
		await physics_frame
		t += 1.0 / TICKS
		camera_moved = maxf(camera_moved, absf(player.camera.position.y - camera_height))
		max_air = maxf(max_air, body._air)
		if not player.is_on_floor:
			air_time += 1.0 / TICKS
			if body._air > 0.9:
				positions.append(float(body.tree.get("parameters/air_pose/blend_position")))
		elif air_time > 0.3 and landed_at < 0.0:
			landed_at = t
		if landed_at > 0.0:
			land_peak = maxf(land_peak, body._land_amount())
			if t > landed_at + 0.6:
				break
	var rises: bool = positions.size() > 2 and positions[0] > 0.3 and positions[-1] < -0.3
	_check("jump (%s): in the air %.2f s, air poses rise -> fall" % [level, air_time], max_air > 0.99 and rises,
		"blend from %.2f to %.2f" % [positions[0] if positions else 0.0, positions[-1] if positions else 0.0])
	_check("jump (%s): landing plays (strength %.2f) and the camera height doesn't move" % [level, land_peak],
		land_peak > 0.15 and camera_moved < 1e-6)


# 5 ---------------------------------------------------------------------------------------------
func _hand_state(body, side: String) -> Array:
	var wrist: Vector3 = (final_pose[side + "Hand"] as Transform3D).origin
	var target: Vector3 = (body._ik_target[side] as Marker3D).global_position
	return [wrist.distance_to(target), body._closed[side], body.arm_ik[side].influence]


func _carry(player, part: RigidBody3D, label: String, hands: Array) -> void:
	var body = _body(player)
	player.holder.pickup(part)
	await _ticks(1.5)
	var detail: Array = []
	var ok: bool = player.holder.held_object == part
	for side in ["Left", "Right"]:
		var h: Array = _hand_state(body, side)
		var used: bool = side in hands
		detail.append("%s %s: wrist %.1f cm off, closed %.1f, ik %.2f" % [side, "on" if used else "free", h[0] * 100, h[1], h[2]])
		ok = ok and (h[0] < 0.02 and h[1] > 0.99 and h[2] > 0.99 if used else h[2] < 0.01)
	var reach: float = part.global_position.distance_to(player.camera.global_position)
	ok = ok and reach < 0.85
	_check("hands: %s gripped (%s)" % [label, " and ".join(hands)], ok, "; ".join(detail) + "; part %.2f m from the eye" % reach)


func _hand_checks() -> void:
	var player = GS.player
	var body = _body(player)
	var workshop = SL.current_scene.get_node("Workshop")
	var rover = SL.current_scene.get_node("ReadyRover")
	player.global_position = rover.global_position + rover.global_basis.x * 1.4 + Vector3.UP * 0.1
	await _ticks(0.5)
	var cartridge: RigidBody3D = workshop.rack_stock.get_node("Slot17")
	await _carry(player, cartridge, "cartridge", ["Right"])
	_check("hands: a one-hand part is held to the right", (player.camera.global_basis.inverse() * (cartridge.global_position - player.camera.global_position)).x > 0.05)
	player.holder.throw()
	await _ticks(0.1)
	var pushed: bool = body.arm_ik["Right"].influence > 0.9
	await _ticks(0.8)
	_check("hands: throwing pushes the arm out, then it goes back to the animation",
		pushed and body.arm_ik["Right"].influence < 0.01 and body.hands_modifier.weight["Right"] < 0.01)
	var wheel: RigidBody3D = null
	for slot in workshop.rack_stock.get_children():
		if slot.get("part_type") == 0 and slot.get("radius") != null:
			wheel = slot
			break
	await _carry(player, wheel, "wheel", ["Left", "Right"])
	player.holder.release()
	await _ticks(0.8)
	_check("hands: dropping opens the hands and the arms go back",
		body.arm_ik["Left"].influence < 0.01 and body._closed["Left"] < 0.01)
	await _ticks(0.5)


func _oversize_checks() -> void:
	var player = GS.player
	var body = _body(player)
	var rover = SL.current_scene.get_node("ReadyRover")
	player.holder.pickup(rover)
	await _ticks(1.0)
	_check("hands: a rover (too big to carry) keeps the old floating hold, arms reaching",
		body.grip == body.Grip.OVERSIZE and player.holder.hold_point == null and body.arm_ik["Left"].influence > 0.5)
	player.holder.release()
	await _ticks(0.5)
	_check("hands: after the rover, the hold point is back", player.holder.hold_point == body.hold_point)


# 6 ---------------------------------------------------------------------------------------------
func _capture_box(socket) -> Array:
	var shape_node: CollisionShape3D = socket.get_node("PartCapture/CollisionShape3D")
	var box: BoxShape3D = shape_node.shape
	return [shape_node.global_transform, box.size]


func _inside(point: Vector3, box: Array, above: float) -> bool:
	var local: Vector3 = (box[0] as Transform3D).affine_inverse() * point
	var half: Vector3 = (box[1] as Vector3) / 2.0
	return absf(local.x) <= half.x * 0.8 and absf(local.z) <= half.z * 0.8 and local.y >= -half.y * 0.8 and local.y <= half.y + above


func _capsule_free(player, at: Vector3, crouched: bool, exclude: Array) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.0 if crouched else 2.0
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (capsule.height / 2.0 + 0.02))
	query.collision_mask = player.collision_mask
	query.exclude = exclude
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Where ObjectHolder's old hold (2 m out along the view, pitch clamped to 30 degrees from
## straight down) would pull a part, for the same player placement
func _old_hold(player) -> Vector3:
	var pitch: float = clampf(player.camera.rotation.x, -PI / 2.0 + deg_to_rad(60.0), PI / 2.0)
	var basis: Basis = player.pivot.global_basis * Basis(Vector3.RIGHT, pitch)
	return player.camera.global_position - basis.z * 2.0


## Places the player where the hold point is over the socket's capture box, lets the part settle
## and, once it is over the box, lets go: the socket must take it. Tries the best few places
## (a part can be blocked on its way by the rover). Returns [problem, old hold could reach it].
func _drop_into(player, socket, part, crouched: bool) -> Array:
	var body = _body(player)
	var box: Array = _capture_box(socket)
	var centre: Vector3 = (box[0] as Transform3D).origin
	# Crouched, the capsule shrinks round its centre and the player stands 0.5 m lower
	var shape: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	var sink: float = 1.0 - shape.height / 2.0
	var ground: float = player.global_position.y + sink
	var exclude: Array = [player.get_rid(), part.get_rid()]
	var candidates: Array = []
	var old_reach: bool = false
	var saved: Transform3D = player.global_transform
	for radius in [0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.7, 0.8, 0.9, 1.1, 1.4, 1.8, 2.2]:
		for k in 36:
			var a: float = TAU * k / 36.0
			var at := Vector3(centre.x + radius * cos(a), ground, centre.z + radius * sin(a))
			if not _capsule_free(player, at, crouched, exclude):
				continue
			var to: Vector3 = centre - at
			for turn in [0, -10, 10, -20, 20, -30, 30]:
				var azimuth: float = atan2(-to.x, -to.z) - player.global_basis.get_euler().y + deg_to_rad(turn)
				for pitch in range(-60, 61, 5):
					player.global_position = at - Vector3.UP * sink
					player.pivot.rotation.y = azimuth
					player.camera.rotation.x = deg_to_rad(pitch)
					old_reach = old_reach or _inside(_old_hold(player), box, 0.25)
					if radius <= 0.9 and _inside(body._hold_position(), box, 0.25):
						candidates.append([absf(pitch) + radius * 10.0 + absf(turn) * 0.2, at, azimuth, pitch])
	player.global_transform = saved
	if candidates.is_empty():
		return ["no place puts the hands over it", old_reach]
	candidates.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var tried: Array = []
	for best in candidates.slice(0, 5):
		if player.holder.held_object != part:
			player.holder.pickup(part)
		player.global_position = best[1] - Vector3.UP * sink
		player.linear_velocity = Vector3.ZERO
		player.controller.camera_azimuth = best[2]
		player.controller.camera_altitude = deg_to_rad(best[3])
		await _ticks(1.2)
		var off: float = (part.global_transform * body._box_centre).distance_to(centre)
		player.holder.release()
		await _ticks(1.5)
		if socket.part == part:
			return ["", old_reach]
		tried.append("pitch %d, part %.2f m from the box: not taken" % [best[3], off])
	return ["; ".join(tried), old_reach]


func _socket_checks() -> void:
	var player = GS.player
	var rover = SL.current_scene.get_node("ReadyRover")
	var workshop = SL.current_scene.get_node("Workshop")
	var sockets: Array = rover.find_children("*", "HotswapSocket", true, false)
	var docked: Transform3D = rover.global_transform
	var spares: Array = workshop.rack_stock.get_children() + (workshop.bench_stock.get_children() if workshop.bench_stock else [])
	for socket in sockets:
		var reached: Array = []
		var lost: Array = []
		for crouched in [false, true]:
			var stance: String = "crouched" if crouched else "standing"
			rover.global_transform = docked
			rover.linear_velocity = Vector3.ZERO
			rover.angular_velocity = Vector3.ZERO
			player.global_position = rover.global_position + rover.global_basis.x * 1.4 + Vector3.UP * 0.05
			await _ticks(0.3)
			var part = socket.part
			if part:
				socket.get_trigger().interact(player)
			else:
				for spare in spares:
					if spare.has_method("is_mounted") and not spare.is_mounted() and socket.accepts_type(spare):
						part = spare
						break
				if part:
					# Fetched from behind the workshop's partition, a spare jams in its window
					part.global_position = player.camera.global_position + Vector3.UP * -0.4
					part.linear_velocity = Vector3.ZERO
					player.holder.pickup(part)
					await _ticks(0.5)
			if not part or player.holder.held_object != part:
				lost.append("%s: no part to try" % stance)
				continue
			if crouched != player.want_to_crouch:
				player._on_controller_crouch(crouched)
				await _ticks(0.9)
			var result: Array = await _drop_into(player, socket, part, crouched)
			if (result[0] as String).is_empty():
				reached.append(stance)
			elif result[1]:
				lost.append("%s: %s (the old 2 m hold reached it)" % [stance, result[0]])
			else:
				lost.append("%s: %s (the old hold couldn't either)" % [stance, result[0]])
			if player.holder.held_object:
				player.holder.release()
				await _ticks(0.5)
				# Put it back for the next stance
				if not socket.part:
					part.global_position = (_capture_box(socket)[0] as Transform3D).origin + Vector3.UP * 0.05
					part.linear_velocity = Vector3.ZERO
					await _ticks(1.0)
			if player.want_to_crouch:
				player._on_controller_crouch(false)
				await _ticks(0.9)
		var type_name: String = ["wheel", "motor", "battery", "mast head", "arm tool", "antenna", "cargo", "thermal"][socket.accepted_type] if not socket.accepts_any_type else "any"
		_check("sockets: %s (%s) takes its part from the hands, %s" % [socket.name, type_name, " and ".join(reached) if reached else "never"],
			not reached.is_empty(), "; ".join(lost))


# 7 ---------------------------------------------------------------------------------------------
func _drive_checks() -> void:
	var player = GS.player
	var body = _body(player)
	var workshop = SL.current_scene.get_node("Workshop")
	workshop._on_console_interacted(player)
	await _ticks(0.5)
	var hidden: bool = not body.visible
	GS.change_state_to(GS.State.PAUSED)
	await process_frame
	var paused_hidden: bool = not body.visible
	GS.change_state_to(GS.State.IN_GAME_ROBOT)
	await process_frame
	var state: int = GS.state
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.5)
	hidden = hidden and paused_hidden
	_check("driving (and pausing while driving) hides the body, leaving shows it again", hidden and body.visible,
		"state while driving %d, hidden %s, visible after %s (state %d)" % [state, hidden, body.visible, GS.state])
