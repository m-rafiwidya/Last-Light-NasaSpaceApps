extends SceneTree
## Headless test: the workshop (tools/blender/WORKSHOP_KIT.md) in the Moon level, then in the
## test level.
##   1. Layout: built from the kit; the rover starts in the dock zone; the rack holds its 15
##      parts on their slots, at rest; every label fits its plate at 50-65 mm caps.
##   2. Reach: from where the player stands (console, between the rover and the rack, the
##      charger), a ray from the eye reaches the console, the restock button, rack parts, the
##      rover's battery socket and the charger within 3 m, nothing in the way.
##   3. Charging: docked, a drained battery charges with the probe up 20 mm under the belly;
##      docked at the zone's edge at an odd heading it still connects, under the rover's origin;
##      0.6 m off it doesn't, and the dock hint says where to go; with no battery it says so.
##   4. Console: E drives the rover and stands the player at the console; Esc brings the view back
##      there.
##   5. The drive: out of the bay door (it opens; the rover touches nothing of the workshop), 12 m
##      out (the door closes behind it), back in along the entry lane, a U-turn and onto the pad
##      by steering for waypoints, stopped by braking like a driver; it must end in the dock zone,
##      charging, upright, never touching the workshop.
##   6. Doors on foot: the personnel door lets the player through (and is locked while the bay
##      door is open on the Moon); the pressure curtain keeps the player in on the Moon, not in the
##      test level.
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_workshop.gd

const TICKS: int = 240
const ROVER_BELLY: float = 0.20      # chassis bottom above the rover's origin

var GS: Node
var SL: Node
var failures: int = 0
var level: Node3D
var workshop
var rover
var tag: String = ""
var touched: Dictionary = {}
var trace: bool = "trace" in OS.get_cmdline_user_args()
var only_level: String = ""


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-70s %s %s" % [tag + name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


## Kit coordinates (x, y along the bay, z up) to world
func _kit(x: float, y: float, z: float = 0.0) -> Vector3:
	return workshop.to_global(Vector3(x, z, -y))


func _kit_of(world: Vector3) -> Vector3:
	var p: Vector3 = workshop.to_local(world)
	return Vector3(p.x, -p.z, p.y)


func _place_rover(kit_x: float, kit_y: float, heading_degrees: float) -> void:
	# heading 0 = facing out of the bay door; positive turns left
	var basis: Basis = workshop.global_basis * Basis(Vector3.UP, deg_to_rad(heading_degrees))
	rover.global_transform = Transform3D(basis, _kit(kit_x, kit_y, 0.12))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO


func _release_all() -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(a)


func _workshop_bodies() -> Dictionary:
	var bodies: Dictionary = {}
	for body in workshop.find_children("*", "CollisionObject3D", true, false):
		if body is StaticBody3D or body is AnimatableBody3D:
			bodies[body] = true
	return bodies


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("level="):
			only_level = arg.trim_prefix("level=")
	for level_id in ["moon_level", "test_level"]:
		if only_level != "" and level_id != only_level:
			continue
		SL.load_scene(level_id)
		while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == level_id):
			await physics_frame
		level = SL.current_scene
		workshop = level.get_node("Workshop")
		rover = workshop.rover
		tag = "[%s] " % level_id
		await _ticks(3.0)
		_layout_checks()
		_reach_checks()
		await _charging_checks()
		await _console_checks()
		await _drive_checks()
		await _door_checks()
	print("RESULT %s" % ("ALL PASS" if failures == 0 else "%d CHECKS FAILED" % failures))
	quit(1 if failures else 0)


# 1 ---------------------------------------------------------------------------------------------
func _layout_checks() -> void:
	var parts: int = workshop.get_node("Parts").get_child_count()
	_check("built from the kit layout", parts == 102, "%d part instances" % parts)
	var offset: Vector2 = workshop.pad.offset_of(rover)
	_check("the rover starts in the dock zone", offset.length() <= workshop.pad.DOCK_ZONE, "%.2f m from the dock point" % offset.length())
	var stock: Node3D = workshop.rack_stock
	var worst_slot: float = 0.0
	var fastest: float = 0.0
	for part in stock.get_children():
		var n: int = String(part.name).trim_prefix("Slot").to_int()
		var slot: Vector3 = workshop.to_global(workshop.anchors["slot_%02d" % n])
		var aabb_centre: Vector3 = _visual_centre(part)
		worst_slot = maxf(worst_slot, Vector2(aabb_centre.x - slot.x, aabb_centre.z - slot.z).length())
		fastest = maxf(fastest, (part as RigidBody3D).linear_velocity.length())
	_check("the rack holds its 15 parts", stock.get_child_count() == 15, "%d" % stock.get_child_count())
	_check("rack parts on their slots, at rest", worst_slot < 0.06 and fastest < 0.01, "farthest %.3f m off its slot, fastest %.3f m/s" % [worst_slot, fastest])
	var fit := true
	var detail := ""
	for label in workshop.labels:
		var n: int = String(label.name).trim_prefix("Label").to_int()
		var room: float = workshop.LABELS[n][1] - 0.04
		var cap: float = workshop.label_cap_height(label)
		if workshop.label_width(label) > room + 0.001 or cap < workshop.LABEL_CAP_MIN - 0.001:
			fit = false
		detail += "%s %.0f mm; " % [label.text, cap * 1000.0]
	_check("rack labels fit their plates, caps 50-65 mm", fit and workshop.labels.size() == 9, detail)


# The middle of a part's visible meshes (world)
func _visual_centre(part: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mesh in part.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree():
			continue
		var b: AABB = mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return part.global_position if first else box.get_center()


# 2 ---------------------------------------------------------------------------------------------
func _ray_hits(from: Vector3, target: Node3D, aim: Vector3 = Vector3.INF) -> bool:
	var to: Vector3 = target.global_position if aim == Vector3.INF else aim
	var direction: Vector3 = (to - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + direction * 3.0, 53)
	q.collide_with_areas = true
	q.exclude = [GS.player.get_rid()]
	var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(q)
	return not hit.is_empty() and (hit["collider"] == target or target.is_ancestor_of(hit["collider"]))


func _reach_checks() -> void:
	var dock: Vector3 = _kit_of(rover.global_position)
	var at_console: Vector3 = workshop.to_global(workshop.anchors["anchor_operator"]) + Vector3(0.0, 1.5, 0.0)
	var at_rack: Vector3 = _kit(dock.x, -2.85, 1.5)
	var at_charger: Vector3 = _kit(1.25, 3.1, 1.5)
	var battery_socket: Node3D = rover.battery_socket.get_trigger()
	var items: Array = [["console", at_console, workshop.console_trigger], ["restock button", at_rack, workshop.restock_trigger],
		["charger", at_charger, workshop.pad.charger_trigger], ["rover's battery socket", at_rack, battery_socket]]
	# The rack is stepped: every part stands in front of the shelf above it, so it's in view and in
	# reach from close up and from across the walkway
	for n in range(1, 16):
		var slot_x: float = workshop.anchors["slot_%02d" % n].x
		for d in [0.45, 1.2, 2.0]:
			items.append(["rack slot_%02d from %.2f m" % [n, d], _kit(slot_x, -3.30 + d, 1.5), workshop.rack_stock.get_node("Slot%02d" % n)])
	for item in items:
		var target: Node3D = item[2]
		var aim: Vector3 = target.global_position
		if target is RigidBody3D:
			aim = _visual_centre(target)
		var distance: float = item[1].distance_to(aim)
		_check("reach: %s from where the player stands" % item[0], distance <= 3.0 and _ray_hits(item[1], target, aim), "%.2f m" % distance)


# 3 ---------------------------------------------------------------------------------------------
func _charging_checks() -> void:
	var pad = workshop.pad
	rover.battery.charge = rover.battery.capacity * 0.5
	await _ticks(3.0)
	var before: float = rover.battery.get_charge_fraction()
	await _ticks(2.0)
	var after: float = rover.battery.get_charge_fraction()
	_check("docked: charging", pad.state == workshop.pad.State.CHARGING and after > before, "%s, %.1f%% -> %.1f%%" % [pad.get_status_text(), before * 100.0, after * 100.0])
	var probe_top: float = pad.probe.global_position.y
	var belly: float = rover.global_position.y + ROVER_BELLY
	_check("docked: the probe up, 20 mm under the belly", absf(belly - probe_top - 0.02) < 0.012, "%.1f mm under it" % ((belly - probe_top) * 1000.0))
	# The zone's edge at an odd heading
	_place_rover(-0.1 + 0.27, -0.3 - 0.27, 37.0)
	await _ticks(4.0)
	var probe_xz := Vector2(pad.probe.global_position.x, pad.probe.global_position.z)
	var origin_xz := Vector2(rover.global_position.x, rover.global_position.z)
	_check("docked at the zone's edge, 37 degrees: connects under the rover's origin", pad.state == workshop.pad.State.CHARGING
		and probe_xz.distance_to(origin_xz) < 0.01, "%s, probe %.1f cm from the origin, %.2f m off the dock point" % [pad.get_status_text(), probe_xz.distance_to(origin_xz) * 100.0, pad.offset_of(rover).length()])
	# Outside the zone: the driver gets told where to go
	_place_rover(-0.1 + 0.6, -0.3, 0.0)
	await _ticks(2.5)
	var hint: String = pad.get_dock_hint(rover)
	_check("0.6 m off: not docked, the hint points the way", pad.state == workshop.pad.State.ON_PAD and hint.begins_with("Charging pad:")
		and hint.contains("to the left") and pad.probe_height() < 0.001, "\"%s\"" % hint)
	# No battery
	var battery = rover.battery_socket.unmount()
	_place_rover(-0.1, -0.3, 0.0)
	await _ticks(2.5)
	_check("no battery: a fault and the hint says so", pad.state == workshop.pad.State.FAULT and pad.get_dock_hint(rover) == "No battery to charge", pad.get_status_text())
	rover.battery_socket.mount(battery)
	battery.charge = battery.capacity
	await _ticks(3.0)
	_check("battery back, full: charged", pad.state == workshop.pad.State.FULL, pad.get_status_text())


# 4 ---------------------------------------------------------------------------------------------
func _console_checks() -> void:
	var player = GS.player
	player.global_position = workshop.to_global(workshop.anchors["spawn_player"]) + Vector3(0.0, 0.05, 0.0)
	await _ticks(0.5)
	workshop._on_console_interacted(player)
	await _ticks(0.5)
	var stand: Vector3 = workshop.to_global(workshop.anchors["anchor_operator"])
	_check("console: E drives the rover", GS.state == GS.State.IN_GAME_ROBOT and GS.robot == rover and root.get_camera_3d() == rover.camera)
	_check("console: the player stands at the console", Vector2(player.global_position.x - stand.x, player.global_position.z - stand.z).length() < 0.15,
		"%.2f m away" % Vector2(player.global_position.x - stand.x, player.global_position.z - stand.z).length())
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.5)
	_check("leaving the rover: the view is back at the console", root.get_camera_3d() == player.camera
		and Vector2(player.global_position.x - stand.x, player.global_position.z - stand.z).length() < 0.15)


# 5 ---------------------------------------------------------------------------------------------
func _drive_to(points: Array, speed: float, timeout: float, stop_at_end: bool) -> bool:
	var bodies: Dictionary = _workshop_bodies()
	var t: float = 0.0
	for i in points.size():
		var target: Vector3 = _kit(points[i].x, points[i].y)
		var last: bool = i == points.size() - 1 and stop_at_end
		while true:
			await physics_frame
			t += 1.0 / TICKS
			for body in rover.get_colliding_bodies():
				if bodies.has(body):
					touched[String(body.get_parent().name) + "/" + String(body.name)] = true
			if trace and int(t * TICKS) % (TICKS / 2) == 0:
				var k: Vector3 = _kit_of(rover.global_position)
				var f: Vector3 = _kit_of(rover.global_position - rover.global_basis.z) - k
				print("TRACE t %5.1f wp %d kit (%.2f, %.2f) heading %4.0f speed %.2f" % [t, i, k.x, k.y, rad_to_deg(atan2(-f.x, f.y)), rover.linear_velocity.length()])
			var forward: Vector3 = -rover.global_basis.z
			var v: float = rover.linear_velocity.dot(forward)
			var to := Vector2(target.x - rover.global_position.x, target.z - rover.global_position.z)
			# A waypoint counts once the rover is near it or has passed it (it's behind the rover),
			# so a waypoint inside the turning circle can't make it circle
			var passed: bool = Vector2(forward.x, forward.z).dot(to) < 0.0
			if (not last and (to.length() < 0.5 or passed)) or (last and to.length() < 0.12 and absf(v) < 0.05):
				break
			if t > timeout:
				_release_all()
				return false
			var heading := Vector2(forward.x, forward.z).normalized()
			var steer: float = clampf(heading.angle_to(to.normalized()) / 0.25, -1.0, 1.0)
			var want: float = speed
			if last:
				want = clampf(to.length() * 0.8, 0.0, speed)
			_release_all()
			if v > want + 0.15:
				Input.action_press("move_backward", clampf((v - want) * 0.6, 0.05, 0.6))
			elif v < want:
				Input.action_press("move_forward", clampf(0.06 + (want - v) * 0.3, 0.05, 0.4))
			if steer > 0.05:
				Input.action_press("move_right", steer)
			elif steer < -0.05:
				Input.action_press("move_left", -steer)
	_release_all()
	return true


func _drive_checks() -> void:
	touched.clear()
	_place_rover(-0.1, -0.3, 0.0)
	await _ticks(1.0)
	GS.drive(rover)
	await _ticks(0.2)
	# Out: straight along the pad's centre line
	var out_ok: bool = await _drive_to([Vector2(-0.1, 2.0), Vector2(-0.1, 6.0), Vector2(-0.6, 12.0)], 1.0, 40.0, false)
	_check("drive out: through the open bay door", out_ok and _kit_of(rover.global_position).y > 11.0, "rover at kit y %.1f" % _kit_of(rover.global_position).y)
	for k in 30:
		await _ticks(0.1)
		var bodies := _workshop_bodies()
		for body in rover.get_colliding_bodies():
			if bodies.has(body):
				touched[String(body.name)] = true
	# Parked out there: the door closes behind it (the rover is driven, but nowhere near)
	await _ticks(4.0)
	_check("the bay door closes behind the rover", workshop.door_open == 0.0, "open %.2f" % workshop.door_open)
	# Back in: the entry lane, then the U-turn round the back of the pad (the tightest turn,
	# radius 1.07 m about (-1.17, -1.0), WORKSHOP_KIT.md 5.2), then onto the dock
	var in_ok: bool = await _drive_to([Vector2(-2.24, 9.0), Vector2(-2.24, 3.0), Vector2(-2.24, -0.6)], 0.9, 60.0, false)
	var arc: Array = []
	for k in range(1, 9):
		var a: float = deg_to_rad(180.0 + 22.5 * k)
		arc.append(Vector2(-1.17 + 1.07 * cos(a), -1.0 + 1.07 * sin(a)))
	in_ok = in_ok and await _drive_to(arc + [Vector2(-0.1, -0.3)], 0.5, 60.0, true)
	await _ticks(3.0)
	var offset: float = workshop.pad.offset_of(rover).length()
	_check("drive in: U-turn and onto the pad", in_ok and offset <= workshop.pad.DOCK_ZONE, "%.2f m off the dock point" % offset)
	_check("drive in: docked and connected", workshop.pad.state in [workshop.pad.State.CHARGING, workshop.pad.State.FULL], workshop.pad.get_status_text())
	_check("the drive never touched the workshop", touched.is_empty(), str(touched.keys()))
	_check("the rover stayed upright", rover.global_basis.y.y > 0.99)
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	for k in 40:
		if workshop.door_open <= 0.0:
			break
		await _ticks(0.25)


# 6 ---------------------------------------------------------------------------------------------
func _walk(from_kit: Vector3, facing_kit: Vector2, seconds: float) -> Vector3:
	var player = GS.player
	player.global_position = _kit(from_kit.x, from_kit.y, 0.05)
	player.linear_velocity = Vector3.ZERO
	var dir: Vector3 = workshop.global_basis * Vector3(facing_kit.x, 0.0, -facing_kit.y)
	player.controller.camera_azimuth = atan2(-dir.x, -dir.z)
	await _ticks(0.3)
	Input.action_press("move_forward")
	for k in int(seconds * 4.0):
		await _ticks(0.25)
		if trace:
			print("TRACE walk %s kit %s personnel %.2f locked %s overlaps %s state %s" % [k, _kit_of(player.global_position).snapped(Vector3.ONE * 0.01),
				workshop.personnel_open, workshop.is_personnel_door_locked(), workshop._personnel_area.get_overlapping_bodies(), GS.State.keys()[GS.state]])
	Input.action_release("move_forward")
	await _ticks(0.5)
	return _kit_of(player.global_position)


func _door_checks() -> void:
	# The personnel door, bay door closed: operator area -> bay and back
	var p: Vector3 = await _walk(Vector3(3.0, -2.0, 0.0), Vector2(-1.0, 0.0), 2.5)
	_check("personnel door: operator area into the bay", p.x < 1.6, "player at kit x %.2f (bay door open %.2f, personnel door open %.2f, locked %s)" % [p.x, workshop.door_open, workshop.personnel_open, workshop.is_personnel_door_locked()])
	p = await _walk(Vector3(1.0, -2.0, 0.0), Vector2(1.0, 0.0), 2.5)
	_check("personnel door: back to the operator area", p.x > 2.6, "player at kit x %.2f" % p.x)
	# The bay door open by hand, then walking out of it
	workshop._on_door_panel_interacted(GS.player)
	await _ticks(3.0)
	if workshop.airlock_barrier:
		p = await _walk(Vector3(3.0, -2.0, 0.0), Vector2(-1.0, 0.0), 2.5)
		_check("personnel door locked while the bay door is open", p.x > 2.1, "player at kit x %.2f" % p.x)
	p = await _walk(Vector3(-1.0, 1.0, 0.0), Vector2(0.0, 1.0), 4.0)
	if workshop.airlock_barrier:
		_check("pressure curtain: the player can't walk out of the open bay door", p.y < 3.85, "player at kit y %.2f" % p.y)
	else:
		_check("no curtain here: the player walks out of the bay door", p.y > 4.5, "player at kit y %.2f" % p.y)
	_check("the rover isn't stopped by the curtain's layer", rover.collision_mask & (1 << 7) == 0)
	GS.player.global_position = workshop.to_global(workshop.anchors["spawn_player"]) + Vector3(0.0, 0.05, 0.0)
	await _ticks(0.5)
	workshop._on_door_panel_interacted(GS.player)
	await _ticks(3.0)
