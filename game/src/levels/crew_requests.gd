class_name CrewRequests

## Hana's and Mira's per-mission requests (res/story/crew_requests.json): the radio lines at mission
## start, the Mission tab lines, and met / missed from a mission's stats (CampaignState.mission_stats).

const PATH: String = "res://res/story/crew_requests.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_data = parsed if parsed is Dictionary else {"missions": {}}
	return _data


static func requests(mission: String) -> Array:
	return data().get("missions", {}).get(mission, {}).get("requests", [])


## The mission's radio lines in order: requests then extra lines. Include optional OGG voice paths.
static func radio_lines(mission: String) -> Array:
	var result: Array = []
	for request in requests(mission):
		var request_id: String = str(request["id"])
		var filename: String = "crew_" + request_id.replace(".", "_") + ".ogg"
		result.append({"id": "crew:" + request_id, "speaker": request["speaker"],
			"text": request["radio"], "audio": "res://res/audio/voice/" + filename})
	var extra: Array = data().get("missions", {}).get(mission, {}).get("lines", [])
	for i in extra.size():
		var filename: String = "crew_%s_line%d.ogg" % [mission, i]
		result.append({"id": "crew:%s.line%d" % [mission, i], "speaker": extra[i]["speaker"],
			"text": extra[i]["text"], "audio": "res://res/audio/voice/" + filename})
	return result


static func planning_note(item_id: String) -> String:
	return str(data().get("planning_notes", {}).get(item_id, ""))


## [{"id", "speaker", "summary", "met", "reason"}] for every request of the mission
static func evaluate(mission: String, stats: Dictionary) -> Array:
	var result: Array = []
	for request in requests(mission):
		var outcome := _check(request["condition"], stats)
		var key: String = outcome["key"]
		result.append({"id": request["id"], "speaker": request["speaker"], "summary": request["summary"],
			"met": key == "met", "reason": str(request.get(key, request.get("missed", ""))).format(outcome["values"])})
	return result


## The frozen results once the downlink is sent, a live evaluation before
static func results(mission: String, stats: Dictionary) -> Array:
	return stats["crew_requests"] if stats.get("crew_requests") is Array else evaluate(mission, stats)


static func _check(condition: Dictionary, stats: Dictionary) -> Dictionary:
	var recoveries: Array = stats.get("recoveries", [])
	match str(condition.get("kind", "")):
		"max_slope":
			var slope: float = float(stats.get("max_slope_deg", 0.0))
			var limit: float = float(condition.get("value", 0.0))
			return _outcome(slope <= limit, {"slope": roundi(slope), "limit": roundi(limit)})
		"dock_battery_min":
			var limit: float = float(condition.get("value", 0.0))
			var values := {"limit": roundi(limit * 100.0), "charge": floori(float(stats.get("dock_battery", 0.0)) * 100.0)}
			if not recoveries.is_empty():
				return {"key": "missed_recovery", "values": values}
			if not stats.has("dock_battery"):
				return {"key": "missed_not_docked", "values": values}
			return _outcome(float(stats["dock_battery"]) >= limit, values)
		"objective_done":
			var objective: String = str(condition.get("objective", ""))
			return _outcome(objective in stats.get("optional_done", []) or CampaignState.is_objective_done(objective), {})
		"no_recoveries":
			var count: int = recoveries.size()
			return _outcome(count == 0, {"recoveries": "1 emergency recovery" if count == 1 else "%d emergency recoveries" % count})
		"thermal_pair":
			var values := {}
			var missing: PackedStringArray = []
			for kind in ["sun", "shade"]:
				if stats.has("thermal_" + kind):
					values[kind] = "%+d °C" % roundi(float(stats["thermal_" + kind]))
				else:
					missing.append(kind)
			values["missing"] = " and ".join(missing)
			return _outcome(missing.is_empty(), values)
	return _outcome(false, {})


static func _outcome(met: bool, values: Dictionary) -> Dictionary:
	return {"key": "met" if met else "missed", "values": values}
