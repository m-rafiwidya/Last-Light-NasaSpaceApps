extends SceneTree
## Plays the opening cutscene in a window, untouched, and reports per shot the frame times (mean,
## p99, worst, frames over 25 / 50 ms with what happened then) and the dialogue: when each line
## starts and ends, its reading time, when its subtitle is on screen and the empty gaps between.
## Then 30 s of play standing at the hatch, as a baseline.
## Needs a window:
##
##     Godot --path game -s res://tools/measure_opening.gd --resolution 1920x1080

var GS: Node
var SL: Node
var DS: Node
var frames: Array = []          # [msec since start, delta ms, shot name, cutscene time]
var events: Array = []          # [msec, text]
var t0: int = 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _log(text: String) -> void:
	events.append([Time.get_ticks_msec() - t0, text])


func _run() -> void:
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	load("res://src/cutscene/cutscene_director.gd").autoplay = true
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	DS = root.get_node("DialogServer")
	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	root.get_node("CampaignState").reset()
	load("res://src/save/save_index.gd").start_new_campaign("slot_3")
	while not (SL.current_level_id == "moon_level" and SL.loading_scene_id.is_empty() and GS.state == GS.State.CUTSCENE):
		await process_frame
	var level: Node = SL.current_scene
	var cutscenes: Node = level.get_node("MissionDirector/Cutscenes")
	var screen: Node = root.get_node("Main").find_child("CutsceneScreen", true, false)
	t0 = Time.get_ticks_msec()
	DS.dialog_played.connect(func(d) -> void: _log("line start  %s (%d chars, reading %.1f s)" % [d.subtitle.left(40), d.subtitle.length(), DS.get_dialog_duration(d)]))
	DS.dialog_ended.connect(func(d) -> void: _log("line end    %s" % d.subtitle.left(40)))
	var shown: int = 0
	var last_shot: String = ""
	var last: int = Time.get_ticks_usec()
	DisplayServer.window_move_to_foreground()
	var compiles: int = _compilations()
	while cutscenes.is_playing():
		await process_frame
		var now: int = Time.get_ticks_usec()
		var shot: String = cutscenes._shot_at(cutscenes.time)["data"]["name"]
		if shot != last_shot:
			_log("shot %s at cutscene %.2f s" % [shot, cutscenes.time])
			last_shot = shot
		var count: int = screen.subtitles.shown_count()
		if count != shown:
			_log("subtitle boxes %d -> %d" % [shown, count])
			shown = count
		var c: int = _compilations()
		frames.append([now / 1000 - t0, (now - last) / 1000.0, shot, cutscenes.time, c - compiles,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
		compiles = c
		last = now
	var end: int = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frames.append([now / 1000 - t0, (now - last) / 1000.0, "gameplay", 0.0, 0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
		last = now
	_report()
	quit(0)


func _compilations() -> int:
	var total: int = 0
	for m in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE,
			Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		total += int(Performance.get_monitor(m))
	return total


func _report() -> void:
	var by_shot: Dictionary = {}
	for f in frames:
		by_shot.get_or_add(f[2], []).append(f[1])
	for shot in by_shot:
		var d: Array = by_shot[shot].duplicate()
		d.sort()
		var mean: float = d.reduce(func(a, b): return a + b, 0.0) / d.size()
		print("SHOT %-12s %5d frames  mean %.1f ms (%.0f fps)  p99 %.1f  worst %.1f  >25ms %d  >50ms %d" % [shot, d.size(), mean,
			1000.0 / mean, d[int(d.size() * 0.99)], d.back(), d.filter(func(x): return x > 25.0).size(), d.filter(func(x): return x > 50.0).size()])
	for f in frames:
		if f[1] > 25.0:
			print("HITCH %6d ms  %.1f ms  in %s at %.2f  pipeline compiles %d  process %.1f ms  physics %.1f ms" % [f[0], f[1], f[2], f[3], f[4], f[5], f[6]])
	var total: int = frames.reduce(func(a, f): return a + f[4], 0)
	print("COMPILES during the opening: %d pipelines, on %d frames" % [total, frames.filter(func(f): return f[4] > 0).size()])
	for e in events:
		print("EVENT %6d ms  %s" % e)
