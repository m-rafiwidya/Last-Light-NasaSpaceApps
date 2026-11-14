class_name SaveSlotInfo

extends RefCounted

## What the PLAY popup shows about one save: read from user://saves/<slot_id>.meta.json by
## SaveIndex. Display metadata only, never gameplay state (the campaign state owns that and
## writes this file next to its save data; format in game/README.md, "Save slot metadata").

## The file name without ".meta.json"
var slot_id: String = ""
## A mission id from docs/examples/MISSIONS.json (wake_kite, first_signal, beyond_the_rim)
var mission_id: String = ""
## Unix time (seconds, UTC) of the save
var saved_at: int = 0
var play_time_sec: int = 0
## Story progress, 0..1
var story_progress: float = 0.0
var is_autosave: bool = false
## The objective the save resumes at ("Activate IRIS")
var current_objective: String = ""


## Builds the info from a parsed metadata file; null when a required field is missing or has
## the wrong type
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
	info.saved_at = int(d["saved_at"])
	info.play_time_sec = maxi(int(_number(d.get("play_time_sec"))), 0)
	info.story_progress = clampf(_number(d.get("story_progress")), 0.0, 1.0)
	info.is_autosave = d.get("is_autosave") == true
	var objective: Variant = d.get("current_objective")
	info.current_objective = objective if objective is String else ""
	return info


func to_dict() -> Dictionary:
	return {
		"format": SaveIndex.META_FORMAT,
		"slot_id": slot_id,
		"mission_id": mission_id,
		"saved_at": saved_at,
		"play_time_sec": play_time_sec,
		"story_progress": story_progress,
		"is_autosave": is_autosave,
		"current_objective": current_objective,
	}


static func _number(value: Variant) -> float:
	return float(value) if value is float or value is int else 0.0
