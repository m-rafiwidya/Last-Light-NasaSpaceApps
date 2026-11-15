class_name CampaignEnding

extends Node

signal finished

const CUTSCENE_ID: String = "ending"
const IRIS_SHOT_TIME: float = 4.0
const DIALOGUE_TIMEOUT_EXTRA: float = 5.0

var director: MissionDirector = null
var playing: bool = false


func _ready() -> void:
	director = get_parent() as MissionDirector
	CampaignState.mission_completed.connect(_on_mission_completed)


func _on_mission_completed(id: String) -> void:
	if id != CampaignState.last_mission() or CampaignState.is_campaign_complete() or playing:
		return
	playing = true
	CampaignState.set_flag(CampaignState.COMPLETE_FLAG)
	UiSettings.set_campaign_finished()
	if director and is_instance_valid(director.rover):
		SaveIndex.save_current(director.rover)
	_play.call_deferred()


func _play() -> void:
	var closing := _closing_sequence()
	if director and director.rover and director.pad and not director.pad.is_in_zone(director.rover):
		director.dock_rover()
	var cutscenes: CutsceneDirector = director.cutscenes if director else null
	if cutscenes and cutscenes.has_cutscene(CUTSCENE_ID):
		await cutscenes.play(CUTSCENE_ID, GameState.State.IN_GAME_PLAYER)
	else:
		await _wait(IRIS_SHOT_TIME)
		GameState.change_state_to(GameState.State.IN_GAME_PLAYER)
	if not is_inside_tree():
		return
	await _wait_for_dialogue(closing, DialogServer.queued_duration() + DIALOGUE_TIMEOUT_EXTRA)
	if not is_inside_tree():
		return
	GameState.change_state_to(GameState.State.IN_GAME_MENU)
	var result := _result_screen()
	if result:
		result.open()
	playing = false
	finished.emit()


## The trigger system's sequence for the ending event, else the missions.json fallback lines queued here
func _closing_sequence() -> DialogSequence:
	var event := _ending_event()
	if DialogueTriggers.has_trigger(event):
		return DialogueTriggers.sequence_for(event)
	var lines := closing_lines()
	if lines.is_empty():
		return null
	var sequence := DialogSequence.new()
	sequence.dialogs = lines
	DialogServer.queue_sequence(sequence)
	return sequence


func _wait_for_dialogue(sequence: DialogSequence, timeout: float) -> void:
	if not DialogServer.is_sequence_pending(sequence):
		return
	var done: Array = [false]
	var on_finished := func(finished_sequence: DialogSequence, _completed: bool) -> void:
		if finished_sequence == sequence:
			done[0] = true
	DialogServer.sequence_finished.connect(on_finished)
	var elapsed: float = 0.0
	while not done[0] and DialogServer.is_sequence_pending(sequence) and elapsed < timeout and is_inside_tree():
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	DialogServer.sequence_finished.disconnect(on_finished)


## The ending event's lines from the dialogue data, else the fallback in missions.json
func closing_lines() -> Array[Dialog]:
	var ending := CampaignState.mission_ending(CampaignState.last_mission())
	var result := DialogueTriggers.lines_for(_ending_event())
	if result.is_empty() and ending.get("lines") is Array:
		for line in ending["lines"]:
			if line is Dictionary:
				result.append(DialogueTriggers.make_dialog(line))
	return result


func _ending_event() -> String:
	return str(CampaignState.mission_ending(CampaignState.last_mission()).get("event", ""))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


func _result_screen() -> CampaignResult:
	return get_tree().get_first_node_in_group(&"campaign_result") as CampaignResult if is_inside_tree() else null
