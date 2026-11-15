extends SceneTree
## Headless test: the sectioned Downlink report (MissionStats, MissionRecords, MissionReport).
##   1. Driving: Kite driven forward under its own power adds distance and drive / electronics Wh
##      matching the battery's drop.
##   2. Route: passing the long route's flags names the long route; a recovery is logged with its cause.
##   3. Save/load: the stats come back from the slot file.
##   4. Report: sending the downlink writes the record; the console shows every section with the
##      stats' numbers, the crew request slot, and no comparison on a first run.
##   5. Comparison: a new campaign's M3 shows "Last campaign: ..." from that record.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_mission_report.gd

const M1_DONE: Array = ["m1.workshop_entered", "m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]
const M2_DONE: Array = ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed", "m2.iris_activated",
	"m2.kite_docked", "m2.telemetry_received"]
const SECTIONS: Array = ["OBJECTIVES", "SCIENCE", "ROVER", "RESOURCES", "ASSISTANCE", "CREW REQUEST"]

var GS: Node
var SL: Node
var CS: Node
var SI: GDScript
var MR: GDScript
var MREC: GDScript
var failures: int = 0
var level: Node3D
var rover: RigidBody3D
var director: Node
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


func _clear() -> void:
	var dir: String = SI.save_dir()
	if DirAccess.dir_exists_absolute(dir):
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))
	MREC.clear()


func _place(at: Vector2) -> void:
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, 500.0, at.y), Vector3(at.x, -500.0, at.y), 1)
	var hit: Dictionary = rover.get_world_3d().direct_space_state.intersect_ray(query)
	rover.global_transform = Transform3D(Basis.IDENTITY, Vector3(at.x, (hit["position"] as Vector3).y + 0.3 if hit else 0.0, at.y))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(0.3)


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	SI = load("res://src/save/save_index.gd")
	MR = load("res://src/ui/mission_console/mission_report.gd")
	MREC = load("res://src/levels/mission_records.gd")
	if not await _wait_state(GS.State.MAIN_MENU):
		_check("main menu comes up", false)
		_finish()
		return
	_clear()
	SI.start_new_campaign("slot_1")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("the Moon level comes up", false)
		_finish()
		return
	SL.load_scene("main_menu")
	await _wait_state(GS.State.MAIN_MENU)
	CS.load_state({"current": "m2", "objectives": M1_DONE + M2_DONE, "missions_done": ["m1", "m2"], "flags": ["iris_online"], "items": {}})
	SL.load_scene("moon_level")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("the Moon level comes up at the end of m2", false)
		_finish()
		return
	await _ticks(1.0)
	var campaign: String = CS.campaign_id
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	director = level.find_child("MissionDirector", true, false)
	console = root.get_node("Main").find_child("MissionConsole", true, false)
	CS.start_mission("m3")
	var stats: Dictionary = CS.mission_stats("m3")
	_check("[start] fresh m3 stats, no earlier record", stats.get("previous", {}).is_empty() and not stats.has("distance_m"))

	# 1. Driving
	console._on_control_kite_pressed()
	await _ticks(0.5)
	_check("[drive] CONTROL KITE: driving", GS.state == GS.State.IN_GAME_ROBOT)
	await _ticks(1.0)
	var charge: float = rover.battery.charge
	var before_wh: float = MR.battery_wh(stats)
	Input.action_press(&"move_forward")
	await _ticks(6.0)
	Input.action_release(&"move_forward")
	await _ticks(2.0)
	var used: float = MR.battery_wh(stats) - before_wh
	var drop: float = charge - rover.battery.charge
	_check("[drive] distance recorded", float(stats.get("distance_m", 0.0)) > 5.0, "%.1f m" % float(stats.get("distance_m", 0.0)))
	_check("[drive] drive and electronics Wh recorded", float(stats.get("drive_wh", 0.0)) > 0.0 and float(stats.get("electronics_wh", 0.0)) > 0.0,
		"%.3f / %.3f" % [float(stats.get("drive_wh", 0.0)), float(stats.get("electronics_wh", 0.0))])
	_check("[drive] Wh recorded match the battery's drop", absf(used - drop) <= maxf(drop * 0.05, 0.01), "%.3f vs %.3f" % [used, drop])
	_check("[drive] lowest charge and slope recorded", float(stats.get("min_battery", 1.0)) < 1.0 and stats.has("max_slope_deg"))

	# 2. Route and a recovery
	var markers: Node = level.get_tree().get_first_node_in_group(&"route_markers")
	var long_route: PackedVector2Array = markers.route("long")
	for i in long_route.size() - 1:
		await _place(long_route[i])
	_check("[route] passing the long flags: long route", stats.get("route", "") == "long", str(stats.get("route_flags", {})))
	var distance_to_pad: float = director.distance_to_pad()
	director._start_recovery()
	await _ticks(director.RECOVERY_DELAY + 1.0)
	var recoveries: Array = stats.get("recoveries", [])
	_check("[recovery] logged with cause and distance", recoveries.size() == 1 and recoveries[0]["cause"] == "battery"
		and absf(float(recoveries[0]["distance_m"]) - distance_to_pad) < 1.0, str(recoveries))

	# 3. Save / load
	SI.save_current(rover)
	var saved: Dictionary = stats.duplicate(true)
	CS.reset()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SI.slot_path("slot_1")))
	_check("[save] the slot loads", data is Dictionary and CS.load_state(data["campaign"]))
	stats = CS.mission_stats("m3")
	_check("[save] stats survive save/load", CS.campaign_id == campaign and stats.get("route") == "long"
		and is_equal_approx(float(stats["distance_m"]), float(saved["distance_m"]))
		and is_equal_approx(float(stats["drive_wh"]), float(saved["drive_wh"])) and stats["recoveries"].size() == 1)

	# 4. The report
	for objective in ["m3.logger_recovered", "m3.kite_docked", "m3.archive_sent"]:
		CS.complete_objective(objective)
	_check("[report] the downlink closes the stats and writes the record", stats.get("sent", false)
		and MREC.read().get("m3", {}).get("campaign") == campaign)
	var frozen: float = float(stats["distance_m"])
	Input.action_press(&"move_forward")
	await _ticks(2.0)
	Input.action_release(&"move_forward")
	_check("[report] no stats after the downlink", float(stats["distance_m"]) == frozen)
	GS.change_state_to(GS.State.MISSION_CONSOLE)
	console.select_section(console.Section.DOWNLINK)
	var text: String = console.get_node("%Description").text
	var missing: Array = SECTIONS.filter(func(title: String) -> bool: return not text.contains(title))
	_check("[report] every section is shown", missing.is_empty(), str(missing))
	var numbers: Array = [
		"Long route round Head: drove %d m" % roundi(float(stats["distance_m"])),
		"steepest slope %d°" % roundi(float(stats["max_slope_deg"])),
		"Battery used %.1f Wh (%d%%)" % [MR.battery_wh(stats), MR.battery_percent(stats)],
		"drive %.1f, electronics %.1f, heater %.1f Wh" % [float(stats["drive_wh"]), float(stats["electronics_wh"]), float(stats.get("heater_wh", 0.0))],
		"ASSISTANCE USED: one emergency recovery, +45 min mission time.",
		"Battery flat %d m from the pad" % roundi(float(recoveries[0]["distance_m"])),
		"after %.1f Wh used this run" % float(recoveries[0]["used_wh"]),
		"Stuck hints shown: %d" % int(stats.get("stuck_hints", 0)),
		CS.mission_report("m3"),
		"Hana: Take both ground temperatures, sun and shade. Missed: Not measured: sun and shade.",
		"Mira: Dock Kite with at least 25% battery. Missed: Kite came home on an emergency recovery.",
	]
	var absent: Array = numbers.filter(func(line: String) -> bool: return not text.contains(line))
	_check("[report] the numbers match the stats", absent.is_empty(), str(absent))
	_check("[report] no comparison on a first run", not text.contains("Last campaign"))

	# 5. Comparison
	CS.reset()
	CS.load_state({"current": "m2", "objectives": M1_DONE + M2_DONE, "missions_done": ["m1", "m2"], "flags": ["iris_online"], "items": {}})
	CS.start_mission("m3")
	var expected: String = "Last campaign: long route, %d m, %d%% battery, 1 recovery" % [roundi(float(saved["distance_m"])),
		MR.battery_percent(saved)]
	var sections: Array = MR.sections("m3")
	_check("[compare] a new campaign compares against the last record", CS.campaign_id != campaign
		and sections[-1].get("body", "") == expected, str(sections[-1]))
	_finish()


func _finish() -> void:
	_clear()
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
