extends SceneTree
## The credits screen: its text (CreditsData reads res://res/credits.md), the `credits` console
## command on the main menu, the 48 s linear roll, SKIP / Esc to the ending,
## WATCH AGAIN and MAIN MENU.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_credits.gd

var GS: Node
var failures: int = 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-62s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _seconds(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame
	await process_frame


func _labels(node: Node) -> PackedStringArray:
	var texts := PackedStringArray()
	for label in node.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


func _run() -> void:
	GS = root.get_node("GameState")
	while GS.state != GS.State.MAIN_MENU:
		await process_frame

	# --- The text ---------------------------------------------------------------------------
	var sections: Array[Dictionary] = CreditsData.sections()
	var titles: PackedStringArray = []
	for section in sections:
		titles.append(section["title"])
	_check("sections in the board's order (closing note untitled)", titles == PackedStringArray(
		["A GAME BY", "TEAM", "REAL DATA", "BUILT WITH", "TYPE", "MUSIC AND SOUND", "SPECIAL THANKS", ""]), str(titles))
	var by_title: Dictionary = {}
	for section in sections:
		by_title[section["title"]] = section["entries"]
	var team: Array = by_title.get("TEAM", [])
	_check("TEAM: four name rows with university and country", team.size() == 4 and team[0]["name"] == "FAHD"
		and team[0]["sub"] == "Institut Teknologi Bandung · Indonesia" and team[3]["name"] == "SATINIZE")
	var data: Array = by_title.get("REAL DATA", [])
	_check("REAL DATA: five sources, lines kept", data.size() == 5 and "\n" in data[2]["text"]
		and (data[2]["text"] as String).contains("ESA/Gaia/DPAC"))
	_check("A GAME BY: the studio and the event", by_title.get("A GAME BY", [{}])[0].get("name", "") == "TANDBORSTE"
		and (by_title["A GAME BY"][0]["sub"] as String).contains("NASA Space Apps Challenge 2026"))
	var type_text: String = by_title.get("TYPE", [{}])[0].get("text", "")
	_check("TYPE names Michroma, Exo 2 and IBM Plex Mono", type_text.contains("Michroma") and type_text.contains("Exo 2")
		and type_text.contains("IBM Plex Mono"))
	_check("SPECIAL THANKS keeps its placeholder", by_title.get("SPECIAL THANKS", [{}])[0].get("text", "") == "[YOUR SPECIAL THANKS]")
	_check("closing note: real data and fiction", (by_title.get("", [{}])[0].get("text", "") as String).contains("are fiction."))

	# --- Opening ----------------------------------------------------------------------------
	var credits: CanvasLayer = root.get_node("Main/UIManager/Credits")
	_check("hidden until asked for", not credits.visible)
	root.get_node("Debug").parse_command("credits")
	await process_frame
	await process_frame
	_check("the `credits` command opens it on the main menu", credits.visible and credits.rolling and not credits.ended)
	var texts: PackedStringArray = _labels(credits.get_node("%Roll"))
	_check("the roll shows the title and every section", "LAST LIGHT" in texts and "TEAM" in texts and "REAL DATA" in texts
		and "SPECIAL THANKS" in texts and "[YOUR SPECIAL THANKS]" in texts and "RAFI WIDYA PRATAMA" in texts, str(texts.size()))
	_check("SKIP shown, the ending not", credits.get_node("%Skip").visible and not credits.get_node("%End").visible)

	# --- The roll: 48 s, linear -------------------------------------------------------------
	var column: Control = credits._column
	var screen_height: float = credits.get_node("%Root").size.y
	_check("the roll starts below the screen and is taller than it", absf(column.position.y - screen_height) < 40.0
		and column.size.y > screen_height, "%.0f of %.0f" % [column.size.y, screen_height])
	_check("it takes 48 s", is_equal_approx(credits.ROLL_TIME, 48.0))
	var y0: float = column.position.y
	var f0: int = Engine.get_process_frames()
	await _seconds(1.0)
	var y1: float = column.position.y
	# (--fixed-fps: every frame lasts the same, whatever the wall clock says)
	var elapsed: float = (Engine.get_process_frames() - f0) * root.get_process_delta_time()
	var speed: float = (screen_height + column.size.y) / credits.ROLL_TIME
	_check("it moves up at (screen + roll) / 48 per second", absf((y0 - y1) - speed * elapsed) < speed * 0.1,
		"%.1f px in %.2f s, expected %.1f" % [y0 - y1, elapsed, speed * elapsed])
	var drift: Control = credits.get_node("%Drift")
	_check("the astronaut drifts across meanwhile", drift.visible and drift.position.x > credits.DRIFT_HOME.x + credits.DRIFT_FROM.x)

	# --- SKIP and the ending ----------------------------------------------------------------
	credits.get_node("%Skip").pressed.emit()
	await process_frame
	_check("SKIP jumps to the ending", credits.ended and not credits.rolling and credits.get_node("%End").visible
		and not credits.get_node("%Roll").visible and not credits.get_node("%Skip").visible)
	var end_texts: PackedStringArray = _labels(credits.get_node("%End"))
	_check("THANK YOU FOR PLAYING and the Earth line", "THANK YOU FOR PLAYING" in end_texts
		and "EARTH UNLOCKED · VISIT IT FROM THE MAIN MENU" in end_texts)
	_check("WATCH AGAIN / MAIN MENU", credits.get_node("%WatchAgain").text == "WATCH AGAIN" and credits.get_node("%MainMenu").text == "MAIN MENU")
	_check("the buttons start hidden", is_zero_approx(credits.get_node("%EndButtons").modulate.a))
	await _seconds(3.2)
	_check("then fade in", is_equal_approx(credits.get_node("%EndButtons").modulate.a, 1.0)
		and is_equal_approx(credits.get_node("%EndText").modulate.a, 1.0))

	# --- WATCH AGAIN, Esc, MAIN MENU --------------------------------------------------------
	credits.get_node("%WatchAgain").pressed.emit()
	await process_frame
	await process_frame
	_check("WATCH AGAIN rolls from the top", credits.rolling and not credits.ended and not credits.get_node("%End").visible
		and absf(credits._column.position.y - screen_height) < 40.0, "%.0f" % credits._column.position.y)
	await _key(KEY_ESCAPE)
	_check("Esc while rolling skips", credits.ended and credits.visible)
	credits.get_node("%MainMenu").pressed.emit()
	await process_frame
	_check("MAIN MENU closes it, back on the main menu", not credits.visible and GS.state == GS.State.MAIN_MENU)

	print("RESULT credits screen ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
