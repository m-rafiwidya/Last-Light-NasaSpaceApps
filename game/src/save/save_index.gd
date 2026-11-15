class_name SaveIndex

extends RefCounted

## The campaign's save slots: one JSON file per slot, user://saves/<slot_id>.json (format in
## game/README.md, "Saves"). Tests (a script run) use user://saves_test instead.

const SAVE_DIR: String = "user://saves"
const TEST_SAVE_DIR: String = "user://saves_test"
const SAVE_SUFFIX: String = ".json"
const SAVE_VERSION: int = 1
const SLOT_IDS: PackedStringArray = ["slot_1", "slot_2", "slot_3"]
const MISSIONS_PATH: String = "res://res/story/missions.json"
## One 16:9 image per mission, named by the mission's legacy_id in missions.json
const MISSION_IMAGE_DIR: String = "res://res/ui/missions"
const CAMPAIGN_LEVEL: String = "moon_level"

## The slot the running campaign saves to; empty = nothing is saved
static var current_slot: String = ""
## Kite's saved parts, applied by the MissionDirector once the Moon level is up
static var pending_kite: Dictionary = {}

static var _legacy_ids: Dictionary = {}


static func save_dir() -> String:
	var args: PackedStringArray = OS.get_cmdline_args()
	return TEST_SAVE_DIR if args.has("-s") or args.has("--script") else SAVE_DIR


static func slot_path(slot_id: String) -> String:
	return save_dir().path_join(slot_id + SAVE_SUFFIX)


static func slot_number(slot_id: String) -> int:
	return SLOT_IDS.find(slot_id) + 1


## Every slot in order, empty and unreadable ones included
static func list_slots() -> Array[SaveSlotInfo]:
	var slots: Array[SaveSlotInfo] = []
	for id in SLOT_IDS:
		slots.append(read_slot(id))
	return slots


## The readable saves, newest first
static func list_saves() -> Array[SaveSlotInfo]:
	var saves: Array[SaveSlotInfo] = []
	for info in list_slots():
		if info.is_readable():
			saves.append(info)
	saves.sort_custom(func(a: SaveSlotInfo, b: SaveSlotInfo) -> bool:
		return a.saved_at > b.saved_at if a.saved_at != b.saved_at else a.slot_id < b.slot_id)
	return saves


static func read_slot(slot_id: String) -> SaveSlotInfo:
	if not FileAccess.file_exists(slot_path(slot_id)):
		return SaveSlotInfo.empty(slot_id)
	var data: Variant = _read_save(slot_id)
	var info: SaveSlotInfo = SaveSlotInfo.from_dict(slot_id, data.get("meta")) if data is Dictionary else null
	if info == null:
		push_warning("SaveIndex: unreadable save %s" % slot_path(slot_id))
		return SaveSlotInfo.unreadable(slot_id)
	return info


## The parsed file when it is this version's format, else null
static func _read_save(slot_id: String) -> Variant:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(slot_path(slot_id))) != OK:
		return null
	var data: Variant = json.data
	if not (data is Dictionary and (data.get("version") is int or data.get("version") is float)
			and int(data["version"]) == SAVE_VERSION and data.get("campaign") is Dictionary
			and data.get("meta") is Dictionary):
		return null
	return data


## Writes the running campaign and `rover`'s parts to the current slot
static func save_current(rover: Robot) -> Error:
	if current_slot.is_empty() or CampaignState.current_mission().is_empty():
		return ERR_UNCONFIGURED
	var mission: String = CampaignState.current_mission()
	var info := SaveSlotInfo.new()
	info.slot_id = current_slot
	info.mission_id = mission
	info.mission_title = CampaignState.mission_title(mission)
	info.saved_at = int(Time.get_unix_time_from_system())
	info.play_time_sec = int(CampaignState.play_time_sec)
	info.story_progress = CampaignState.story_progress()
	info.current_objective = CampaignState.objective_title(CampaignState.current_objective())
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"meta": info.to_dict(),
		"campaign": CampaignState.save_state(),
		"kite": KiteSave.capture(rover) if rover else pending_kite,
	}
	return write_save(current_slot, data)


static func write_save(slot_id: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(save_dir())
	var temp: String = slot_path(slot_id) + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return DirAccess.rename_absolute(temp, slot_path(slot_id))


## Restores the slot's campaign, then loads the Moon level (Kite's parts follow there). Tyre tracks
## are not saved: every load starts the Moon with bare ground.
## False, changing nothing, when the file can't be read.
static func load_slot(slot_id: String) -> bool:
	var data: Variant = _read_save(slot_id)
	if data == null or not CampaignState.load_state(data["campaign"]):
		push_warning("SaveIndex: cannot load %s" % slot_path(slot_id))
		return false
	if CampaignState.current_mission().is_empty():
		CampaignState.start_mission("m1")
	current_slot = slot_id
	TrackLog.clear_all()
	pending_kite = data["kite"] if data.get("kite") is Dictionary else {}
	SceneLoader.load_scene(CAMPAIGN_LEVEL)
	return true


## Clears `slot_id` (or the first empty slot, else the oldest) and starts m1 in it
static func start_new_campaign(slot_id: String = "") -> void:
	var slot: String = slot_id if slot_id else new_campaign_slot()
	delete_slot(slot)
	current_slot = slot
	pending_kite = {}
	TrackLog.clear_all()
	CampaignState.reset()
	CampaignState.start_mission("m1")
	SceneLoader.load_scene(CAMPAIGN_LEVEL)


## The first empty slot; when all are used, an unreadable one, else the oldest save
static func new_campaign_slot() -> String:
	var oldest: SaveSlotInfo = null
	for info in list_slots():
		if info.is_empty():
			return info.slot_id
		if oldest == null or info.saved_at < oldest.saved_at:
			oldest = info
	return oldest.slot_id


static func delete_slot(slot_id: String) -> Error:
	if slot_id == current_slot:
		current_slot = ""
	var path: String = slot_path(slot_id)
	return DirAccess.remove_absolute(path) if FileAccess.file_exists(path) else OK


static func mission_title(mission_id: String) -> String:
	return CampaignState.mission_title(mission_id)


## The mission's 16:9 image, or null if it has none
static func mission_image(mission_id: String) -> Texture2D:
	if _legacy_ids.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MISSIONS_PATH))
		if data is Dictionary and data.get("missions") is Array:
			for mission in data["missions"]:
				if mission is Dictionary and mission.get("id") is String and mission.get("legacy_id") is String:
					_legacy_ids[mission["id"]] = mission["legacy_id"]
	var path: String = MISSION_IMAGE_DIR.path_join(str(_legacy_ids.get(mission_id, mission_id)) + ".png")
	return load(path) if ResourceLoader.exists(path) else null


## `fakesaves`: sample saves in every slot (marked "fake"), dated in local time. Returns how many
## were written.
static func write_fake_saves() -> int:
	# [local date and time, mission, objectives done, minutes played]
	var samples: Array = [
		["2026-10-12T22:41:00", "m2", ["m1.workshop_entered", "m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked",
			"m1.inspection_sent", "m2.cargo_ordered", "m2.module_loaded"], 16],
		["2026-10-12T22:27:00", "m1", ["m1.workshop_entered", "m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked"], 7],
		["2026-10-11T21:05:00", "m1", ["m1.workshop_entered", "m1.kite_prepared"], 3],
	]
	var bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var written: int = 0
	for i in samples.size():
		var s: Array = samples[i]
		var done: Array = s[2]
		var next: String = ""
		for objective in CampaignState.mission_objectives(s[1]):
			if not done.has(objective):
				next = objective
				break
		var info := SaveSlotInfo.new()
		info.mission_id = s[1]
		info.mission_title = CampaignState.mission_title(s[1])
		info.saved_at = Time.get_unix_time_from_datetime_string(s[0]) - bias_sec
		info.story_progress = CampaignState.story_progress_of(done)
		info.play_time_sec = s[3] * 60
		info.current_objective = CampaignState.objective_title(next)
		var campaign: Dictionary = {"current": s[1], "objectives": done,
			"missions_done": ["m1"] if s[1] == "m2" else [], "flags": [], "items": {}, "play_time_sec": s[3] * 60}
		var data: Dictionary = {"version": SAVE_VERSION, "fake": true, "meta": info.to_dict(),
			"campaign": campaign, "kite": {}}
		if write_save(SLOT_IDS[i], data) == OK:
			written += 1
	return written


## `clearsaves`: removes the fake saves only. Returns how many were removed.
static func clear_fake_saves() -> int:
	var removed: int = 0
	for id in SLOT_IDS:
		var data: Variant = _read_save(id) if FileAccess.file_exists(slot_path(id)) else null
		if data is Dictionary and data.get("fake") == true and delete_slot(id) == OK:
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
