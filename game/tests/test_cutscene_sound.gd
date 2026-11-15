extends SceneTree
## Headless test: the opening's sound (CutsceneSound, the "music" of cutscenes.json) at the default
## volumes, on the Moon level, played through.
##   1. Never silent for long: every half second of the opening, the loudest of the music, the
##      rumble and the hatch (mean dBFS: file level + player + bus + Master) is above AUDIBLE, and
##      no stretch below it lasts over MAX_QUIET.
##   2. The levels: the rumble builds to a clear level (louder than before), no source is hot.
##   3. No sound in vacuum: the rumble is silent while the camera is past RUMBLE_FAR from the lander
##      or its engine is off; the radio's carrier is silent between lines.
##   4. The touchdown thump and the hatch's start and stop each played once, in that order.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_cutscene_sound.gd

## Mean dBFS of the files (ffmpeg volumedetect)
const MUSIC_MEAN: float = -28.0
const RUMBLE_MEAN: float = -34.1
const HATCH_MEAN: float = -36.8
const THUMP_PEAK: float = -22.0
const AUDIBLE: float = -50.0
const MAX_QUIET: float = 3.0
const SAMPLE: float = 0.5

var GS: Node
var SL: Node
var CS: Node
var AM: Node
var failures: int = 0
var samples: Array = []


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-72s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _bus_db(bus: StringName) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus)) + AudioServer.get_bus_volume_db(0)


func _run() -> void:
	await process_frame
	load("res://src/cutscene/cutscene_director.gd").autoplay = true
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	AM = root.get_node("AudioManager")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	CS.reset()
	load("res://src/save/save_index.gd").start_new_campaign("slot_1")
	while not (SL.current_level_id == "moon_level" and GS.state == GS.State.CUTSCENE):
		await physics_frame
	var director = SL.current_scene.get_node("MissionDirector/Cutscenes")
	var lander = SL.current_scene.get_node("Lander")
	var sound = director.sound
	var events: Array = sound.events
	var far: float = sound.RUMBLE_FAR
	var thump_db: float = sound.THUMP_DB
	var vacuum_ok: bool = true
	var vacuum_detail: String = ""
	var peak_rumble: float = -100.0
	var next_sample: float = 0.0
	var radio_leak: bool = false
	var rumble_off_for: float = 0.0
	var line_closed_for: float = 0.0
	while director.is_playing():
		await physics_frame
		if not is_instance_valid(director.sound):
			break
		if director._clock < next_sample:
			continue
		next_sample += SAMPLE
		var music: float = AM.music_player.volume_db + MUSIC_MEAN + _bus_db(&"Music")
		var rumble: float = sound._rumble.volume_db + RUMBLE_MEAN + _bus_db(&"SFX")
		var hatch: float = (sound._hatch.volume_db + HATCH_MEAN + _bus_db(&"SFX")) if sound._hatch.playing else -100.0
		samples.append(maxf(music, maxf(rumble, hatch)))
		peak_rumble = maxf(peak_rumble, rumble)
		var distance: float = director.camera.global_position.distance_to(lander.global_position)
		# The release tails (rumble 0.25 s, carrier 0.15 s) are allowed one second
		rumble_off_for = rumble_off_for + SAMPLE if (distance > far or not lander.engine_on) else 0.0
		line_closed_for = line_closed_for + SAMPLE if not sound.line_open else 0.0
		if rumble_off_for > 1.0 and sound.rumble_gain > 0.01:
			vacuum_ok = false
			vacuum_detail = "t %.1f dist %.0f engine %s gain %.2f" % [director._clock, distance, lander.engine_on, sound.rumble_gain]
		if line_closed_for > 1.0 and sound.static_gain > 0.01:
			radio_leak = true

	var quiet_run: float = 0.0
	var longest: float = 0.0
	var quietest: float = 0.0
	for level in samples:
		if level < AUDIBLE:
			quiet_run += SAMPLE
			longest = maxf(longest, quiet_run)
		else:
			quiet_run = 0.0
		quietest = minf(quietest, level) if quietest != 0.0 else level
	_check("[levels] the opening was sampled", samples.size() > 100, "%d samples" % samples.size())
	_check("[levels] never silent for long at the default volumes", longest <= MAX_QUIET, "longest quiet %.1f s, quietest %.1f dBFS" % [longest, quietest])
	_check("[levels] the descent rumble is clear and not hot", peak_rumble > -34.0 and peak_rumble < -15.0, "%.1f dBFS mean" % peak_rumble)
	_check("[levels] the thump is strong and its peak stays under -6 dBFS", thump_db >= 12.0 and THUMP_PEAK + thump_db + _bus_db(&"SFX") < -6.0,
		"%.1f dBFS peak" % (THUMP_PEAK + thump_db + _bus_db(&"SFX")))
	_check("[vacuum] no rumble past the structure's reach or with the engine off", vacuum_ok, vacuum_detail)
	_check("[vacuum] the radio carrier is silent between lines", not radio_leak)
	_check("[events] one thump, then the hatch starts and stops", events.count("thump") == 1 and events.count("hatch_start") == 1
		and events.count("hatch_stop") == 1 and events.find("thump") < events.find("hatch_start") and events.find("hatch_start") < events.find("hatch_stop"), str(events))
	print("RESULT test_cutscene_sound %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
