extends SceneTree
## The CampaignState autoload (res://res/story/missions.json is its mission data):
##   1. The data loads: m1, m2 and m3 start, and an unknown mission or objective only warns.
##   2. An objective completes (and signals) once; mission_completed fires when every required
##      objective of the current mission is done, once; optional objectives don't count.
##   3. Flags signal only when the value changes.
##   4. Items add and remove; removing more than is held changes nothing.
##   5. reset() clears everything; the console commands drive the same state.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_campaign_state.gd

var CS: Node
var failures: int = 0
var started: Array = []
var completed: Array = []
var objectives: Array = []
var flags: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-62s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _clear_logs() -> void:
	started.clear()
	completed.clear()
	objectives.clear()
	flags.clear()


func _run() -> void:
	CS = root.get_node("CampaignState")
	CS.mission_started.connect(func(id: String) -> void: started.append(id))
	CS.mission_completed.connect(func(id: String) -> void: completed.append(id))
	CS.objective_completed.connect(func(id: String) -> void: objectives.append(id))
	CS.flag_changed.connect(func(flag_name: String, value: bool) -> void: flags.append([flag_name, value]))

	# --- data and unknown ids -----------------------------------------------------------------
	_check("no mission is current at the start", CS.current_mission() == "")
	for id in ["m1", "m2", "m3"]:
		CS.start_mission(id)
		_check("%s starts" % id, CS.current_mission() == id and started.back() == id)
	_clear_logs()
	CS.reset()
	CS.start_mission("m9")
	CS.complete_objective("m9.nothing")
	_check("unknown mission is refused", CS.current_mission() == "" and started.is_empty())
	_check("unknown objective is refused", objectives.is_empty() and not CS.is_objective_done("m9.nothing"))

	# --- objectives and mission completion ----------------------------------------------------
	CS.start_mission("m1")
	CS.complete_objective("m1.iris_scanned")
	CS.complete_objective("m1.iris_scanned")
	_check("an objective completes and signals once", CS.is_objective_done("m1.iris_scanned") and objectives == ["m1.iris_scanned"])
	_check("the mission isn't completed yet", completed.is_empty())
	CS.complete_objective("m1.kite_prepared")
	CS.complete_objective("m1.kite_docked")
	_check("still not completed with one objective left", completed.is_empty())
	CS.complete_objective("m1.inspection_sent")
	_check("mission_completed fires when every objective is done", completed == ["m1"])
	_check("objective_completed came first for the last one", objectives.size() == 4 and objectives.back() == "m1.inspection_sent")
	CS.complete_objective("m1.inspection_sent")
	_check("nothing is emitted again", completed == ["m1"] and objectives.size() == 4)

	_clear_logs()
	CS.start_mission("m2")
	CS.complete_objective("m2.near_sample_collected")
	for id in ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed", "m2.iris_activated", "m2.kite_docked"]:
		CS.complete_objective(id)
	_check("an optional objective doesn't count", completed.is_empty() and CS.is_objective_done("m2.near_sample_collected"))
	_check("m2's last objective is the telemetry downlink", CS.current_objective() == "m2.telemetry_received", CS.current_objective())
	CS.complete_objective("m2.telemetry_received")
	_check("the required objectives complete m2", completed == ["m2"])

	_clear_logs()
	CS.start_mission("m3")
	CS.complete_objective("m1.kite_docked")
	_check("an objective of another mission doesn't complete the current one", completed.is_empty())
	CS.complete_objective("m3.logger_recovered")
	CS.complete_objective("m3.kite_docked")
	_check("m3 isn't completed before the archive is sent", completed.is_empty())
	CS.complete_objective("m3.archive_sent")
	_check("m3 completes with the logger, the dock and the archive", completed == ["m3"])

	_clear_logs()
	CS.reset()
	CS.start_mission("m2")
	for id in ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed", "m2.iris_activated", "m2.kite_docked", "m2.telemetry_received"]:
		CS.complete_objective(id)
	_check("m2 completes without its optional objective", completed == ["m2"] and not CS.is_objective_done("m2.near_sample_collected"))
	CS.complete_objective("m2.near_sample_collected")
	_check("an optional objective after completion emits no second mission_completed", completed == ["m2"])

	# --- flags --------------------------------------------------------------------------------
	_clear_logs()
	CS.set_flag("iris_online")
	CS.set_flag("iris_online")
	CS.set_flag("iris_online", true)
	_check("a flag signals once when set", CS.has_flag("iris_online") and flags == [["iris_online", true]])
	CS.set_flag("sample_near_taken", false)
	_check("clearing a flag that isn't set doesn't signal", flags.size() == 1 and not CS.has_flag("sample_near_taken"))
	CS.set_flag("iris_online", false)
	CS.set_flag("iris_online", false)
	_check("a flag signals once when cleared", not CS.has_flag("iris_online") and flags == [["iris_online", true], ["iris_online", false]])

	# --- items --------------------------------------------------------------------------------
	_check("no item at the start", not CS.has_item("battery"))
	CS.add_item("battery")
	CS.add_item("battery", 2)
	_check("items add up", CS.has_item("battery") and CS._items["battery"] == 3)
	CS.remove_item("battery", 2)
	_check("items remove", CS.has_item("battery") and CS._items["battery"] == 1)
	CS.remove_item("battery", 5)
	_check("removing more than held changes nothing", CS._items["battery"] == 1)
	CS.remove_item("battery")
	_check("the last one removes the item", not CS.has_item("battery"))
	CS.remove_item("battery")
	CS.add_item("battery", 0)
	CS.add_item("battery", -1)
	_check("removing an absent item or adding a bad count is refused", not CS.has_item("battery"))

	# --- reset --------------------------------------------------------------------------------
	CS.set_flag("iris_online")
	CS.add_item("module", 2)
	CS.start_mission("m1")
	CS.complete_objective("m1.kite_prepared")
	CS.reset()
	_check("reset clears the mission, objectives, flags and items", CS.current_mission() == "" and not CS.is_objective_done("m1.kite_prepared")
		and not CS.has_flag("iris_online") and not CS.has_item("module") and CS._done_missions.is_empty())
	_clear_logs()
	CS.start_mission("m1")
	for id in ["m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]:
		CS.complete_objective(id)
	_check("a mission can be completed again after a reset", completed == ["m1"])

	# --- console commands ---------------------------------------------------------------------
	var debug: Node = root.get_node("Debug")
	CS.reset()
	debug.parse_command("startmission m2")
	debug.parse_command("objective m2.module_loaded")
	debug.parse_command("flag iris_online")
	_check("console: startmission, objective and flag", CS.current_mission() == "m2" and CS.is_objective_done("m2.module_loaded") and CS.has_flag("iris_online"))
	debug.parse_command("flag iris_online false")
	_check("console: flag <name> false clears it", not CS.has_flag("iris_online"))
	debug.parse_command("campaign")
	var dump: String = "\n".join(CS.debug_dump())
	_check("console: campaign prints the state", dump.contains("Current mission: m2") and dump.contains("[x] m2.module_loaded") and dump.contains("[ ] m3.archive_sent"))
	CS.reset()

	print("RESULT campaign state ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
