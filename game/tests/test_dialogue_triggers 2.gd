extends SceneTree
## DialogueTriggers and the DialogServer queue:
##   1. Data: every trigger names an existing line and a real mission or objective event.
##   2. Queued sequences play one line at a time, in order; a direct play_dialog line stacks beside them.
##   3. Each trigger fires once; events fired outside a level wait for one.
##   4. Played triggers survive save_state/load_state, which emits nothing, and never replay.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_dialogue_triggers.gd

var CS: Node
var DS: Node
var DT: Node
var GS: Node
var failures: int = 0
var played: Array[Dialog] = []
var max_active: int = 0
var active: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-66s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _seconds(seconds: float) -> void:
	await create_timer(seconds, false).timeout


func _run() -> void:
	await process_frame
	CS = root.get_node("CampaignState")
	DS = root.get_node("DialogServer")
	DT = root.get_node("DialogueTriggers")
	GS = root.get_node("GameState")
	DS.dialog_played.connect(func(dialog: Dialog) -> void:
		played.append(dialog)
		active += 1
		max_active = maxi(max_active, active))
	DS.dialog_ended.connect(func(_dialog: Dialog) -> void: active -= 1)

	# --- 1. data ------------------------------------------------------------------------------
	_check("[data] triggers and lines load", DT.triggers.size() > 0 and DT.lines.size() > 0,
		"%d triggers, %d lines" % [DT.triggers.size(), DT.lines.size()])
	_check("[data] every trigger names an existing line and a real event", DT.problems().is_empty(), str(DT.problems()))
	_check("[data] a bad event or line is reported", not DT.is_real_event("objective:m9.nope")
		and not DT.is_real_event("mission_started:m9") and not DT.is_real_event("docked:m1")
		and DT.is_real_event("objective:m1.iris_scanned") and DT.is_real_event("mission_completed:m3"))
	var dialog: Dialog = DT.make_dialog({"speaker": "Mira", "text": "Hello there.", "audio": "res://res/audio/voice/missing.ogg"})
	_check("[data] a line without its audio file is subtitle only", dialog.audio_stream == null
		and dialog.get_display_text() == "Mira: Hello there.")
	var voiced := Dialog.new()
	voiced.subtitle = "A long line that would take a while to read on screen, much longer than its audio."
	var tone := AudioStreamWAV.new()
	var samples := PackedByteArray()
	samples.resize(22050 * 2)
	tone.mix_rate = 22050
	tone.data = samples
	voiced.audio_stream = tone
	voiced.min_duration = 0.0
	_check("[data] a voiced line lasts as long as its audio", tone.get_length() > 1.0
		and is_equal_approx(DS.get_dialog_duration(voiced), tone.get_length()),
		str(DS.get_dialog_duration(voiced)))

	# --- 3a. outside a level: held --------------------------------------------------------------
	CS.reset()
	CS.start_mission("m1")
	_check("[hold] a line fired outside a level is marked played but waits", CS.is_trigger_played("mission_started:m1|mira_m1_01")
		and not DS.is_playing() and DT.sequence_for("mission_started:m1") != null)
	GS.player = load("res://src/player/player.gd").new()
	root.get_node("SceneLoader").level_loaded.emit("test")
	_check("[hold] it plays once a level is loaded", DS.is_playing() and played.size() == 1
		and played[0].subtitle == DT.lines["mira_m1_01"]["text"])
	DS.stop_all()
	played.clear()
	active = 0

	# --- 2. queue -----------------------------------------------------------------------------
	CS.complete_objective("m1.kite_prepared")
	CS.complete_objective("m1.iris_scanned")
	CS.complete_objective("m1.kite_docked")
	_check("[queue] three events queue three sequences, one line plays", played.size() == 1 and active == 1)
	var scan := Dialog.new()
	scan.speaker = "Rover"
	scan.subtitle = "Scan report."
	DS.play_dialog(scan)
	_check("[queue] a direct line plays at once beside the radio line", active == 2 and played.back() == scan)
	var hud: Node = load("res://src/ui/subtitle_stack/subtitle_stack.tscn").instantiate()
	root.add_child(hud)
	DS.stop_all()
	played.clear()
	active = 0
	max_active = 0
	CS.reset()
	CS.start_mission("m1")
	CS.complete_objective("m1.kite_prepared")
	CS.complete_objective("m1.iris_scanned")
	await process_frame
	DS.play_dialog(scan)
	await process_frame
	_check("[stack] the radio line and the direct line are both boxes in the SubtitleStack",
		hud.get_node("Boxes").get_child_count() == 2 and hud.dialog_boxes.size() == 2)
	DS.stop_all()
	played.clear()
	active = 0
	max_active = 0
	hud.queue_free()

	CS.reset()
	CS.start_mission("m1")
	CS.complete_objective("m1.kite_prepared")
	CS.complete_objective("m1.iris_scanned")
	CS.complete_objective("m1.kite_docked")
	var start: int = Time.get_ticks_msec()
	while DS.is_playing() and Time.get_ticks_msec() - start < 60000:
		await process_frame
	var order := played.map(func(d: Dialog) -> String: return d.subtitle)
	var expected := ["mira_m1_01", "mira_m1_02", "hana_m1_01", "mira_m1_03"].map(
		func(id: String) -> String: return DT.lines[id]["text"])
	_check("[queue] lines play in order, all of them", order == expected, str(order.size()))
	_check("[queue] never two queued lines at once", max_active == 1, str(max_active))

	# --- 3b. once -----------------------------------------------------------------------------
	played.clear()
	CS.start_mission("m1")
	DT.fire("objective:m1.kite_prepared")
	await process_frame
	_check("[once] a fired trigger never fires again", played.is_empty() and not DS.is_playing())

	# --- 4. save / load -----------------------------------------------------------------------
	var saved: Dictionary = CS.save_state()
	_check("[save] played triggers are saved", Array(saved["triggers_played"]).has("objective:m1.iris_scanned|hana_m1_01"))
	var signals: Array = []
	var on_signal := func(id: String) -> void: signals.append(id)
	CS.mission_started.connect(on_signal)
	CS.objective_completed.connect(on_signal)
	CS.mission_completed.connect(on_signal)
	CS.reset()
	_check("[save] reset clears played triggers", not CS.is_trigger_played("objective:m1.iris_scanned|hana_m1_01"))
	_check("[load] load_state restores them without a signal", CS.load_state(JSON.parse_string(JSON.stringify(saved)))
		and CS.is_trigger_played("objective:m1.iris_scanned|hana_m1_01") and signals.is_empty() and not DS.is_playing())
	CS.complete_objective("m1.inspection_sent")
	await process_frame
	_check("[load] a new event after loading plays only its own line", played.size() == 1
		and played[0].subtitle == DT.lines["mira_m1_04"]["text"], str(played.size()))
	DS.stop_all()
	played.clear()
	CS.start_mission("m1")
	for objective in CS.mission_objectives("m1"):
		DT.fire("objective:" + objective)
	await process_frame
	_check("[load] nothing that played before the save replays", played.is_empty())
	var old_save: Dictionary = saved.duplicate()
	old_save.erase("triggers_played")
	_check("[load] a save from before triggers were recorded still loads", CS.load_state(old_save))

	GS.player.free()
	GS.player = null
	print("RESULT test_dialogue_triggers %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
