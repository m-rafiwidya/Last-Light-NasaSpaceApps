extends SceneTree
## The Data Sources screen (DataSourcesScreen, res/story/data_sources.json):
##   1. Data: every group and entry of the JSON is shown, each link on a LinkButton (opens in the
##      browser); the NASA, science, assumptions and challenge groups exist, the challenge one a placeholder.
##   2. Main menu: DATA SOURCES opens it, Esc closes it and gives the menu back.
##   3. Campaign result: its DATA SOURCES button opens it; BACK closes it.
##   4. Fit: at five window sizes the panel and BACK are on screen, nothing runs wider than the
##      list, and the list scrolls.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_data_sources.gd

const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1024, 640),
]
const GROUPS: Array = ["nasa", "science", "assumptions", "challenge"]

var GS: Node
var failures: int = 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-66s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _esc() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)
	await _frames(2)


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	var start: int = Time.get_ticks_msec()
	while GS.state != GS.State.MAIN_MENU and Time.get_ticks_msec() - start < 60000:
		await process_frame
	var screen: Node = get_first_node_in_group(&"data_sources")
	var menu: Node = root.get_node("Main/UIManager/MainMenu")
	menu.skip_intro()
	await _frames(30)

	# 1. Data
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://res/story/data_sources.json"))
	var expected: Array = []
	for group: Dictionary in data["groups"]:
		for entry: Dictionary in group["entries"]:
			expected.append([group["id"], entry["name"], entry["use"], entry.get("link", "")])
	var shown: Array = screen.entries.map(func(e: Dictionary) -> Array: return [e["group"], e["name"], e["use"], e["link"]])
	_check("[data] every JSON entry is on the screen, in order", expected.size() > 20 and shown == expected,
		"%d of %d" % [shown.size(), expected.size()])
	var missing: Array = screen.entries.filter(func(e: Dictionary) -> bool: return not _shows(e))
	_check("[data] each shows its name, use and link", missing.is_empty(), str(missing.map(func(e: Dictionary) -> String: return e["name"])))
	var ids: Array = data["groups"].map(func(g: Dictionary) -> String: return g["id"])
	var challenge: Dictionary = data["groups"][ids.find("challenge")] if "challenge" in ids else {}
	_check("[data] NASA, science, assumptions and a placeholder challenge group", ids == GROUPS
		and challenge.get("placeholder", false) and _text_shown(screen, challenge.get("note", "?")), str(ids))
	var names: String = " ".join(expected.map(func(e: Array) -> String: return e[1]))
	_check("[data] the DTM, SLDEM and Head crater's gazetteer entry are listed", names.contains("Apollo 12 landing site (2 m)")
		and names.contains("SLDEM2015") and names.contains("Head crater"))

	# 2. Main menu
	var button: Button = menu.find_child("DataSources", true, false)
	_check("[menu] DATA SOURCES sits beside SETTINGS", button != null and button.get_index() == menu.find_child("Settings", true, false).get_index() + 1)
	button.pressed.emit()
	await _frames(2)
	_check("[menu] it opens the screen, BACK focused", screen.is_open() and screen.back.has_focus())
	await _esc()
	_check("[menu] Esc closes it, the menu is back", not screen.is_open() and GS.state == GS.State.MAIN_MENU and button.has_focus())

	# 3. Campaign result
	var result: Node = get_first_node_in_group(&"campaign_result")
	result.show()
	var result_button: Button = result.get_node("%DataSources")
	result_button.pressed.emit()
	await _frames(2)
	_check("[result] DATA SOURCES on the result screen opens it", screen.is_open())
	screen.back.pressed.emit()
	await _frames(2)
	_check("[result] BACK closes it", not screen.is_open())
	result.hide()

	# 4. Fit
	for size: Vector2i in SIZES:
		await _check_fit(size)

	print("RESULT test_data_sources %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)


func _shows(entry: Dictionary) -> bool:
	var row: Control = entry["node"]
	var labels: Array = row.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	var link: LinkButton = row.get_node_or_null("Link")
	var link_ok: bool = link.uri == entry["link"] if entry["link"] != "" else link == null
	return entry["name"] in labels and (entry["use"] == "" or entry["use"] in labels) and link_ok


func _text_shown(screen: Node, text: String) -> bool:
	return screen.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == text)


func _check_fit(size: Vector2i) -> void:
	var view := SubViewport.new()
	view.size = size
	root.add_child(view)
	var screen: Node = load("res://src/ui/data_sources/data_sources_screen.gd").new()
	view.add_child(screen)
	screen.open()
	await _frames(4)
	var label := "[fit] %dx%d" % [size.x, size.y]
	var bounds := Rect2(Vector2.ZERO, Vector2(size))
	var panel: Rect2 = screen.panel.get_global_rect()
	var list: Rect2 = screen.scroll.get_global_rect()
	_check(label + ": panel and BACK on screen", bounds.encloses(panel) and panel.encloses(screen.back.get_global_rect()),
		"panel %s back %s" % [panel, screen.back.get_global_rect()])
	var wide: Array = []
	for e: Dictionary in screen.entries:
		if e["node"].get_global_rect().end.x > list.end.x + 1.0 or _row_overflows(e["node"]):
			wide.append(e)
	_check(label + ": no entry wider than the list", wide.is_empty(), str(wide.map(func(e: Dictionary) -> String: return e["name"])))
	var bar: VScrollBar = screen.scroll.get_v_scroll_bar()
	_check(label + ": the list has room and scrolls", list.size.y > 150.0 and bar.max_value > list.size.y,
		"list %.0f px, content %.0f px" % [list.size.y, bar.max_value])
	view.queue_free()
	await process_frame


func _row_overflows(row: Control) -> bool:
	var rect: Rect2 = row.get_global_rect()
	for child: Control in row.get_children():
		if child.get_global_rect().end.x > rect.end.x + 1.0 or child.get_combined_minimum_size().x > rect.size.x + 1.0:
			return true
	return false
