extends SceneTree
## Headless test: Evan's notes (ReadableNote, plan item K).
##   1. Workshop note: in group readable_note with the prop as highlight_node; reading shows an
##      "Evan:" subtitle with its text (no voice file yet, so text only); reading again skips it.
##      The player reads it through its InteractTrigger.
##   2. IRIS note: hidden and unreadable until m2.telemetry_received, then readable.
##   3. Logger note: plays once by itself when the driven Kite comes within range; E skips it and
##      doesn't replay it.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_readable_note.gd

const TICKS: int = 240

var GS: Node
var SL: Node
var CS: Node
var DS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("%s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail else ""])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _note(scene: String, at: Vector3) -> Node3D:
	var note: Node3D = (load(scene) as PackedScene).instantiate()
	level.add_child(note)
	note.global_position = at
	return note


func _press_e() -> void:
	Input.action_press(&"interact_use")
	await physics_frame
	await physics_frame
	Input.action_release(&"interact_use")
	await physics_frame


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	DS = root.get_node("DialogServer")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	CS.reset()
	load("res://src/save/save_index.gd").start_new_campaign()
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	await _ticks(1.0)
	DS.stop_all()
	var shown: Array = []
	DS.dialog_played.connect(func(dialog: Resource) -> void: shown.append(dialog))

	# 1. Workshop note
	var kite_note: Node3D = _note("res://src/field/evan_note_kite.tscn", rover.global_position + Vector3(0.0, 0.0, 50.0))
	await _ticks(0.1)
	_check("workshop: in group readable_note", kite_note.is_in_group(&"readable_note"))
	_check("workshop: highlight_node is the prop", kite_note.highlight_node != null
		and not kite_note.highlight_node.find_children("*", "MeshInstance3D", true, false).is_empty())
	_check("workshop: reading shows it", kite_note.toggle() and kite_note.is_showing())
	var line: Resource = shown.back() if not shown.is_empty() else null
	_check("workshop: an Evan subtitle with the note's text",
		line != null and line.speaker == "Evan" and line.subtitle.begins_with("KITE — STORAGE CHECK"),
		line.get_display_text() if line else "none")
	var voice_exists: bool = ResourceLoader.exists("res://res/audio/voice/evan_note_kite.ogg")
	_check("workshop: voice file loads when available", line != null and (line.audio_stream != null) == voice_exists)
	_check("workshop: reading again skips it", kite_note.toggle() and not kite_note.is_showing() and not DS.is_playing())
	kite_note.get_node("InteractTrigger").interact(GS.player)
	_check("workshop: the player reads it through its InteractTrigger", kite_note.is_showing())
	kite_note.toggle()

	# 2. IRIS note
	var iris_note: Node3D = _note("res://src/field/evan_note_iris.tscn", rover.global_position + Vector3(0.0, 0.0, 60.0))
	await _ticks(0.1)
	_check("iris: hidden and unreadable before m2.telemetry_received",
		not iris_note.visible and not iris_note.toggle() and not iris_note.is_showing())
	CS.complete_objective("m2.telemetry_received")
	await _ticks(0.1)
	_check("iris: readable after it", iris_note.visible and iris_note.toggle() and iris_note.is_showing()
		and shown.back().subtitle.begins_with("IRIS — FINAL FIELD CHECK"))
	iris_note.toggle()

	# 3. Logger note
	var logger_note: Node3D = _note("res://src/field/evan_note_logger.tscn", rover.global_position + Vector3(2.0, 0.0, 0.0))
	await _ticks(0.2)
	_check("logger: not played while Kite isn't driven", not logger_note.was_read)
	GS.drive(rover)
	await _ticks(0.3)
	_check("logger: plays by itself once Kite is driven within range", logger_note.was_read and logger_note.is_showing()
		and shown.back().subtitle.contains("second label underneath"))
	await _press_e()
	_check("logger: E skips it", not logger_note.is_showing())
	await _press_e()
	await _ticks(0.2)
	_check("logger: and doesn't replay it", not logger_note.is_showing())

	print("RESULT test_readable_note %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
