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

	# 1. Data
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://res/story/cutscenes.json"))
	var shared: Array = data["lines"].keys().filter(func(id: String) -> bool: return DT.lines.has(id))
	var trigger_lines: Array = DT.triggers.map(func(t: Dictionary) -> String: return t["line"])
	_check("[data] cutscene lines are not in lines.json or the triggers", shared.is_empty()
		and not data["lines"].keys().any(func(id: String) -> bool: return id in trigger_lines), str(shared))
	_check("[data] every line approved for the opening is there", data["lines"].size() == 9
		and data["lines"].keys().all(func(id: String) -> bool: return id.begins_with("cs_open_")))

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
	_check("[skip] end states: player at the hatch, lander landed, engine off", flat.call(GS.player.global_position).distance_to(flat.call(hatch)) < 0.5
		and lander.global_position.is_equal_approx(lander_rest) and not lander.engine_on and not lander.engine_glow.visible,
		"%.2f m" % flat.call(GS.player.global_position).distance_to(flat.call(hatch)))
	_check("[skip] still marked played, the cutscene camera gone", CS.is_cutscene_played("opening")
		and level.get_node_or_null("CutsceneCamera") == null)
	await _wait(func() -> bool: return played.has(DT.lines["mira_m1_01"]["text"]), 10.0)
	_check("[skip] the held trigger line plays after", not DT.hold and played.has(DT.lines["mira_m1_01"]["text"]))
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
	var view: Vector3 = -root.get_viewport().get_camera_3d().global_basis.z
	var to_iris: Vector3 = (iris.global_position + Vector3.UP * 1.6 - root.get_viewport().get_camera_3d().global_position).normalized()
	_check("[iris] the camera frames IRIS", view.dot(to_iris) > 0.99, "%.3f" % view.dot(to_iris))
	var time_before: float = cutscenes.time
	GS.change_state_to(GS.State.PAUSED)
	await _ticks(1.0)
	_check("[pause] the cutscene stops while paused", absf(cutscenes.time - time_before) < 0.6, "%.2f" % (cutscenes.time - time_before))
	GS.return_to_game()
	await _ticks(0.2)
	_check("[pause] resume returns to the cutscene", GS.state == GS.State.CUTSCENE)
	await _wait(func() -> bool: return not cutscenes.is_playing(), 30.0)
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
	var length: float = cutscenes.duration("opening")
	_check("[full] the opening is 60 to 90 s", length >= 60.0 and length <= 90.0, "%.1f s" % length)
	await _wait(func() -> bool: return not cutscenes.is_playing(), 240.0)
	await _ticks(0.5)
	var texts: Array = data["lines"].keys().map(func(id: String) -> String: return data["lines"][id]["text"])
	var own: Array = played.filter(func(text: String) -> bool: return text in texts)
	_check("[full] every opening line played once, in order", own == texts, "%d of %d" % [own.size(), texts.size()])
	_check("[full] not skipped, back to the player at the hatch", not cutscenes.skipped and GS.state == GS.State.IN_GAME_PLAYER
		and Vector3(GS.player.global_position.x, 0, GS.player.global_position.z).distance_to(
			Vector3(SL.current_scene.get_node("Lander/Hatch").global_position.x, 0, SL.current_scene.get_node("Lander/Hatch").global_position.z)) < 0.5)
	await _wait(func() -> bool: return played.has(DT.lines["mira_m1_01"]["text"]), 30.0)
	_check("[full] the held trigger line plays after the opening", played.back() == DT.lines["mira_m1_01"]["text"]
		or played.find(DT.lines["mira_m1_01"]["text"]) > played.find(texts.back()))
	var counts: Dictionary = {}
	for text in played:
		counts[text] = counts.get(text, 0) + 1
	_check("[full] no line played twice", counts.values().all(func(n: int) -> bool: return n == 1), str(counts.values()))
	_finish()


func _finish() -> void:
	_clear_dir()
	print("RESULT test_cutscenes %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
