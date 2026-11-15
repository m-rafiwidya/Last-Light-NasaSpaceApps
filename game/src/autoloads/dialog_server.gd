extends Node
## Plays dialog lines and sequences and broadcasts them to the UI.
##
## Lifetime is tracked with a "generation" counter: every coroutine remembers
## the generation it started in, and stop_all() bumps it. Any coroutine that wakes
## up in a newer generation knows it was cancelled and exits without touching state.

signal dialog_played(dialog: Dialog)
signal dialog_ended(dialog: Dialog)
## `completed` is false when the sequence was cancelled (e.g. the level unloaded).
signal sequence_finished(sequence: DialogSequence, completed: bool)

const CHARACTERS_PER_SECOND: float = 1000.0 / 60.0
## Pause between two lines: the shown one fades out (SubtitleStack.SINGLE_FADE) before the next fades in
const SEQUENCE_GAP: float = 0.35

## Bus the voice lines play on (Settings > Audio > Voice Volume)
const AUDIO_BUS: StringName = &"Voice"
const SKIP_ACTION: StringName = &"dialogue_skip"
## A line with a repeat_id doesn't play again within this many seconds of game time
const REPEAT_COOLDOWN: float = 20.0

## Game time (s), paused with the tree; the repeat cooldown runs on it
var clock: float = 0.0
var _generation: int = 0
var _active_dialogs: Array[Dialog] = []
var _audio_players: Dictionary = {}  # Dialog -> AudioStreamPlayer
var _timers: Dictionary = {}  # Dialog -> SceneTreeTimer
var _active_sequence: DialogSequence = null
var _sequence_dialog: Dialog = null
var _queue: Array[DialogSequence] = []
var _queue_running: bool = false
var _last_played: Dictionary = {}  # repeat_id -> clock
## Direct lines waiting for the shown line to end; they go before the queue's next line
var _pending: Array[Dialog] = []
var _free_at: float = 0.0


func _ready() -> void:
	SceneLoader.level_unloaded.connect(_on_scene_loader_level_unloaded)


func _process(delta: float) -> void:
	clock += delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(SKIP_ACTION) and not event.is_echo() and skip_allowed() and skip_current():
		get_viewport().set_input_as_handled()


## Gameplay and the console; never in a cutscene or a menu
func skip_allowed() -> bool:
	return GameState.is_in_game() or GameState.state == GameState.State.MISSION_CONSOLE


## The line the skip key would end now (whichever is showing), or null
func skippable_dialog() -> Dialog:
	return _active_dialogs[0] if not _active_dialogs.is_empty() else null


## Ends the line showing now; the next one plays. False when none is showing.
func skip_current() -> bool:
	var dialog := skippable_dialog()
	var timer: SceneTreeTimer = _timers.get(dialog)
	if timer == null:
		return false
	timer.time_left = 0.0
	return true


func is_cooling_down(repeat_id: String) -> bool:
	return repeat_id != "" and _last_played.has(repeat_id) and clock - float(_last_played[repeat_id]) < REPEAT_COOLDOWN


func _on_scene_loader_level_unloaded(_level_name) -> void:
	stop_all()


## The audio's length when the line has a voice, else the text's reading time; at least min_duration.
func get_dialog_duration(dialog: Dialog) -> float:
	if dialog.audio_stream:
		return max(dialog.audio_stream.get_length(), dialog.min_duration)
	return max(dialog.subtitle.length() / CHARACTERS_PER_SECOND, dialog.min_duration)


func is_playing() -> bool:
	return not _active_dialogs.is_empty() or _active_sequence != null or not _queue.is_empty() or not _pending.is_empty()


## Plays `sequence` after every sequence queued before it. Only one line plays at a time.
func queue_sequence(sequence: DialogSequence) -> void:
	_queue.append(sequence)
	if not _queue_running:
		_run_queue()


## True while `sequence` is queued or playing
func is_sequence_pending(sequence: DialogSequence) -> bool:
	return sequence != null and (sequence == _active_sequence or sequence in _queue)


## True while `sequence` is queued and hasn't started
func is_sequence_waiting(sequence: DialogSequence) -> bool:
	return sequence != null and sequence in _queue


## Upper bound (s) for the playing and queued sequences to finish
func queued_duration() -> float:
	var total: float = 0.0
	var sequences: Array[DialogSequence] = _queue.duplicate()
	if _active_sequence:
		sequences.append(_active_sequence)
	for sequence in sequences:
		for dialog in sequence.dialogs:
			total += get_dialog_duration(dialog) + SEQUENCE_GAP
	return total


func _run_queue() -> void:
	_queue_running = true
	var generation := _generation
	while not _queue.is_empty():
		while _active_sequence != null:
			await get_tree().process_frame
			if generation != _generation:
				return
		await play_dialog_sequence(_queue.pop_front())
		if generation != _generation:
			return
		if not _queue.is_empty():
			await get_tree().create_timer(SEQUENCE_GAP, false).timeout
			if generation != _generation:
				return
	_queue_running = false


## Plays one line: at once when none is showing, else right after the shown one (before the queue's
## next line). Returns true if it played to the end (or was skipped), false if it was cancelled, or
## ignored because the same Dialog is already playing or waiting or its repeat_id is cooling down.
func play_dialog(dialog: Dialog) -> bool:
	return await _play(dialog, true)


func _play(dialog: Dialog, direct: bool) -> bool:
	if dialog in _active_dialogs or dialog in _pending or is_cooling_down(dialog.repeat_id):
		return false
	if dialog.repeat_id != "":
		_last_played[dialog.repeat_id] = clock

	var generation := _generation
	if direct:
		_pending.append(dialog)
	while not _may_start(dialog, direct):
		await get_tree().process_frame
		if generation != _generation:
			return false
	_pending.erase(dialog)
	_active_dialogs.append(dialog)
	_start_audio(dialog)
	dialog_played.emit(dialog)

	# process_always = false: pauses with the tree, scales with Engine.time_scale
	var timer := get_tree().create_timer(get_dialog_duration(dialog), false)
	_timers[dialog] = timer
	await timer.timeout
	if generation != _generation:
		return false

	_timers.erase(dialog)
	_active_dialogs.erase(dialog)
	_free_at = clock + SEQUENCE_GAP
	_stop_audio(dialog)
	dialog_ended.emit(dialog)
	return true


func _may_start(dialog: Dialog, direct: bool) -> bool:
	if not _active_dialogs.is_empty() or clock < _free_at:
		return false
	return _pending.front() == dialog if direct else _pending.is_empty()


## Plays every line in order. Returns true if the whole sequence completed.
## Ignored (returns false) while another sequence is already playing.
func play_dialog_sequence(dialog_sequence: DialogSequence) -> bool:
	if _active_sequence != null:
		return false

	var generation := _generation
	_active_sequence = dialog_sequence
	var completed := true

	var dialogs: Array[Dialog] = []
	for dialog in dialog_sequence.dialogs:
		if not is_cooling_down(dialog.repeat_id):
			dialogs.append(dialog)
	var last_index := dialogs.size() - 1
	for i in dialogs.size():
		_sequence_dialog = dialogs[i]
		var played := await _play(dialogs[i], false)
		if generation == _generation:
			_sequence_dialog = null
		if not played:
			completed = false
			break
		if i == last_index:
			break
		await get_tree().create_timer(SEQUENCE_GAP, false).timeout
		if generation != _generation:
			completed = false
			break

	# A newer generation owns _active_sequence now; don't clobber it.
	if generation == _generation:
		_active_sequence = null
	sequence_finished.emit(dialog_sequence, completed)
	return completed


## Drops `sequence` from the queue, or cuts it off if it is playing; the rest of the queue still plays
func cancel_sequence(sequence: DialogSequence) -> void:
	if sequence in _queue:
		_queue.erase(sequence)
	elif sequence != null and sequence == _active_sequence:
		var rest := _queue.duplicate()
		stop_all()
		for queued in rest:
			queue_sequence(queued)


## Cancels everything that is playing. Running coroutines notice on their next wake-up.
func stop_all() -> void:
	_generation += 1
	_active_sequence = null
	_sequence_dialog = null
	_timers.clear()
	_queue.clear()
	_pending.clear()
	_free_at = 0.0
	_queue_running = false
	var ended := _active_dialogs.duplicate()
	_active_dialogs.clear()
	for dialog in ended:
		_stop_audio(dialog)
		dialog_ended.emit(dialog)


func _start_audio(dialog: Dialog) -> void:
	if dialog.audio_stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = dialog.audio_stream
	player.bus = AUDIO_BUS
	add_child(player)
	player.play()
	_audio_players[dialog] = player


func _stop_audio(dialog: Dialog) -> void:
	var player: AudioStreamPlayer = _audio_players.get(dialog)
	_audio_players.erase(dialog)
	if is_instance_valid(player):
		player.stop()
		player.queue_free()
