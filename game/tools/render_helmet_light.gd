extends SceneTree
## Renders the player's helmet light into tools/previews/helmet_light/ (repo root) and measures
## how well it shows parts on the ground in the dark. Needs a window (not --headless):
##
##     Godot --path game -s res://tools/render_helmet_light.gd --resolution 1920x1080
##
## Shots: on the floor of the Moon level's permanently shadowed crater, a wheel, a motor and a
## battery on the ground 2.5, 5 and 8 m ahead, looking down at them, with the helmet light off
## and on; the same with the driven rover's headlights on too (from the player's view); and the
## test level in daylight with the light on. Prints a MEASURE line per part: its mean brightness on
## screen (0-1, the middle of the part) with the light off and on, and the ground's beside it.

const OUT_DIR: String = "res://../tools/previews/helmet_light"
const CRATER := Vector2(192.0, 384.0)
const LOOK_DOWN: float = -28.0
const PARTS: Array = [["wheel", 2.5], ["motor", 5.0], ["battery", 8.0]]
const SAMPLE: int = 6   # half the side of the sampled square, pixels

var GS: Node
var SL: Node


func _initialize() -> void:
	_watchdog(300.0)
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	# A covered or background window isn't redrawn on macOS: the screenshots would be old frames
	DisplayServer.window_move_to_foreground()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	while GS.state != GS.State.MAIN_MENU:
		await process_frame

	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await process_frame
	var level: Node = SL.current_scene
	var terrain: Node = level.get_node("Terrain")
	var player: Node = GS.player
	await _frames(30)

	# The player on the crater floor facing north-west (away from the rim the sun is behind)
	var azimuth: float = deg_to_rad(40.0)
	var forward := Vector3(-sin(azimuth), 0.0, -cos(azimuth))
	var at := Vector3(CRATER.x, terrain.height_at(CRATER.x, CRATER.y) + 0.05, CRATER.y)
	player.global_position = at
	player.linear_velocity = Vector3.ZERO
	player.controller.camera_azimuth = azimuth
	player.controller.camera_altitude = deg_to_rad(LOOK_DOWN)
	var parts: Array = []
	for entry in PARTS:
		var part: Node3D = load("res://src/robot/socket/%s_part.tscn" % entry[0]).instantiate()
		level.add_child(part)
		var spot: Vector3 = at + forward * entry[1] + forward.cross(Vector3.UP) * 0.4
		part.global_position = Vector3(spot.x, terrain.height_at(spot.x, spot.z) + 0.4, spot.z)
		parts.append(part)
	await _frames(240)   # the parts settle

	# `-- light_energy=2 spot_angle=30 ...`: try other values of the helmet light's properties
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=")
		if kv.size() == 2 and kv[0] in player.helmet_light:
			player.helmet_light.set(kv[0], kv[1].to_float())
			print("INFO helmet light %s = %s" % [kv[0], kv[1]])
	player.helmet_light_on = false
	await _frames(30)
	var off: Array = _measure(player.camera, parts)
	await _save("crater_floor_off")
	player.helmet_light_on = true
	await _frames(30)
	var on: Array = _measure(player.camera, parts)
	await _save("crater_floor_helmet_light")
	for i in parts.size():
		print("MEASURE %-8s %.1f m ahead: part %.3f off -> %.3f on, ground beside it %.3f off -> %.3f on" % [
			PARTS[i][0], PARTS[i][1], off[i][0], on[i][0], off[i][1], on[i][1]])

	# The rover beside the player with its headlights on too, seen from the player
	var rover: Node = level.get_node("ReadyRover")
	var rover_at: Vector3 = at - forward.cross(Vector3.UP) * 2.0 + forward * 1.0
	rover.global_transform = Transform3D(Basis(Vector3.UP, azimuth), Vector3(rover_at.x, terrain.height_at(rover_at.x, rover_at.z) + 0.4, rover_at.z))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	rover.headlights_on = true
	await _frames(180)
	await _save("crater_floor_helmet_light_and_headlights")

	SL.load_scene("test_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "test_level"):
		await process_frame
	await _frames(60)
	GS.player.controller.camera_altitude = deg_to_rad(LOOK_DOWN)
	GS.player.helmet_light_on = true
	await _frames(60)
	await _save("test_level_helmet_light")
	quit()


# [part brightness, ground brightness beside it] per part, from the current frame
func _measure(camera: Camera3D, parts: Array) -> Array:
	var image: Image = root.get_texture().get_image()
	var out: Array = []
	for part in parts:
		var centre: Vector2 = camera.unproject_position((part as Node3D).global_position)
		var right: Vector2 = camera.unproject_position((part as Node3D).global_position + camera.global_basis.x * 0.5)
		out.append([_brightness(image, centre), _brightness(image, right)])
	return out


func _brightness(image: Image, at: Vector2) -> float:
	var total: float = 0.0
	var count: int = 0
	for y in range(int(at.y) - SAMPLE, int(at.y) + SAMPLE):
		for x in range(int(at.x) - SAMPLE, int(at.x) + SAMPLE):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				total += image.get_pixel(x, y).get_luminance()
				count += 1
	return total / maxf(count, 1)


func _save(shot: String) -> void:
	if not DisplayServer.window_is_focused():
		printerr("WARNING: the window isn't focused; %s may be an old frame" % shot)
	var path: String = ProjectSettings.globalize_path("%s/%s.jpg" % [OUT_DIR, shot])
	root.get_texture().get_image().save_jpg(path, 0.9)
	print("SAVED %s" % path)


# A hang fails the run instead of stalling it
func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
