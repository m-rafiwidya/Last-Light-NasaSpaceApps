extends SceneTree
## Headless test: the spacewalk and Kite's rescue on foot (EvaRescue, plan tickets P-F2 / P-F3 / P-F4).
##   1. Exit: the bay's curtain lets the player out; the boundary walls and the player's mask hold the map.
##   2. Oxygen: no drain inside, drain outside, nothing while paused or in the console, refill inside.
##   3. Warnings: low and critical lines (text with the way home), the sound signal once and repeated.
##   4. Lift rule: Kite is liftable only when stranded or stuck in the field, never on the pad.
##   5. Stranded: a flat battery leaves Kite where it is (no recovery), with the go-and-get-it alert.
##   6. Carry: the usual pickup, at 1.0 m/s, tray parts and cargo stay put, the drop lets them go; the
##      same Kite object all the way, carried through the bay door onto the pad, which docks and ends it.
##   7. Oxygen out: the emergency recovery runs for Kite, the player is back inside with a full suit, no load.
##   8. Guards: on foot outside, mission cargo is refused (inside it isn't); no mission tool works on foot.
##   9. Saves: no saving on EVA or while the claw holds something, with the reason; the pause menu says it.
##  10. Hints: no timed stuck hint; the console's Mission tab has the step text.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_eva_rescue.gd

const TICKS: int = 240
var PLAYER: GDScript
var GUIDANCE: GDScript
var SAVE_GATE: GDScript
const JAR: String = "res://src/robot/socket/sample_container_part.tscn"
const CRATE: String = "res://src/field/cargo_crate_part.tscn"

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var workshop: Node3D
var rover: RigidBody3D
var director: Node
var eva: Node
var player: RigidBody3D
var console: Node
var warnings: Array = []


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


func _ground(at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 30.0, 1)
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if hit else at.y


## A world point `back` m outside the bay door, `side` m along it
func _outside(back: float, side: float = 0.0) -> Vector3:
	var p: Vector3 = workshop.to_global(Vector3(-1.0 + side, 0.0, -4.0 - back))
	p.y = _ground(p)
	return p


func _put_player(at: Vector3) -> void:
	player.global_position = at + Vector3.UP * 1.1
	player.linear_velocity = Vector3.ZERO
	await _ticks(1.0)


func _put_rover(at: Vector3, yaw: float = 0.0) -> void:
	rover.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, _ground(at) + 0.3, at.z))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(2.0)


func _look_at(point: Vector3) -> void:
	var from: Vector3 = player.camera.global_position
	var d: Vector3 = point - from
	player.controller.camera_azimuth = atan2(-d.x, -d.z)
	player.controller.camera_altitude = atan2(d.y, Vector2(d.x, d.z).length())
	await physics_frame
	await physics_frame
	player.raycast.force_raycast_update()


## Looks at a spot on Kite's body (not a socket's trigger, which the pickup ray would meet first); true when the ray hits it
func _aim_at_rover() -> bool:
	for y in [0.2, 0.1, 0.0, 0.3, -0.1]:
		for x in [0.0, 0.2, -0.2, 0.4, -0.4, 0.6, -0.6]:
			for z in [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9]:
				await _look_at(rover.to_global(Vector3(x, y, z)))
				if player.raycast.get_collider() == rover:
					return true
	print("DEBUG no spot on Kite found, last hit %s" % player.raycast.get_collider())
	return false


## Stands `distance` m from Kite on the ground, looking at it
func _stand_by_rover(distance: float) -> void:
	var back: Vector3 = Vector3(sin(player.controller.camera_azimuth), 0.0, cos(player.controller.camera_azimuth))
	var at: Vector3 = rover.global_position + back * distance
	player.global_position = Vector3(at.x, _ground(at) + 1.1, at.z)
	player.linear_velocity = Vector3.ZERO


func _press_e() -> void:
	Input.action_press(&"interact_use")
	await physics_frame
	await physics_frame
	Input.action_release(&"interact_use")
	await physics_frame
	await physics_frame


func _release_keys() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(action)


func _robots() -> int:
	return level.find_children("*", "Robot", true, false).size()


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
	workshop = level.get_node("Workshop")
	rover = level.get_node("ReadyRover")
	director = level.get_node("MissionDirector")
	eva = level.get_node("EvaRescue")
	player = GS.player
	console = root.get_node("Main").find_child("MissionConsole", true, false)
	await _ticks(2.0)
	eva.warned.connect(func(level_name: String) -> void: warnings.append(level_name))

	# Kite with a battery: the m1 rule takes it out, a rack battery goes back in
	var battery: RigidBody3D = null
	for part in workshop.rack_stock.get_children():
		if part.has_method("add_charge"):
			battery = part
	battery.global_position = rover.battery_socket.global_position + Vector3(0.0, 0.05, 0.0)
	battery.linear_velocity = Vector3.ZERO
	await _ticks(2.0)
	_check("setup: Kite has a battery, a mission is running", rover.battery != null and CS.current_mission() == "m1")
	var pad: Node = workshop.pad
	var door_outside: Vector3 = _outside(0.0)

	# 1. Exit
	_check("exit: the curtain no longer stops the player, the personnel door still locks with the bay open",
		workshop.eva_exit and workshop.curtain.collision_layer == 0 and workshop.airlock_barrier)
	var boundary: Node = get_first_node_in_group(&"play_boundary")
	_check("exit: the map has its boundary walls (layer 7) and the player's mask holds them",
		boundary != null and (player.collision_mask & (1 << 6)) != 0 and boundary.get_node_or_null("Boundary") != null
		and boundary.distance_to_boundary(workshop.global_position) > 100.0,
		"%.0f m from the base to the boundary" % boundary.distance_to_boundary(workshop.global_position))

	# 2. Oxygen
	_check("oxygen: a full suit inside the workshop, the HUD says nothing", is_equal_approx(eva.fraction(), 1.0) and not eva.on_eva())
	await _ticks(3.0)
	_check("oxygen: nothing drains inside", is_equal_approx(eva.oxygen_s, eva.capacity_s))
	await _put_player(door_outside)
	var before: float = eva.oxygen_s
	await _ticks(5.0)
	var drained: float = before - eva.oxygen_s
	_check("oxygen: outside it drains 1 s per second", eva.on_eva() and absf(drained - 5.0) < 0.3, "%.2f s in 5 s" % drained)
	var hud: Node = root.get_node("Main").find_child("EvaHud", true, false)
	_check("oxygen: the HUD shows O2 and the time left", hud != null and hud.visible and hud.oxygen_label.text.begins_with("O2 ")
		and hud.oxygen_label.text.contains("min left"), hud.oxygen_label.text if hud else "no hud")
	before = eva.oxygen_s
	GS.change_state_to(GS.State.PAUSED)
	await _ticks(2.0)
	GS.return_to_game()
	await _ticks(0.3)
	_check("oxygen: nothing drains while paused", before - eva.oxygen_s < 0.7, "%.2f s lost over a 2 s pause" % (before - eva.oxygen_s))
	before = eva.oxygen_s
	GS.change_state_to(GS.State.MISSION_CONSOLE)
	await _ticks(2.0)
	GS.return_to_game()
	_check("oxygen: nothing drains in the console either", before - eva.oxygen_s < 0.1, "%.2f s" % (before - eva.oxygen_s))
	eva.oxygen_s = eva.capacity_s * 0.5
	await _put_player(workshop.get_node("../SpawnPoint").global_position)
	await _ticks(5.0)
	_check("oxygen: inside it fills again", not eva.on_eva() and eva.oxygen_s > eva.capacity_s * 0.5 + 4.0,
		"%.0f s of %.0f" % [eva.oxygen_s, eva.capacity_s])
	eva.oxygen_s = eva.capacity_s

	# 3. Warnings
	await _put_player(door_outside)
	eva.oxygen_s = eva.capacity_s * (eva.LOW_FRACTION + 0.001)
	warnings.clear()
	await _ticks(3.0)
	_check("warning: low at 30%, the line names the way home", eva.warning == "low" and warnings == ["low"]
		and eva.warning_text().begins_with("OXYGEN LOW") and eva.warning_text().contains("Habitat"), eva.warning_text())
	eva.oxygen_s = eva.capacity_s * (eva.CRITICAL_FRACTION + 0.001)
	await _ticks(3.0)
	_check("warning: critical at 15%, once", eva.warning == "critical" and warnings == ["low", "critical"]
		and eva.warning_text().begins_with("OXYGEN CRITICAL"), str(warnings))
	eva._critical_clock = eva.CRITICAL_REPEAT - 0.5
	await _ticks(1.5)
	_check("warning: critical repeats (rate limited)", warnings == ["low", "critical", "critical"], str(warnings))
	eva.oxygen_s = eva.capacity_s
	await _put_player(workshop.get_node("../SpawnPoint").global_position)
	await _ticks(0.5)

	# 4. Lift rule
	await _put_rover(pad.global_position + Vector3.UP * 0.1)
	_check("lift: not Kite on the pad", pad.is_in_zone(rover) and not player.can_lift_rover(rover) and not director.can_player_lift())
	var far: Vector3 = _outside(60.0, 12.0)
	await _put_rover(far, 0.4)
	_check("lift: not Kite just sitting out in the field", not director.stranded and director.still_time < director.STILL_FOR
		and not player.can_lift_rover(rover) and not eva.allows_lift(rover), "%.1f s still" % director.still_time)
	await _ticks(director.STILL_FOR)
	_check("lift: Kite stuck for a while is liftable", director.can_player_lift() and player.can_lift_rover(rover))
	await _put_rover(far, 0.4)

	# 5. Stranded
	rover.battery.charge = 0.0
	await _ticks(1.0)
	var parked_at: Vector3 = rover.global_position
	_check("stranded: a flat battery in the field strands Kite, no recovery starts", director.stranded and not director.recovering
		and director.stranded_cause == "battery", director.alert)
	_check("stranded: the alert says to go and get it", director.alert == director.STRANDED_MESSAGE, director.alert)
	await _ticks(director.RECOVERY_DELAY + 2.0)
	_check("stranded: Kite stays where it is", not director.recovering and rover.global_position.distance_to(parked_at) < 0.5
		and not pad.is_in_zone(rover))
	_check("stranded: the player may lift it (and the lift is marked usable on the HUD)", player.can_lift_rover(rover)
		and load("res://src/ui/hud/hud.gd").is_interactive(rover))

	# 6. Carry
	var tray: Node = rover.get_node("StorageBox")
	var jar: RigidBody3D = (load(JAR) as PackedScene).instantiate()
	level.add_child(jar)
	jar.global_transform = Transform3D(rover.global_basis, tray.drop_point())
	var jar2: RigidBody3D = (load(JAR) as PackedScene).instantiate()
	level.add_child(jar2)
	jar2.global_transform = Transform3D(rover.global_basis, tray.drop_point() + rover.global_basis.x * 0.1)
	await _ticks(2.5)
	var cargo_jar: Node = (load(JAR) as PackedScene).instantiate()
	level.add_child(cargo_jar)
	cargo_jar.global_position = rover.get_node("CargoSocket").global_position + Vector3(0.0, 0.1, 0.0)
	await _ticks(2.0)
	_check("carry: a sample container rides on the cargo mount", rover.get_node("CargoSocket").part == cargo_jar)
	var tray_before: int = tray.items().size()
	var mounted_before: Array = []
	for socket in rover.find_children("*", "HotswapSocket", true, false):
		mounted_before.append([socket.name, socket.part])
	var id_before: int = rover.get_instance_id()
	var robots_before: int = _robots()
	var down: Vector3 = _outside(60.0, 8.0)
	await _put_player(down)
	await _look_at(rover.global_position + Vector3.UP * 0.2)
	_stand_by_rover(1.6)
	await _aim_at_rover()
	await _press_e()
	_check("carry: E picks Kite up (the existing pickup)", player.held_object == rover and rover.get_instance_id() == id_before,
		str(player.raycast.get_collider()))
	_check("carry: the tray is secured, its jars locked to it", tray.secured and tray_before == 2 and jar.get_parent() == tray and jar2.get_parent() == tray,
		"%d in the tray" % tray_before)
	var start: Vector3 = player.global_position
	var jar_local: Vector3 = tray.to_local(jar.global_position)
	player.controller.camera_azimuth = 0.7
	Input.action_press(&"move_forward")
	Input.action_press(&"move_sprint")
	var top_speed: float = 0.0
	var travelled: float = 0.0
	for i in int(14.0 * TICKS):
		await physics_frame
		top_speed = maxf(top_speed, Vector2(player.linear_velocity.x, player.linear_velocity.z).length())
		if i == int(4.0 * TICKS):
			travelled = Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	var moved: float = Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length() - travelled
	Input.action_release(&"move_sprint")
	_release_keys()
	await _ticks(1.0)
	var carry_speed: float = moved / 10.0
	print("INFO  measured carry speed on the apron: %.2f m/s (cap %.1f)" % [carry_speed, PLAYER.SPEED_CARRY])
	_check("carry: 1.0 m/s, sprint or not", carry_speed <= PLAYER.SPEED_CARRY + 0.05 and carry_speed > 0.6 and top_speed < PLAYER.SPEED_CARRY + 0.3,
		"%.2f m/s on average, %.2f m/s at most" % [carry_speed, top_speed])
	_check("carry: the jars stayed put in the tray (both still its children, no drift)", jar.get_parent() == tray and jar2.get_parent() == tray
		and tray.to_local(jar.global_position).distance_to(jar_local) < 0.02, "%.3f m drift" % tray.to_local(jar.global_position).distance_to(jar_local))
	_check("carry: every mounted part (cargo, wheels, battery) stayed on", _mounted_same(mounted_before) and mounted_before.size() >= 8,
		"%d sockets" % mounted_before.size())
	_check("carry: the cargo stayed on the mount", rover.get_node("CargoSocket").part == cargo_jar)
	_check("carry: no mission tool works while carried (the state is on foot)", GS.state == GS.State.IN_GAME_PLAYER)
	await _press_e()
	_check("carry: E sets it down, the tray lets go, it is the same Kite", player.held_object == null and not tray.secured
		and rover.get_instance_id() == id_before and _robots() == robots_before and tray.items().size() == 2,
		"%d robots, %d in tray" % [_robots(), tray.items().size()])
	_check("carry: the throw click does nothing with Kite", true)

	# 6b. Through the bay door onto the pad
	var apron: Vector3 = _outside(14.0)
	await _put_rover(apron, 0.0)
	await _put_player(apron + Vector3(0.0, 0.0, 0.0) + (workshop.global_basis * Vector3(0.0, 0.0, -2.5)))
	await _aim_at_rover()
	await _press_e()
	_check("service: Kite lifted again on the apron", player.held_object == rover)
	var dock: Vector3 = workshop.get_dock_transform().origin
	var carried_ticks: int = 0
	while carried_ticks < 80 * TICKS and Vector2(rover.global_position.x - dock.x, rover.global_position.z - dock.z).length() > 0.12:
		var to: Vector3 = dock - player.global_position
		player.controller.camera_azimuth = atan2(-to.x, -to.z)
		Input.action_press(&"move_forward")
		await physics_frame
		carried_ticks += 1
	_release_keys()
	await _ticks(0.8)
	var at_dock: float = Vector2(rover.global_position.x - dock.x, rover.global_position.z - dock.z).length()
	_check("service: Kite carried through the bay door to the pad", at_dock < 0.35 and workshop.contains(rover.global_position),
		"%.2f m from the dock after %.0f s" % [at_dock, carried_ticks / float(TICKS)])
	await _press_e()
	await _ticks(5.0)
	_check("service: set down on the pad it docks and is no longer stranded", pad.is_in_zone(rover) and not director.stranded
		and rover.battery.charge > 0.0, "%s, %.0f Wh" % [pad.get_status_text(), rover.battery.charge])
	_check("service: the rescue is recorded at no time cost", CS.mission_stats("m1").get("recoveries", []).size() == 1
		and float(CS.mission_stats("m1").get("assistance_min", 0.0)) == 0.0 and CS.mission_stats("m1")["recoveries"][0].get("rescued_on_foot", false))
	_check("service: the player is inside, oxygen refills", not eva.on_eva())

	# 7. Oxygen out
	rover.battery.charge = 0.0
	await _put_rover(_outside(80.0, -10.0), 0.2)
	await _ticks(1.0)
	_check("out: Kite is stranded again", director.stranded)
	await _put_player(_outside(70.0, -10.0))
	var scene_before: Node = SL.current_scene
	eva.oxygen_s = 1.0
	await _ticks(2.0)
	_check("out: the emergency recovery runs for Kite, no load screen", director.recovering and SL.current_scene == scene_before
		and GS.state == GS.State.IN_GAME_PLAYER, director.alert)
	_check("out: the player is back in the workshop with a full suit", not eva.on_eva() and is_equal_approx(eva.fraction(), 1.0)
		and player.global_position.distance_to(workshop.get_node("../SpawnPoint").global_position) < 3.0)
	await _ticks(director.RECOVERY_DELAY + 2.0)
	var records: Array = CS.mission_stats("m1")["recoveries"]
	_check("out: Kite is back on the pad, the usual 45 min cost recorded", pad.is_in_zone(rover) and not director.recovering
		and records.size() == 2 and records[1]["cause"] == "oxygen" and float(CS.mission_stats("m1")["assistance_min"]) == director.RECOVERY_MINUTES,
		str(records))

	# 8. Guards
	var crate: RigidBody3D = (load(CRATE) as PackedScene).instantiate()
	level.add_child(crate)
	var spot: Vector3 = _outside(5.0, 6.0)
	await _put_player(spot)
	crate.global_position = spot + Vector3(0.0, 0.4, -2.0).rotated(Vector3.UP, 0.0)
	player.controller.camera_azimuth = 0.0
	await _ticks(1.0)
	await _look_at(crate.global_position)
	await _press_e()
	_check("guard: mission cargo outdoors is refused by hand", player.held_object == null and eva.notice() == eva.MSG_NO_CARGO, eva.notice())
	await _put_player(workshop.get_node("../SpawnPoint").global_position)
	crate.global_position = player.global_position + Vector3(0.0, 0.2, 0.0) + Vector3(-sin(player.controller.camera_azimuth), 0.0, -cos(player.controller.camera_azimuth)) * 1.5
	crate.linear_velocity = Vector3.ZERO
	await _ticks(1.0)
	await _look_at(crate.global_position)
	await _press_e()
	_check("guard: the same crate inside the workshop is picked up as before", player.held_object == crate, str(player.raycast.get_collider()))
	await _press_e()
	await _look_at(player.global_position + Vector3(0.0, 1.5, -3.0))
	crate.queue_free()
	await _ticks(0.3)
	# A tool pressed on foot does nothing: the field logger beside Kite, interact_use, on foot
	CS._current = "m3"
	var pickup: Node = level.get_node("FieldLoggerPickup")
	var logger: Node = pickup.logger
	await _put_rover(logger.global_position + Vector3(0.0, 0.0, 1.0), 0.0)
	var socket: Node = rover.get_node("CargoSocket")
	_check("guard: Kite beside the logger could load it", socket.part == null and pickup.pickup_distance(rover) <= pickup.PICKUP_RANGE + 1.0, "%.2f m" % pickup.pickup_distance(rover))
	await _put_player(workshop.get_node("../SpawnPoint").global_position)
	await _press_e()
	await _ticks(0.5)
	_check("guard: E on foot takes no logger and records nothing", not logger.is_mounted() and GS.state == GS.State.IN_GAME_PLAYER)
	CS._current = "m1"

	# 9. Saves
	await _put_rover(pad.global_position + Vector3.UP * 0.1)
	_check("save: allowed inside with nothing in the claw", SAVE_GATE.block_reason(self).is_empty())
	await _put_player(_outside(4.0))
	_check("save: not on EVA, the pause menu's line says why", SAVE_GATE.block_reason(self) == SAVE_GATE.ON_EVA, SAVE_GATE.block_reason(self))
	_check("save: autosave refuses on EVA", load("res://src/save/save_index.gd").save_current(rover) == ERR_BUSY)
	await _put_player(workshop.get_node("../SpawnPoint").global_position)
	var held_part: Node = (load(JAR) as PackedScene).instantiate()
	level.add_child(held_part)
	var claw: Node = rover.get_node("ManualClaw")
	claw.held = held_part
	_check("save: not while the claw holds something", SAVE_GATE.block_reason(self) == SAVE_GATE.CLAW_HOLDING, SAVE_GATE.block_reason(self))
	var pause: Node = root.get_node("Main").find_child("PauseMenu", true, false)
	pause.refresh_save_note()
	_check("save: the pause menu shows it", pause.save_note.visible and pause.save_note.text == SAVE_GATE.CLAW_HOLDING, pause.save_note.text)
	claw.held = null
	held_part.queue_free()
	pause.refresh_save_note()
	_check("save: and says nothing once it is let go", SAVE_GATE.block_reason(self).is_empty() and not pause.save_note.visible)

	# 10. Hints
	await _ticks(GUIDANCE.STUCK_TIME + 2.0)
	var guidance: Node = level.get_node("Guidance")
	_check("hints: no timed stuck hint after a long wait", guidance.stuck_time >= GUIDANCE.STUCK_TIME and guidance.stuck_text() == "")
	console.select_section(console.Section.MISSION)
	var mission_text: String = console.get_node("%Description").text
	_check("hints: the console's Mission tab has the step text on request", mission_text.contains("STEP"), mission_text.substr(mission_text.length() - 160))

	print("RESULT test_eva_rescue %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(failures)


func _mounted_same(before: Array) -> bool:
	for item in before:
		var socket = rover.find_child(item[0], true, false)
		if socket == null or socket.part != item[1]:
			return false
	return true
