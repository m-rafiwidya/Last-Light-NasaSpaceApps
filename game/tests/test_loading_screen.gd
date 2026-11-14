extends SceneTree
## The loading screen: its layout, the facts (glyphs, a random first one, rotation), the bar and
## the stage text following SceneLoader, and CONTINUE. A gameplay level waits for CONTINUE (Enter,
## Space or a click) with the player not yet spawned and the state still LOADING; Esc does
## nothing there; the main menu (Quit To Menu) goes straight through. A script run defaults to
## not waiting (so the other tests and the tools never hang on it).
## The loader's state is set directly where a headless run can't reach it (MoonTerrain builds no
## meshes headless, so the "LOADING TERRAIN" stage is checked with a stand-in node).
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_loading_screen.gd
##
## Windowed with `-- --shot=<dir>` it also saves loading.png (CONTINUE shown) and
## loading_progress.png (a bar part-way, the terrain stage).

const SCALE: float = 1.2

var GS: Node
var SL: Node
var loading: CanvasLayer
var failures: int = 0
var shot_dir: String = ""


## Stands in for MoonTerrain while it builds its meshes
class FakeContent extends Node:
	var progress: float = 0.0

	func is_ready_to_play() -> bool:
		return progress >= 1.0

	func content_progress() -> float:
		return progress


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_dir = arg.trim_prefix("--shot=")
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-62s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _wait_state(state: int, level_id: String = "", seconds: float = 120.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if GS.state == state and (level_id.is_empty() or SL.current_level_id == level_id):
			return true
		await process_frame
	return false


func _until(condition: Callable, seconds: float = 60.0) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if condition.call():
			return true
		await process_frame
	return false


func _seconds(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(file: String) -> void:
	if shot_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shot_dir.path_join(file))


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame
	await process_frame


func _mouse_to(control: Control) -> Vector2:
	var at: Vector2 = root.get_final_transform() * control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = Vector2(3.0, 0.0)
	Input.parse_input_event(motion)
	await process_frame
	await process_frame
	return at


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
	await process_frame
	await process_frame


func _node(path: String) -> Node:
	return loading.get_node(path)


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	loading = root.get_node("Main/UIManager/LoadingScreen") as CanvasLayer
	if not await _wait_state(GS.State.MAIN_MENU):
		_check("the main menu comes up", false)
		_finish()
		return
	root.get_node("Main/UIManager/MainMenu").skip_intro()
	await _seconds(0.5)
	while loading.visible:
		await process_frame

	_check_script_default()
	_check_facts()
	await _check_random_first_fact()
	await _check_rotation()
	await _check_stage_with_terrain()

	# Gameplay level: waits for CONTINUE; three ways to press it
	await _continue_flow("test_level", "Enter", true)
	await _continue_flow("test_level", "Space", false)
	await _continue_flow("test_level", "click", false)
	await _continue_flow("moon_level", "Enter", false)

	# Quit To Menu: no CONTINUE
	await _quit_to_menu()
	SL.wait_for_continue = false
	_finish()


# --- Pieces -------------------------------------------------------------------------------------

func _check_script_default() -> void:
	_check("a script run defaults to not waiting for CONTINUE", SL.wait_for_continue == false)
	_check("the loading screen is idle between loads", SL.stage == SL.Stage.IDLE and SL.overall_progress() == 0.0)


func _check_facts() -> void:
	var facts: Array = loading.FACTS
	_check("eight facts, each with a source", facts.size() == 8 and facts.all(
		func(f: Dictionary) -> bool: return not f["text"].is_empty() and not f["source"].is_empty()))
	_check("one dot per fact", _node("Control/FactColumn/Dots").get_child_count() == facts.size())
	var michroma: Font = (_node("Control/FactColumn/FactBox/Fact") as Control).get_theme_font(&"font")
	var exo: Font = (_node("Control/FactColumn/FactBox/Source") as Control).get_theme_font(&"font")
	var missing: String = ""
	for f in facts:
		for c in f["text"]:
			if not michroma.has_char(c.unicode_at(0)):
				missing += "%s(Michroma) " % c
		for c in f["source"]:
			if not exo.has_char(c.unicode_at(0)):
				missing += "%s(Exo 2) " % c
	_check("every fact's glyphs are in the fonts they use", missing.is_empty(), missing)
	_check("fonts: Michroma fact, Exo 2 caption and heading, Plex Mono stage",
		(_node("Control/FactColumn/FactBox/Fact") as Control).get_theme_font_size(&"font_size") == 36
		and (_node("Control/FactColumn/DidYouKnow") as Control).get_theme_font_size(&"font_size") >= 26
		and (_node("Control/Bottom/Column/Row/Stage") as Control).get_theme_font(&"font").get_font_name().begins_with("IBM Plex Mono"),
		(_node("Control/Bottom/Column/Row/Stage") as Control).get_theme_font(&"font").get_font_name())


func _check_random_first_fact() -> void:
	loading.show()
	var seen: Dictionary = {}
	for i in 60:
		loading.reset()
		seen[loading.fact_index] = true
	await process_frame
	_check("the first fact is random (not always the same one)", seen.size() >= 4, "%d of 8 in 60 loads" % seen.size())
	_check("the first fact's text and source are shown",
		_node("Control/FactColumn/FactBox/Fact").text == loading.FACTS[loading.fact_index]["text"]
		and _node("Control/FactColumn/FactBox/Source").text == loading.FACTS[loading.fact_index]["source"])
	loading.hide()


func _check_rotation() -> void:
	loading.show()
	loading.reset()
	await process_frame
	var first: int = loading.fact_index
	await _seconds(loading.FACT_PERIOD - 1.0)
	_check("the fact stays for about 7 s", loading.fact_index == first)
	await _seconds(1.6)
	var second: int = loading.fact_index
	_check("then the next fact comes up, in order", second == (first + 1) % loading.FACTS.size(), "%d -> %d" % [first, second])
	await _seconds(1.0)
	var fact_box: Control = _node("Control/FactColumn/FactBox")
	_check("it has faded in", is_equal_approx(fact_box.modulate.a, 1.0))
	var dots: Node = _node("Control/FactColumn/Dots")
	var on: Color = dots.get_theme_color(&"text", &"UIColor")
	var lit: int = 0
	for i in dots.get_child_count():
		if (dots.get_child(i) as Control).self_modulate.is_equal_approx(on):
			lit += 1
			_check("the lit dot is the fact's", i == second)
	_check("exactly one dot is lit", lit == 1)
	loading.hide()


# The stage text and the bar with content being built (a stand-in for the terrain's meshes)
func _check_stage_with_terrain() -> void:
	var fake := FakeContent.new()
	SL.stage = SL.Stage.BUILDING_CONTENT
	SL._content_nodes.append(fake)
	loading.show()
	loading.reset()
	await _seconds(0.3)
	_check("content at 0 % is the end of the scene's share", is_equal_approx(SL.overall_progress(), SL.ASSET_SHARE))
	_check("the terrain stage reads LOADING TERRAIN", _node("Control/Bottom/Column/Row/Stage").text == "LOADING TERRAIN")
	fake.progress = 0.5
	await _seconds(1.0)
	var expected: float = SL.ASSET_SHARE + (1.0 - SL.ASSET_SHARE) * 0.5
	_check("content at 50 % moves the bar there", is_equal_approx(SL.overall_progress(), expected))
	_check("the bar shows it", absf(_fill().anchor_right - expected) < 0.001, "%.3f" % _fill().anchor_right)
	_check("the percentage matches", _node("Control/Bottom/Column/Row/Percent").text == "%d%%" % floori(expected * 100.0),
		_node("Control/Bottom/Column/Row/Percent").text)
	await _shot("loading_progress.png")
	SL.stage = SL.Stage.LOADING_ASSETS
	SL._content_nodes.clear()
	SL.progress = [0.2]
	await _seconds(0.2)
	_check("the scene's first half is PREPARING THE WORKSHOP", _node("Control/Bottom/Column/Row/Stage").text == "PREPARING THE WORKSHOP")
	SL.progress = [0.8]
	await _seconds(0.2)
	_check("its second half is WAKING UP KITE", _node("Control/Bottom/Column/Row/Stage").text == "WAKING UP KITE")
	SL.stage = SL.Stage.IDLE
	SL.progress = [0.0]
	loading.hide()
	fake.free()


func _fill() -> Control:
	return _node("Control/Bottom/Column/Track/Fill")


# One gameplay load that waits for CONTINUE, then `how` presses it
func _continue_flow(level_id: String, how: String, check_layout: bool) -> void:
	var tag: String = "[%s, %s]" % [level_id, how]
	SL.wait_for_continue = true
	var sampled: Array[float] = []
	var stages_seen: Dictionary = {}
	SL.load_scene(level_id)
	var waiting: bool = false
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 120000:
		if loading.visible:
			sampled.append(_fill().anchor_right)
			stages_seen[_node("Control/Bottom/Column/Row/Stage").text] = true
		if SL.stage == SL.Stage.AWAITING_CONTINUE:
			waiting = true
			break
		await process_frame
	_check(tag + " the level waits for CONTINUE", waiting)
	var button := _node("Control/Bottom/Column/Row/Continue") as Button
	await _until(func() -> bool: return button.visible, 10.0)
	_check(tag + " CONTINUE appears once the bar is full",
		button.visible and is_equal_approx(_fill().anchor_right, 1.0)
		and _node("Control/Bottom/Column/Row/Percent").text == "100%")
	_check(tag + " the stage text gives way to it", not _node("Control/Bottom/Column/Row/Stage").visible)
	_check(tag + " the bar never went backwards", _non_decreasing(sampled), "%d samples" % sampled.size())
	_check(tag + " only the stage texts of the spec were shown", stages_seen.keys().all(
		func(t: String) -> bool: return t in ["PREPARING THE WORKSHOP", "WAKING UP KITE", "LOADING TERRAIN", "ALMOST THERE"]),
		str(stages_seen.keys()))
	_check(tag + " CONTINUE is focused", button.has_focus())
	await _seconds(1.0)
	_check(tag + " the level is loaded but not started: still LOADING, no player",
		GS.state == GS.State.LOADING and GS.player == null and SL.current_level_id == level_id
		and loading.visible and SL.stage == SL.Stage.AWAITING_CONTINUE)
	await _key(KEY_ESCAPE)
	_check(tag + " Esc does nothing while it waits", GS.state == GS.State.LOADING and SL.stage == SL.Stage.AWAITING_CONTINUE)
	if check_layout:
		_check_layout()
		await _shot("loading.png")
	match how:
		"Enter":
			await _key(KEY_ENTER)
		"Space":
			await _key(KEY_SPACE)
		"click":
			await _click(await _mouse_to(button))
	_check(tag + " pressing it starts the level",
		await _wait_state(GS.State.IN_GAME_PLAYER, level_id, 30.0) and GS.player != null)
	_check(tag + " the screen fades out and hides", await _until(func() -> bool: return not loading.visible, 5.0))
	_check(tag + " nothing is loading any more", SL.loading_scene_id == "" and SL.stage == SL.Stage.IDLE)
	await _seconds(0.5)


func _non_decreasing(values: Array[float]) -> bool:
	for i in range(1, values.size()):
		if values[i] < values[i - 1] - 0.00001:
			return false
	return true


# The board's positions x 1.2 (for a viewport at least 1920 wide)
func _check_layout() -> void:
	var size: Vector2 = root.get_visible_rect().size
	# The window's shape varies (a headless one is square): everything is placed from its edges
	var column := _node("Control/FactColumn") as Control
	_check("layout: the fact column is at (180, 180), 984 wide",
		column.get_global_rect().position.is_equal_approx(Vector2(180.0, 180.0)) and is_equal_approx(column.size.x, 984.0),
		str(column.get_global_rect()))
	var track := _node("Control/Bottom/Column/Track") as Control
	_check("layout: the bar is 2 px high between x 180 and x 1740",
		is_equal_approx(track.size.y, 2.0) and is_equal_approx(track.global_position.x, 180.0)
		and is_equal_approx(track.size.x, size.x - 360.0), str(track.get_global_rect()))
	_check("layout: the bar's bottom is 115 px above the screen's",
		absf(size.y - 115.2 - (track.global_position.y + track.size.y)) < 1.0, str(track.get_global_rect()))
	var logo := _node("Control/LogoHolder") as Control
	_check("layout: the astronaut is on the right, 252 x 286, 228 from the edge",
		is_equal_approx(logo.size.x, 252.0) and absf(logo.size.y - 285.6) < 0.1
		and is_equal_approx(size.x - logo.get_global_rect().end.x, 228.0), str(logo.get_global_rect()))
	var percent := _node("Control/Bottom/Column/Row/Percent") as Control
	_check("layout: the percentage ends at the bar's right end",
		absf(percent.get_global_rect().end.x - track.get_global_rect().end.x) < 1.0)
	var fact := _node("Control/FactColumn/FactBox") as Control
	var dots := _node("Control/FactColumn/Dots") as Control
	_check("layout: the dots are under the fact", dots.global_position.y > fact.get_global_rect().end.y
		and dots.get_global_rect().end.y < (_node("Control/Bottom") as Control).global_position.y)
	_check("layout: the fact is clear of the astronaut", fact.get_global_rect().end.x < logo.get_global_rect().position.x)
	var starfield := _node("Control/Starfield") as Control
	_check("layout: the starfield fills the screen", starfield.size == size)


func _quit_to_menu() -> void:
	SL.wait_for_continue = true
	var waited: bool = false
	var continue_shown: bool = false
	var button := _node("Control/Bottom/Column/Row/Continue") as Button
	SL.load_scene("main_menu")
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 60000:
		waited = waited or SL.stage == SL.Stage.AWAITING_CONTINUE
		continue_shown = continue_shown or button.visible
		if GS.state == GS.State.MAIN_MENU and SL.current_level_id == "main_menu":
			break
		await process_frame
	_check("[quit to menu] goes straight through, with no CONTINUE", GS.state == GS.State.MAIN_MENU
		and not waited and not continue_shown)
	_check("[quit to menu] the screen fades out and hides", await _until(func() -> bool: return not loading.visible, 5.0))


func _finish() -> void:
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
