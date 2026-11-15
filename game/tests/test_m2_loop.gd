extends SceneTree
## Headless test: M2 "First Signal" from the cargo order to the telemetry downlink, through the
## game's own paths (the console's Planning tab, the player's holder and Kite's cargo mount, the
## console's CONTROL KITE, IRIS's module cradle, the charging pad, the Downlink action), with no
## debug command. The campaign starts at m2 as a loaded save would.
##   1. Delivery (the heaviest valid order): the crate lands at the landing zone (flag
##      cargo_at_landing_zone, the cargo lander there); nothing in the bay, the ordered parts off the rack.
##   2. Recovery: Kite with the crate aboard, stuck, recovered: the crate stays where Kite stopped and
##      is fetched again with E.
##   3. No soft-lock: a real drive apron -> crate -> apron with the crate aboard, on the light battery
##      at G1's 40 Wh; the round trip (pad legs included) + 30% fits in 40 Wh.
##   4. Home: Kite in the bay completes m2.cargo_retrieved and unpacks: the module in the bay's crate,
##      the ordered parts on the rack and bench.
##   5. Guidance: its targets resolve to the crate, the module itself, the cargo socket, the console
##      and the IRIS module cradle, whose hint replaces the step line while driving.
##   6. The chain: module_loaded, module_installed + iris_activated, near_sample_collected (S-1 from the
##      bench, guidance's waypoint to the site), kite_docked, telemetry_received, and m2 completes.
##   7. Save and load after the install: no radio module in the workshop (rack or crate), one in
##      IRIS's bay.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_m2_loop.gd

const M1_DONE: Array = ["m1.workshop_entered", "m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]
## G1's light battery (Wh) and the margin the fetch must keep
const LIGHT_WH: float = 40.0
const FETCH_MARGIN: float = 1.3
const SPEED: float = 3.0
const TICKS: int = 240

var GS: Node
var SL: Node
var CS: Node
var SI: GDScript
var failures: int = 0
var level: Node3D
var workshop: Node3D
var rover: RigidBody3D
var iris: Node3D
var guidance: Node
var plan: Script
var console: Node


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-66s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * 240):
		await physics_frame


func _wait_state(state: int, level_id: String = "", seconds: float = 120.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if GS.state == state and (level_id.is_empty() or SL.current_level_id == level_id):
			return true
		await process_frame
	return false


func _clear_dir() -> void:
	var dir: String = SI.save_dir()
	if DirAccess.dir_exists_absolute(dir):
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))


func _grab_level() -> void:
	level = SL.current_scene
	workshop = level.get_node("Workshop")
	rover = level.get_node("ReadyRover")
	iris = level.get_node("Iris")
	guidance = level.get_node("Guidance")
	console = root.get_node("Main").find_child("MissionConsole", true, false)


## Every radio-power module under `container`
func _modules(container: Node) -> Array:
	var found: Array = []
	for part in container.find_children("*", "RigidBody3D", true, false):
		if part.has_method("get_catalog_id") and part.get_catalog_id() == "radio_module" and not part.is_queued_for_deletion():
			found.append(part)
	return found


func _place(at: Vector3, facing: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0, 1)
	var hit: Dictionary = rover.get_world_3d().direct_space_state.intersect_ray(query)
	var ground: float = (hit["position"] as Vector3).y if hit else at.y
	rover.global_transform = Transform3D(Basis(Vector3.UP, atan2(-facing.x, -facing.z)), Vector3(at.x, ground + 0.3, at.z))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(2.0)


## The heaviest order any service accepts: [service, ids, kg]
func _heaviest_order() -> Array:
	var optional: Array = plan.items().map(func(e: Dictionary) -> String: return e["id"]).filter(
		func(id: String) -> bool: return not plan.required_items().has(id))
	var best: Array = ["", [], -1.0]
	for service in plan.services():
		for mask in 1 << optional.size():
			var ids: Array = Array(plan.required_items())
			for k in optional.size():
				if mask & (1 << k):
					ids.append(optional[k])
			if plan.validate(service["id"], ids) == "" and plan.order_mass(ids) > best[2]:
				best = [service["id"], ids, plan.order_mass(ids)]
	return best


func _count(catalog_id: String) -> int:
	var n: int = 0
	for part in workshop.rack_stock.get_children() + workshop.bench_stock.get_children():
		if part.has_method("get_catalog_id") and part.get_catalog_id() == catalog_id and not part.is_queued_for_deletion():
			n += 1
	return n


func _crates() -> Array:
	return level.find_children("*", "RigidBody3D", true, false).filter(func(p: Node) -> bool:
		return p.has_method("get_catalog_id") and p.get_catalog_id() == "cargo_crate" and not p.is_queued_for_deletion())


func _release_all() -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(a)


## Drives to (x, z) at SPEED; true on arrival within 1.5 m
func _drive_to(target: Vector2) -> bool:
	var best: float = INF
	var since: float = 0.0
	while true:
		await physics_frame
		var forward: Vector3 = -rover.global_basis.z
		var v: float = rover.linear_velocity.dot(forward)
		var to := Vector2(target.x - rover.global_position.x, target.y - rover.global_position.z)
		if to.length() < 1.5:
			break
		if to.length() < best - 2.0:
			best = to.length()
			since = 0.0
		else:
			since += 1.0 / TICKS
			if since > 40.0 or rover.battery.charge <= 0.0:
				_release_all()
				return false
		var heading := Vector2(forward.x, forward.z).normalized()
		var steer: float = clampf(heading.angle_to(to.normalized()) / 0.25, -1.0, 1.0)
		_release_all()
		if v > SPEED + 0.15:
			Input.action_press("move_backward", clampf((v - SPEED) * 0.6, 0.05, 0.6))
		elif v < SPEED:
			Input.action_press("move_forward", clampf(0.06 + (SPEED - v) * 0.3, 0.05, 0.5))
		if steer > 0.05:
			Input.action_press("move_right", steer)
		elif steer < -0.05:
			Input.action_press("move_left", -steer)
	_release_all()
	for i in TICKS:
		await physics_frame
		if rover.linear_velocity.length() < 0.05:
			break
	return true


## Kite stopped alongside the crate (its deck beside it), then E
func _fetch(crate: Node3D) -> bool:
	var side := Vector3(1.0, 0.0, 0.3).normalized()
	await _place(crate.global_position + side * 1.1, Vector3(-side.z, 0.0, side.x))
	Input.action_press(&"interact_use")
	await physics_frame
	await physics_frame
	Input.action_release(&"interact_use")
	await _ticks(0.3)
	return rover.get_node("CargoSocket").part == crate


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	SI = load("res://src/save/save_index.gd")
	plan = load("res://src/levels/cargo_plan.gd")
	if not await _wait_state(GS.State.MAIN_MENU):
		_check("main menu comes up", false)
		_finish()
		return
	_clear_dir()
	CS.reset()
	SI.start_new_campaign("slot_1")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("the Moon level comes up", false)
		_finish()
		return
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)
	CS.load_state({"current": "m2", "objectives": M1_DONE, "missions_done": ["m1"], "flags": [], "items": {}})
	SL.load_scene("moon_level")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("the Moon level comes up at m2", false)
		_finish()
		return
	_grab_level()
	await _ticks(1.0)
	var director: Node = level.get_node("MissionDirector")
	var zone: Node3D = level.get_node("LandingZone")

	# 1. Delivery: the heaviest order any lander takes lands at the landing zone
	_check("[crate] before the order: the bay's crate hidden, no module anywhere", not workshop.cargo_crate.visible and _modules(level).is_empty())
	var order: Array = _heaviest_order()
	console.select_section(console.Section.PLANNING)
	console.select_service(order[0])
	for entry in plan.items():
		console.set_item(entry["id"], order[1].has(entry["id"]))
	console._on_action_pressed()
	await _ticks(0.5)
	console.skip_flight()
	await _ticks(2.5)
	_check("[order] m2.cargo_ordered through the console; the crate is out at the landing zone", CS.is_objective_done("m2.cargo_ordered")
		and CS.has_flag("cargo_delivered") and CS.has_flag("cargo_at_landing_zone") and CS.current_objective() == "m2.cargo_retrieved",
		CS.current_objective())
	var crates: Array = _crates()
	var parcel: RigidBody3D = crates[0] if crates.size() == 1 else null
	_check("[zone] one crate, set down at the landing zone, as heavy as the order", parcel != null
		and parcel.global_position.distance_to(director.crate_point()) < 1.0 and is_equal_approx(parcel.mass, order[2]),
		"%s, %s %.1f kg" % [crates, order[0], order[2]])
	_check("[zone] the cargo lander stands there; the zone is in group landing_zone", zone.has_node("CargoLander")
		and zone.is_in_group(&"landing_zone"))
	var pad_xz := Vector2(workshop.pad.global_position.x, workshop.pad.global_position.z)
	var zone_m: float = Vector2(zone.global_position.x, zone.global_position.z).distance_to(pad_xz)
	_check("[zone] a few hundred metres from the pad", zone_m > 200.0 and zone_m < 400.0, "%.0f m" % zone_m)
	_check("[zone] nothing in the bay yet: no crate, no module, no grip wheels on the rack", workshop.cargo_crate == null
		and _modules(level).is_empty() and _count("wheel_high_grip") == 0)
	await _ticks(0.3)
	_check("[guidance] fetch: the console first", guidance.index == 0 and guidance.step_text().ends_with("Open the mission console"),
		guidance.step_text())
	console.select_section(console.Section.KITE)
	var kite_tab: String = console.get_node("%Description").text
	_check("[console] the Kite tab gives the trip and Kite's range", kite_tab.contains("Crate at the landing zone: round trip ~")
		and kite_tab.contains("Kite's range ~"), kite_tab)

	# 2. Fetch, stuck, recovered: the crate stays where Kite stopped
	console._on_control_kite_pressed()
	await _ticks(0.5)
	_check("[guidance] driving: the landing zone waypoint", GS.state == GS.State.IN_GAME_ROBOT
		and guidance.target == zone.get_node("CargoLander") and guidance.is_waypoint(), str(guidance.target))
	_check("[fetch] stopped beside the crate, E loads it", await _fetch(parcel), str(rover.get_node("CargoSocket").part))
	await _ticks(0.3)
	_check("[guidance] loaded: bring it home", guidance.target == workshop.get_node("Parts/ws_pad_01") and guidance.is_waypoint(),
		str(guidance.target))
	var stopped_at: Vector3 = rover.global_position
	await _ticks(director.STILL_FOR + 0.5)
	_check("[recovery] stuck: the console offers the recovery", director.request_recovery())
	await _ticks(director.RECOVERY_DELAY + 1.0)
	var left: Vector3 = parcel.global_position - stopped_at
	left.y = 0.0
	_check("[recovery] Kite on the pad, the crate left where Kite stopped, still to fetch", workshop.pad.is_in_zone(rover)
		and rover.get_node("CargoSocket").part == null and left.length() < 1.5 and director.left_parts.has_parts()
		and CS.has_flag("cargo_at_landing_zone") and not CS.is_objective_done("m2.cargo_retrieved"), "%.2f m" % left.length())

	# 3. No soft-lock: the round trip with the heaviest crate on G1's 40 Wh light battery
	var socket: Node = rover.battery_socket
	var old_battery: RigidBody3D = socket.unmount()
	old_battery.freeze = true
	old_battery.global_position = Vector3(0.0, 500.0, 0.0)
	var light: Node3D = (load("res://src/robot/socket/battery_light_part.tscn") as PackedScene).instantiate()
	level.add_child(light)
	light.global_position = socket.global_position
	socket.mount(light)
	light.capacity = LIGHT_WH
	light.charge = LIGHT_WH
	var apron: Vector2 = level.get_node("RouteMarkers").start()
	var crate_xz := Vector2(parcel.global_position.x, parcel.global_position.z)
	var toward: Vector2 = (crate_xz - apron).normalized()
	await _place(Vector3(apron.x, 0.0, apron.y), Vector3(toward.x, 0.0, toward.y))
	var charge: float = light.charge
	var short_of: Vector2 = crate_xz - toward * 4.0
	var out_ok: bool = await _drive_to(short_of)
	var out_wh: float = charge - light.charge
	_check("[trip] Kite drives out to the crate", out_ok, "%.0f m, %.1f Wh" % [apron.distance_to(short_of), out_wh])
	_check("[fetch] the crate fetched again after the recovery", await _fetch(parcel))
	charge = light.charge
	var from := Vector2(rover.global_position.x, rover.global_position.z)
	var home_ok: bool = await _drive_to(apron)
	var back_wh: float = charge - light.charge
	var back_m: float = from.distance_to(apron)
	var pad_wh: float = 2.0 * apron.distance_to(pad_xz) * back_wh / maxf(back_m, 1.0)
	var total: float = out_wh + back_wh + pad_wh
	_check("[trip] home with the crate; the round trip + 30%% fits %d Wh" % LIGHT_WH, home_ok
		and rover.get_node("CargoSocket").part == parcel and total * FETCH_MARGIN <= LIGHT_WH,
		"%.1f kg crate, crate %.0f m from the pad: %.1f Wh out + %.1f Wh back + %.1f Wh pad legs = %.1f Wh, x%.1f = %.1f Wh" % [
			order[2], crate_xz.distance_to(pad_xz), out_wh, back_wh, pad_wh, total, FETCH_MARGIN, total * FETCH_MARGIN])

	# 4. Home: in the bay the crate is unpacked
	var bay: Transform3D = workshop.get_dock_transform()
	bay.origin += Vector3.UP * 0.3
	rover.global_transform = bay
	rover.linear_velocity = Vector3.ZERO
	await _ticks(1.0)
	_check("[home] Kite in the bay: m2.cargo_retrieved, flag cleared, crate unpacked", CS.is_objective_done("m2.cargo_retrieved")
		and not CS.has_flag("cargo_at_landing_zone") and _crates().is_empty() and CS.current_objective() == "m2.module_loaded",
		CS.current_objective())
	_check("[home] the ordered parts are on the rack and bench", _count("wheel_high_grip") == 4 and _count("thermal_cover") == 1
		and _count("sample_scoop") == 1 and _count("sample_container") == 1,
		str([_count("wheel_high_grip"), _count("thermal_cover"), _count("sample_scoop"), _count("sample_container")]))
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.5)
	var crate: Node3D = workshop.cargo_crate
	var modules: Array = _modules(level)
	_check("[crate] open in the bay, and the module is in it and nowhere else", crate != null and crate.visible and crate.is_open
		and modules.size() == 1 and crate.is_ancestor_of(modules[0]) and _modules(workshop.rack_stock).is_empty()
		and _modules(rover).is_empty() and _modules(iris).is_empty(), str(modules))
	var local: Vector3 = crate.to_local(modules[0].global_position) if modules.size() == 1 else Vector3.INF
	_check("[crate] the module lies inside it", absf(local.x) < crate.SIZE.x / 2.0 and absf(local.z) < crate.SIZE.z / 2.0
		and local.y > 0.0 and local.y < crate.SIZE.y, str(local))
	var front: Vector3 = crate.global_basis.z
	var door: Vector3 = workshop.to_global(Vector3(2.1, 0.0, 2.0)) - crate.global_position
	door.y = 0.0
	_check("[crate] its label faces the personnel door, beside the pad", front.dot(door.normalized()) > 0.3
		and absf(crate.global_position.distance_to(workshop.pad.global_position)) < 2.5,
		"%.2f, %.1f m from the pad" % [front.dot(door.normalized()), crate.global_position.distance_to(workshop.pad.global_position)])

	# 5. Guidance and the module's pickup
	var player: Node3D = GS.player
	var module: RigidBody3D = modules[0]
	await _ticks(0.3)
	_check("[guidance] first the crate", guidance.index == 0 and guidance.target == crate, str(guidance.target))
	player.global_position = crate.global_position + crate.global_basis.z * 1.0 + Vector3.UP * 0.1
	await _ticks(0.3)
	_check("[guidance] near it: the module itself", guidance.index == 1 and guidance.target == module, str(guidance.target))
	player.holder.pickup(module)
	await _ticks(0.3)
	var cargo_socket: Node3D = rover.get_node("CargoSocket")
	_check("[guidance] holding it: the cargo socket", guidance.index == 2 and guidance.target == cargo_socket.get_node("PartCapture"),
		str(guidance.target))
	player.holder.release()
	module.global_position = cargo_socket.global_position + Vector3.UP * 0.05
	module.linear_velocity = Vector3.ZERO
	await _ticks(1.5)
	_check("[load] released over the cargo socket: mounted, m2.module_loaded", cargo_socket.part == module
		and CS.is_objective_done("m2.module_loaded") and CS.current_objective() == "m2.module_installed",
		"%s, %s" % [cargo_socket.part, CS.current_objective()])

	# 6. Install
	_check("[guidance] install: the console first", guidance.index == 0 and guidance.step_text().ends_with("Open the mission console"), guidance.step_text())
	console._on_control_kite_pressed()
	await _ticks(0.5)
	var cradle: Node3D = iris.get_node("ModuleCradle")
	_check("[guidance] driving: the IRIS module cradle", GS.state == GS.State.IN_GAME_ROBOT and guidance.target == cradle
		and guidance.is_waypoint(), str(guidance.target))
	var facing: Vector3 = iris.global_basis.x
	await _place(cradle.park_marker.global_position + facing * -20.0, facing)
	_check("[guidance] far from the bay the step shows its own text", guidance.target_hint() == ""
		and guidance.step_text() == guidance.current_step()["text"], guidance.step_text())
	await _place(cradle.park_marker.global_position + facing * -4.0, facing)
	_check("[guidance] near the bay the cradle's hint is the step line", guidance.step_text().contains("closer")
		and guidance.step_text() == cradle.get_hint(rover), guidance.step_text())
	await _place(cradle.park_marker.global_position, facing)
	_check("[guidance] parked: In position", guidance.step_text().begins_with("In position"), guidance.step_text())
	Input.action_press(&"interact_use")
	await _ticks(0.1)
	Input.action_release(&"interact_use")
	await _ticks(0.5)
	_check("[install] E at the bay: m2.module_installed and m2.iris_activated", CS.is_objective_done("m2.module_installed")
		and CS.is_objective_done("m2.iris_activated") and CS.has_flag("iris_online") and iris.is_online)
	_check("[install] the module is seated in IRIS's bay, once", cradle.occupant == module and _modules(level).size() == 1
		and _modules(workshop).is_empty())

	# 6b. The near sample: S-1 from the bench on the cargo mount, E at the site
	var site: Node3D = get_first_node_in_group(&"near_sample_site")
	await _ticks(0.3)
	_check("[sample] next: the near sample, a waypoint to its site", CS.current_objective() == "m2.near_sample_collected"
		and guidance.target != null and (guidance.target == site or guidance.target == site.highlight_node)
		and guidance.is_waypoint(), "%s, %s" % [CS.current_objective(), guidance.target])
	var s1: RigidBody3D = null
	for part in workshop.bench_stock.get_children():
		if part.has_method("get_catalog_id") and part.get_catalog_id() == "sample_container":
			s1 = part
	_check("[sample] S-1 is on the bench", s1 != null)
	if s1:
		s1.get_parent().remove_child(s1)
		level.add_child(s1)
		s1.global_position = cargo_socket.global_position
		cargo_socket.mount(s1)
	var park: Vector3 = site.find_child("park_sample", true, false).global_position
	await _place(park, -site.global_basis.z)
	rover.linear_velocity = Vector3.ZERO
	await _ticks(0.2)
	_check("[sample] parked with S-1: In position", guidance.step_text().begins_with("In position"), guidance.step_text())
	Input.action_press(&"interact_use")
	await _ticks(0.1)
	Input.action_release(&"interact_use")
	await _ticks(0.5)
	_check("[sample] E at the site: m2.near_sample_collected, then the dock", CS.is_objective_done("m2.near_sample_collected")
		and CS.current_objective() == "m2.kite_docked", CS.current_objective())

	# 6c. Back to the pad and the downlink
	await _place(workshop.get_dock_transform().origin - workshop.global_basis.z * 2.0, -workshop.global_basis.z)
	var dock: Transform3D = workshop.get_dock_transform()
	dock.origin += Vector3.UP * 0.3
	rover.global_transform = dock
	rover.linear_velocity = Vector3.ZERO
	await _ticks(2.0)
	_check("[dock] back on the pad: m2.kite_docked", CS.is_objective_done("m2.kite_docked"), CS.current_objective())
	var docked_at: float = float(CS.mission_stats("m2").get("dock_battery", -1.0))
	_check("[dock] the charge on docking is recorded for Mira's request", docked_at > 0.0 and docked_at <= 1.0, str(docked_at))
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.3)
	console.select_section(console.Section.DOWNLINK)
	var action: Button = console.get_node("%Action")
	_check("[downlink] Receive telemetry is enabled", action.visible and not action.disabled, action.text)
	console._on_action_pressed()
	await _ticks(console.DOWNLINK_TIME + 0.5)
	_check("[downlink] m2.telemetry_received and m2 complete, no debug command used", CS.is_objective_done("m2.telemetry_received")
		and CS.is_mission_completed("m2"), CS.current_objective())

	# 7. Save and load
	await _ticks(0.5)
	_check("[save] the slot was written", SI.save_current(rover) == OK)
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)
	CS.reset()
	_check("[load] load_slot starts loading", SI.load_slot("slot_1"))
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("[load] the Moon level comes up", false)
		_finish()
		return
	_grab_level()
	await _ticks(3.0)
	_check("[load] m2 is still complete", CS.is_mission_completed("m2") and CS.is_objective_done("m2.module_installed"))
	_check("[load] no radio module in the workshop (rack or crate)", _modules(workshop).is_empty(), str(_modules(workshop)))
	var cradle_after: Node3D = iris.get_node("ModuleCradle")
	_check("[load] one radio module in the level: IRIS's bay", _modules(level).size() == 1 and cradle_after.is_installed(),
		str(_modules(level)))
	_finish()


func _finish() -> void:
	_clear_dir()
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
