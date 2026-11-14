class_name CampaignEnding

extends Node

signal finished

const TRIGGERS_PATH: String = "res://res/story/dialogue_triggers.json"
const LINES_PATH: String = "res://res/story/lines.json"
const IRIS_SHOT_TIME: float = 4.0
const LINE_MIN_DURATION: float = 3.0
const DIALOGUE_TIMEOUT_EXTRA: float = 5.0
const CAMERA_DISTANCE: float = 9.0
const CAMERA_HEIGHT: float = 3.0

var director: MissionDirector = null
var playing: bool = false
var _closing_sequence: DialogSequence = null


func _ready() -> void:
	director = get_parent() as MissionDirector
	CampaignState.mission_completed.connect(_on_mission_completed)


func _on_mission_completed(id: String) -> void:
	if id != CampaignState.last_mission() or CampaignState.is_campaign_complete() or playing:
		return
	playing = true
	CampaignState.set_flag(CampaignState.COMPLETE_FLAG)
	if director and is_instance_valid(director.rover):
		SaveIndex.save_current(director.rover)
	_play.call_deferred()


func _play() -> void:
	GameState.change_state_to(GameState.State.IN_GAME_MENU)
	if director and director.rover and director.pad and not director.pad.is_in_zone(director.rover):
		director.dock_rover()
	await _show_iris()
	if not is_inside_tree():
		return
	GameState.change_state_to(GameState.State.IN_GAME_PLAYER)
	_play_closing_lines_until_trigger_system()
	await _wait_for_dialogue(_dialogue_timeout())
	if not is_inside_tree():
		return
	GameState.change_state_to(GameState.State.IN_GAME_MENU)
	var result := _result_screen()
	if result:
		result.open()
	playing = false
	finished.emit()


func _show_iris() -> void:
	var result := _result_screen()
	var iris := director.get_parent().get_node_or_null("Iris") as Node3D if director else null
	if iris == null:
		await _wait(IRIS_SHOT_TIME)
		return
	var previous := get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	camera.name = "EndingCamera"
	director.get_parent().add_child(camera)
	var away: Vector3 = (director.workshop.global_position - iris.global_position) if director.workshop else Vector3.BACK
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	camera.global_position = iris.global_position + away * CAMERA_DISTANCE + Vector3.UP * CAMERA_HEIGHT
	camera.look_at(iris.global_position + Vector3.UP * 1.5)
	camera.make_current()
	if result:
		result.show_caption("Kite docked. IRIS online, transmitting.")
	await _wait(IRIS_SHOT_TIME)
	if result:
		result.hide_caption()
	if is_instance_valid(previous):
		previous.make_current()
	camera.queue_free()


## Delete once the dialogue trigger system plays the lines for the ending's event (mission_completed:m3).
func _play_closing_lines_until_trigger_system() -> void:
	var lines := closing_lines()
	if lines.is_empty():
		return
	_closing_sequence = DialogSequence.new()
	_closing_sequence.dialogs = lines
	DialogServer.play_dialog_sequence(_closing_sequence)


func _wait_for_dialogue(timeout: float) -> void:
	var done: Array = [false]
	var on_finished := func(sequence: DialogSequence, _completed: bool) -> void:
		if _closing_sequence == null or sequence == _closing_sequence:
			done[0] = true
	DialogServer.sequence_finished.connect(on_finished)
	var elapsed: float = 0.0
	while not done[0] and elapsed < timeout and is_inside_tree():
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	DialogServer.sequence_finished.disconnect(on_finished)
	_closing_sequence = null


func _dialogue_timeout() -> float:
	var total: float = DIALOGUE_TIMEOUT_EXTRA
	for line in closing_lines():
		total += DialogServer.get_dialog_duration(line) + DialogServer.SEQUENCE_GAP
	return total


## The ending event's lines from dialogue_triggers.json / lines.json, else the fallback in missions.json
func closing_lines() -> Array[Dialog]:
	var ending := CampaignState.mission_ending(CampaignState.last_mission())
	var event: String = ending.get("event", "")
	var triggers: Variant = _read_json(TRIGGERS_PATH)
	var lines: Variant = _read_json(LINES_PATH)
	var result: Array[Dialog] = []
	if triggers is Array and lines is Dictionary:
		for trigger in triggers:
			if trigger is Dictionary and trigger.get("on") == event and lines.get(trigger.get("line")) is Dictionary:
				result.append(_dialog(lines[trigger["line"]]))
	if result.is_empty() and ending.get("lines") is Array:
		for line in ending["lines"]:
			if line is Dictionary:
				result.append(_dialog(line))
	return result


func _dialog(entry: Dictionary) -> Dialog:
	var dialog := Dialog.new()
	dialog.speaker = str(entry.get("speaker", ""))
	dialog.subtitle = str(entry.get("text", ""))
	dialog.min_duration = LINE_MIN_DURATION
	var audio: String = str(entry.get("audio", ""))
	if audio and ResourceLoader.exists(audio):
		dialog.audio_stream = load(audio)
	return dialog


func _read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


func _result_screen() -> CampaignResult:
	return get_tree().get_first_node_in_group(&"campaign_result") as CampaignResult if is_inside_tree() else null
