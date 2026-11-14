extends SceneTree
## Headless test: the workshop (tools/blender/WORKSHOP_KIT.md) in the Moon level, then in the
## test level.
##   1. Layout: built from the kit; the rover starts in the dock zone; the rack holds its 17
##      parts on their slots, at rest; every label fits its plate at 50-65 mm caps.
##   2. Reach: from where the player stands (console, between the rover and the rack, the
##      charger), a ray from the eye reaches the console, the restock button, rack parts, the
##      rover's battery socket and the charger within 3 m, nothing in the way.
##   3. Charging: docked, a drained battery charges with the probe up 20 mm under the belly;
##      docked at the zone's edge at an odd heading it still connects, under the rover's origin;
##      0.6 m off it doesn't, and the dock hint says where to go; with no battery it says so.
##   4. Console: E drives the rover and stands the player at the console; Esc brings the view back
##      there. The seated operator (tools/blender/ASTRONAUT_KIT.md) shows only while the console
##      drives the rover, through a pause too; the empty suit stands on its stand, which the player
##      walks past and can't walk through.
##   5. The drive: out of the bay door (it opens; the rover touches nothing of the workshop), 12 m
##      out (the door closes behind it), back in along the entry lane, a U-turn and onto the pad
##      by steering for waypoints, stopped by braking like a driver; it must end in the dock zone,
##      charging, upright, never touching the workshop.
##   6. Doors on foot: the personnel door lets the player through (and is locked while the bay
##      door is open on the Moon); the pressure curtain keeps the player in on the Moon, not in the
##      test level.
##   7. Decor (tools/blender/DECOR_KIT.md), checked before the drive and the doors so those run
##      with it in place (the reach checks above already cast through its colliders): built; every
##      text from decor_texts.json drawn and fitting its paper or plate; the history cards' NASA
##      photos and credits; scenery only (static bodies on layer 1, mask 0; nothing that can be
##      picked up, used or scanned); looking at it leaves the crosshair plain and the part tooltip
##      hidden (the desk items show the console's own prompt); the player can't walk through the
##      tool chest; the exterior rests on the ground and is outside the bay door's rover
##      detection; the tracks only on the Moon terrain's layer; the triangle and draw budget.
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


## The dock point in kit coordinates (x, y)
func _dock() -> Vector2:
	var local: Vector3 = workshop.anchors["dock_point"]
	return Vector2(local.x, -local.z)


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
		await _astronaut_checks()
		await _decor_checks()
		await _drive_checks()
		await _door_checks()
	print("RESULT %s" % ("ALL PASS" if failures == 0 else "%d CHECKS FAILED" % failures))
	quit(1 if failures else 0)


# 1 ---------------------------------------------------------------------------------------------
func _layout_checks() -> void:
	var parts: int = workshop.get_node("Parts").get_child_count()
	_check("built from the kit layout", parts == 103, "%d part instances" % parts)
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
	_check("the rack holds its 17 parts (with the cartridge and the light battery)", stock.get_child_count() == 17, "%d" % stock.get_child_count())
	var batteries: Array = []
	for part in stock.get_children():
		if part.has_method("drain"):  # a BatteryPart (named by method: the class needs the autoloads)
			batteries.append(part)
	var distinct: bool = batteries.size() == 2 and batteries[0].capacity != batteries[1].capacity and batteries[0].mass != batteries[1].mass \
		and batteries[0].get_catalog_id() != batteries[1].get_catalog_id()
	var named: bool = distinct and batteries.all(func(b): return b.get_display_name() != "Part")
	_check("the rack holds two batteries with distinct Wh, kg and catalog entries", named,
		", ".join(batteries.map(func(b): return "%s %.0f Wh %.1f kg" % [b.get_catalog_id(), b.capacity, b.mass])))
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
	_place_rover(_dock().x + 0.27, _dock().y - 0.27, 37.0)
	await _ticks(4.0)
	var probe_xz := Vector2(pad.probe.global_position.x, pad.probe.global_position.z)
	var origin_xz := Vector2(rover.global_position.x, rover.global_position.z)
	_check("docked at the zone's edge, 37 degrees: connects under the rover's origin", pad.state == workshop.pad.State.CHARGING
		and probe_xz.distance_to(origin_xz) < 0.01, "%s, probe %.1f cm from the origin, %.2f m off the dock point" % [pad.get_status_text(), probe_xz.distance_to(origin_xz) * 100.0, pad.offset_of(rover).length()])
	# Outside the zone: the driver gets told where to go
	_place_rover(_dock().x + 0.6, _dock().y, 0.0)
	await _ticks(2.5)
	var hint: String = pad.get_dock_hint(rover)
	_check("0.6 m off: not docked, the hint points the way", pad.state == workshop.pad.State.ON_PAD and hint.begins_with("Charging pad:")
		and hint.contains("to the left") and pad.probe_height() < 0.001, "\"%s\"" % hint)
	# No battery
	var battery = rover.battery_socket.unmount()
	_place_rover(_dock().x, _dock().y, 0.0)
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
	var seat: Vector3 = workshop.to_global(workshop.anchors["anchor_seat"])
	_check("console: the seated operator shows while the console drives", workshop.operator.is_visible_in_tree()
		and workshop.operator.global_position.distance_to(seat) < 0.001)
	GS.change_state_to(GS.State.PAUSED)
	await process_frame
	var paused_visible: bool = workshop.operator.visible
	GS.change_state_to(GS.State.IN_GAME_ROBOT)
	await process_frame
	_check("console: the operator stays seated through a pause", paused_visible and workshop.operator.visible)
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.5)
	_check("leaving the rover: the view is back at the console", root.get_camera_3d() == player.camera
		and Vector2(player.global_position.x - stand.x, player.global_position.z - stand.z).length() < 0.15)
	_check("leaving the rover: the operator is gone", not workshop.operator.visible)


func _astronaut_checks() -> void:
	var suit: Node3D = workshop.suit_on_stand
	var at: Vector3 = workshop.to_global(workshop.anchors["anchor_suit"])
	_check("astronaut: the empty suit stands on its stand, the helmet on the shelf", suit.is_visible_in_tree()
		and suit.global_position.distance_to(at) < 0.001 and suit.find_child("astronaut_helmet", true, false) != null,
		"suit at kit %s" % _kit_of(suit.global_position).snapped(Vector3.ONE * 0.01))
	_check("astronaut: no operator at the console while nobody drives", not workshop.operator.is_visible_in_tree())
	# Walking along the operator area's south side, past the stand, to the east wall
	var p: Vector3 = await _walk(Vector3(2.6, -2.6, 0.0), Vector2(1.0, 0.0), 2.0)
	_check("astronaut: the player walks past the suit stand", p.x > 4.2 and absf(p.y + 2.6) < 0.1, "player at kit (%.2f, %.2f)" % [p.x, p.y])
	# Straight at it: the stand stops the player in front of the suit
	p = await _walk(Vector3(4.0, -2.2, 0.0), Vector2(0.0, -1.0), 2.0)
	_check("astronaut: the player can't walk into the suit on its stand", p.y > -3.05 + 0.25 - 0.02, "player at kit y %.2f" % p.y)
	GS.player.global_position = workshop.to_global(workshop.anchors["spawn_player"]) + Vector3(0.0, 0.05, 0.0)
	await _ticks(0.5)


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
			# within 1.5 m, so a waypoint inside the turning circle can't make it circle
			var passed: bool = Vector2(forward.x, forward.z).dot(to) < 0.0 and to.length() < 1.5
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


## Heading in the kit frame, degrees from +Y (out of the bay door), positive towards -X
func _kit_heading() -> float:
	var f: Vector3 = _kit_of(rover.global_position - rover.global_basis.z) - _kit_of(rover.global_position)
	return rad_to_deg(atan2(-f.x, f.y))


## Full left lock at a crawl until the rover faces out of the bay door again, then brake to a stop
func _u_turn(timeout: float) -> bool:
	var bodies: Dictionary = _workshop_bodies()
	var t: float = 0.0
	var turned: float = 0.0
	var last: float = _kit_heading()
	while turned < 172.0:
		await physics_frame
		t += 1.0 / TICKS
		if t > timeout:
			_release_all()
			return false
		var h: float = _kit_heading()
		if trace and int(t * TICKS) % (TICKS / 4) == 0:
			var k: Vector3 = _kit_of(rover.global_position)
			print("TRACE uturn t %.2f kit (%.2f, %.2f) heading %.0f v %.2f steer %.2f turned %.0f" % [t, k.x, k.y, h, rover.linear_velocity.length(), rover.controller.steer, turned])
		turned += absf(wrapf(h - last, -180.0, 180.0))
		last = h
		for body in rover.get_colliding_bodies():
			if bodies.has(body):
				touched[String(body.get_parent().name) + "/" + String(body.name)] = true
		var v: float = rover.linear_velocity.dot(-rover.global_basis.z)
		_release_all()
		Input.action_press("move_left", 1.0)
		# Slow down first, then a steady 20% throttle (about 0.4 m/s): the tightest turn. The circle
		# widens both slower (1.36 m at 0.19 m/s) and faster (1.1 m at 0.8 m/s)
		if v > 0.55:
			Input.action_press("move_backward", 0.3)
		else:
			Input.action_press("move_forward", 0.2)
	_release_all()
	while rover.linear_velocity.length() > 0.03 and t < timeout:
		await physics_frame
		t += 1.0 / TICKS
		_release_all()
		if rover.linear_velocity.dot(-rover.global_basis.z) > 0.05:
			Input.action_press("move_backward", 0.3)
	_release_all()
	return true


func _drive_checks() -> void:
	touched.clear()
	_place_rover(_dock().x, _dock().y, 0.0)
	await _ticks(1.0)
	GS.drive(rover)
	await _ticks(0.2)
	# Out: straight along the pad's centre line
	var d: Vector2 = _dock()
	var out_ok: bool = await _drive_to([Vector2(d.x, 2.0), Vector2(d.x, 6.0), Vector2(d.x - 0.5, 12.0)], 1.0, 40.0, false)
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
	# Back in like a driver (WORKSHOP_KIT.md 5.2): through the door on x -2.2, drifting west inside
	# the bay to x -2.8, then a U-turn on full left lock at a steady 20% throttle round a centre on
	# y -0.8, straightening when it faces the door again, then braking to a stop on the pad
	var in_ok: bool = await _drive_to([Vector2(-2.2, 9.0), Vector2(-2.2, 3.0)], 0.9, 60.0, false)
	in_ok = in_ok and await _drive_to([Vector2(-2.8, 0.2), Vector2(-2.8, -0.8)], 0.4, 30.0, false)
	in_ok = in_ok and await _u_turn(30.0)
	# Then creep forwards onto the pad, straight ahead, to the dock point's line
	var after: Vector3 = _kit_of(rover.global_position)
	if after.y < d.y - 0.05:
		in_ok = in_ok and await _drive_to([Vector2(after.x, d.y)], 0.3, 20.0, true)
	await _ticks(3.0)
	var offset: float = workshop.pad.offset_of(rover).length()
	var end: Vector3 = _kit_of(rover.global_position)
	_check("drive in: U-turn and onto the pad", in_ok and offset <= workshop.pad.DOCK_ZONE, "%.2f m off the dock point, rover at kit (%.2f, %.2f) heading %.0f" % [
		offset, end.x, end.y, _kit_heading()])
	_check("drive in: docked and connected", workshop.pad.state in [workshop.pad.State.CHARGING, workshop.pad.State.FULL], workshop.pad.get_status_text())
	_check("the drive never touched the workshop", touched.is_empty(), str(touched.keys()))
	_check("the rover stayed upright", rover.global_basis.y.y > 0.99)
	# Docked at the zone's east edge (nearest the door's east jamb), straight out of the door
	touched.clear()
	_place_rover(d.x + 0.4, d.y, 0.0)
	await _ticks(1.0)
	var edge_ok: bool = await _drive_to([Vector2(d.x + 0.4, 6.0)], 0.8, 30.0, false)
	var east_gap: float = 1.0 - (_kit_of(rover.global_position).x + 0.628)
	_check("docked at the zone's east edge: straight out, clear of the jamb", edge_ok and touched.is_empty() and east_gap >= 0.3,
		"%.2f m to the east jamb, touched %s" % [east_gap, str(touched.keys())])
	await _ticks(0.5)
	_place_rover(d.x, d.y, 0.0)
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


# 7 ---------------------------------------------------------------------------------------------
## True when the node's script, or one it extends, is one of the game's `classes`
func _has_class(node: Node, classes: Array) -> bool:
	var script: Script = node.get_script()
	while script:
		if script.get_global_name() in classes:
			return true
		script = script.get_base_script()
	return false


## Stands the player at kit (x, y) looking at the kit point `at` (x, y, height)
func _look_at_kit(stand: Vector2, at: Vector3) -> void:
	var player = GS.player
	player.global_position = _kit(stand.x, stand.y, 0.05)
	player.linear_velocity = Vector3.ZERO
	var eye: Vector3 = _kit(stand.x, stand.y, 1.55)
	var d: Vector3 = _kit(at.x, at.y, at.z) - eye
	player.controller.camera_azimuth = atan2(-d.x, -d.z)
	player.controller.camera_altitude = atan2(d.y, Vector2(d.x, d.z).length())


func _decor_checks() -> void:
	var decor = workshop.decor
	_check("decor: built (interior, exterior, cable, tracks)", decor != null and decor.interior != null
		and decor.exterior_pieces.size() == 5 and decor.cable != null and decor.tracks.size() == 15,
		"%d exterior pieces, %d track decals" % [decor.exterior_pieces.size(), decor.tracks.size()] if decor else "no decor")
	if decor == null:
		return

	# Words: every entry of the texts file drawn, nothing drawn that isn't in it, all fitting
	var wanted: Array[String] = []
	for section in ["notes", "signs", "labels", "cards"]:
		for key in decor.texts.get(section, {}):
			wanted.append(key)
	var drawn: Array[String] = []
	for full in decor.text_keys:
		drawn.append(full.substr(full.get_slice("_", 0).length() + 1))
	wanted.sort()
	drawn.sort()
	var empty_labels: int = 0
	var smallest: float = 1.0
	for item in decor.labels:
		if (item[0] as Label3D).text.strip_edges().is_empty():
			empty_labels += 1
		smallest = minf(smallest, decor.cap_height(item[0]))
	_check("decor: every text in decor_texts.json drawn, and only those", wanted == drawn and empty_labels == 0,
		"%d texts, %d labels, %d empty; missing %s, unknown %s" % [wanted.size(), decor.labels.size(), empty_labels,
		wanted.filter(func(k): return not k in drawn), drawn.filter(func(k): return not k in wanted)])
	var misfits: Array[String] = decor.misfits()
	_check("decor: every text fits its paper or plate", misfits.is_empty(), "smallest caps %.1f mm; %s" % [smallest * 1000.0, misfits])

	# The history cards: the NASA photo on each, the credit naming its NASA ID
	var cards_ok := true
	var detail := ""
	for key in decor.PHOTOS:
		var photo := decor.interior.find_child("card_photo_" + key, true, false) as MeshInstance3D
		var material := photo.material_override as StandardMaterial3D if photo else null
		var texture_path: String = material.albedo_texture.resource_path if material and material.albedo_texture else ""
		var nasa_id: String = texture_path.get_file().get_basename().to_upper()
		var credit: String = decor.texts["cards"][key]["credit"]
		cards_ok = cards_ok and texture_path == decor.PHOTOS[key] and credit.contains(nasa_id) and credit.begins_with("Photo: NASA")
		detail += "%s: %s, \"%s\"; " % [key, texture_path.get_file(), credit]
	_check("decor: the history cards carry their NASA photos and credits", cards_ok, detail)

	# Scenery only
	var bad: Array[String] = []
	var bodies: int = 0
	for node in decor.find_children("*", "Node", true, false):
		# (game classes by name: this script compiles before the game's autoloads exist)
		if node is RigidBody3D or node is Area3D or _has_class(node, ["InteractTrigger", "HotswapPart", "CargoPort", "Robot", "Iris"]):
			bad.append(String(node.name))
		for group in ["scan_target", "charging_pad", "iris", "cargo_port", "workshop"]:
			if node.is_in_group(group):
				bad.append("%s in %s" % [node.name, group])
		if node is CollisionObject3D:
			bodies += 1
			if not node is StaticBody3D or node.collision_layer != 1 or node.collision_mask != 0:
				bad.append("%s layer %d mask %d" % [node.name, node.collision_layer, node.collision_mask])
	_check("decor: scenery only (static bodies on layer 1, mask 0; nothing to pick up, use or scan)", bad.is_empty() and bodies > 0,
		"%d static bodies; %s" % [bodies, bad])

	# Looking at it, as the player does: the crosshair stays plain and the part tooltip hidden
	var hud: Node = root.get_node("Main").find_child("HUD", true, false)
	var tooltip: Control = hud.find_child("PartTooltip", true, false)
	var hud_script: Script = hud.get_script()
	var looks: Array = [["tool chest", Vector2(-3.3, -1.95), Vector3(-4.5, -1.95, 0.7)],
		["crates", Vector2(-3.2, -2.6), Vector3(-4.4, -3.55, 0.5)],
		["oxygen rack", Vector2(-3.5, 2.35), Vector3(-4.6, 2.35, 1.0)],
		["spare wheel", Vector2(-3.5, 0.75), Vector3(-4.65, 0.75, 1.55)],
		["rack's service note", Vector2(1.4, -3.0), Vector3(2.01, -3.30, 1.45)],
		["history card", Vector2(3.9, -0.95), Vector3(4.76, -0.95, 1.5)],
		["plant lab", Vector2(3.9, 1.0), Vector3(4.6, 1.0, 1.0)]]
	for look in looks:
		_look_at_kit(look[1], look[2])
		await _ticks(0.3)
		await process_frame
		var target: Object = GS.player.looking_at_object
		var interactive: bool = hud_script.is_interactive(target)
		_check("decor: looking at the %s, no use crosshair or tooltip" % look[0], not interactive and not tooltip.visible,
			"looking at %s" % (target.name if target else "nothing"))
	# The mug on the console desk sits inside the console's trigger: the console's own prompt
	_look_at_kit(Vector2(3.2, 0.2), Vector3(2.22, 0.2, 0.95))
	await _ticks(0.3)
	await process_frame
	var on_desk: Object = GS.player.looking_at_object
	_check("decor: looking at the mug on the desk shows only the console's prompt", on_desk == workshop.console_trigger and tooltip.visible,
		"looking at %s" % (on_desk.name if on_desk else "nothing"))
	# The tool chest has collision: walking into it stops the player
	var p: Vector3 = await _walk(Vector3(-3.4, -1.95, 0.0), Vector2(-1.0, 0.0), 2.0)
	_check("decor: the player can't walk through the tool chest", p.x > -4.30 + 0.25 - 0.03, "player at kit x %.2f" % p.x)

	# Exterior: rested on the ground (its own ray, past every body of the workshop) and never seen
	# by the bay door's rover detection
	var exclude: Array[RID] = []
	for body in workshop.find_children("*", "CollisionObject3D", true, false):
		exclude.append(body.get_rid())
	var worst: float = 0.0
	var resting: int = 0
	for piece in decor.exterior_pieces:
		if absf(piece.position.y) > 0.3:
			continue
		var top: Vector3 = piece.global_position + workshop.global_basis.y * 1.0
		var q := PhysicsRayQueryParameters3D.create(top, top - workshop.global_basis.y * 3.0, 1)
		q.exclude = exclude
		var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(q)
		var gap: float = 1.0 if hit.is_empty() else (piece.global_position - hit["position"]).dot(workshop.global_basis.y) + decor.GROUND_SINK
		worst = maxf(worst, absf(gap))
		resting += 1
	_check("decor: the exterior pieces rest on the ground (within 2 cm)", resting == 3 and worst <= 0.02, "%d pieces, worst %.3f m" % [resting, worst])
	_check("decor: outside the bay door's rover detection", workshop._door_area.collision_mask & 1 == 0)
	var mask_ok := true
	var terrain_layer: int = load("res://src/levels/terrain/moon_terrain.gd").RENDER_LAYER
	for decal in decor.tracks:
		mask_ok = mask_ok and decal.cull_mask == 1 << (terrain_layer - 1)
	_check("decor: the tyre tracks only paint the Moon terrain", mask_ok)

	# Budget (DECOR_KIT.md 7): triangles and the interior's draw calls
	var triangles: int = 0
	var surfaces: int = 0
	for mesh in decor.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mesh as MeshInstance3D).mesh
		if m == null:
			continue
		triangles += m.get_faces().size() / 3
		if decor.interior.is_ancestor_of(mesh):
			surfaces += m.get_surface_count()
	_check("decor: within its budget (3,500 triangles, the interior about 10 draw calls)", triangles <= 3500 and surfaces <= 12,
		"%d triangles, %d interior surfaces, %d labels" % [triangles, surfaces, decor.labels.size()])
	GS.player.global_position = workshop.to_global(workshop.anchors["spawn_player"]) + Vector3(0.0, 0.05, 0.0)
	await _ticks(0.5)
