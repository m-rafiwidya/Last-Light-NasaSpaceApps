class_name SaveSlotInfo

extends RefCounted

## What the PLAY popup shows about one save slot: the "meta" section of
## user://saves/<slot_id>.json, read by SaveIndex (format in game/README.md, "Saves").

enum State {EMPTY, OK, UNREADABLE}

var slot_id: String = ""
var state: State = State.OK
## A CampaignState mission id (m1, m2, m3)
var mission_id: String = ""
var mission_title: String = ""
## Unix time (seconds, UTC) of the save
var saved_at: int = 0
var play_time_sec: int = 0
## Story progress, 0..1
var story_progress: float = 0.0
var is_autosave: bool = false
## Title of the objective the save resumes at
var current_objective: String = ""


static func empty(id: String) -> SaveSlotInfo:
	var info := SaveSlotInfo.new()
	info.slot_id = id
	info.state = State.EMPTY
	return info


static func unreadable(id: String) -> SaveSlotInfo:
	var info := SaveSlotInfo.new()
	info.slot_id = id
	info.state = State.UNREADABLE
	return info


## Null when a required field is missing or has the wrong type
static func from_dict(id: String, data: Variant) -> SaveSlotInfo:
	if not data is Dictionary:
		return null
	var d: Dictionary = data
	if not (d.get("mission_id") is String and not (d["mission_id"] as String).is_empty()):
		return null
	if not (d.get("saved_at") is float or d.get("saved_at") is int):
		return null
	var info := SaveSlotInfo.new()
	info.slot_id = id
	info.mission_id = d["mission_id"]
	info.mission_title = d["mission_title"] if d.get("mission_title") is String else ""
	info.saved_at = int(d["saved_at"])
	info.play_time_sec = maxi(int(_number(d.get("play_time_sec"))), 0)
	info.story_progress = clampf(_number(d.get("story_progress")), 0.0, 1.0)
	info.is_autosave = d.get("is_autosave") == true
	info.current_objective = d["current_objective"] if d.get("current_objective") is String else ""
	return info


func to_dict() -> Dictionary:
	return {
		"mission_id": mission_id,
		"mission_title": mission_title,
		"saved_at": saved_at,
		"play_time_sec": play_time_sec,
		"story_progress": story_progress,
		"is_autosave": is_autosave,
		"current_objective": current_objective,
	}


func is_empty() -> bool:
	return state == State.EMPTY


func is_readable() -> bool:
	return state == State.OK


static func _number(value: Variant) -> float:
	return float(value) if value is float or value is int else 0.0
