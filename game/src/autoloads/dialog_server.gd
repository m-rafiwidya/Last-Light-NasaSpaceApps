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
## Pause between the lines of a sequence. Shorter than the DialogBox hold + fade-out,
## so consecutive lines are on screen together and the HUD stacks them.
const SEQUENCE_GAP: float = 0.35

## Bus the voice lines play on (Settings > Audio > Voice Volume)
const AUDIO_BUS: StringName = &"Voice"

var _generation: int = 0
var _active_dialogs: Array[Dialog] = []
var _audio_players: Dictionary = {}  # Dialog -> AudioStreamPlayer
var _active_sequence: DialogSequence = null
var _queue: Array[DialogSequence] = []
var _queue_running: bool = false


func _ready() -> void:
	SceneLoader.level_unloaded.connect(_on_scene_loader_level_unloaded)


func _on_scene_loader_level_unloaded(_level_name) -> void:
	stop_all()


## The audio's length when the line has a voice, else the text's reading time; at least min_duration.
func get_dialog_duration(dialog: Dialog) -> float:
	if dialog.audio_stream:
		return max(dialog.audio_stream.get_length(), dialog.min_duration)
	return max(dialog.subtitle.length() / CHARACTERS_PER_SECOND, dialog.min_duration)


func is_playing() -> bool:
	return not _active_dialogs.is_empty() or _active_sequence != null or not _queue.is_empty()


## Plays `sequence` after every sequence queued before it, so queued lines never overlap.
## Direct play_dialog() lines still play at once, next to them.
func queue_sequence(sequence: DialogSequence) -> void:
	_queue.append(sequence)
	if not _queue_running:
		_run_queue()


## True while `sequence` is queued or playing
func is_sequence_pending(sequence: DialogSequence) -> bool:
	return sequence != null and (sequence == _active_sequence or sequence in _queue)


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


## Plays one line. Returns true if it played to the end, false if it was
## cancelled or ignored because the same Dialog is already playing.
func play_dialog(dialog: Dialog) -> bool:
	if dialog in _active_dialogs:
		return false

	var generation := _generation
	_active_dialogs.append(dialog)
	_start_audio(dialog)
	dialog_played.emit(dialog)

	# process_always = false: pauses with the tree, scales with Engine.time_scale
	await get_tree().create_timer(get_dialog_duration(dialog), false).timeout
	if generation != _generation:
		return false

	_active_dialogs.erase(dialog)
	_stop_audio(dialog)
	dialog_ended.emit(dialog)
	return true


## Plays every line in order. Returns true if the whole sequence completed.
## Ignored (returns false) while another sequence is already playing.
func play_dialog_sequence(dialog_sequence: DialogSequence) -> bool:
	if _active_sequence != null:
		return false

	var generation := _generation
	_active_sequence = dialog_sequence
	var completed := true

	var last_index := dialog_sequence.dialogs.size() - 1
	for i in dialog_sequence.dialogs.size():
		if not await play_dialog(dialog_sequence.dialogs[i]):
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
	_queue.clear()
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
