extends SceneTree
## Headless test: the cutscene system (CutsceneDirector, res/story/cutscenes.json) and the walk-in.
##   1. Data: no problems; cutscene lines are only in cutscenes.json.
##   2. Opening, skipped: plays on a new campaign (CUTSCENE, its camera, letterbox, title card,
##      trigger lines held), input blocked, a short hold doesn't skip, a 1 s hold does: end states
##      applied (player at the hatch, lander landed, engine off), marked played, player state back.
##   3. Walk-in: arrival mode (curtain off, bay door opens for the player outside), guidance and the
##      on-foot waypoint on the bay door, the tip at the hatch, m1.workshop_entered only once inside.
##   4. Load: cutscenes_played saved; loading never replays the opening.
##   5. IRIS: m2.iris_activated plays it from the rover, input blocked, pause returns to it, the
##      robot state and camera restored after, never twice.
##   6. Opening, played through (a second campaign): every line once, in order, then the held line.
##   7. Layout at five window sizes: the title card and its caption inside the safe margins, the
##      longest line inside the bottom bar, clear of the skip key.
##   8. Ending, started on foot: the full astronaut stands in where the player is.
##   9. Opening, played through: the plume starts only below 10 m and stops at engine cutoff; the
##      radio clicks on and off for every line, one touchdown thump; the music down by touchdown and
##      back after.
##   10. Gameplay lines on foot (a direct line arriving during a radio line, then one alone): one line
##      at a time, the direct one after the radio line; the HUD's backing shows only with them.
##   Throughout: no subtitle backing is ever visible while its text is empty or transparent, nor
##   more opaque than its text, and a cutscene's subtitles have no backing at all;
##   the cutscene camera never under the terrain (+0.9 m) nor inside the lander;
##   during every cutscene at most one line is on screen (and playing), always inside
##   the bottom bar; the player's first-person body is never visible to a cutscene camera.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_cutscenes.gd

var GS: Node
var SL: Node
var CS: Node
var DS: Node
var DT: Node
var SI: GDScript
var failures: int = 0
var played: Array[String] = []
const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1024, 640),
]
var watch: Dictionary = {"frames": 0, "most_shown": 0, "most_playing": 0, "outside": 0, "outside_at": "", "body_seen": 0, "camera_frames": 0}
var line_times: Array = []
var cam: Dictionary = {"frames": 0, "low": 0, "low_at": "", "inside": 0, "inside_at": ""}
var plume: Dictionary = {"first_on_altitude": -1.0, "on_above_10": 0, "on_after_cutoff": 0, "frames_on": 0, "engine_was_on": false, "off_at_cutoff": false}
var music_at_touchdown: float = 0.0
var backing: Dictionary = {"frames": 0, "cutscene_frames": 0, "gameplay_frames": 0, "empty": 0, "cutscene_backing": 0, "at": "", "gameplay_most": 0}


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-66s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * 240):
		await physics_frame


func _wait(condition: Callable, seconds: float = 120.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if condition.call():
			return true
		await process_frame
	return false


func _clear_dir() -> void:
	var dir: String = SI.save_dir()
	if DirAccess.dir_exists_absolute(dir):
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))


func _cutscenes() -> Node:
	return SL.current_scene.get_node("MissionDirector/Cutscenes")


func _new_campaign(slot: String) -> bool:
	CS.reset()
	SI.start_new_campaign(slot)
	return await _wait(_in_moon_level)


func _in_moon_level() -> bool:
	return SL.current_level_id == "moon_level" and SL.loading_scene_id.is_empty() \
		and (GS.state == GS.State.CUTSCENE or GS.state == GS.State.IN_GAME_PLAYER)


func _run() -> void:
	await process_frame
	load("res://src/cutscene/cutscene_director.gd").autoplay = true
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	DS = root.get_node("DialogServer")
	DT = root.get_node("DialogueTriggers")
	SI = load("res://src/save/save_index.gd")
	DS.dialog_played.connect(func(dialog: Dialog) -> void: played.append(dialog.subtitle))
	if not await _wait(func() -> bool: return GS.state == GS.State.MAIN_MENU):
		_check("main menu comes up", false)
		_finish()
		return
	_clear_dir()
	var screen = root.get_node("Main").find_child("CutsceneScreen", true, false)
	process_frame.connect(_watch_lines.bind(screen))
	process_frame.connect(_watch_backing.bind(screen))
	DS.dialog_played.connect(func(_d) -> void: line_times.append(["start", _clock(), GS.cutscene_active]))
	DS.dialog_ended.connect(func(_d) -> void: line_times.append(["end", _clock(), GS.cutscene_active]))

	# 1. Data
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://res/story/cutscenes.json"))
	var shared: Array = data["lines"].keys().filter(func(id: String) -> bool: return DT.lines.has(id))
	var trigger_lines: Array = DT.triggers.map(func(t: Dictionary) -> String: return t["line"])
	_check("[data] cutscene lines are not in lines.json or the triggers", shared.is_empty()
		and not data["lines"].keys().any(func(id: String) -> bool: return id in trigger_lines), str(shared))
	_check("[data] the nine approved opening lines and the two narrator placeholders are there", data["lines"].size() == 11
		and data["lines"].keys().all(func(id: String) -> bool: return id.begins_with("cs_open_"))
		and data["lines"].keys().filter(func(id: String) -> bool: return data["lines"][id].get("placeholder", false)) == ["cs_open_n1", "cs_open_n2"])

	# 2. Opening, skipped
	if not await _new_campaign("slot_1"):
		_check("[opening] the Moon level comes up", false)
		_finish()
		return
	var level: Node = SL.current_scene
	var cutscenes = _cutscenes()
	var lander = level.get_node("Lander")
	var lander_rest: Vector3 = cutscenes._rest["Lander"].origin
	var workshop = level.get_node("Workshop")
	var rover = level.get_node("ReadyRover")
	_check("[data] the director reports no problems", cutscenes.problems().is_empty(), str(cutscenes.problems()))
	_check("[opening] a new campaign plays the opening", GS.state == GS.State.CUTSCENE and cutscenes.playing_id == "opening"
		and CS.is_cutscene_played("opening"))
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	_check("[opening] its camera is current, the player's input off", camera != null and camera.name == "CutsceneCamera"
		and not GS.player.controller.is_input_enabled() and not rover.controller.is_input_enabled())
	await _ticks(2.0)
	_check("[opening] letterbox and the title card on black", screen.visible and screen.bars > 0.99
		and screen.black.color.a > 0.99 and screen.title_label.text == "SURFACE RESEARCH PROGRAMME"
		and screen.title_label.modulate.a > 0.5, "%.2f %.2f" % [screen.bars, screen.black.color.a])
	_check("[opening] the hold-to-skip key shows", screen.skip_box.visible and screen.skip_box.modulate.a > 0.0)
	_check("[opening] the trigger line for m1 waits", DT.hold and not played.has(DT.lines["mira_m1_01"]["text"]))
	var start_position: Vector3 = GS.player.global_position
	Input.action_press(&"move_forward")
	Input.action_press(&"move_jump")
	await _ticks(0.5)
	Input.action_release(&"move_forward")
	Input.action_release(&"move_jump")
	_check("[input] the player doesn't move during a cutscene", GS.player.global_position.distance_to(start_position) < 0.05,
		str(GS.player.global_position.distance_to(start_position)))
	Input.action_press(&"cutscene_skip")
	await _ticks(0.6)
	Input.action_release(&"cutscene_skip")
	await _ticks(0.1)
	_check("[skip] a 0.6 s hold doesn't skip, the line empties", cutscenes.is_playing() and not cutscenes.skipped
		and screen.skip_fill.size.x == 0.0)
	Input.action_press(&"cutscene_skip")
	await _ticks(0.5)
	_check("[skip] holding fills the line", screen.skip_fill.size.x > 0.3 * screen.SKIP_WIDTH and screen.skip_box.modulate.a == 1.0,
		str(screen.skip_fill.size.x))
	await _ticks(0.7)
	_check("[skip] a 1 s hold skips", cutscenes.skipped)
	await _ticks(0.5)
	_check("[skip] it waits for the key to be let go", cutscenes.is_playing() and GS.state == GS.State.CUTSCENE)
	Input.action_release(&"cutscene_skip")
	await _ticks(1.0)
	var hatch: Vector3 = lander.hatch.global_position
	var flat := func(v: Vector3) -> Vector3: return Vector3(v.x, 0.0, v.z)
	_check("[skip] the player's state, camera and input are back", GS.state == GS.State.IN_GAME_PLAYER
		and root.get_viewport().get_camera_3d() == GS.player.camera and GS.player.controller.is_input_enabled()
		and not GS.cutscene_active and not cutscenes.is_playing())
	_check("[skip] end states: player at the hatch, lander landed, engine off, ramp down", flat.call(GS.player.global_position).distance_to(flat.call(hatch)) < 0.5
		and lander.global_position.is_equal_approx(lander_rest) and not lander.engine_on and not lander.engine_glow.visible and lander.is_deployed(),
		"%.2f m" % flat.call(GS.player.global_position).distance_to(flat.call(hatch)))
	_check("[skip] still marked played, the cutscene camera gone", CS.is_cutscene_played("opening")
		and level.get_node_or_null("CutsceneCamera") == null)
	await _wait(func() -> bool: return not DT.hold, 10.0)
	_check("[skip] the hold ends, the cut opening lines don't play, mira_m1_01 waits for the walk-in", not DT.hold
		and not played.has(data["lines"]["cs_open_09"]["text"]) and not played.has(DT.lines["mira_m1_01"]["text"])
		and not CS.is_objective_done("m1.workshop_entered"), "hold %s, played %s" % [DT.hold, str(played)])
	await _ticks(0.8)
	_check("[skip] the screen is gone", not screen.visible)

	# 3. Walk-in
	_check("[arrival] m1.workshop_entered is current, arrival mode on", CS.current_objective() == "m1.workshop_entered"
		and workshop.arrival and workshop.curtain.collision_layer == 0)
	var guidance = level.get_node("Guidance")
	await _ticks(0.3)
	_check("[arrival] guidance: the bay door, a waypoint on foot", guidance.target != null and guidance.target.name == "bay_door"
		and guidance.is_waypoint() and guidance.overlay.marker.visible, str(guidance.target))
	_check("[arrival] the marker counts metres from the player", guidance.overlay.marker_text().begins_with("Workshop")
		and not guidance.overlay.marker_text().ends_with(" 0 m"), guidance.overlay.marker_text())
	var tips = root.get_node("Main").find_child("HUD", true, false).tips
	_check("[arrival] the walk-in tip was shown at the hatch, before the workshop", CS.is_tip_shown("on_foot")
		and not workshop.contains(GS.player.global_position), str(tips.tip))
	GS.player.global_position = workshop.to_global(Vector3(-1.0, 0.6, -6.0))
	GS.player.linear_velocity = Vector3.ZERO
	await _ticks(1.5)
	_check("[arrival] outside the door: not entered, the bay door opens", not CS.is_objective_done("m1.workshop_entered")
		and workshop.door_open > 0.3, "%.2f" % workshop.door_open)
	GS.player.global_position = workshop.to_global(Vector3(-1.0, 0.3, 0.0))
	GS.player.linear_velocity = Vector3.ZERO
	await _ticks(0.3)
	_check("[arrival] inside: m1.workshop_entered, then the battery", CS.is_objective_done("m1.workshop_entered")
		and CS.current_objective() == "m1.kite_prepared")
	_check("[arrival] arrival off: the curtain holds again", not workshop.arrival
		and workshop.curtain.collision_layer == 1 << (workshop.PLAYER_BARRIER_LAYER - 1))
	await _wait(func() -> bool: return played.has(DT.lines["mira_m1_01"]["text"]), 20.0)
	_check("[arrival] entering the workshop, after a skipped opening, plays mira_m1_01",
		played.has(DT.lines["mira_m1_01"]["text"]) and CS.is_trigger_played("objective:m1.workshop_entered|mira_m1_01"))

	# 4. Load
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SI.slot_path("slot_1")))
	_check("[save] cutscenes_played is saved", saved is Dictionary and saved["campaign"]["cutscenes_played"] == ["opening"])
	CS.reset()
	_check("[load] load_slot starts", SI.load_slot("slot_1"))
	if not await _wait(func() -> bool: return GS.state == GS.State.IN_GAME_PLAYER and SL.loading_scene_id.is_empty()):
		_check("[load] the level comes up", false)
		_finish()
		return
	await _ticks(1.0)
	_check("[load] the opening doesn't replay", GS.state == GS.State.IN_GAME_PLAYER and not _cutscenes().is_playing()
		and CS.is_cutscene_played("opening") and not DT.hold)
	var reload: Dictionary = CS.save_state()
	reload["cutscenes_played"] = []
	CS.load_state(reload)
	_check("[load] a save without the list loads, nothing played", not CS.is_cutscene_played("opening"))
	CS.mark_cutscene_played("opening")

	# 5. IRIS
	level = SL.current_scene
	cutscenes = _cutscenes()
	rover = level.get_node("ReadyRover")
	var debug: Node = root.get_node("Debug")
	debug.parse_command("startmission m2")
	for id in ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed"]:
		debug.parse_command("objective " + id)
	GS.drive(rover)
	await _ticks(0.3)
	var rover_camera: Camera3D = root.get_viewport().get_camera_3d()
	debug.parse_command("objective m2.iris_activated")
	debug.parse_command("flag iris_online")
	await _ticks(0.3)
	_check("[iris] m2.iris_activated plays the IRIS cutscene", GS.state == GS.State.CUTSCENE and cutscenes.playing_id == "iris_online"
		and root.get_viewport().get_camera_3d().name == "CutsceneCamera")
	_check("[iris] the rover takes no input", not rover.controller.is_input_enabled() and not GS.player.controller.is_input_enabled())
	var iris: Node3D = level.get_node("Iris")
	var iris_camera: Camera3D = root.get_viewport().get_camera_3d()
	var indicator: Node3D = iris.highlight_node
	var dish: Node3D = iris.find_child("iris_antenna_dish", true, false)
	_check("[iris] the camera frames the indicator and the antenna, close", iris_camera.is_position_in_frustum(indicator.global_position)
		and iris_camera.is_position_in_frustum(dish.global_position) and iris_camera.global_position.distance_to(indicator.global_position) < 7.0
		and iris.is_online, "%.1f m" % iris_camera.global_position.distance_to(indicator.global_position))
	var iris_cutscenes = cutscenes
	var antenna_tracked: Array = [false]
	var earth_seen: Array = [false]
	var earth_dir: Vector3 = level.get("earth_direction").normalized()
	var watch_iris := func() -> void:
		var c: Camera3D = root.get_viewport().get_camera_3d()
		if iris_cutscenes.playing_id != "iris_online" or c == null or c.name != "CutsceneCamera":
			return
		if iris.antenna_pose().is_equal_approx(iris.ANTENNA_TRACKED) and c.is_position_in_frustum(dish.global_position):
			antenna_tracked[0] = true
			if c.is_position_in_frustum(c.global_position + earth_dir * 1000.0):
				earth_seen[0] = true
	process_frame.connect(watch_iris)
	var time_before: float = cutscenes.time
	GS.change_state_to(GS.State.PAUSED)
	await _ticks(1.0)
	_check("[pause] the cutscene stops while paused", absf(cutscenes.time - time_before) < 0.6, "%.2f" % (cutscenes.time - time_before))
	GS.return_to_game()
	await _ticks(0.2)
	_check("[pause] resume returns to the cutscene", GS.state == GS.State.CUTSCENE)
	await _wait(func() -> bool: return not cutscenes.is_playing(), 30.0)
	process_frame.disconnect(watch_iris)
	_check("[iris] the antenna seen locked on, then Earth behind it in one frame", antenna_tracked[0] and earth_seen[0],
		"tracked %s, earth %s" % [antenna_tracked[0], earth_seen[0]])
	await _ticks(0.2)
	_check("[iris] the robot state and its camera are back", GS.state == GS.State.IN_GAME_ROBOT and GS.robot == rover
		and root.get_viewport().get_camera_3d() == rover_camera and rover.controller.is_input_enabled())
	CS.objective_completed.emit("m2.iris_activated")
	await _ticks(0.3)
	_check("[iris] it never plays twice", GS.state == GS.State.IN_GAME_ROBOT and not cutscenes.is_playing())

	# 6. Opening, played through
	SL.load_scene("main_menu")
	await _wait(func() -> bool: return GS.state == GS.State.MAIN_MENU)
	played.clear()
	if not await _new_campaign("slot_2"):
		_check("[full] the Moon level comes up", false)
		_finish()
		return
	cutscenes = _cutscenes()
	line_times.clear()
	process_frame.connect(_watch_plume)
	var sound = cutscenes.sound
	var lander_node: Node = SL.current_scene.get_node("Lander")
	lander_node.touched_down.connect(func() -> void: music_at_touchdown = root.get_node("AudioManager").music_player.volume_db)
	var length: float = cutscenes.duration("opening")
	_check("[full] the opening is 60 to 90 s", length >= 60.0 and length <= 90.0, "%.1f s" % length)
	var hatch_start: float = length - 8.0
	await _wait(func() -> bool: return cutscenes.time >= hatch_start + 7.6 or not cutscenes.is_playing(), 240.0)
	var stand_in: Node3D = cutscenes.stand_in
	var marker: Node3D = SL.current_scene.get_node("Lander/Hatch")
	var helmet: GeometryInstance3D = stand_in.find_child("astronaut_helmet", true, false) if stand_in else null
	_check("[full] the hatch shot ends on the full astronaut, stepped out to the porch", stand_in != null and stand_in.visible
		and stand_in.global_position.distance_to(marker.global_position) < 0.05 and helmet != null and helmet.is_visible_in_tree()
		and helmet.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
		str(stand_in.global_position.distance_to(marker.global_position)) if stand_in else "no stand-in")
	var events: Array = sound.events.duplicate() if is_instance_valid(sound) else []
	await _wait(func() -> bool: return not cutscenes.is_playing(), 240.0)
	if is_instance_valid(sound):
		events = sound.events.duplicate()
	process_frame.disconnect(_watch_plume)
	await process_frame
	_check("[plume] starts below 10 m, never above, growing as the lander drops", plume["frames_on"] > 100
		and plume["first_on_altitude"] <= 10.0 and plume["first_on_altitude"] > 8.0 and plume["on_above_10"] == 0, str(plume))
	_check("[plume] stops at engine cutoff, never after", plume["off_at_cutoff"] and plume["on_after_cutoff"] == 0, str(plume))
	_check("[sound] a radio click on and off for each of the 11 lines, one thump", events.count("click_on") == 11
		and events.count("click_off") >= 10 and events.count("thump") == 1, str(events))
	_check("[music] ducked under the descent by touchdown, not silent", music_at_touchdown < -6.0 and music_at_touchdown > -20.0, "%.1f dB" % music_at_touchdown)
	_check("[full] at the cut: the stand-in gone, the player's first-person view and body", cutscenes.stand_in == null
		and root.get_viewport().get_camera_3d() == GS.player.camera and GS.player.get_node("Body").visible)
	var gaps: Array = []
	var shown: float = 0.0
	for i in line_times.size() - 1:
		if line_times[i][0] == "end" and line_times[i + 1][0] == "start" and line_times[i + 1][2]:
			gaps.append(line_times[i + 1][1] - line_times[i][1])
	_check("[timing] the opening's lines run on without holding a shot, gaps under 5 s", cutscenes.held_time < 0.1
		and not gaps.is_empty() and gaps.max() < 5.0, "held %.2f s, gaps %s" % [cutscenes.held_time, str(gaps.map(func(g): return snappedf(g, 0.01)))])
	await _ticks(0.5)
	var order: Array = []
	for shot in data["cutscenes"]["opening"]["shots"]:
		for entry in shot.get("lines", []):
			order.append(entry["id"])
	var texts: Array = order.map(func(id: String) -> String: return data["lines"][id]["text"])
	var own: Array = played.filter(func(text: String) -> bool: return text in texts)
	_check("[full] every opening line played once, in order", own == texts, "%d of %d" % [own.size(), texts.size()])
	_check("[full] not skipped, back to the player at the hatch", not cutscenes.skipped and GS.state == GS.State.IN_GAME_PLAYER
		and Vector3(GS.player.global_position.x, 0, GS.player.global_position.z).distance_to(
			Vector3(SL.current_scene.get_node("Lander/Hatch").global_position.x, 0, SL.current_scene.get_node("Lander/Hatch").global_position.z)) < 0.5)
	_check("[full] mira_m1_01 has not played yet: the player is outside the workshop", not played.has(DT.lines["mira_m1_01"]["text"])
		and not CS.is_objective_done("m1.workshop_entered"))
	var full_workshop: Node3D = SL.current_scene.get_node("Workshop")
	GS.player.global_position = full_workshop.to_global(Vector3(-1.0, 0.3, 0.0))
	GS.player.linear_velocity = Vector3.ZERO
	await _wait(func() -> bool: return played.has(DT.lines["mira_m1_01"]["text"]), 30.0)
	_check("[full] walking into the workshop plays mira_m1_01, after every opening line", CS.is_objective_done("m1.workshop_entered")
		and played.find(DT.lines["mira_m1_01"]["text"]) > played.find(texts.back()))
	var counts: Dictionary = {}
	for text in played:
		counts[text] = counts.get(text, 0) + 1
	_check("[lines] during every cutscene at most one line on screen and playing", watch["frames"] > 1000
		and watch["most_shown"] == 1 and watch["most_playing"] == 1, str(watch))
	_check("[lines] every line inside the bottom bar", watch["outside"] == 0, str(watch["outside_at"]))
	print("RESULT [lines] the opening's shots were held %.1f s for their lines" % cutscenes.held_time)
	_check("[full] no line played twice", counts.values().all(func(n: int) -> bool: return n == 1), str(counts.values()))

	# 8. Ending, on foot
	await _ticks(1.0)
	var player_at: Vector3 = GS.player.global_position
	cutscenes.play("ending", GS.State.IN_GAME_PLAYER)
	await _ticks(0.5)
	_check("[ending] on foot: the full astronaut where the player stands, the body hidden", cutscenes.stand_in != null
		and Vector2(cutscenes.stand_in.global_position.x, cutscenes.stand_in.global_position.z).distance_to(Vector2(player_at.x, player_at.z)) < 0.3
		and not GS.player.get_node("Body").is_visible_in_tree())
	await _wait(func() -> bool: return not cutscenes.is_playing(), 30.0)
	await process_frame
	_check("[cameras] never under the terrain (+0.9 m)", cam["frames"] > 1000 and cam["low"] == 0, "%d of %d %s" % [cam["low"], cam["frames"], cam["low_at"]])
	_check("[cameras] never inside the lander", cam["inside"] == 0, "%d %s" % [cam["inside"], cam["inside_at"]])
	await _ticks(7.0)
	_check("[music] back to its normal level after the cutscenes", root.get_node("AudioManager").music_player.volume_db > -3.0,
		"%.1f dB" % root.get_node("AudioManager").music_player.volume_db)
	_check("[cameras] the first-person body never visible to a cutscene camera", watch["camera_frames"] > 1000 and watch["body_seen"] == 0,
		"%d of %d frames" % [watch["body_seen"], watch["camera_frames"]])
	await _gameplay_lines()
	_check("[backing] never visible while its text is empty or transparent", backing["frames"] > 1000 and backing["empty"] == 0,
		"%d bad of %d frames %s" % [backing["empty"], backing["frames"], backing["at"]])
	_check("[backing] none behind cutscene subtitles", backing["cutscene_frames"] > 1000 and backing["cutscene_backing"] == 0,
		"%d of %d" % [backing["cutscene_backing"], backing["cutscene_frames"]])
	_check("[backing] gameplay lines show it with their text", backing["gameplay_frames"] > 100, str(backing["gameplay_frames"]))
	await _layout_checks(data)
	_finish()


## Lines on foot: a direct line arriving while a radio line is up waits for it, then one alone
func _gameplay_lines() -> void:
	await _wait(func() -> bool: return GS.state == GS.State.IN_GAME_PLAYER and not GS.cutscene_active, 30.0)
	DS.stop_all()
	await _ticks(1.0)
	var sequence := DialogSequence.new()
	sequence.dialogs = [DT.make_dialog({"speaker": "Mira", "text": "Short line one."}),
		DT.make_dialog({"speaker": "Hana", "text": "A second line, a little longer than the first, so the backing changes size."})]
	DS.queue_sequence(sequence)
	await _wait(func() -> bool: return sequence.dialogs[0] in DS._active_dialogs, 30.0)
	var order: Array[Dialog] = []
	var record := func(d: Dialog) -> void: order.append(d)
	DS.dialog_played.connect(record)
	var direct: Dialog = DT.make_dialog({"speaker": "Kite", "text": "Scan report."})
	DS.play_dialog(direct)
	await _wait(func() -> bool: return not DS.is_playing(), 30.0)
	DS.dialog_played.disconnect(record)
	_check("[gameplay] the direct line plays right after the radio line, before the queue's next", order == [direct, sequence.dialogs[1]],
		str(order.map(func(d: Dialog) -> String: return d.subtitle.left(20))))
	await _ticks(2.0)
	DS.play_dialog(DT.make_dialog({"speaker": "Mira", "text": "And one on its own."}))
	await _ticks(8.0)
	_check("[gameplay] never two lines on screen", backing["gameplay_most"] == 1, str(backing["gameplay_most"]))


## Every frame: each subtitle stack's backing against its text, measured from the nodes themselves
func _watch_backing(screen) -> void:
	for stack in root.get_tree().get_nodes_in_group(&"subtitle_stack"):
		if not stack.is_visible_in_tree() or stack.size.y < 0.5:
			continue
		var fill: float = 0.0
		var style: StyleBox = stack.get_theme_stylebox(&"panel")
		if style is StyleBoxFlat:
			fill = (style as StyleBoxFlat).bg_color.a
		fill = maxf(fill, stack.backing_alpha() * stack._backing_color.a)
		var text: float = 0.0
		for box in stack.boxes.get_children():
			if box.is_queued_for_deletion() or not box.visible:
				continue
			var label: RichTextLabel = box.get_node("Content/Column/RichTextLabel")
			if not label.get_parsed_text().strip_edges().is_empty():
				text = maxf(text, box.modulate.a)
		var in_cutscene: bool = stack == screen.subtitles
		if not in_cutscene:
			backing["gameplay_most"] = maxi(backing["gameplay_most"], stack.shown_count())
		backing["frames"] += 1
		if in_cutscene:
			backing["cutscene_frames"] += 1
			if fill > 0.0:
				backing["cutscene_backing"] += 1
		elif fill > 0.01:
			backing["gameplay_frames"] += 1
		if fill > 0.01 and (text < 0.01 or fill > text * 0.8 + 0.01):
			backing["empty"] += 1
			backing["at"] = "%s fill %.2f text %.2f" % [stack.get_path(), fill, text]


## Every frame of a cutscene: how many lines are shown and playing, and whether a shown line
## leaves the bottom bar (once the bars are in)
## The playing cutscene's clock (s)
func _clock() -> float:
	var level: Node = SL.current_scene if SL else null
	var cutscenes: Node = level.get_node_or_null("MissionDirector/Cutscenes") if level else null
	return cutscenes.time if cutscenes else 0.0


func _watch_lines(screen) -> void:
	if GS == null:
		return
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	if camera and camera.name == "CutsceneCamera":
		_watch_camera(camera)
	if camera and camera.name == "CutsceneCamera" and is_instance_valid(GS.player):
		watch["camera_frames"] += 1
		if GS.player.get_node("Body").is_visible_in_tree():
			watch["body_seen"] += 1
	if not GS.cutscene_active or not screen.visible:
		return
	watch["frames"] += 1
	watch["most_shown"] = maxi(watch["most_shown"], screen.subtitles.shown_count())
	watch["most_playing"] = maxi(watch["most_playing"], DS._active_dialogs.size())
	if screen.bars < 0.999:
		return
	var bar: Rect2 = screen.bottom_bar_rect().grow(0.5)
	for box in screen.subtitles.boxes.get_children():
		if box.visible and not bar.encloses(box.get_global_rect()):
			watch["outside"] += 1
			watch["outside_at"] = "%s in %s" % [box.get_global_rect(), bar]


## The camera against the terrain and the lander's collision (a 0.2 m sphere)
func _watch_camera(camera: Camera3D) -> void:
	var level: Node = SL.current_scene
	var terrain: Node = level.get_node_or_null("Terrain") if level else null
	var lander: Node3D = level.get_node_or_null("Lander") if level else null
	if terrain == null or lander == null:
		return
	cam["frames"] += 1
	var at: Vector3 = camera.global_position
	var clearance: float = at.y - terrain.height_at(at.x, at.z)
	if clearance < 0.9:
		cam["low"] += 1
		cam["low_at"] = "%.2f m at %s, %s" % [clearance, at, _cutscenes().playing_id]
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = 0xFFFFFFFF
	for hit in camera.get_world_3d().direct_space_state.intersect_shape(query, 8):
		if hit["collider"] is Node and lander.is_ancestor_of(hit["collider"]):
			cam["inside"] += 1
			cam["inside_at"] = "%s at %.1f s" % [at, _clock()]
	if lander.get_node("Body") and lander.to_local(at).y < lander.HULL.end.y and lander.HULL.has_point(lander.to_local(at)):
		cam["inside"] += 1
		cam["inside_at"] = "hull box %s at %.1f s" % [lander.to_local(at), _clock()]


func _watch_plume() -> void:
	var level: Node = SL.current_scene
	var lander: Node = level.get_node_or_null("Lander") if level else null
	if lander == null or not GS.cutscene_active:
		return
	var p = lander.plume
	if lander.engine_on:
		plume["engine_was_on"] = true
	if p.rate > 0.0:
		plume["frames_on"] += 1
		if plume["first_on_altitude"] < 0.0:
			plume["first_on_altitude"] = p.altitude
		if p.altitude > 10.0:
			plume["on_above_10"] += 1
		if not lander.engine_on:
			plume["on_after_cutoff"] += 1
	elif plume["engine_was_on"] and not lander.engine_on and plume["frames_on"] > 0 and not plume["off_at_cutoff"]:
		plume["off_at_cutoff"] = true


func _layout_checks(data: Dictionary) -> void:
	var longest: String = ""
	for id in data["lines"]:
		if longest.is_empty() or data["lines"][id]["text"].length() > data["lines"][longest]["text"].length():
			longest = id
	var title: Dictionary = data["cutscenes"]["opening"]["shots"][0]["title"]
	for size in SIZES:
		var view := SubViewport.new()
		view.size = size
		root.add_child(view)
		var screen = load("res://src/ui/cutscene_screen/cutscene_screen.gd").new()
		view.add_child(screen)
		await process_frame
		screen.begin(true)
		screen.set_title(title["text"], title["caption"], 1.0, 1.0)
		DS.stop_all()
		DS.play_dialog(DT.make_dialog(data["lines"][longest]))
		await _ticks(1.2)
		var label := "[layout] %dx%d" % [size.x, size.y]
		var room: float = size.x - 2.0 * screen.safe_margin(size.x)
		for l in [screen.title_label, screen.title_caption]:
			var width: float = l.get_theme_font(&"font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size(&"font_size")).x
			_check("%s %s inside the safe margins" % [label, l.name], width <= room and l.get_global_rect().size.x <= size.x,
				"%.0f of %.0f px, size %d" % [width, room, l.get_theme_font_size(&"font_size")])
		var bar: Rect2 = screen.bottom_bar_rect()
		var shown: Array = screen.subtitles.boxes.get_children()
		var line_rect: Rect2 = screen.subtitles.get_global_rect()
		_check(label + " the longest line inside the bottom bar, clear of the skip key", shown.size() == 1
			and bar.grow(0.5).encloses(shown[0].get_global_rect()) and bar.size.y <= size.y * 0.3
			and not line_rect.intersects(screen.skip_box.get_global_rect()),
			"line %s, bar %s" % [shown[0].get_global_rect() if shown.size() > 0 else "none", bar])
		DS.stop_all()
		view.queue_free()
		await process_frame


func _finish() -> void:
	_clear_dir()
	print("RESULT test_cutscenes %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
