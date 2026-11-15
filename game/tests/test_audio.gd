extends SceneTree
## Headless test: music, UI sounds and audio settings (AudioManager, AudioSettings).
##   1. The Music and UI buses exist and send to Master; every UI sound loads (hover and click in
##      three variations).
##   2. Music: the memory loop (OGG, loop on, offset 0, exactly 60 s) plays on the Music bus,
##      fades in, keeps playing while the tree is paused and across a level change (same player,
##      position not reset).
##   3. UI sounds play on the UI bus while paused, at their tuned pitch, and each one-shot player
##      frees itself when it finishes; variations never repeat back to back.
##   4. Hover is silent for disabled buttons, without real mouse movement and right after a state
##      change; slider ticks are throttled.
##   5. Volumes: the settings menu's Music slider sets the Music bus, is saved in
##      user://settings.cfg (restored afterwards), and the other menu's slider follows.
##   6. The level buttons press with game_start (main menu) and confirm (pause menu).
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_audio.gd
##
## Audio plays in real time (headless: the Dummy driver) while --fixed-fps runs game time as fast
## as it can, so the audio checks wait in real time and the watchdog counts real time too.

const TICKS: int = 240
const SETTINGS_PATH: String = "user://settings.cfg"

var GS: Node
var SL: Node
var AM: Node
var failures: int = 0
var _saved_settings: String = ""
var _had_settings: bool = false


var _deadline_ms: int = 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_deadline_ms = Time.get_ticks_msec() + 240 * 1000
	_run.call_deferred()


# Real-time watchdog (a game-time timer would fire early under --fixed-fps)
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline_ms:
		printerr("WATCHDOG: no result after 240 s, quitting")
		_restore_settings()
		quit(2)
	return false


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-58s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


# Real-time wait (works while paused, regardless of Engine.time_scale and --fixed-fps)
func _wait(seconds: float) -> void:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _one_shots() -> Array:
	return AM.get_children().filter(func(n: Node) -> bool:
		return n is AudioStreamPlayer and n != AM.music_player and not n.is_queued_for_deletion())


func _move_mouse() -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(3, 1)
	motion.position = Vector2(400, 300)
	Input.parse_input_event(motion)
	for i in 3:   # buffered motion is delivered at the end of a frame
		await process_frame


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	AM = root.get_node("AudioManager")
	_backup_settings()
	var volume_at_boot: float = AM.music_player.volume_db
	await _ticks(1.0)   # the fade is a tween: game time
	var volume_later: float = AM.music_player.volume_db
	while GS.state != GS.State.MAIN_MENU:
		await process_frame

	# 1. Buses and sounds
	for bus in ["Music", "UI"]:
		var index: int = AudioServer.get_bus_index(bus)
		_check("bus %s exists, sends to Master" % bus, index > 0 and AudioServer.get_bus_send(index) == &"Master")
	var missing: Array = AM.SOUNDS.filter(func(s: StringName) -> bool: return AM._streams[s].is_empty())
	_check("every UI sound loads", missing.is_empty(), str(missing))
	_check("hover and click have 3 variations", AM._streams[&"hover"].size() == 3 and AM._streams[&"click"].size() == 3)

	# 2. Music
	var music: AudioStreamPlayer = AM.music_player
	var stream := music.stream as AudioStreamOggVorbis
	_check("music is the memory OGG", stream != null and stream.resource_path.ends_with("deep_space_memory.ogg"))
	_check("music loops from the start", stream != null and stream.loop and stream.loop_offset == 0.0)
	_check("music is exactly 60 s", stream != null and absf(stream.get_length() - 60.0) < 0.001, "%.4f s" % stream.get_length())
	_check("music plays on the Music bus", music.playing and music.bus == &"Music")
	_check("music fades in at start", volume_at_boot < -30.0 and volume_later > volume_at_boot and volume_later < -0.5,
		"%.1f -> %.1f dB after 1 s" % [volume_at_boot, volume_later])

	paused = true
	var position: float = music.get_playback_position()
	await _wait(0.5)
	_check("music keeps playing while paused", music.playing and music.get_playback_position() > position,
		"%.2f -> %.2f s" % [position, music.get_playback_position()])

	# 3. UI sounds while paused, freed after playing, variations
	var before: int = _one_shots().size()
	AM.play_ui(&"click")
	var shots: Array = _one_shots()
	var shot: AudioStreamPlayer = shots.back() if shots.size() > before else null
	_check("a UI sound plays while paused", shot != null and shot.playing and shot.bus == &"UI")
	_check("UI sounds play at their tuned pitch", shot != null and shot.pitch_scale == 1.0)
	await _wait(1.2)
	_check("the one-shot player frees itself when done", _one_shots().size() == before,
		"%d players left" % _one_shots().size())
	paused = false

	var last: int = -1
	var repeats: int = 0
	var used := {}
	for i in 60:
		var index: int = AM._pick(&"hover", 3)
		repeats += int(index == last)
		used[index] = true
		last = index
	_check("variations never repeat back to back, all used", repeats == 0 and used.size() == 3)

	# 4. Hover and slider guards
	await _wait(AM.QUIET_AFTER_STATE_CHANGE + 0.05)
	var button := Button.new()
	root.add_child(button)
	before = _one_shots().size()
	await _wait(AM.HOVER_MOUSE_WINDOW + 0.05)
	AM.play_hover(button)
	_check("no hover without real mouse movement", _one_shots().size() == before)
	await _move_mouse()
	button.disabled = true
	AM.play_hover(button)
	_check("no hover on a disabled button", _one_shots().size() == before)
	button.disabled = false
	AM.play_hover(button)
	_check("hover plays after mouse movement", _one_shots().size() == before + 1)
	button.queue_free()

	before = _one_shots().size()
	for i in 10:
		AM.play_slider_tick()
	_check("slider ticks are throttled", _one_shots().size() == before + 1, "%d ticks" % (_one_shots().size() - before))

	# 5. Volume settings through the menu sliders
	_check("a script run keeps its audio settings apart, from the defaults", AudioSettings.path != AudioSettings.PATH
		and AudioSettings.options.path == AudioSettings.path
		and AudioSettings.DEFAULTS.keys().all(func(key: String) -> bool: return AudioSettings.get_volume(key) == AudioSettings.DEFAULTS[key]))
	var main_slider: HSlider = _volume_slider("UIManager/MainMenu/SettingsSubMenu", "Music Volume")
	var pause_slider: HSlider = _volume_slider("UIManager/PauseMenu/Root/SettingsSubMenu", "Music Volume")
	_check("both menus have a Music Volume slider", main_slider != null and pause_slider != null)
	if main_slider and pause_slider:
		main_slider.value = 35.0
		var bus_db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
		_check("Music slider sets the Music bus", is_equal_approx(bus_db, linear_to_db(0.35)), "%.2f dB" % bus_db)
		var config := ConfigFile.new()
		config.load(AudioSettings.path)
		_check("volume is saved with the settings", is_equal_approx(config.get_value("audio", "music", -1.0), 35.0))
		_check("the other menu's slider follows", is_equal_approx(pause_slider.value, 35.0))

	# 6. Press sounds of the buttons that start a level
	var popup: Node = root.get_node("Main/UIManager/MainMenu").find_child("PlayPopup", true, false)
	var pause_level: Node = root.get_node("Main/UIManager/PauseMenu").find_child("LevelChoice", true, false)
	_check("START NEW CAMPAIGN plays game_start", ["StartEmpty", "StartList"].all(func(n: String) -> bool:
		return popup.find_child(n, true, false).get_node("ButtonSoundComponent").press_sound == &"game_start"))
	_check("pause menu level buttons play confirm", _press_sound(pause_level) == &"confirm")

	# 2b. Music across a level change: same player, not restarted
	position = music.get_playback_position()
	SL.load_scene("test_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "test_level"):
		await process_frame
	await _ticks(0.25)
	_check("music keeps playing across a level change", AM.music_player == music and music.playing
		and music.get_playback_position() > position,
		"%.2f -> %.2f s" % [position, music.get_playback_position()])

	_restore_settings()
	print("RESULT test_audio %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)


func _volume_slider(menu_path: String, label_text: String) -> HSlider:
	var menu: Node = root.get_node_or_null("Main/" + menu_path)
	if menu == null:
		return null
	for label in menu.find_children("*", "Label", true, false):
		if label.text == label_text:
			return label.get_parent().get_child(label.get_index() + 1) as HSlider
	return null


func _press_sound(level_choice: Node) -> StringName:
	if level_choice == null or level_choice.get_child_count() == 0:
		return &"(none)"
	return level_choice.get_child(0).get_node("ButtonSoundComponent").press_sound


func _backup_settings() -> void:
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_saved_settings = FileAccess.get_file_as_string(SETTINGS_PATH)


func _restore_settings() -> void:
	if _had_settings:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		file.store_string(_saved_settings)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
