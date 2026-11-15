class_name CutsceneSound

extends Node

## A cutscene's sound, by the no-sound-through-vacuum rule: the descent engine is only felt through
## the lander's structure, so its rumble is heard while the camera is near the lander and the
## engine is on; the touchdown thump the same way; everything else is the radio: a click as each
## line opens and closes and a quiet carrier hiss under it, silent between lines. CutsceneDirector makes one per cutscene from its
## "sound" entry {rumble: node path of a Lander, radio: bool}.

const RUMBLE: AudioStream = preload("res://res/audio/sfx/engine_rumble_loop.ogg")
const STATIC: AudioStream = preload("res://res/audio/sfx/radio_static_loop.ogg")
const CLICK_ON: AudioStream = preload("res://res/audio/sfx/radio_click_on.wav")
const CLICK_OFF: AudioStream = preload("res://res/audio/sfx/radio_click_off.wav")
const THUMP: AudioStream = preload("res://res/audio/sfx/impact_regolith_heavy_2.wav")
const SFX_BUS: StringName = &"SFX"
const RADIO_BUS: StringName = &"Voice"
## Full rumble with the camera this close to the lander, none past RUMBLE_FAR (m)
const RUMBLE_NEAR: float = 12.0
const RUMBLE_FAR: float = 70.0
const RUMBLE_DB: float = 4.0
const RUMBLE_ATTACK: float = 0.6
const RUMBLE_CUTOFF: float = 0.25
const STATIC_DB: float = 0.0
## Static between lines (none: it is the open carrier of a line)
const STATIC_IDLE: float = 0.0
const STATIC_FADE: float = 0.15
const THUMP_DB: float = 6.0
const THUMP_PITCH: float = 0.7

var director: CutsceneDirector
var lander: Node3D = null
var radio: bool = false
var rumble_gain: float = 0.0
var static_gain: float = 0.0
var line_open: bool = false
## What played (for tests): "click_on", "click_off", "thump"
var events: Array[String] = []

var _rumble: AudioStreamPlayer
var _static: AudioStreamPlayer
var _opened: Callable
var _closed: Callable


func setup(owner_director: CutsceneDirector, data: Dictionary) -> void:
	director = owner_director
	name = "CutsceneSound"
	_opened = _on_line.bind(true)
	_closed = _on_line.bind(false)
	lander = director.resolve(str(data.get("rumble", ""))) as Node3D
	radio = bool(data.get("radio", false))
	if lander:
		_rumble = _player(RUMBLE, SFX_BUS)
		_rumble.play()
		if lander.has_signal("touched_down"):
			lander.touched_down.connect(_on_touched_down)
	if radio:
		_static = _player(STATIC, RADIO_BUS)
		_static.play()
		DialogServer.dialog_played.connect(_opened)
		DialogServer.dialog_ended.connect(_closed)
	_apply()


func _exit_tree() -> void:
	if _opened.is_valid() and DialogServer.dialog_played.is_connected(_opened):
		DialogServer.dialog_played.disconnect(_opened)
		DialogServer.dialog_ended.disconnect(_closed)


func update(step: float) -> void:
	if lander:
		var target: float = 0.0
		if bool(lander.get("engine_on")) and director.camera:
			var distance: float = director.camera.global_position.distance_to(lander.global_position)
			target = 1.0 - smoothstep(RUMBLE_NEAR, RUMBLE_FAR, distance)
		var rate: float = RUMBLE_ATTACK if target > rumble_gain else RUMBLE_CUTOFF
		rumble_gain = move_toward(rumble_gain, target, step / rate)
	if radio:
		var level: float = 1.0 if line_open else STATIC_IDLE
		static_gain = move_toward(static_gain, level, step / STATIC_FADE)
	_apply()


func _apply() -> void:
	if _rumble:
		_rumble.volume_db = linear_to_db(maxf(rumble_gain, 1e-4)) + RUMBLE_DB
	if _static:
		_static.volume_db = linear_to_db(maxf(static_gain, 1e-4)) + STATIC_DB


func _on_line(_dialog: Dialog, opened: bool) -> void:
	line_open = opened
	_one_shot(CLICK_ON if opened else CLICK_OFF, RADIO_BUS)
	events.append("click_on" if opened else "click_off")


func _on_touched_down() -> void:
	if director.skipped:
		return
	var player := _one_shot(THUMP, SFX_BUS)
	player.volume_db = THUMP_DB
	player.pitch_scale = THUMP_PITCH
	events.append("thump")


func _one_shot(stream: AudioStream, bus: StringName) -> AudioStreamPlayer:
	var player := _player(stream, bus)
	player.finished.connect(player.queue_free)
	player.play()
	return player


func _player(stream: AudioStream, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus
	add_child(player)
	return player
