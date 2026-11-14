extends SceneTree
## Renders the workshop's decor (tools/blender/DECOR_KIT.md) in the Moon level into
## tools/previews/decor/ (repo root), to check how it reads in the workshop's light: the bay's
## west wall, the crates' corner, the bay door wall, the charger's wall, the console desk, the
## history cards (and one up close, at reading distance), a service note up close, the plant
## lab, and from outside: the rover's chase camera coming home over the tracks and the apron
## from beside the door. Needs a window (not --headless):
##
##     Godot --path game -s res://tools/render_decor_previews.gd --resolution 1920x1080
##
## Prints a MEASURE line per shot: the mean brightness (0-1) of the middle of the screen and the
## share of nearly black pixels in it.

const OUT_DIR: String = "res://../tools/previews/decor"

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


func _hide_huds() -> void:
	for ui in ["HUD", "RobotHUD"]:
		var hud: Node = root.get_node("Main").find_child(ui, true, false)
		if hud:
			hud.visible = false


## Stands the player at kit (x, y) and turns the eye to the kit point `kit_at` (x, y, height)
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
	_hide_huds()
	await _frames(60)

	for shot in [
			["bay_west_wall", Vector3(-2.4, -0.6, 0.0), Vector3(-4.7, 0.6, 1.0)],
			["bay_crates_corner", Vector3(-2.3, -1.9, 0.0), Vector3(-4.0, -3.6, 0.4)],
			["bay_door_wall", Vector3(-2.6, 1.6, 0.0), Vector3(-3.9, 3.8, 1.1)],
			["charger_wall", Vector3(0.8, 1.9, 0.0), Vector3(1.6, 3.8, 1.5)],
			["console_desk", Vector3(3.2, -0.3, 0.0), Vector3(2.3, -0.3, 0.92)],
			["history_cards", Vector3(3.3, -1.3, 0.0), Vector3(4.8, -1.3, 1.45)],
			["history_card_close", Vector3(4.3, -0.95, 0.0), Vector3(4.8, -0.95, 1.40)],
			["service_note_close", Vector3(1.45, -3.0, 0.0), Vector3(2.05, -3.3, 1.45)],
			["plant_lab", Vector3(3.7, 0.4, 0.0), Vector3(4.75, 1.1, 1.0)]]:
		_look_from(player, workshop, shot[1], shot[2])
		await _shot(shot[0])

	# Coming home: the rover 14 m out facing the door, driven, chase camera (tracks and exterior)
	rover.global_transform = Transform3D(workshop.global_basis * Basis(Vector3.UP, PI), workshop.to_global(Vector3(-1.0, 0.4, -14.0)))
	rover.linear_velocity = Vector3.ZERO
	GS.drive(rover)
	_hide_huds()
	rover.get_node("CameraRig")._switch(0)
	await _frames(240)
	await _shot("chase_coming_home")
	rover.get_node("CameraRig")._switch(1)
	await _frames(60)
	await _shot("mast_coming_home")
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	_hide_huds()
	_look_from(player, workshop, Vector3(4.5, 9.0, 0.0), Vector3(-1.0, 4.5, 0.4))
	await _shot("apron_from_east")
	quit()


func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
