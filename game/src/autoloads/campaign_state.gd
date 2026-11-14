extends Node

signal mission_started(id: String)
signal mission_completed(id: String)
signal objective_completed(id: String)
signal flag_changed(name: String, value: bool)

const MISSIONS_PATH: String = "res://res/story/missions.json"

var _missions: Dictionary = {}
var _mission_order: PackedStringArray = []
var _objective_mission: Dictionary = {}

var _current: String = ""
var _done_objectives: Dictionary = {}
var _done_missions: Dictionary = {}
var _flags: Dictionary = {}
var _items: Dictionary = {}


func _ready() -> void:
	_load_missions()


func start_mission(id: String) -> void:
	if not _missions.has(id):
		push_warning("CampaignState: unknown mission \"%s\"" % id)
		return
	_current = id
	_done_missions.erase(id)
	mission_started.emit(id)


func current_mission() -> String:
	return _current


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


func reset() -> void:
	_current = ""
	_done_objectives.clear()
	_done_missions.clear()
	_flags.clear()
	_items.clear()


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
		_missions[id] = {"objectives": required, "optional_objectives": optional}
		_mission_order.append(id)
		for objective in required + optional:
			_objective_mission[objective] = id


func _strings(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result
