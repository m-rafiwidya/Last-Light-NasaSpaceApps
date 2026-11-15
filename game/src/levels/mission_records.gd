class_name MissionRecords

## Each mission's stats from the last campaign that sent its downlink, kept outside the save slots
## so a new campaign's report can compare against it. Tests (a script run) use their own file.

const PATH: String = "user://mission_records.json"
const TEST_PATH: String = "user://mission_records_test.json"


static func path() -> String:
	var args: PackedStringArray = OS.get_cmdline_args()
	return TEST_PATH if args.has("-s") or args.has("--script") else PATH


static func read() -> Dictionary:
	if not FileAccess.file_exists(path()):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path()))
	return data if data is Dictionary else {}


## The mission's record from another campaign, or {} when there is none
static func previous(mission: String, campaign_id: String) -> Dictionary:
	var record: Variant = read().get(mission)
	if record is Dictionary and record.get("campaign") != campaign_id and record.get("stats") is Dictionary:
		return record["stats"]
	return {}


static func store(mission: String, campaign_id: String, stats: Dictionary) -> void:
	var data := read()
	var kept := stats.duplicate(true)
	kept.erase("previous")
	data[mission] = {"campaign": campaign_id, "stats": kept}
	var file := FileAccess.open(path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


static func clear() -> void:
	if FileAccess.file_exists(path()):
		DirAccess.remove_absolute(path())
