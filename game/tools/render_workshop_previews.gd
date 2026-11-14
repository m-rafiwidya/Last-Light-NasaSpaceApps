extends SceneTree
## Renders the workshop in the Moon level into tools/previews/workshop/ (repo root), to check its
## lighting and readability (tools/blender/WORKSHOP_KIT.md 8). Needs a window (not --headless):
##
##     Godot --path game -s res://tools/render_workshop_previews.gd --resolution 1920x1080
##
## Shots (the player's helmet light off unless the name says so): the console, from where the
## operator stands; the bay from beside the door; the rack from the walkway; the docked rover
## charging, from beside the pad; the rover's chase camera coming home to the open door; the
## building from outside. Prints a MEASURE line per shot: the mean brightness (0-1) of the middle
## of the screen and the share of nearly black pixels in it.

const OUT_DIR: String = "res://../tools/previews/workshop"

var GS: Node
var SL: Node


func _initialize() -> void:
	_watchdog(300.0)
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _frames(count: int) -> void:
	DisplayServer.window_move_to_foreground()
	for i in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames(20)
	var image: Image = root.get_texture().get_image()
	image.save_jpg(ProjectSettings.globalize_path(OUT_DIR + "/" + name + ".jpg"), 0.88)
	var w: int = image.get_width()
	var h: int = image.get_height()
	var total: float = 0.0
	var black: int = 0
	var count: int = 0
	for y in range(h / 4, 3 * h / 4, 8):
		for x in range(w / 4, 3 * w / 4, 8):
			var v: float = image.get_pixel(x, y).get_luminance()
			total += v
			black += 1 if v < 0.03 else 0
			count += 1
	print("MEASURE %-28s mean brightness %.2f, nearly black %.0f%%" % [name, total / count, 100.0 * black / count])


func _look_from(player: Node, workshop: Node3D, kit_from: Vector3, kit_at: Vector3) -> void:
	var from: Vector3 = workshop.to_global(Vector3(kit_from.x, 0.05, -kit_from.y))
	var at: Vector3 = workshop.to_global(Vector3(kit_at.x, kit_at.z, -kit_at.y))
	player.global_position = from
	player.linear_velocity = Vector3.ZERO
	var eye: Vector3 = from + Vector3(0.0, 1.5, 0.0)
	var d: Vector3 = at - eye
	player.controller.camera_azimuth = atan2(-d.x, -d.z)
	player.controller.camera_altitude = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	DisplayServer.window_move_to_foreground()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await process_frame
	var level: Node = SL.current_scene
	var workshop: Node3D = level.get_node("Workshop")
	var rover: Node = workshop.rover
	var player: Node = GS.player
	for ui in ["HUD", "RobotHUD"]:
		var hud: Node = root.get_node("Main").find_child(ui, true, false)
		if hud:
			hud.visible = false
	await _frames(60)

	_look_from(player, workshop, Vector3(3.2, -0.3, 0.0), Vector3(0.0, -0.4, 0.6))
	await _shot("console_from_operator")
	_look_from(player, workshop, Vector3(-1.5, 3.0, 0.0), Vector3(-0.1, -2.5, 0.6))
	await _shot("bay_from_door")
	_look_from(player, workshop, Vector3(-0.1, -1.9, 0.0), Vector3(-0.1, -3.55, 0.8))
	await _shot("rack_from_walkway")
	player.helmet_light_on = true
	await _shot("rack_from_walkway_helmet_light")
	player.helmet_light_on = false
	rover.battery.charge = rover.battery.capacity * 0.4
	_look_from(player, workshop, Vector3(1.5, 1.4, 0.0), Vector3(-0.1, -0.3, 0.3))
	await _frames(240)
	await _shot("pad_charging")

	# Coming home: the rover 12 m out facing the door, driven, chase camera
	rover.global_transform = Transform3D(workshop.global_basis * Basis(Vector3.UP, PI), workshop.to_global(Vector3(-1.0, 0.4, -12.0)))
	rover.linear_velocity = Vector3.ZERO
	GS.drive(rover)
	for ui in ["HUD", "RobotHUD"]:
		var hud: Node = root.get_node("Main").find_child(ui, true, false)
		if hud:
			hud.visible = false
	rover.get_node("CameraRig")._switch(0)
	await _frames(240)
	await _shot("chase_coming_home")
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	for ui in ["HUD", "RobotHUD"]:
		var hud: Node = root.get_node("Main").find_child(ui, true, false)
		if hud:
			hud.visible = false
	_look_from(player, workshop, Vector3(9.0, 16.0, 0.0), Vector3(0.0, 0.0, 1.5))
	await _shot("outside")
	quit()


func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
