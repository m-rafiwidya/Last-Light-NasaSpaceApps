extends SceneTree
## Crew requests (CrewRequests, res/story/crew_requests.json):
##   1. Data: Hana and Mira each ask once per mission; every condition and objective is real.
##   2. Conditions: each request is met and missed from mission stats.
##   3. Radio: the requests play once at mission start, after its own lines; never again after a load.
##   4. Report: the downlink freezes met / missed into the stats, the report shows them, a save keeps them.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_crew_requests.gd

const KINDS: Array = ["max_slope", "dock_battery_min", "objective_done", "no_recoveries", "thermal_pair"]
const M1_DONE: Array = ["m1.workshop_entered", "m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]
const M2_DONE: Array = ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed", "m2.iris_activated",
	"m2.kite_docked", "m2.telemetry_received"]
const RECOVERY: Array = [{"cause": "battery", "distance_m": 80.0}]

var CS: Node
var DS: Node
var DT: Node
var GS: Node
var CR: GDScript
var MR: GDScript
var CP: GDScript
var MREC: GDScript
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-66s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _result(mission: String, speaker: String, stats: Dictionary) -> Dictionary:
	for result in CR.evaluate(mission, stats):
		if result["speaker"] == speaker:
			return result
	return {}


func _invalid(request: Dictionary) -> bool:
	var condition: Dictionary = request["condition"]
	if not condition.get("kind") in KINDS or str(request.get("radio", "")) == "" or str(request.get("summary", "")) == "":
		return true
	return condition["kind"] == "objective_done" and not CS.has_objective(condition.get("objective", ""))


func _met(mission: String, speaker: String, stats: Dictionary, reason: String) -> void:
	var result := _result(mission, speaker, stats)
	_check("[%s] %s met: %s" % [mission, speaker, reason], result.get("met", false) and result["reason"] == reason, str(result))


func _missed(mission: String, speaker: String, stats: Dictionary, reason: String) -> void:
	var result := _result(mission, speaker, stats)
	_check("[%s] %s missed: %s" % [mission, speaker, reason], not result.is_empty() and not result["met"]
		and result["reason"] == reason, str(result))


func _run() -> void:
	await process_frame
	CS = root.get_node("CampaignState")
	DS = root.get_node("DialogServer")
	DT = root.get_node("DialogueTriggers")
	GS = root.get_node("GameState")
	CR = load("res://src/levels/crew_requests.gd")
	MR = load("res://src/ui/mission_console/mission_report.gd")
	CP = load("res://src/levels/cargo_plan.gd")
	MREC = load("res://src/levels/mission_records.gd")

	# 1. Data
	for mission in CS.mission_order():
		var requests: Array = CR.requests(mission)
		var speakers: Array = requests.map(func(r: Dictionary) -> String: return r["speaker"])
		var bad: Array = requests.filter(_invalid)
		_check("[data] %s: one request each from Hana and Mira, all valid" % mission, speakers == ["Hana", "Mira"] and bad.is_empty(),
			"%s, bad %s" % [speakers, bad])
	_check("[data] the thermal turret isn't ordered (one is on the rack) and has no planning note",
		CR.planning_note("thermal_turret") == "" and CP.item("thermal_turret").is_empty())

	# 2. Conditions
	CS.reset()
	_met("m1", "Hana", {"max_slope_deg": 4.9}, "Steepest slope 5°, within 15°.")
	_missed("m1", "Hana", {"max_slope_deg": 22.0}, "Steepest slope 22°, over the 15° limit.")
	_met("m1", "Mira", {"dock_battery": 0.83}, "Docked with 83% left.")
	_missed("m1", "Mira", {"dock_battery": 0.42}, "Docked with 42%, under 50%.")
	_missed("m1", "Mira", {"dock_battery": 1.0, "recoveries": RECOVERY}, "Kite came home on an emergency recovery.")
	_missed("m1", "Mira", {}, "Kite never docked on its own.")
	_missed("m2", "Hana", {"optional_skipped": ["m2.near_sample_collected"]}, "No near-site sample this time.")
	_met("m2", "Hana", {"optional_done": ["m2.near_sample_collected"]}, "The near-site sample came home with Kite.")
	_met("m2", "Mira", {}, "Kite came home on its own.")
	_missed("m2", "Mira", {"recoveries": RECOVERY + RECOVERY}, "2 emergency recoveries during the mission.")
	_met("m3", "Hana", {"thermal_sun": 61.6, "thermal_shade": -150.0}, "Sun +62 °C, shade -150 °C.")
	_missed("m3", "Hana", {"thermal_sun": 61.6}, "Not measured: shade.")
	_met("m3", "Mira", {"dock_battery": 0.31}, "Docked with 31% left.")
	_missed("m3", "Mira", {"dock_battery": 0.18}, "Docked with 18%, under 25%.")

	# 3. Radio at mission start
	GS.player = load("res://src/player/player.gd").new()
	CS.reset()
	CS.load_state({"current": "m1", "objectives": M1_DONE, "missions_done": ["m1"], "flags": [], "items": {}})
	CS.start_mission("m2")
	var sequence: DialogSequence = DT.sequence_for("mission_started:m2")
	var texts: Array = sequence.dialogs.map(func(d: Dialog) -> String: return d.subtitle) if sequence else []
	var radio: Array = CR.radio_lines("m2").map(func(l: Dictionary) -> String: return l["text"])
	var own: int = DT.lines_for("mission_started:m2").size()
	_check("[radio] m2 start: its own lines, then Hana's, Mira's and the M3 turret line", texts.size() == own + 3
		and texts.slice(own) == radio and radio[2].contains("thermal turret"), str(texts.size()))
	_check("[radio] the speakers are Hana and Mira", sequence != null and sequence.dialogs[own].speaker == "Hana"
		and sequence.dialogs[own + 1].speaker == "Mira")
	DS.stop_all()
	_check("[radio] a mission restart doesn't repeat them", DT.fire("mission_started:m2") == null)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(CS.save_state()))
	CS.reset()
	CS.load_state(saved)
	_check("[radio] nothing replays after a load", not DS.is_playing() and DT.fire("mission_started:m2") == null)

	# 4. Report
	var stats: Dictionary = CS.mission_stats("m2")
	stats["recoveries"] = RECOVERY
	CS.complete_objective("m2.near_sample_collected")
	for objective in M2_DONE:
		CS.complete_objective(objective)
	var frozen: Variant = stats.get("crew_requests")
	_check("[report] the downlink freezes both results", frozen is Array and frozen.size() == 2
		and frozen[0]["met"] and not frozen[1]["met"], str(frozen))
	var crew: Dictionary = MR.sections("m2")[5]
	var expected := "Hana: Collect the near-site sample. Met: The near-site sample came home with Kite.\n" \
		+ "Mira: No emergency recoveries. Missed: 1 emergency recovery during the mission."
	_check("[report] the crew requests section shows met and missed", crew["why"] == expected, crew["why"])
	stats["recoveries"] = []
	_check("[report] the result stays as sent", MR.sections("m2")[5]["why"] == expected)
	saved = JSON.parse_string(JSON.stringify(CS.save_state()))
	CS.reset()
	CS.load_state(saved)
	_check("[save] the results load with the campaign", MR.crew_lines("m2", CS.mission_stats("m2"))
		== PackedStringArray(expected.split("\n")))

	MREC.clear()
	DS.stop_all()
	GS.player.free()
	GS.player = null
	print("RESULT test_crew_requests %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
