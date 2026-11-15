extends SceneTree
## Headless test: the bottom-right TipCard stays fully on screen and clear of the SubtitleStack
## at several viewport sizes, for every tip.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_hud_layout.gd

const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1024, 640),
]
const LINE: String = "Control, Kite is on the ramp. Take it slowly and keep the antenna pointed at the base when you cross the ridge."

const SETTINGS_PATH: String = "user://settings.cfg"

var failures: int = 0
var _had_settings: bool = false
var _saved_settings: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-70s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _run() -> void:
	await process_frame
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_saved_settings = FileAccess.get_file_as_string(SETTINGS_PATH)
	var campaign: Node = root.get_node("CampaignState")
	var tip_script: GDScript = load("res://src/ui/tip_card/tip_card.gd")
	var stack_scene: PackedScene = load("res://src/ui/subtitle_stack/subtitle_stack.tscn")
	for size: Vector2i in SIZES:
		for tip: StringName in tip_script.TIPS:
			campaign.reset()
			var view := SubViewport.new()
			view.size = size
			root.add_child(view)
			var stack: Control = stack_scene.instantiate()
			view.add_child(stack)
			var card: Control = tip_script.new()
			card.avoid = stack
			view.add_child(card)
			var box: Control = stack.dialog_box_scene.instantiate()
			box.set_line("CONTROL", LINE)
			stack.boxes.add_child(box)
			card.offer(tip)
			for i in 3:
				await process_frame
			var screen := Rect2(Vector2.ZERO, Vector2(size))
			var rect := card.get_global_rect()
			var label := "%dx%d %s" % [size.x, size.y, tip]
			_check(label + ": card inside the viewport", screen.encloses(rect), str(rect))
			_check(label + ": all rows shown", card._row_nodes.size() == tip_script.TIPS[tip].size()
				and card._row_nodes.all(func(row: Control) -> bool: return row.visible and row.size.y > 0.0))
			_check(label + ": clear of the subtitles", not rect.intersects(stack.get_global_rect()),
				"card %s stack %s" % [rect, stack.get_global_rect()])
			view.queue_free()
			await process_frame
	await _check_top_left(campaign)
	_check_traction()
	_restore_settings()
	print("RESULT hud layout %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


## The top-left tracker and the rover HUD's mission hint with their longest lines, and a waypoint
## label at the screen edges
func _check_top_left(campaign: Node) -> void:
	for size: Vector2i in SIZES:
		var view := SubViewport.new()
		view.size = size
		root.add_child(view)
		var hint: PanelContainer = load("res://src/ui/mission_hint/mission_hint.gd").new()
		var overlay: CanvasLayer = load("res://src/ui/guidance/guidance_overlay.gd").new()
		hint.set_process(false)
		overlay.set_process(false)
		view.add_child(hint)
		view.add_child(overlay)
		var step: String = "[E]  In position: press E to install the radio-power module now"
		var stuck: String = "Stuck? Back up, turn the wheels away from the rock and try the slope from the side instead."
		for label: Label in [hint.objective_label, overlay.objective_label]:
			label.text = "OBJECTIVE  Bring the delivery crate to the charging pad"
		for label: Label in [hint.step_label, overlay.step_label]:
			label.text = step
		for label: Label in [hint.stuck_label, overlay.stuck_label]:
			label.text = stuck
		hint.return_label.text = "LOW BATTERY: RETURN TO BASE   ~100% needed, 999 m to the pad"
		hint.alert_label.text = "Boundary: turn back, you are leaving the mission area"
		for i in 3:
			await process_frame
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		var name: String = "%dx%d" % [size.x, size.y]
		_check(name + ": mission hint inside the viewport", screen.encloses(hint.get_global_rect()), str(hint.get_global_rect()))
		_check(name + ": objective tracker inside the viewport", screen.encloses(overlay.tracker.get_global_rect()),
			str(overlay.tracker.get_global_rect()))
		var width: float = size.x
		for edge_x: float in [72.0, width - 72.0]:
			var back := Rect2(edge_x - 140.0, 100.0, 280.0, 26.0)
			var shifted: Rect2 = back
			shifted.position.x += overlay.label_shift(back, width)
			_check("%s: waypoint label at x=%d stays inside" % [name, edge_x], screen.encloses(shifted), str(shifted))
		view.queue_free()
		await process_frame


func _check_traction() -> void:
	var panel: Control = load("res://src/ui/robot_hud/friction_circles.gd").new()
	root.add_child(panel)
	var bounds: Rect2 = panel.content_bounds()
	var content := Rect2(0.0, panel.HEADER_HEIGHT, panel.custom_minimum_size.x, panel.custom_minimum_size.y - panel.HEADER_HEIGHT)
	_check("traction panel: hidden by default", not panel.visible)
	var debug: Node = root.get_node("Debug")
	debug.parse_command("traction on")
	_check("traction panel: the console command shows it", panel.visible)
	debug.parse_command("traction")
	_check("traction panel: no argument flips it off", not panel.visible)
	var general: Object = load("res://src/settings/general_settings.gd")
	general.section.set_value("show_traction", true)
	_check("traction panel: the Settings value shows it", panel.visible)
	general.section.set_value("show_traction", false)
	_check("traction panel: everything drawn is inside the panel", content.encloses(bounds), "%s in %s" % [bounds, content])
	_check("traction panel: no empty area under the last row", panel.custom_minimum_size.y - bounds.end.y <= 24.0,
		"%.0f px" % (panel.custom_minimum_size.y - bounds.end.y))
	panel.free()


func _restore_settings() -> void:
	if _had_settings:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		file.store_string(_saved_settings)
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
