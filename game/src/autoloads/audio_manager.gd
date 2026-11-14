extends Node

## Background music and UI sounds (autoload, runs while paused).
##
## Music: the Deep Space "memory" loop on the Music bus, faded in at start. As an autoload it keeps
## playing across level changes and while the game is paused. The OGG is imported with loop on
## (game/music/export_to_game.py sets it); `loop` is enforced here too.
##
## UI sounds: play_ui(&"confirm") plays res/audio/ui/<name>.wav on the UI bus, each in its own
## AudioStreamPlayer that frees itself when done. Sounds with variations (hover_1..3, click_1..3)
## pick one at random (never the same twice in a row), always at their tuned pitch.
## Buttons get hover/press sounds from ButtonSoundComponent; menus open/close from state changes.
## The files come from game/music (ui_sounds.py, export_to_game.py).

signal volume_changed(key: String, percent: float)

const MUSIC: AudioStream = preload("res://res/audio/music/deep_space_memory.ogg")
const MUSIC_BUS: StringName = &"Music"
const UI_BUS: StringName = &"UI"
const MUSIC_FADE_IN: float = 6.0
const MUSIC_SILENT_DB: float = -50.0
const UI_DIR: String = "res://res/audio/ui/"
const SOUNDS: Array[StringName] = [
	&"hover", &"click", &"confirm", &"back", &"error", &"menu_open", &"menu_close",
	&"toggle_on", &"toggle_off", &"slider_tick", &"notification", &"game_start",
]
## Sounds rendered in variations <name>_1 .. <name>_N
const VARIATIONS: int = 3
## Dragging a slider plays at most one tick per this many seconds
const SLIDER_TICK_INTERVAL: float = 0.07
## Hover only plays if the mouse itself moved this recently: a menu sliding in under a still
## cursor (scene load, pause) also fires mouse_entered
const HOVER_MOUSE_WINDOW: float = 0.15
## No hover sounds this long after a game state change (menus are still sliding in)
const QUIET_AFTER_STATE_CHANGE: float = 0.3

var music_player: AudioStreamPlayer

var _streams: Dictionary = {}          # name -> Array[AudioStream]
var _last_variation: Dictionary = {}   # name -> index played last
var _last_mouse_motion: float = -INF
var _quiet_until: float = -INF
var _last_slider_tick: float = -INF


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sound in SOUNDS:
		_streams[sound] = _load_variants(sound)
	AudioSettings.apply()
	GameState.state_changed.connect(_on_state_changed)
	_start_music()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative != Vector2.ZERO:
		_last_mouse_motion = _now()


## Plays a UI sound by name (see SOUNDS)
func play_ui(sound: StringName) -> void:
	var variants: Array = _streams.get(sound, [])
	if variants.is_empty():
		push_warning("AudioManager: no UI sound %s" % sound)
		return
	var player := AudioStreamPlayer.new()
	player.stream = variants[_pick(sound, variants.size())]
	player.bus = UI_BUS
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


## Hover over a button: not for disabled buttons, and only for real mouse movement
func play_hover(button: BaseButton = null) -> void:
	if button and button.disabled:
		return
	var now: float = _now()
	if now < _quiet_until or now - _last_mouse_motion > HOVER_MOUSE_WINDOW:
		return
	play_ui(&"hover")


func play_toggle(on: bool) -> void:
	play_ui(&"toggle_on" if on else &"toggle_off")


## Throttled, so dragging a slider fast doesn't spam it
func play_slider_tick() -> void:
	var now: float = _now()
	if now - _last_slider_tick < SLIDER_TICK_INTERVAL:
		return
	_last_slider_tick = now
	play_ui(&"slider_tick")


## Volume of one AudioSettings key ("master", "music", "interface"), applied and saved
func set_volume(key: String, percent: float) -> void:
	AudioSettings.set_volume(key, percent)
	volume_changed.emit(key, AudioSettings.get_volume(key))


func _start_music() -> void:
	var stream: AudioStream = MUSIC
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	music_player = AudioStreamPlayer.new()
	music_player.name = "Music"
	music_player.stream = MUSIC
	music_player.bus = MUSIC_BUS
	music_player.volume_db = MUSIC_SILENT_DB
	add_child(music_player)
	music_player.play()
	var tween := create_tween()
	tween.set_ignore_time_scale(true)   # pausing tweens Engine.time_scale to 0
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(music_player, "volume_db", 0.0, MUSIC_FADE_IN)


func _on_state_changed(old_state, new_state) -> void:
	_quiet_until = _now() + QUIET_AFTER_STATE_CHANGE
	var overlays: Array = [GameState.State.PAUSED, GameState.State.MISSION_CONSOLE]
	if new_state in overlays and GameState.is_in_game(old_state):
		play_ui(&"menu_open")
	elif old_state in overlays and GameState.is_in_game(new_state):
		play_ui(&"menu_close")


func _load_variants(sound: StringName) -> Array:
	var single: String = UI_DIR + sound + ".wav"
	if ResourceLoader.exists(single):
		return [load(single)]
	var variants: Array = []
	for i in range(1, VARIATIONS + 1):
		var path: String = "%s%s_%d.wav" % [UI_DIR, sound, i]
		if ResourceLoader.exists(path):
			variants.append(load(path))
	return variants


func _pick(sound: StringName, count: int) -> int:
	if count == 1:
		return 0
	var index: int = randi() % count
	if index == _last_variation.get(sound, -1):
		index = (index + 1 + randi() % (count - 1)) % count
	_last_variation[sound] = index
	return index


# Real time in seconds: unaffected by Engine.time_scale and pausing
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
