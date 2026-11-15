class_name MissionReport

## The Downlink report of a mission from its stats (CampaignState.mission_stats): five sections,
## each with one "why" line, the crew request slot and a comparison with the last campaign.
## Sections are {"title", "why", "body"} for MissionConsole.report_text.

const ROUTES: Dictionary = {"short": "Short route through Head crater", "long": "Long route round Head"}
const CAUSES: Dictionary = {"battery": "battery ran flat", "cold": "electronics got too cold", "stuck": "Kite was stuck"}
const COUNTS: Array[String] = ["No", "One", "Two", "Three", "Four", "Five"]
# Item G wires the real request; until then the slot shows this placeholder
const CREW_REQUEST_PLACEHOLDER: String = "Request from Hana: (crew request, item G) met / missed"


static func sections(mission: String) -> Array:
	var stats := CampaignState.mission_stats(mission)
	var result: Array = [
		{"title": "Objectives", "why": _objectives_why(mission, stats)},
		{"title": "Science", "why": _science_why(stats), "body": CampaignState.mission_report(mission)},
		{"title": "Rover", "why": _rover_why(mission, stats), "body": _payload(stats)},
		{"title": "Resources", "why": _resources_why(mission, stats), "body": _battery_line(stats)},
		{"title": "Assistance", "why": _assistance_why(stats), "body": "Stuck hints shown: %d." % int(stats.get("stuck_hints", 0))},
		{"title": "Crew request", "why": CREW_REQUEST_PLACEHOLDER},
	]
	var line := comparison(stats.get("previous", {}))
	if line:
		result.append({"body": line})
	return result


static func battery_wh(stats: Dictionary) -> float:
	return float(stats.get("drive_wh", 0.0)) + float(stats.get("electronics_wh", 0.0)) + float(stats.get("heater_wh", 0.0))


static func battery_percent(stats: Dictionary) -> int:
	var capacity: float = float(stats.get("capacity_wh", 0.0))
	return roundi(battery_wh(stats) / capacity * 100.0) if capacity > 0.0 else 0


static func route_of(mission: String, stats: Dictionary) -> String:
	return stats.get("route", "") if mission == MissionDirector.COLD_MISSION else ""


## "Last campaign: long route, 51% battery, no recoveries", or "" with no earlier record
static func comparison(previous: Variant) -> String:
	if not (previous is Dictionary) or previous.is_empty():
		return ""
	var parts: PackedStringArray = []
	if previous.get("route", "") in ROUTES:
		parts.append("%s route" % previous["route"])
	parts.append("%d m" % roundi(float(previous.get("distance_m", 0.0))))
	parts.append("%d%% battery" % battery_percent(previous))
	var count: int = previous.get("recoveries", []).size()
	parts.append("no recoveries" if count == 0 else "1 recovery" if count == 1 else "%d recoveries" % count)
	return "Last campaign: %s" % ", ".join(parts)


static func _objectives_why(mission: String, stats: Dictionary) -> String:
	var line := "All %d objectives met" % CampaignState.mission_objectives(mission).size()
	var done: Array = stats.get("optional_done", [])
	var total: int = done.size() + stats.get("optional_skipped", []).size()
	if total > 0:
		line += ", %d of %d optional done" % [done.size(), total]
	return line + "."


static func _science_why(stats: Dictionary) -> String:
	var done: Array = stats.get("optional_done", [])
	var skipped: Array = stats.get("optional_skipped", [])
	if done:
		return "Extra science: %s." % ", ".join(done.map(CampaignState.objective_title))
	if skipped:
		return "Skipped: %s, so no extra science this time." % ", ".join(skipped.map(CampaignState.objective_title))
	return "Downlink sent %d min into the mission." % roundi(float(stats.get("minutes", 0.0)))


static func _rover_why(mission: String, stats: Dictionary) -> String:
	var route := route_of(mission, stats)
	var line := "drove %d m, steepest slope %d°" % [roundi(float(stats.get("distance_m", 0.0))),
		roundi(float(stats.get("max_slope_deg", 0.0)))]
	return "%s: %s." % [ROUTES[route], line] if route else line[0].to_upper() + line.substr(1) + "."


static func _payload(stats: Dictionary) -> String:
	var kg: float = float(stats.get("max_payload_kg", 0.0))
	return "Heaviest payload %.1f kg." % kg if kg > 0.0 else "No payload carried."


static func _resources_why(mission: String, stats: Dictionary) -> String:
	var route := route_of(mission, stats)
	var prefix: String = ROUTES[route] + ": " if route else ""
	var heater: float = float(stats.get("heater_s", 0.0))
	var cold: float = float(stats.get("cold_s", 0.0))
	if heater > 0.0:
		return "%sheater ran %d s in cold shade (%.1f Wh)." % [prefix, roundi(heater), float(stats.get("heater_wh", 0.0))]
	if cold > 0.0:
		return "%s%d s in cold shade with no heater running." % [prefix, roundi(cold)]
	return "%sno cold shade, so no heater power was needed." % prefix if prefix else "No cold shade, so no heater power was needed."


static func _battery_line(stats: Dictionary) -> String:
	return "Battery used %.1f Wh (%d%%): drive %.1f, electronics %.1f, heater %.1f Wh. Lowest charge %d%%." % [
		battery_wh(stats), battery_percent(stats), float(stats.get("drive_wh", 0.0)), float(stats.get("electronics_wh", 0.0)),
		float(stats.get("heater_wh", 0.0)), roundi(float(stats.get("min_battery", 1.0)) * 100.0)]


static func _assistance_why(stats: Dictionary) -> String:
	var recoveries: Array = stats.get("recoveries", [])
	if recoveries.is_empty():
		return "No emergency recoveries: Kite came home on its own."
	var first: Dictionary = recoveries[0]
	var count: String = COUNTS[recoveries.size()] if recoveries.size() < COUNTS.size() else str(recoveries.size())
	return "%s emergency recover%s: %s %d m from the pad." % [count, "y" if recoveries.size() == 1 else "ies",
		CAUSES.get(first.get("cause", ""), "recovered"), roundi(float(first.get("distance_m", 0.0)))]
