extends SceneTree
## Headless test: the M2 and M3 downlinks and the campaign ending, driven by the debug console's
## startmission / objective commands (no field interaction scenes needed).
##   1. M2: Receive telemetry is disabled until the dock (the optional sample never blocks it),
##      then shows the telemetry report and completes m2.
##   2. M3: Send archive is disabled until the logger and the dock, then shows the archive report.
##   3. Ending: fires once on m3, IRIS camera cut (no online_changed) with player input off, closing lines, result
##      screen with the right counts, campaign marked complete and saved.
##   4. Load: the completed slot loads into free play without replaying the ending.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_campaign_ending.gd

var GS: Node
var SL: Node
var CS: Node
var DS: Node
var SI: GDScript
var debug: Node
var failures: int = 0
var console: Node
var result: Node
var level: Node
var ending_runs: int = 0
var online_changes: int = 0


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


func _wait_state(state: int, level_id: String = "", seconds: float = 120.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if GS.state == state and (level_id.is_empty() or SL.current_level_id == level_id):
			return true
		await process_frame
	return false


func _clear_dir() -> void:
	var dir: String = SI.save_dir()
	if DirAccess.dir_exists_absolute(dir):
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))


func _cmd(text: String) -> void:
	debug.parse_command(text)


func _action() -> Button:
	return console.get_node("%Action")


func _open_console() -> void:
	if GS.state != GS.State.IN_GAME_PLAYER:
		GS.change_state_to(GS.State.IN_GAME_PLAYER)
		await _ticks(0.2)
	level.get_node("Workshop")._on_console_used(GS.player)
	await _ticks(0.2)
	console.select_section(console.Section.DOWNLINK)


func _attach_level() -> void:
	level = SL.current_scene
	level.get_node("MissionDirector").ending.finished.connect(func() -> void: ending_runs += 1)


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	DS = root.get_node("DialogServer")
	debug = root.get_node("Debug")
	SI = load("res://src/save/save_index.gd")
	console = root.get_node("Main").find_child("MissionConsole", true, false)
	result = root.get_node("Main").find_child("CampaignResult", true, false)
	if not await _wait_state(GS.State.MAIN_MENU):
		_check("main menu comes up", false)
		_finish()
		return
	_clear_dir()
	CS.reset()
	SI.start_new_campaign("slot_1")
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("the Moon level comes up", false)
		_finish()
		return
	_attach_level()
	await _ticks(1.0)

	# 1. M2 telemetry
	_cmd("startmission m2")
	await _open_console()
	_check("[m2] Receive telemetry is shown but disabled at the start", _action().visible and _action().disabled
		and _action().text == "Receive telemetry", _action().text)
	for id in ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed", "m2.iris_activated"]:
		_cmd("objective " + id)
	var iris: Node = level.get_node("Iris")
	var flag_changes: Array = []
	iris.online_changed.connect(func(online: bool) -> void: flag_changes.append(online))
	_cmd("flag iris_online")
	_check("[iris] setting iris_online brings IRIS online live, once", iris.is_online and flag_changes == [true], str(flag_changes))
	CS.flag_changed.emit("iris_online", true)
	_check("[iris] a flag_changed matching IRIS's state doesn't call set_online", flag_changes == [true], str(flag_changes))
	iris.online_changed.connect(func(_online: bool) -> void: online_changes += 1)
	console.refresh()
	_check("[m2] still disabled after IRIS is active but Kite isn't docked", _action().disabled)
	_cmd("objective m2.kite_docked")
	console.refresh()
	_check("[m2] enabled once docked, with the optional sample not done", not _action().disabled
		and not CS.is_objective_done("m2.near_sample_collected"))
	console._on_action_pressed()
	await _ticks(0.5)
	_check("[m2] the progress bar shows while receiving", console.get_node("%DownlinkProgress").visible
		and console.get_node("%Description").text.contains("Receiving"), console.get_node("%Description").text)
	await _ticks(console.DOWNLINK_TIME)
	var report: String = console.get_node("%Description").text
	_check("[m2] telemetry received, m2 complete", CS.is_objective_done("m2.telemetry_received") and CS.is_mission_completed("m2"))
	_check("[m2] the report: IRIS live again, a missing field logger", report.contains("transmitting")
		and report.contains("field logger"), report)
	_check("[m2] no attachment image under the M2 report", console.get_node("%Attachments").get_child_count() == 0)
	_check("[m2] the ending doesn't fire for m2", ending_runs == 0 and not CS.is_campaign_complete())

	var director: Node = level.get_node("MissionDirector")
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	director._start_recovery()
	await _ticks(director.RECOVERY_DELAY + 0.5)
	_check("[recovery] an emergency recovery is counted", CS.recoveries == 1, str(CS.recoveries))

	# 2. M3 archive
	_cmd("startmission m3")
	await _open_console()
	_check("[m3] Send archive is disabled at the start", _action().visible and _action().disabled
		and _action().text == "Send archive", _action().text)
	_cmd("objective m3.logger_recovered")
	console.refresh()
	_check("[m3] still disabled before the dock", _action().disabled)
	_cmd("objective m3.kite_docked")
	console.refresh()
	_check("[m3] enabled once the logger is in and Kite docked", not _action().disabled)
	var play_time_before: float = CS.play_time_sec
	console._on_action_pressed()
	await _ticks(console.DOWNLINK_TIME + 0.1)
	_check("[m3] archive sent, m3 complete", CS.is_objective_done("m3.archive_sent") and CS.is_mission_completed("m3"))
	console.select_section(console.Section.DOWNLINK)
	report = console.get_node("%Description").text
	_check("[m3] the report: archive complete with the earlier crew's last record",
		report.contains("archive is complete") and report.contains("earlier crew"), report)

	# 3. Ending
	_check("[ending] the campaign is marked complete", CS.is_campaign_complete())
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SI.slot_path("slot_1")))
	_check("[ending] and saved", saved is Dictionary and "campaign_complete" in saved["campaign"]["flags"])
	await _ticks(0.3)
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	_check("[ending] the IRIS camera cut is current, input off", camera != null and camera.name == "EndingCamera"
		and GS.state == GS.State.IN_GAME_MENU and not GS.player.controller.is_input_enabled(), str(camera))
	_check("[ending] a caption over the cut", result.get_node("%Caption").visible)
	await _ticks(2.0)
	_check("[ending] the cut frames IRIS running, online and antenna tracked", iris.is_online
		and iris.antenna_pose().is_equal_approx(iris.ANTENNA_TRACKED), str(iris.antenna_pose()))
	var lines: Array = director.ending.closing_lines()
	_check("[ending] closing lines come from the dialogue data or the fallback", lines.size() >= 2
		and lines[0].speaker == "Hana" and lines[1].speaker == "Mira", str(lines.map(func(l) -> String: return l.speaker)))
	var start: int = Time.get_ticks_msec()
	while GS.state != GS.State.IN_GAME_PLAYER and Time.get_ticks_msec() - start < 20000:
		await process_frame
	await _ticks(0.3)
	_check("[ending] back to the player for the lines", GS.state == GS.State.IN_GAME_PLAYER
		and root.get_viewport().get_camera_3d() == GS.player.camera)
	_check("[ending] DialogServer plays the closing lines", DS.is_playing())
	_check("[ending] the result screen waits for the lines", not result.is_open())
	start = Time.get_ticks_msec()
	while not result.is_open() and Time.get_ticks_msec() - start < 60000:
		await process_frame
	_check("[result] the result screen opens after the lines", result.is_open() and GS.state == GS.State.IN_GAME_MENU
		and not DS.is_playing())
	var summary: Dictionary = result.summary()
	_check("[result] missions completed: m2 and m3", Array(summary["missions"]) == ["m2", "m3"], str(summary["missions"]))
	_check("[result] the near sample is listed as skipped", Array(summary["optional_skipped"]) == ["m2.near_sample_collected"]
		and summary["optional_done"].is_empty(), str(summary))
	_check("[result] one emergency recovery, play time counted", summary["recoveries"] == 1
		and summary["play_time_sec"] >= int(play_time_before), str(summary))
	var text: String = result.get_node("%Summary").text
	_check("[result] the text lists skipped tasks, recoveries and Mars", text.contains("skipped")
		and text.contains("Emergency recoveries[/b]  1") and text.contains("Mars"), text)
	_check("[ending] ran once", ending_runs == 1, str(ending_runs))
	_check("[ending] IRIS's online_changed never fired", online_changes == 0 and iris.is_online, str(online_changes))
	CS.mission_completed.emit("m3")
	CS.complete_objective("m3.archive_sent")
	await _ticks(1.0)
	_check("[ending] doesn't fire again", ending_runs == 1 and result.is_open())
	result.get_node("%Continue").pressed.emit()
	await _ticks(0.8)
	_check("[result] Continue returns to the workshop", GS.state == GS.State.IN_GAME_PLAYER and not result.visible)

	# 4. Load
	result.get_node("%MainMenu").pressed.emit()
	await _wait_state(GS.State.MAIN_MENU)
	CS.reset()
	ending_runs = 0
	_check("[load] load_slot starts loading", SI.load_slot("slot_1"))
	if not await _wait_state(GS.State.IN_GAME_PLAYER, "moon_level"):
		_check("[load] the Moon level comes up", false)
		_finish()
		return
	_attach_level()
	await _ticks(3.0)
	_check("[load] the campaign is complete, free play in the workshop", CS.is_campaign_complete()
		and GS.state == GS.State.IN_GAME_PLAYER and not result.visible)
	_check("[load] the ending didn't replay", ending_runs == 0 and not level.get_node("MissionDirector").ending.playing)
	_check("[load] IRIS is online", level.get_node("Iris").is_online)
	_check("[load] recoveries kept", CS.recoveries == 1)
	level.get_node("Workshop")._on_console_used(GS.player)
	await _ticks(0.2)
	console.select_section(console.Section.MISSION)
	_check("[load] the console shows free play", console.get_node("%Title").text.contains("Campaign complete")
		and not _action().visible, console.get_node("%Title").text)
	_finish()


func _finish() -> void:
	_clear_dir()
	print("RESULT test_campaign_ending %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
