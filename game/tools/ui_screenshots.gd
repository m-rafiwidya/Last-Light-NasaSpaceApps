extends SceneTree
## Windowed screenshots of the in-game screens the UI tests don't capture, to check the look at a
## window size (the UI is drawn at the window's real resolution, stretch mode canvas_items): the
## player HUD with a subtitle and the FPS counter, the robot HUD, the debug console, the mission
## console. (The UI gallery has its own: `Godot --path game res://src/ui/components/ui_gallery.tscn
## --resolution <size> -- --shot=<file.png>`. The main menu, opening sequence, PLAY popup, loading
## screen, pause menu and settings come from their tests' `-- --shot=<dir>`.)
##
##     Godot --path game -s res://tools/ui_screenshots.gd --resolution 3187x1793 -- --shot=<dir>
##
## Saves hud_on_foot.png, hud_driving.png, console.png and mission_console.png.
## Changes no saved setting (it shows the FPS counter directly, not through the setting).

var GS: Node
var SL: Node
var shot_dir: String = ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_dir = arg.trim_prefix("--shot=")
	if shot_dir.is_empty():
		printerr("usage: -- --shot=<dir>")
		quit(1)
		return
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _wait(seconds: float) -> void:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(shot_dir.path_join(file))
	print("SHOT %s %s" % [file, image.get_size()])


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	SL.load_scene("test_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "test_level"):
		await process_frame
	await _wait(1.5)

	# On foot: a subtitle and the FPS counter (not saved: the section is put back below)
	var counter: CanvasLayer = root.get_node("Main/UIManager/FpsCounter")
	counter.visible = true
	counter.set_process(true)
	var dialog: Resource = load("res://src/dialog/dialog.gd").new()
	dialog.speaker = "Kite"
	dialog.subtitle = "Field Of View, Resolution and the settings text should read cleanly at any window size."
	dialog.min_duration = 10.0
	root.get_node("DialogServer").play_dialog(dialog)
	await _wait(1.0)
	await _shot("hud_on_foot.png")

	var console: Window = root.get_node("Main/UIManager/Console")
	console.popup()
	await _wait(0.5)
	await _shot("console.png")
	console.hide()
	await _wait(0.3)

	GS.change_state_to(GS.State.MISSION_CONSOLE)
	await _wait(1.0)
	await _shot("mission_console.png")
	GS.return_to_game()
	await _wait(0.8)

	var rover: Node = SL.current_scene.get_node_or_null("ReadyRover")
	if rover:
		GS.drive(rover)
		await _wait(1.5)
		await _shot("hud_driving.png")
		GS.change_state_to(GS.State.IN_GAME_PLAYER)
		await _wait(0.5)
	root.get_node("DialogServer").stop_all()
	quit(0)
