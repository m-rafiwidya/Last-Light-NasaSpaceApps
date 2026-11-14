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
## Must be longer than the DialogBox hold + fade-out (0.3s) so boxes don't overlap.
const SEQUENCE_GAP: float = 0.35

## Bus the voice lines play on. Change to a dedicated bus once the project has a bus layout.
const AUDIO_BUS: StringName = &"Master"

var _generation: int = 0
var _active_dialogs: Array[Dialog] = []
var _audio_players: Dictionary = {}  # Dialog -> AudioStreamPlayer
var _active_sequence: DialogSequence = null


func _ready() -> void:
	SceneLoader.level_unloaded.connect(_on_scene_loader_level_unloaded)


func _on_scene_loader_level_unloaded(_level_name) -> void:
	stop_all()


func get_dialog_duration(dialog: Dialog) -> float:
	var duration: float = dialog.subtitle.length() / CHARACTERS_PER_SECOND
	if dialog.audio_stream:
		duration = max(duration, dialog.audio_stream.get_length())
	return max(duration, dialog.min_duration)


func is_playing() -> bool:
	return not _active_dialogs.is_empty() or _active_sequence != null


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


## Cancels everything that is playing. Running coroutines notice on their next wake-up.
func stop_all() -> void:
	_generation += 1
	_active_sequence = null
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
