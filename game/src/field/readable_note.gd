class_name ReadableNote

extends Node3D

## One of Evan's notes (game/docs/STORY_SCRIPT.md), a small readable prop (the decor kit's service
## note). Reading shows the text as an "Evan:" subtitle through DialogServer, with the voice file
## res://res/audio/voice/<note_id>.ogg or .mp3 when it exists (text only otherwise). E again while it shows
## skips it.
##
## Read on foot: the player aims at it and presses E (an InteractTrigger, layer 5, like the sockets).
## Read by Kite: with `kite_range` > 0, E while driving within that range of the note; with
## `auto_play` it plays once by itself when Kite first comes that close.
## With `unlock_objective` set, the note is hidden and can't be read until that objective is done.
## Guidance can target it (`group:readable_note` or its path) and glows `highlight_node` (the prop).

signal read(note: ReadableNote)

const GROUP: StringName = &"readable_note"
const MODEL: String = "res://res/models/decor_kit/dc_service_note.glb"
const VOICE_DIR: String = "res://res/audio/voice/"
const TRIGGER_SIZE := Vector3(0.4, 0.3, 0.4)
const READ_SPEED: float = 15.0        # characters per second for the subtitle's minimum time

## Names the voice file (<note_id>.ogg or .mp3)
@export var note_id: String = ""
@export var speaker: String = "Evan"
@export_multiline var text: String = ""
## Hidden and unreadable until this objective is done ("" = always there)
@export var unlock_objective: String = ""
## Kite reads it with E within this distance (m, horizontal); 0 = on foot only
@export var kite_range: float = 0.0
## Plays once by itself when Kite first comes within kite_range
@export var auto_play: bool = false
## What Guidance lights up (the prop's model, set in _ready)
@export var highlight_node: Node3D
var was_read: bool = false
var _showing: Dialog = null
var _trigger: InteractTrigger = null


func _ready() -> void:
	add_to_group(GROUP)
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	highlight_node = model
	_trigger = InteractTrigger.new()
	_trigger.name = "InteractTrigger"
	_trigger.tooltip = 'Press "E" to read %s\'s note' % speaker
	_trigger.collision_layer = 16
	_trigger.collision_mask = 0
	_trigger.monitoring = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = TRIGGER_SIZE
	shape.shape = box
	shape.position = Vector3(0.0, TRIGGER_SIZE.y / 2.0, 0.0)
	_trigger.add_child(shape)
	add_child(_trigger)
	_trigger.interacted.connect(func(_player: Player) -> void: toggle())
	DialogServer.dialog_ended.connect(func(dialog: Dialog) -> void:
		if dialog == _showing:
			_showing = null)
	_update_unlocked()
	CampaignState.objective_completed.connect(func(_id: String) -> void: _update_unlocked())


func is_unlocked() -> bool:
	return unlock_objective.is_empty() or CampaignState.is_objective_done(unlock_objective)


func is_showing() -> bool:
	return _showing != null


func _update_unlocked() -> void:
	visible = is_unlocked()
	_trigger.collision_layer = 16 if visible else 0


## Shows the note, or skips it when it's showing; false when it's still locked
func toggle() -> bool:
	if not is_unlocked():
		return false
	if _showing:
		DialogServer.stop_all()
		_showing = null
		return true
	var line := Dialog.new()
	line.speaker = speaker
	line.subtitle = text
	line.min_duration = maxf(4.0, text.length() / READ_SPEED)
	for extension in [".ogg", ".mp3"]:   # ElevenLabs downloads are .mp3
		var voice: String = VOICE_DIR + note_id + extension
		if not note_id.is_empty() and ResourceLoader.exists(voice):
			line.audio_stream = load(voice)
			break
	DialogServer.play_dialog(line)
	_showing = line
	was_read = true
	read.emit(self)
	return true


func kite_distance(rover: Robot) -> float:
	var offset: Vector3 = rover.global_position - global_position
	offset.y = 0.0
	return offset.length()


func _physics_process(_delta: float) -> void:
	if kite_range <= 0.0 or not is_unlocked() or GameState.state != GameState.State.IN_GAME_ROBOT \
			or not is_instance_valid(GameState.robot) or kite_distance(GameState.robot) > kite_range:
		return
	if auto_play and not was_read:
		toggle()
	# An auto-play note only skips on E (E there also loads the logger), it doesn't replay
	elif Input.is_action_just_pressed(&"interact_use") and (not auto_play or _showing):
		toggle()
