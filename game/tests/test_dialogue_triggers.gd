extends SceneTree
## DialogueTriggers and the DialogServer queue:
##   1. Data: every trigger names an existing line and a real mission or objective event.
##   2. Queued sequences play one line at a time, in order; a direct play_dialog line stacks beside them.
##   3. Each trigger fires once; events fired outside a level wait for one.
##   4. Played triggers survive save_state/load_state, which emits nothing, and never replay.
##   5. The skip key (dialogue_skip) ends only the radio line showing, in game, with a key chip; cutscenes ignore it.
##   6. Repeatable alert lines don't replay within DialogServer.REPEAT_COOLDOWN, do after it.
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


func _press_skip() -> void:
	var event := InputEventAction.new()
	event.action = DS.SKIP_ACTION
	event.pressed = true
	root.push_input(event)
	await process_frame


func _line(text: String) -> Dialog:
	var dialog := Dialog.new()
	dialog.speaker = "Mira"
	dialog.subtitle = text
	dialog.min_duration = 8.0
	return dialog


func _skip_and_cooldown() -> void:
	DS.stop_all()
	played.clear()
	active = 0
	var ended: Array[Dialog] = []
	DS.dialog_ended.connect(func(dialog: Dialog) -> void: ended.append(dialog))
	var hud: Node = load("res://src/ui/subtitle_stack/subtitle_stack.tscn").instantiate()
	root.add_child(hud)

	# --- 5. skip key --------------------------------------------------------------------------
	var IB: GDScript = load("res://src/settings/input_bindings.gd")
	var state_before = GS.state
	_check("[skip] the skip key is a rebindable action listed in Settings > Controls", InputMap.has_action(DS.SKIP_ACTION)
		and IB.is_rebindable(DS.SKIP_ACTION) and IB.action_text(DS.SKIP_ACTION) == "Q", IB.action_text(DS.SKIP_ACTION))
	var used: Array = []
	for action in InputMap.get_actions():
		var key: InputEventKey = IB.key_event(action)
		if action != DS.SKIP_ACTION and not str(action).begins_with("ui_") and key and key.physical_keycode == KEY_Q:
			used.append(action)
	_check("[skip] no other action uses its key", used.is_empty(), str(used))
	var sequence := DialogSequence.new()
	var lines_in: Array[Dialog] = [_line("One."), _line("Two."), _line("Three.")]
	sequence.dialogs = lines_in
	GS.state = GS.State.CUTSCENE
	DS.queue_sequence(sequence)
	await process_frame
	await process_frame
	var box: Variant = hud.dialog_boxes.get(sequence.dialogs[0].get_instance_id())
	_check("[skip] no key chip on a cutscene's line", is_instance_valid(box) and not box.skip_shown())
	await _press_skip()
	await _seconds(0.6)
	_check("[skip] cutscenes ignore the skip key", ended.is_empty() and played.size() == 1, "%d ended" % ended.size())
	GS.state = GS.State.IN_GAME_PLAYER
	await process_frame
	await process_frame
	_check("[skip] in game the playing radio line shows the key chip", is_instance_valid(box) and box.skip_shown())
	await _press_skip()
	await _seconds(DS.SEQUENCE_GAP + 0.3)
	_check("[skip] the key skips only the current line, the queue plays the next", ended == [sequence.dialogs[0]]
		and played.size() == 2 and played[1] == sequence.dialogs[1] and DS.is_sequence_pending(sequence),
		"%d ended, %d played" % [ended.size(), played.size()])
	var direct := _line("Kite: direct report.")
	DS.play_dialog(direct)
	await _press_skip()
	await _seconds(DS.SEQUENCE_GAP + 0.3)
	_check("[skip] one press, one line: the direct line stays", direct in DS._active_dialogs and ended.size() == 2
		and played.back() == sequence.dialogs[2], "%d ended" % ended.size())
	DS.stop_all()
	played.clear()
	ended.clear()

	# --- 6. repeat cooldown -------------------------------------------------------------------
	_check("[cooldown] the alerts are real repeatable events", DT.problems().is_empty()
		and DT.triggers.filter(func(t: Dictionary) -> bool: return t["repeatable"]).size() == DT.ALERTS.size())
	_check("[cooldown] an alert plays", DT.alert("low_battery") != null)
	await process_frame
	_check("[cooldown] ... as a radio line", played.size() == 1 and played[0].subtitle == DT.lines["mira_alert_low_battery"]["text"])
	DS.stop_all()
	DS.clock += DS.REPEAT_COOLDOWN - 1.0
	_check("[cooldown] it doesn't replay within the cooldown", DT.alert("low_battery") == null)
	_check("[cooldown] another alert has its own cooldown", DT.alert("cold") != null)
	DS.stop_all()
	DS.clock += 2.0
	played.clear()
	_check("[cooldown] it plays again after the cooldown", DT.alert("low_battery") != null)
	await process_frame
	_check("[cooldown] ... and is shown", played.size() == 1)
	DS.stop_all()
	var refused := _line("Can't mount this.")
	refused.repeat_id = "test_refused"
	DS.play_dialog(refused)
	DS.stop_all()
	_check("[cooldown] a direct line with a repeat_id is dropped within the cooldown", not await DS.play_dialog(refused))
	CS.reset()
	CS.start_mission("m1")
	DS.stop_all()
	DS.clock += DS.REPEAT_COOLDOWN + 1.0
	_check("[cooldown] one-time story triggers are unaffected: still once", DT.fire("mission_started:m1") == null
		and CS.is_trigger_played("mission_started:m1|mira_m1_01"))
	DS.stop_all()
	hud.queue_free()
	GS.state = state_before


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
	var crew: Array = load("res://src/levels/crew_requests.gd").radio_lines("m1")
	for i in crew.size():
		expected.insert(1 + i, crew[i]["text"])
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

	await _skip_and_cooldown()

	GS.player.free()
	GS.player = null
	print("RESULT test_dialogue_triggers %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
