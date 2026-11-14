class_name SaveIndex

extends RefCounted

## Read-only index of the save slots for the PLAY popup. It reads only the small metadata files
## user://saves/<slot_id>.meta.json (format in game/README.md, "Save slot metadata"); the
## campaign state writes them next to its own save data. There is no campaign state yet, so
## today the list is empty unless the `fakesaves` console command wrote sample files.

const SAVE_DIR: String = "user://saves"
const META_SUFFIX: String = ".meta.json"
const META_FORMAT: int = 1
const MISSIONS_PATH: String = "res://docs/examples/MISSIONS.json"
## Placeholder images, one per mission id; drop real ones in with the same names
const MISSION_IMAGE_DIR: String = "res://res/ui/missions"
## The level a new campaign (and, for now, every save) starts in
const CAMPAIGN_LEVEL: String = "moon_level"
## Slot ids of the `fakesaves` samples; `clearsaves` removes only these
const FAKE_PREFIX: String = "fake_"

static var _mission_titles: Dictionary = {}   # mission id -> title, read once


## Every readable slot, newest first. Broken or incomplete files are skipped.
static func list_saves() -> Array[SaveSlotInfo]:
	var saves: Array[SaveSlotInfo] = []
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return saves
	for file_name in DirAccess.get_files_at(SAVE_DIR):
		if not file_name.ends_with(META_SUFFIX):
			continue
		var id: String = file_name.trim_suffix(META_SUFFIX)
		var text: String = FileAccess.get_file_as_string(SAVE_DIR.path_join(file_name))
		var info: SaveSlotInfo = SaveSlotInfo.from_dict(id, JSON.parse_string(text)) if not text.is_empty() else null
		if info == null or id.is_empty():
			push_warning("SaveIndex: ignoring unreadable save metadata %s" % file_name)
			continue
		saves.append(info)
	saves.sort_custom(func(a: SaveSlotInfo, b: SaveSlotInfo) -> bool:
		return a.saved_at > b.saved_at if a.saved_at != b.saved_at else a.slot_id < b.slot_id)
	return saves


## Loads a save slot.
## TODO(campaign state): restore the slot's campaign state here. Until it exists this only
## starts the Moon level, like START NEW CAMPAIGN.
static func load_slot(slot_id: String) -> void:
	var message: String = "TODO(campaign state): SaveIndex.load_slot(\"%s\") is a stub; starting the Moon level" % slot_id
	print(message)
	Debug.add_log(message)
	start_new_campaign()


## Starts a new campaign: the Moon level, through the normal loading path
static func start_new_campaign() -> void:
	if CampaignState.current_mission().is_empty():
		CampaignState.start_mission("m1")
	SceneLoader.load_scene(CAMPAIGN_LEVEL)


static func mission_title(mission_id: String) -> String:
	if _mission_titles.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MISSIONS_PATH))
		if data is Dictionary and data.get("missions") is Array:
			for mission in data["missions"]:
				if mission is Dictionary and mission.has("id") and mission.has("title"):
					_mission_titles[mission["id"]] = mission["title"]
	return _mission_titles.get(mission_id, mission_id.capitalize())


## The mission's 16:9 image, or null if it has none
static func mission_image(mission_id: String) -> Texture2D:
	var path: String = MISSION_IMAGE_DIR.path_join(mission_id + ".png")
	return load(path) if ResourceLoader.exists(path) else null


## Writes a slot's metadata file (used by the fake saves; the campaign state can use it too)
static func write_meta(info: SaveSlotInfo) -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(SAVE_DIR.path_join(info.slot_id + META_SUFFIX), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(info.to_dict(), "\t"))
	return OK


## `fakesaves`: the five sample saves of the UI board (docs/ui/boards/Main.dc.html), dated in
## local time. Returns how many were written.
static func write_fake_saves() -> int:
	# [local date and time, mission, segments of 16 done, minutes played, autosave, objective]
	var samples: Array = [
		["2026-10-12T22:41:00", "first_signal", 6, 16, false, "Activate IRIS"],
		["2026-10-12T22:38:00", "first_signal", 5, 13, true, "Install the module at IRIS"],
		["2026-10-12T22:31:00", "first_signal", 4, 9, true, "Load the replacement module"],
		["2026-10-12T22:27:00", "wake_kite", 3, 7, true, "Downlink the inspection"],
		["2026-10-11T21:05:00", "wake_kite", 1, 3, true, "Photograph IRIS's service panel"],
	]
	var bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var written: int = 0
	for i in samples.size():
		var s: Array = samples[i]
		var info := SaveSlotInfo.new()
		info.slot_id = "%s%02d" % [FAKE_PREFIX, i + 1]
		info.mission_id = s[1]
		info.saved_at = Time.get_unix_time_from_datetime_string(s[0]) - bias_sec
		info.story_progress = s[2] / 16.0
		info.play_time_sec = s[3] * 60
		info.is_autosave = s[4]
		info.current_objective = s[5]
		if write_meta(info) == OK:
			written += 1
	return written


## `clearsaves`: removes the fake saves only. Returns how many were removed.
static func clear_fake_saves() -> int:
	var removed: int = 0
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return removed
	for file_name in DirAccess.get_files_at(SAVE_DIR):
		if file_name.begins_with(FAKE_PREFIX) and file_name.ends_with(META_SUFFIX):
			if DirAccess.remove_absolute(SAVE_DIR.path_join(file_name)) == OK:
				removed += 1
	return removed


## "12/10/2026 22:41" in local time
static func format_date(unix_time: int) -> String:
	var bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time + bias_sec)
	return "%02d/%02d/%04d %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute]


## "16 min played", "1 h 12 min played"
static func format_play_time(seconds: int) -> String:
	var minutes: int = maxi(seconds, 0) / 60
	if minutes < 60:
		return "%d min played" % minutes
	if minutes % 60 == 0:
		return "%d h played" % (minutes / 60)
	return "%d h %d min played" % [minutes / 60, minutes % 60]
