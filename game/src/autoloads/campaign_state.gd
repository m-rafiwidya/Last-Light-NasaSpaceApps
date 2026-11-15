extends Node

signal mission_started(id: String)
signal mission_completed(id: String)
signal objective_completed(id: String)
signal flag_changed(name: String, value: bool)

const MISSIONS_PATH: String = "res://res/story/missions.json"
const COMPLETE_FLAG: String = "campaign_complete"

var _missions: Dictionary = {}
var _mission_order: PackedStringArray = []
var _objective_mission: Dictionary = {}
var _objective_titles: Dictionary = {}

var _current: String = ""
var _done_objectives: Dictionary = {}
var _done_missions: Dictionary = {}
var _flags: Dictionary = {}
var _items: Dictionary = {}
var _played_triggers: Dictionary = {}
var _shown_tips: Dictionary = {}
var play_time_sec: float = 0.0
var recoveries: int = 0


func _ready() -> void:
	_load_missions()


func _process(delta: float) -> void:
	if GameState.is_in_game() or GameState.state == GameState.State.MISSION_CONSOLE:
		play_time_sec += delta


func start_mission(id: String) -> void:
	if not _missions.has(id):
		push_warning("CampaignState: unknown mission \"%s\"" % id)
		return
	_current = id
	_done_missions.erase(id)
	mission_started.emit(id)


func current_mission() -> String:
	return _current


func mission_title(id: String) -> String:
	return _missions[id]["title"] if _missions.has(id) else id


func mission_objectives(id: String, include_optional: bool = false) -> PackedStringArray:
	if not _missions.has(id):
		return PackedStringArray()
	var list: Array = _missions[id]["objectives"] + (_missions[id]["optional_objectives"] if include_optional else [])
	return PackedStringArray(list)


func objective_title(id: String) -> String:
	return _objective_titles.get(id, id)


func current_objective() -> String:
	for objective in mission_objectives(_current):
		if not _done_objectives.has(objective):
			return objective
	return ""


func is_mission_completed(id: String) -> bool:
	return _done_missions.has(id)


func next_mission(id: String) -> String:
	var index: int = _mission_order.find(id)
	return _mission_order[index + 1] if index >= 0 and index + 1 < _mission_order.size() else ""


func mission_report(id: String) -> String:
	return _missions[id]["report"] if _missions.has(id) else ""


func mission_downlink(id: String) -> Dictionary:
	return _missions[id]["downlink"] if _missions.has(id) else {}


func mission_ending(id: String) -> Dictionary:
	return _missions[id]["ending"] if _missions.has(id) else {}


func last_mission() -> String:
	return _mission_order[-1] if not _mission_order.is_empty() else ""


func mission_order() -> PackedStringArray:
	return _mission_order.duplicate()


func is_campaign_complete() -> bool:
	return has_flag(COMPLETE_FLAG)


func record_recovery() -> void:
	recoveries += 1


func complete_objective(id: String) -> void:
	if not _objective_mission.has(id):
		push_warning("CampaignState: unknown objective \"%s\"" % id)
		return
	if _done_objectives.has(id):
		return
	_done_objectives[id] = true
	objective_completed.emit(id)
	_check_mission_done()


func is_objective_done(id: String) -> bool:
	return _done_objectives.has(id)


@warning_ignore("shadowed_variable_base_class")
func set_flag(name: String, value: bool = true) -> void:
	if has_flag(name) == value:
		return
	if value:
		_flags[name] = true
	else:
		_flags.erase(name)
	flag_changed.emit(name, value)


@warning_ignore("shadowed_variable_base_class")
func has_flag(name: String) -> bool:
	return _flags.has(name)


func add_item(id: String, count: int = 1) -> void:
	if count <= 0:
		push_warning("CampaignState: add_item(\"%s\", %d) needs a positive count" % [id, count])
		return
	_items[id] = int(_items.get(id, 0)) + count


func remove_item(id: String, count: int = 1) -> void:
	var held: int = int(_items.get(id, 0))
	if count <= 0 or count > held:
		push_warning("CampaignState: cannot remove %d of \"%s\", holding %d" % [count, id, held])
		return
	if held == count:
		_items.erase(id)
	else:
		_items[id] = held - count


func has_item(id: String) -> bool:
	return _items.has(id)


## Dialogue triggers (DialogueTriggers.trigger_id) that already played this campaign
func mark_trigger_played(id: String) -> void:
	_played_triggers[id] = true


func is_trigger_played(id: String) -> bool:
	return _played_triggers.has(id)


func mark_tip_shown(id: String) -> void:
	_shown_tips[id] = true


func is_tip_shown(id: String) -> bool:
	return _shown_tips.has(id)


func has_objective(id: String) -> bool:
	return _objective_mission.has(id)


func has_mission(id: String) -> bool:
	return _missions.has(id)


func reset() -> void:
	_current = ""
	_done_objectives.clear()
	_done_missions.clear()
	_flags.clear()
	_items.clear()
	_played_triggers.clear()
	_shown_tips.clear()
	play_time_sec = 0.0
	recoveries = 0


func story_progress() -> float:
	return story_progress_of(_done_objectives.keys())


func story_progress_of(done: Array) -> float:
	var total: int = 0
	var count: int = 0
	for mission_id in _mission_order:
		for objective in _missions[mission_id]["objectives"]:
			total += 1
			if done.has(objective):
				count += 1
	return float(count) / total if total > 0 else 0.0


func save_state() -> Dictionary:
	return {
		"current": _current,
		"objectives": _done_objectives.keys(),
		"missions_done": _done_missions.keys(),
		"flags": _flags.keys(),
		"items": _items.duplicate(),
		"triggers_played": _played_triggers.keys(),
		"tips_shown": _shown_tips.keys(),
		"play_time_sec": play_time_sec,
		"recoveries": recoveries,
	}


## Restores a save_state() dictionary without emitting any signal. Returns false, changing
## nothing, when the data is malformed; unknown missions and objectives are dropped.
func load_state(data: Dictionary) -> bool:
	if not (data.get("current") is String and data.get("objectives") is Array and data.get("missions_done") is Array
			and data.get("flags") is Array and data.get("items") is Dictionary):
		return false
	reset()
	_current = data["current"] if _missions.has(data["current"]) else ""
	for objective in data["objectives"]:
		if _objective_mission.has(str(objective)):
			_done_objectives[str(objective)] = true
	for mission_id in data["missions_done"]:
		if _missions.has(str(mission_id)):
			_done_missions[str(mission_id)] = true
	for flag in data["flags"]:
		_flags[str(flag)] = true
	for item in data["items"]:
		var count: Variant = data["items"][item]
		if (count is int or count is float) and int(count) > 0:
			_items[str(item)] = int(count)
	var played: Variant = data.get("triggers_played")
	if played is Array:
		for trigger in played:
			_played_triggers[str(trigger)] = true
	var tips: Variant = data.get("tips_shown")
	if tips is Array:
		for tip in tips:
			_shown_tips[str(tip)] = true
	var time: Variant = data.get("play_time_sec")
	play_time_sec = maxf(float(time), 0.0) if time is int or time is float else 0.0
	var recovered: Variant = data.get("recoveries")
	recoveries = maxi(int(recovered), 0) if recovered is int or recovered is float else 0
	return true


func debug_dump() -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("Current mission: %s" % (_current if not _current.is_empty() else "(none)"))
	for mission_id in _mission_order:
		var parts: PackedStringArray = []
		for objective in _missions[mission_id]["objectives"] + _missions[mission_id]["optional_objectives"]:
			parts.append("%s %s" % ["[x]" if _done_objectives.has(objective) else "[ ]", objective])
		lines.append("%s%s: %s" % [mission_id, " (completed)" if _done_missions.has(mission_id) else "", ", ".join(parts)])
	lines.append("Flags: %s" % (", ".join(_flags.keys()) if not _flags.is_empty() else "(none)"))
	var item_parts: PackedStringArray = []
	for item in _items:
		item_parts.append("%s x%d" % [item, _items[item]])
	lines.append("Items: %s" % (", ".join(item_parts) if not item_parts.is_empty() else "(none)"))
	return lines


func _check_mission_done() -> void:
	if _current.is_empty() or _done_missions.has(_current):
		return
	for objective in _missions[_current]["objectives"]:
		if not _done_objectives.has(objective):
			return
	_done_missions[_current] = true
	mission_completed.emit(_current)


func _load_missions() -> void:
	_missions.clear()
	_mission_order.clear()
	_objective_mission.clear()
	_objective_titles.clear()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MISSIONS_PATH))
	if not (data is Dictionary and data.get("missions") is Array):
		push_warning("CampaignState: cannot read missions from %s" % MISSIONS_PATH)
		return
	for entry in data["missions"]:
		if not (entry is Dictionary and entry.get("id") is String):
			continue
		var id: String = entry["id"]
		var required: Array = _strings(entry.get("objectives"))
		var optional: Array = _strings(entry.get("optional_objectives"))
		_missions[id] = {"objectives": required, "optional_objectives": optional,
			"title": str(entry.get("title", id)), "report": "\n".join(_strings(entry.get("report"))),
			"downlink": entry.get("downlink") if entry.get("downlink") is Dictionary else {},
			"ending": entry.get("ending") if entry.get("ending") is Dictionary else {}}
		var titles: Variant = entry.get("objective_titles")
		if titles is Dictionary:
			for objective in titles:
				_objective_titles[str(objective)] = str(titles[objective])
		_mission_order.append(id)
		for objective in required + optional:
			_objective_mission[objective] = id


func _strings(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result
