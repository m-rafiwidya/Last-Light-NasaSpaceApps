extends SceneTree
## The credits screen: its text (CreditsData reads res://res/credits.md, plus the engine licence it
## builds from the running engine), the `credits` console
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
		["A GAME BY", "TEAM", "ORIGINAL PROTOTYPE", "REAL DATA", "NASA SPACE APPS CHALLENGE RESOURCES", "BUILT WITH", "AI TOOLS", "TYPE",
		"MUSIC AND SOUND", "SPECIAL THANKS", "", "GODOT ENGINE LICENCE"]), str(titles))
	var by_title: Dictionary = {}
	for section in sections:
		by_title[section["title"]] = section["entries"]
	var team: Array = by_title.get("TEAM", [])
	_check("TEAM: three name rows with university and country", team.size() == 3 and team[0]["name"] == "FAHD MUHAMMAD ZAHID"
		and team[0]["sub"] == "Institut Teknologi Bandung · Indonesia" and team[2]["name"] == "FAIQ HAIDAR DZIKRULLAH SATRIAWAN")
	var prototype: Array = by_title.get("ORIGINAL PROTOTYPE", [])
	_check("ORIGINAL PROTOTYPE: one name row, not in TEAM", prototype.size() == 1
		and prototype[0].get("name", "") == "RAYHAN SATRIO ADI NURDJAMAN" and prototype[0].get("sub", "") == "Former team member (first-person base)"
		and not team.any(func(e: Dictionary) -> bool: return e.get("name", "") == "RAYHAN SATRIO ADI NURDJAMAN"))
	var data: Array = by_title.get("REAL DATA", [])
	_check("REAL DATA: six sources, lines kept", data.size() == 6 and "\n" in data[2]["text"]
		and (data[2]["text"] as String).contains("ESA/Gaia/DPAC"))
	_check("REAL DATA: the USGS Gazetteer entry", (data[5]["text"] as String).contains("Head crater")
		and (data[5]["text"] as String).contains("USGS Gazetteer of Planetary Nomenclature"))
	var space_apps: String = "\n".join((by_title.get("NASA SPACE APPS CHALLENGE RESOURCES", []) as Array).map(
		func(e: Dictionary) -> String: return e["text"]))
	_check("Space Apps resources: the four, and no endorsement", space_apps.contains("Design and Develop Science Missions")
		and space_apps.contains("Concept Maturity Levels") and space_apps.contains("Mission Design Lab")
		and space_apps.contains("Build It Yourself") and space_apps.contains("does not endorse"))
	var ai_text: String = by_title.get("AI TOOLS", [{}])[0].get("text", "")
	_check("AI TOOLS: Claude Opus 5.5 and Sonnet 5.5", ai_text.contains("Claude Opus 5.5") and ai_text.contains("Claude Sonnet 5.5")
		and ai_text.contains("Anthropic"))
	var ai_all: String = "\n".join((by_title.get("AI TOOLS", []) as Array).map(func(e: Dictionary) -> String: return e["text"]))
	_check("AI TOOLS: code, Blender scripts, music; images and sound effects; the logo and its NASA photo",
		ai_all.contains("Blender scripts") and ai_all.contains("music composition") and ai_all.contains("Images:")
		and ai_all.contains("Sound effects:") and ai_all.contains("Title logo: AI-generated silhouette")
		and ai_all.contains("Bruce McCandless II, STS-41-B, 1984") and ai_all.contains("S84-27017"))
	_check("A GAME BY: the studio and the event", by_title.get("A GAME BY", [{}])[0].get("name", "") == "TANDBORSTE"
		and (by_title["A GAME BY"][0]["sub"] as String).contains("NASA Space Apps Challenge 2026"))
	var type_text: String = by_title.get("TYPE", [{}])[0].get("text", "")
	_check("TYPE names Michroma, Exo 2 and IBM Plex Mono", type_text.contains("Michroma") and type_text.contains("Exo 2")
		and type_text.contains("IBM Plex Mono"))
	var type_all: String = "\n".join((by_title.get("TYPE", []) as Array).map(func(e: Dictionary) -> String: return e["text"]))
	_check("TYPE: Caveat, the four copyright lines and the OFL notice", type_all.contains("Caveat")
		and type_all.contains("Copyright 2011 The Michroma Project Authors") and type_all.contains("Copyright 2013 The Exo 2 Project Authors")
		and type_all.contains("Copyright 2017 IBM Corp.") and type_all.contains("Copyright 2014 The Caveat Project Authors")
		and type_all.contains("SIL Open Font License, Version 1.1"))
	var sound_all: String = "\n".join((by_title.get("MUSIC AND SOUND", []) as Array).map(func(e: Dictionary) -> String: return e["text"]))
	_check("MUSIC AND SOUND: Kenney (CC0) and the GeneralUser GS soundfont", sound_all.contains("Kenney") and sound_all.contains("CC0")
		and sound_all.contains("GeneralUser GS") and sound_all.contains("S. Christian Collins"))
	var engine: Array = by_title.get("GODOT ENGINE LICENCE", [])
	var engine_text: String = "\n".join(engine.map(func(e: Dictionary) -> String: return e["fine"]))
	_check("engine licence: Godot's own text, from the engine", engine_text.contains("Permission is hereby granted")
		and engine_text.contains("Godot Engine contributors") and not Engine.get_license_text().is_empty())
	var component_lines: PackedStringArray = CreditsData.third_party_lines()
	_check("engine licence: one line per third-party component, each with its licence", component_lines.size() > 50
		and component_lines.size() == Engine.get_copyright_info().size() - 1 and component_lines.size() > 0
		and Array(component_lines).all(func(l: String) -> bool: return l.ends_with(")") and ": " in l), str(component_lines.size()))
	_check("engine licence: is the last section", sections[sections.size() - 1]["title"] == "GODOT ENGINE LICENCE")
	var thanks: String = by_title.get("SPECIAL THANKS", [{}])[0].get("text", "")
	_check("SPECIAL THANKS: Space Apps, the Melbourne organisers and the playtesters, no placeholder",
		thanks.replace("\n", " ") == "NASA Space Apps Challenge 2026, the Melbourne local event organisers, and everyone who playtested Last Light."
		and not thanks.contains("["), thanks)
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
		and "SPECIAL THANKS" in texts and texts.has("NASA Space Apps Challenge 2026,\nthe Melbourne local event organisers,\nand everyone who playtested Last Light.") and "MUHAMMAD RAFI WIDYATAMA" in texts
		and "AI TOOLS" in texts and "GODOT ENGINE LICENCE" in texts, str(texts.size()))
	_check("SKIP shown, the ending not", credits.get_node("%Skip").visible and not credits.get_node("%End").visible)

	# --- The roll: 48 s, linear -------------------------------------------------------------
	var column: Control = credits._column
	var screen_height: float = credits.get_node("%Root").size.y
	_check("the roll starts below the screen and is taller than it", absf(column.position.y - screen_height) < 40.0
		and column.size.y > screen_height, "%.0f of %.0f" % [column.size.y, screen_height])
	var widest: float = 0.0
	for label: Label in credits.get_node("%Roll").find_children("*", "Label", true, false):
		if label.text == "FAIQ HAIDAR DZIKRULLAH SATRIAWAN":
			widest = maxf(widest, label.get_minimum_size().x)
	_check("the longest team names fit on the screen", widest > 0.0 and widest < credits.get_node("%Root").size.x - 80.0,
		"%.0f of %.0f" % [widest, credits.get_node("%Root").size.x])
	_check("it takes 48 s plus the engine licence's share, at the same speed", is_equal_approx(credits.ROLL_TIME, 48.0)
		and credits.roll_time > credits.ROLL_TIME, "%.1f s" % credits.roll_time)
	var engine_box: Control = credits._engine_box
	var main_speed: float = (screen_height + column.size.y - engine_box.size.y - credits.SECTION_GAP) / credits.ROLL_TIME
	_check("the engine licence is on the roll, and does not speed it up", engine_box != null and engine_box.size.y > 400.0
		and absf((screen_height + column.size.y) / credits.roll_time - main_speed) < 0.5, "%.0f px box, %.1f px/s" % [engine_box.size.y, main_speed])
	var y0: float = column.position.y
	var f0: int = Engine.get_process_frames()
	await _seconds(1.0)
	var y1: float = column.position.y
	# (--fixed-fps: every frame lasts the same, whatever the wall clock says)
	var elapsed: float = (Engine.get_process_frames() - f0) * root.get_process_delta_time()
	var speed: float = (screen_height + column.size.y) / credits.roll_time
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
