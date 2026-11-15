class_name MissionReport

## The Downlink report of a mission from its stats (CampaignState.mission_stats): five sections,
## each with one "why" line, the crew request slot and a comparison with the last campaign.
## Sections are {"title", "why", "body"} for MissionConsole.report_text.

const ROUTES: Dictionary = {"short": "Short route through Head crater", "long": "Long route round Head"}
const CAUSES: Dictionary = {"battery": "battery ran flat", "cold": "electronics got too cold", "stuck": "Kite was stuck",
	"slip": "Kite slipped on loose ground"}
const COUNTS: Array[String] = ["No", "One", "Two", "Three", "Four", "Five"]


## "Hana: Collect the near-site sample. Met: the near-site sample came home with Kite."
static func crew_lines(mission: String, stats: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	for result in CrewRequests.results(mission, stats):
		lines.append("%s: %s. %s: %s" % [result["speaker"], result["summary"], "Met" if result["met"] else "Missed", result["reason"]])
	return lines


static func sections(mission: String) -> Array:
	var stats := CampaignState.mission_stats(mission)
	var result: Array = [
		{"title": "Objectives", "why": _objectives_why(mission, stats)},
		{"title": "Science", "why": _science_why(stats), "body": _science_body(mission, stats)},
		{"title": "Rover", "why": _rover_why(mission, stats), "body": _payload(stats)},
		{"title": "Resources", "why": _resources_why(mission, stats), "body": _battery_line(stats)},
		{"title": "Assistance", "why": _assistance_why(stats), "body": "Stuck hints shown: %d." % int(stats.get("stuck_hints", 0))},
		{"title": "Crew requests", "why": "\n".join(crew_lines(mission, stats))},
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


## The mission's report text, then the ground temperature line when the thermal turret took readings
static func _science_body(mission: String, stats: Dictionary) -> String:
	var report := CampaignState.mission_report(mission)
	if not (stats.has("thermal_sun") or stats.has("thermal_shade")):
		return report
	return "%s\n%s" % [report, ground_temperature(stats)]


## "Ground temperature: sun +112 °C, shade -150 °C"
static func ground_temperature(stats: Dictionary) -> String:
	var parts: PackedStringArray = []
	for kind in ["sun", "shade"]:
		var key: String = "thermal_" + kind
		parts.append("%s %s" % [kind, "%+d °C" % roundi(float(stats[key])) if stats.has(key) else "not measured"])
	return "Ground temperature: %s" % ", ".join(parts)


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
	var count: String = COUNTS[recoveries.size()] if recoveries.size() < COUNTS.size() else str(recoveries.size())
	var lines: PackedStringArray = ["ASSISTANCE USED: %s emergency recover%s, +%d min mission time." % [count.to_lower(),
		"y" if recoveries.size() == 1 else "ies", roundi(float(stats.get("assistance_min", 0.0)))]]
	for entry in recoveries:
		lines.append(why_line(entry))
	return "\n".join(lines)


## What went wrong and what to change, for one recovery record (MissionDirector._start_recovery)
static func why_line(entry: Dictionary) -> String:
	var metres: int = roundi(float(entry.get("distance_m", 0.0)))
	var leg: String = "on the way back" if entry.get("leg", "") == "back" else "on the way out"
	match entry.get("cause", ""):
		"slip":
			return "Slipped on the %s %s with standard wheels: fit the high-grip wheels or take the long route." % [
				entry.get("zone", "loose ground"), leg]
		"cold":
			return "Cold shutdown in %s's shade %s, %d m from the pad, without the thermal cover and heater: fit both, or take a sunlit route." % [
				entry.get("zone", "the crater"), leg, metres]
		"battery":
			var wh: float = float(entry.get("battery_wh", 0.0))
			var used: float = float(entry.get("used_wh", 0.0))
			var route: String = str(entry.get("route", ""))
			var line := "Battery flat %d m from the pad %s" % [metres, leg]
			if used > 0.0:
				line += ", after %.1f Wh used this run" % used
			if wh > 0.0 and route in ROUTES:
				return "%s: the %d Wh battery can't cover the %s route. Fit the standard battery or carry less." % [
					line, roundi(wh), route]
			return "%s: fit a bigger battery or turn back sooner (watch the return estimate)." % line
		"stuck":
			return "Kite was stuck %d m from the pad %s: F rights it; back out of rocks before calling a recovery." % [metres, leg]
	return "%s %d m from the pad." % [CAUSES.get(entry.get("cause", ""), "Recovered").capitalize(), metres]
