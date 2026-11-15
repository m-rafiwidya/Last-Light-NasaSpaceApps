extends SceneTree
## Headless test: the M2 cargo order (CargoPlan, the console's Planning tab) and its M3 effects.
##   1. Plan: masses from the part scenes, the Courier can't fit the grip wheels, the module is
##      required, a late Freighter needs the thermal kit.
##   2. Console: Planning closed before m1 is complete; Confirm disabled over the limit and without
##      the module; the flight can be skipped; delivery records the items once, completes
##      m2.cargo_ordered and fills the rack and bench.
##   3. Save/load keeps the order. 4. Cold zones: Head crater has no shade under a Courier M3's
##      high sun; after a late arrival its west wall is cold, the thermal kit protects, the timer
##      ends in recovery; the forecast names both routes.
##   5. The Freighter completes an order too.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_cargo_planning.gd

var GS: Node
var SL: Node
var CS: Node
var SI: GDScript
var debug: Node
var failures: int = 0
var console: Node
var level: Node
var CargoPlan: GDScript
var MD: GDScript


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


func _action() -> Button:
	return console.get_node("%Action")


func _stock(workshop: Node) -> Dictionary:
	var counts: Dictionary = {}
	for part in workshop.rack_stock.get_children() + workshop.bench_stock.get_children():
		if part.has_method("get_catalog_id") and not part.is_queued_for_deletion():
			counts[part.get_catalog_id()] = int(counts.get(part.get_catalog_id(), 0)) + 1
	return counts


func _order(service: String, items: Array) -> void:
	console.select_service(service)
	for entry in CargoPlan.items():
		console.set_item(entry["id"], items.has(entry["id"]))


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	debug = root.get_node("Debug")
	SI = load("res://src/save/save_index.gd")
	console = root.get_node("Main").find_child("MissionConsole", true, false)
	CargoPlan = load("res://src/levels/cargo_plan.gd")
	MD = load("res://src/levels/mission_director.gd")

	# 1. Plan
	_check("[plan] masses come from the part scenes", is_equal_approx(CargoPlan.item_mass("radio_module"), 12.0)
		and is_equal_approx(CargoPlan.item_mass("grip_wheels"), 20.0) and is_equal_approx(CargoPlan.item_mass("thermal_kit"), 1.5)
		and is_equal_approx(CargoPlan.item_mass("sampling_kit"), 1.4) and is_equal_approx(CargoPlan.item_mass("thermal_turret"), 5.3))
	_check("[plan] the Courier can't fit the grip wheels", CargoPlan.validate("courier", ["radio_module", "grip_wheels"]).begins_with("Over"),
		CargoPlan.validate("courier", ["radio_module", "grip_wheels"]))
	_check("[plan] the Courier fits all the light kit", CargoPlan.validate("courier",
		["radio_module", "thermal_kit", "sampling_kit", "thermal_turret"]) == "")
	_check("[plan] the module is required", CargoPlan.validate("courier", ["thermal_kit"]) != "")
	_check("[plan] Courier: M3 in daylight; Freighter: near nightfall", not CargoPlan.is_late("courier") and CargoPlan.is_late("freighter"))
	_check("[plan] a late Freighter needs the thermal kit", CargoPlan.validate("freighter", ["radio_module", "grip_wheels"]) != ""
		and CargoPlan.validate("freighter", ["radio_module", "grip_wheels", "thermal_kit"]) == "")

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
	level = SL.current_scene
	var workshop: Node = level.get_node("Workshop")
	var director: Node = level.get_node("MissionDirector")
	await _ticks(1.0)

	# 2. Console
	var stock: Dictionary = _stock(workshop)
	_check("[stock] before the order: no grip wheels, module, turret or kits", not stock.has("wheel_high_grip")
		and not stock.has("radio_module") and not stock.has("thermal_cover") and not stock.has("sample_scoop"), str(stock))
	console.select_section(console.Section.PLANNING)
	_check("[console] Planning is closed before m1 is complete", not console.planning_open()
		and console.tab_button(console.Section.PLANNING).disabled and not _action().visible)
	for id in ["m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]:
		CS.complete_objective(id)
	debug.parse_command("startmission m2")
	console.refresh()
	_check("[console] m2 starts with m2.cargo_ordered", CS.current_objective() == "m2.cargo_ordered")
	_check("[console] Planning is open and offers Confirm order", console.planning_open() and _action().visible
		and _action().text.nocasecmp_to("Confirm order") == 0)
	_check("[console] no service chosen: Confirm disabled", _action().disabled)
	_order("courier", ["radio_module", "grip_wheels"])
	_check("[console] Courier with grip wheels: over the limit, Confirm disabled", _action().disabled
		and console.confirm_blocked().begins_with("Over"), console.confirm_blocked())
	console.set_item("radio_module", false)
	_check("[console] the module can't be removed", console.manifest_ids().has("radio_module")
		and console._item_boxes["radio_module"].disabled)
	console._manifest["radio_module"] = false
	console.refresh()
	_check("[console] without the module: Confirm disabled", _action().disabled and console.confirm_blocked() != "")
	_order("courier", ["radio_module", "thermal_kit", "sampling_kit"])
	_check("[console] a valid Courier order enables Confirm", not _action().disabled, console.confirm_blocked())
	console._on_action_pressed()
	_check("[flight] Confirm starts the flight", console.flying() and _action().disabled
		and not CS.is_objective_done("m2.cargo_ordered"))
	console.set_item("thermal_turret", true)
	_check("[flight] the manifest is locked in flight", not console.manifest_ids().has("thermal_turret"))
	await _ticks(0.5)
	console.skip_flight()
	await physics_frame
	_check("[flight] Skip delivers at once", not console.flying() and CS.is_objective_done("m2.cargo_ordered")
		and CS.current_objective() == "m2.module_loaded")
	console.skip_flight()
	var items: Dictionary = CS.save_state()["items"]
	_check("[delivery] items recorded once", items.get("cargo.radio_module") == 1 and items.get("cargo.thermal_kit") == 1
		and items.get("cargo.sampling_kit") == 1 and items.get("cargo.service.courier") == 1
		and not items.has("cargo.grip_wheels") and not items.has("cargo.thermal_turret") and CS.has_flag("cargo_delivered"), str(items))
	_check("[delivery] a second delivery is refused", not CargoPlan.deliver("courier", ["radio_module"]))
	await physics_frame
	stock = _stock(workshop)
	_check("[stock] the order fills the bench; the module goes to the crate, not the rack", stock.get("thermal_cover") == 1
		and stock.get("thermal_heater") == 1 and stock.get("sample_scoop") == 1 and not stock.has("radio_module")
		and not stock.has("wheel_high_grip") and not stock.has("arm_tool_thermal"), str(stock))
	_check("[crate] crate_parts lists the module", CargoPlan.crate_parts() == PackedStringArray(["res://src/robot/socket/radio_module_part.tscn"]))
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SI.slot_path("slot_1")))
	_check("[save] the delivery autosaved", saved is Dictionary and saved["campaign"]["items"].has("cargo.thermal_kit")
		and saved["campaign"]["objectives"].has("m2.cargo_ordered"))

	# 3. Save/load
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)
	CS.reset()
	_check("[load] the slot loads", SI.load_slot("slot_1"))
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("[load] the Moon level comes up", false)
		_finish()
		return
	level = SL.current_scene
	workshop = level.get_node("Workshop")
	director = level.get_node("MissionDirector")
	await _ticks(1.0)
	_check("[load] the order survives", CargoPlan.is_delivered() and CargoPlan.delivered_service() == "courier"
		and CargoPlan.is_ordered("thermal_kit") and not CargoPlan.is_ordered("grip_wheels")
		and CS.is_objective_done("m2.cargo_ordered"))
	stock = _stock(workshop)
	_check("[load] the rack and bench follow the order", stock.get("thermal_cover") == 1 and not stock.has("wheel_high_grip"), str(stock))

	# 4. Cold zones: real shade for M3's sun (Head crater's west wall at dusk)
	var rover: RigidBody3D = director.rover
	var west_wall := Vector3(-76.0, 0.0, -50.0)
	_check("[cold] no cold zone outside M3", director.cold_zone_at(west_wall) == null)
	debug.parse_command("startmission m3")
	_check("[cold] Courier M3 (high sun): no shade in Head", director.cold_zone_at(west_wall) == null)
	console.select_section(console.Section.MISSION)
	var forecast: String = console.get_node("%Description").text
	_check("[forecast] the m3 Mission tab shows the route forecast", forecast.contains("ROUTE FORECAST")
		and not forecast.contains("near nightfall") and forecast.contains("no thermal kit needed"))
	_check("[forecast] it names both routes", forecast.contains("Short route (through Head crater)") and forecast.contains("Long route (north loop round Head)"))
	CS.remove_item("cargo.service.courier")
	CS.add_item("cargo.service.freighter")
	director.apply_mission_sun()
	_check("[cold] Freighter M3 (dusk): Head's west wall is cold", CargoPlan.m3_near_nightfall() and director.cold_zone_at(west_wall) != null)
	console.refresh()
	_check("[forecast] late arrival: the forecast says near nightfall", console.get_node("%Description").text.contains("near nightfall"))
	rover.freeze = true
	rover.global_position = west_wall + Vector3.UP * 20.0
	director._update_cold(1.0)
	_check("[cold] without the kit: a warning", director.cold_time > 0.0 and director.alert.begins_with("COLD"), director.alert)
	director._update_cold(MD.COLD_LIMIT)
	_check("[cold] the timer ends in the emergency recovery", director.recovering and director.alert == MD.COLD_MESSAGE)
	await _ticks(MD.RECOVERY_DELAY + 0.5)
	_check("[cold] Kite is recovered to the pad", not director.recovering and workshop.pad.is_in_zone(rover))
	for socket in rover.find_children("*", "HotswapSocket", true, false):
		if socket.accepted_catalog_id in ["thermal_cover", "thermal_heater"]:
			for part in workshop.bench_stock.get_children():
				if part.has_method("get_catalog_id") and part.get_catalog_id() == socket.accepted_catalog_id:
					socket.mount(part)
					break
	rover.global_position = west_wall + Vector3.UP * 20.0
	director._update_cold(5.0)
	_check("[cold] with cover and heater fitted: no cold", director.thermal_kit_fitted() and director.cold_time == 0.0
		and not director.recovering)
	rover.freeze = false
	director.dock_rover()

	# 5. The Freighter
	var state: Dictionary = CS.save_state()
	CS.load_state({"current": "m2", "objectives": ["m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"],
		"missions_done": ["m1"], "flags": [], "items": {}})
	workshop.account_rack()
	console.select_section(console.Section.PLANNING)
	_order("freighter", ["radio_module", "grip_wheels", "thermal_kit", "sampling_kit", "thermal_turret"])
	_check("[freighter] everything is over its limit", _action().disabled and console.confirm_blocked().begins_with("Over"))
	_order("freighter", ["radio_module", "grip_wheels", "sampling_kit"])
	_check("[freighter] without the thermal kit: Confirm disabled", _action().disabled
		and console.confirm_blocked().contains("nightfall"), console.confirm_blocked())
	_order("freighter", ["radio_module", "grip_wheels", "thermal_kit", "sampling_kit"])
	_check("[freighter] a valid order enables Confirm", not _action().disabled, console.confirm_blocked())
	console._on_action_pressed()
	await _ticks(console.FLIGHT_TIME + 0.5)
	await physics_frame
	_check("[freighter] the full flight delivers", not console.flying() and CS.is_objective_done("m2.cargo_ordered")
		and CargoPlan.delivered_service() == "freighter" and CargoPlan.m3_near_nightfall())
	stock = _stock(workshop)
	_check("[freighter] the grip wheels are on the rack", stock.get("wheel_high_grip") == 4, str(stock))
	CS.load_state(state)
	_finish()


func _finish() -> void:
	_clear_dir()
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
