extends Node
## Queues dialogue_triggers.json lines on DialogServer for CampaignState events, each once per campaign.

const TRIGGERS_PATH: String = "res://res/story/dialogue_triggers.json"
const LINES_PATH: String = "res://res/story/lines.json"
const EVENT_KINDS: PackedStringArray = ["objective", "mission_started", "mission_completed"]
const LINE_MIN_DURATION: float = 3.0

var triggers: Array[Dictionary] = []
var lines: Dictionary = {}
var _sequences: Dictionary = {}
var _held: Array[DialogSequence] = []
## While true (a cutscene that owns the dialogue), fired lines wait for release()
var hold: bool = false


func _ready() -> void:
	load_data()
	for problem in problems():
		push_warning("DialogueTriggers: " + problem)
	CampaignState.mission_started.connect(func(id: String) -> void: fire("mission_started:" + id))
	CampaignState.objective_completed.connect(func(id: String) -> void: fire("objective:" + id))
	CampaignState.mission_completed.connect(func(id: String) -> void: fire("mission_completed:" + id))
	SceneLoader.level_loaded.connect(_on_level_loaded)
	CampaignState.campaign_reset.connect(_on_campaign_reset)


func load_data() -> void:
	triggers.clear()
	var trigger_data: Variant = _read_json(TRIGGERS_PATH)
	if trigger_data is Array:
		for trigger in trigger_data:
			if trigger is Dictionary:
				triggers.append({"on": str(trigger.get("on", "")), "line": str(trigger.get("line", ""))})
	var line_data: Variant = _read_json(LINES_PATH)
	lines = line_data if line_data is Dictionary else {}


## Data errors: triggers naming a missing line or an event that is not a real mission or objective
func problems() -> PackedStringArray:
	var result: PackedStringArray = []
	for trigger in triggers:
		if not (lines.get(trigger["line"]) is Dictionary):
			result.append("\"%s\" names a missing line \"%s\"" % [trigger["on"], trigger["line"]])
		if not is_real_event(trigger["on"]):
			result.append("\"%s\" (line \"%s\") is not a real event" % [trigger["on"], trigger["line"]])
	return result


func is_real_event(event: String) -> bool:
	var kind: String = event.get_slice(":", 0)
	var id: String = event.trim_prefix(kind + ":")
	if not event.contains(":") or not kind in EVENT_KINDS:
		return false
	return CampaignState.has_objective(id) if kind == "objective" else CampaignState.has_mission(id)


static func trigger_id(trigger: Dictionary) -> String:
	return "%s|%s" % [trigger["on"], trigger["line"]]


func has_trigger(event: String) -> bool:
	return triggers.any(func(trigger: Dictionary) -> bool: return trigger["on"] == event)


## The event's lines in file order, whether or not they played
func lines_for(event: String) -> Array[Dialog]:
	var result: Array[Dialog] = []
	for trigger in triggers:
		if trigger["on"] == event and lines.get(trigger["line"]) is Dictionary:
			result.append(make_dialog(lines[trigger["line"]]))
	return result


## The sequence last queued for `event`, null if none
func sequence_for(event: String) -> DialogSequence:
	return _sequences.get(event)


## Queues the event's not yet played lines as one sequence; null when there are none
func fire(event: String) -> DialogSequence:
	var dialogs: Array[Dialog] = []
	for trigger in triggers:
		var id := trigger_id(trigger)
		if trigger["on"] != event or CampaignState.is_trigger_played(id) or not (lines.get(trigger["line"]) is Dictionary):
			continue
		CampaignState.mark_trigger_played(id)
		dialogs.append(make_dialog(lines[trigger["line"]]))
	if dialogs.is_empty():
		return null
	var sequence := DialogSequence.new()
	sequence.dialogs = dialogs
	_sequences[event] = sequence
	if _in_level():
		DialogServer.queue_sequence(sequence)
	else:
		_held.append(sequence)
	return sequence


static func make_dialog(entry: Dictionary) -> Dialog:
	var dialog := Dialog.new()
	dialog.speaker = str(entry.get("speaker", ""))
	dialog.subtitle = str(entry.get("text", ""))
	dialog.min_duration = LINE_MIN_DURATION
	var audio: String = str(entry.get("audio", ""))
	if audio and ResourceLoader.exists(audio):
		dialog.audio_stream = load(audio)
	return dialog


func _on_campaign_reset() -> void:
	_sequences.clear()
	_held.clear()
	hold = false
	DialogServer.stop_all()


func _in_level() -> bool:
	return SceneLoader.loading_scene_id.is_empty() and is_instance_valid(GameState.player) and not hold


## Ends a hold: the lines fired meanwhile are queued, in order
func release() -> void:
	hold = false
	_on_level_loaded("")


func _on_level_loaded(_level_name) -> void:
	if not _in_level():
		return
	var held := _held.duplicate()
	_held.clear()
	for sequence in held:
		DialogServer.queue_sequence(sequence)


func _read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
