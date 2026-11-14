extends SceneTree
## Renders the wheels' dust (WheelDust) into tools/previews/dust/ (repo root): the Moon level, then
## the test level, the rover driving on open ground. Needs a window (not --headless):
##
##     Godot --path game -s res://tools/render_dust_previews.gd --resolution 1920x1080
##     (append `-- surface_effects=low` for the Low setting, the files then start with low_;
##     `only=<shot>` renders only the shots whose names contain it)
##
## Shots (<level>_...):
##   side_cruise / side_full  side-on from 3 m on the sunlit side, the camera 0.35 m up, so the
##                            spray stands against the sky, at 30% throttle (about 2.5 m/s) and full
##   trails                   the same view at 30%, the brightest of 45 frames (0.75 s): each
##                            grain's path, so the arcs show
##   chase                    the game's chase camera at full throttle
##   front                    from ahead and to the side, the rover coming at the camera at 30%
##   sun / shade (Moon)       the chase view at 40% in the sun, then in the workshop's shadow
## Prints a MEASURE line per shot: mean brightness of the middle of the frame.

const OUT_DIR: String = "res://../tools/previews/dust"
const CHASE: int = 0

var GS: Node
var SL: Node
var prefix: String = ""
var camera: Camera3D
var only: String = ""


func _initialize() -> void:
	_watchdog(600.0)
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _frames(count: int) -> void:
	DisplayServer.window_move_to_foreground()
	for i in count:
		await process_frame


func _save(image: Image, name: String) -> void:
	image.save_jpg(ProjectSettings.globalize_path(OUT_DIR + "/" + prefix + name + ".jpg"), 0.9)
	var w: int = image.get_width()
	var h: int = image.get_height()
	var total: float = 0.0
	var count: int = 0
	for y in range(h / 4, 3 * h / 4, 8):
		for x in range(w / 4, 3 * w / 4, 8):
			total += image.get_pixel(x, y).get_luminance()
			count += 1
	print("MEASURE %-28s mean brightness %.3f" % [prefix + name, total / count])


func _shot(name: String) -> void:
	DisplayServer.window_move_to_foreground()
	await process_frame
	_save(root.get_texture().get_image(), name)


# The brightest of `count` frames per pixel (at half resolution): grains' paths
func _trails(name: String, count: int) -> void:
	var out: Image = null
	DisplayServer.window_move_to_foreground()
	for i in count:
		await process_frame
		var image: Image = root.get_texture().get_image()
		image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		image.convert(Image.FORMAT_RGB8)
		if out == null:
			out = image
			continue
		var a: PackedByteArray = out.get_data()
		var b: PackedByteArray = image.get_data()
		for k in a.size():
			if b[k] > a[k]:
				a[k] = b[k]
		out = Image.create_from_data(out.get_width(), out.get_height(), false, Image.FORMAT_RGB8, a)
	_save(out, name)


func _wanted(name: String) -> bool:
	return only.is_empty() or name.contains(only)


func _hide_huds() -> void:
	for ui in ["HUD", "RobotHUD"]:
		var hud: Node = root.get_node("Main").find_child(ui, true, false)
		if hud:
			hud.visible = false


func _ground(level: Node, x: float, z: float) -> float:
	var terrain: Node = level.get_node_or_null("Terrain")
	return terrain.height_at(x, z) if terrain else 0.0


# Horizontal direction towards the level's sun (its first DirectionalLight3D)
func _to_sun(level: Node) -> Vector3:
	var lights: Array = level.find_children("*", "DirectionalLight3D", true, false)
	if lights.is_empty():
		return Vector3.RIGHT
	var d: Vector3 = (lights[0] as Node3D).global_basis.z
	return Vector3(d.x, 0.0, d.z).normalized()


func _place(rover: Node, at: Vector3, heading: Vector3) -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(a)
	rover.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), at)
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	for wheel in rover.running_gear.wheel_states:
		rover.running_gear.wheel_states[wheel][0] = 0.0


# Drives from `start` along `heading` at `throttle` until the rover is `distance` along, with the
# side camera 5 m to its left looking across the track at that point
func _side_run(level: Node, rover: Node, start: Vector3, heading: Vector3, throttle: float, distance: float, name: String, trails: bool) -> void:
	if not _wanted(name):
		return
	_place(rover, start, heading)
	await _frames(60)
	var at: Vector3 = start + heading * distance
	# On the sunlit side of the track, the sun behind the camera
	var side: Vector3 = heading.cross(Vector3.UP).normalized()
	if side.dot(_to_sun(level)) < 0.0:
		side = -side
	var eye: Vector3 = at + side * 3.0
	eye.y = _ground(level, eye.x, eye.z) + 0.35
	var target: Vector3 = at + Vector3.UP * 0.5
	camera.global_transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	camera.make_current()
	Input.action_press("move_forward", throttle)
	var lead: float = 0.5 if trails else 1.2
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 40000:
		await process_frame
		if (rover.global_position - start).dot(heading) > distance - lead:
			break
	if trails:
		await _trails(name, 45)
	else:
		await _shot(name)
	print("INFO %s at %.2f m/s, %.1f m along, %.1f m from the camera" % [prefix + name, rover.linear_velocity.length(),
		(rover.global_position - start).dot(heading), rover.global_position.distance_to(camera.global_position)])
	Input.action_release("move_forward")


func _chase_run(rover: Node, start: Vector3, heading: Vector3, throttle: float, seconds: float, name: String) -> void:
	if not _wanted(name):
		return
	_place(rover, start, heading)
	await _frames(60)
	rover.camera.make_current()
	rover.get_node("CameraRig")._switch(CHASE)
	Input.action_press("move_forward", throttle)
	await _frames(int(seconds * 60.0))
	await _shot(name)
	print("INFO %s at %.2f m/s" % [prefix + name, rover.linear_velocity.length()])
	Input.action_release("move_forward")


func _shade_run(level: Node, rover: Node, start: Vector3, heading: Vector3) -> void:
	if not (_wanted("moon_sun") or _wanted("moon_shade")):
		return
	_place(rover, start, heading)
	await _frames(60)
	rover.camera.make_current()
	rover.get_node("CameraRig")._switch(CHASE)
	Input.action_press("move_forward", 0.4)
	var sun_taken: bool = false
	# Where the sun was first hidden 1.5 m up, and stayed hidden since (-1: not yet)
	var hidden_from: float = -1.0
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 40000:
		await process_frame
		var travelled: float = (rover.global_position - start).dot(heading)
		if not sun_taken and travelled > 12.0:
			await _shot("moon_sun")
			print("INFO moon_sun at %.2f m/s, sun hidden: %s" % [rover.linear_velocity.length(), _sun_hidden(level, rover)])
			sun_taken = true
		elif sun_taken:
			# Hidden 1.5 m up (the rover and most of its spray), all the last 4 m (a crate on the
			# apron hides the sun from a single point well before the building's shadow)
			if not _sun_hidden(level, rover, 1.5):
				hidden_from = -1.0
				continue
			if hidden_from < 0.0:
				hidden_from = travelled
			if travelled - hidden_from < 4.0:
				continue
			await _shot("moon_shade")
			print("INFO moon_shade at %.2f m/s, sun hidden: %s" % [rover.linear_velocity.length(), _sun_hidden(level, rover)])
			break
	Input.action_release("move_forward")


# Whether something (the workshop) stands between the sun and the point `height` over the rover
func _sun_hidden(level: Node, rover: Node3D, height: float = 0.4) -> bool:
	var lights: Array = level.find_children("*", "DirectionalLight3D", true, false)
	var to_sun: Vector3 = (lights[0] as Node3D).global_basis.z
	var origin: Vector3 = rover.global_position + Vector3.UP * height
	var query := PhysicsRayQueryParameters3D.create(origin, origin + to_sun * 60.0, 1)
	query.exclude = [rover.get_rid()]
	return not rover.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _front_run(level: Node, rover: Node, start: Vector3, heading: Vector3, name: String) -> void:
	if not _wanted(name):
		return
	_place(rover, start, heading)
	await _frames(60)
	var at: Vector3 = start + heading * 12.0
	var side: Vector3 = heading.cross(Vector3.UP).normalized()
	var eye: Vector3 = at + heading * 3.0 + side * 2.5
	eye.y = _ground(level, eye.x, eye.z) + 0.6
	camera.global_transform = Transform3D(Basis.looking_at(at + Vector3.UP * 0.3 - eye, Vector3.UP), eye)
	camera.make_current()
	Input.action_press("move_forward", 0.3)
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 40000:
		await process_frame
		if (rover.global_position - start).dot(heading) > 12.0:
			break
	await _shot(name)
	Input.action_release("move_forward")


func _load(level_id: String) -> Node:
	SL.load_scene(level_id)
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == level_id):
		await process_frame
	await _frames(30)
	var level: Node = SL.current_scene
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.far = 2000.0
	camera.near = 0.02
	level.add_child(camera)
	return level


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	DisplayServer.window_move_to_foreground()
	# Full frame rate even if the window loses the focus (main.gd caps an unfocused window at
	# 30 fps, and the captured frames then lag the rover by most of a second)
	root.get_node("Main").throttle_when_unfocused = false
	Engine.max_fps = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for arg in OS.get_cmdline_user_args():
		if arg == "surface_effects=low":
			prefix = "low_"
		elif arg.begins_with("only="):
			only = arg.get_slice("=", 1)
	while GS.state != GS.State.MAIN_MENU:
		await process_frame

	# --- Moon: open ground 30 m out from the workshop's door, driving away from it ---
	var level: Node = await _load("moon_level")
	var rover: Node = level.get_node("ReadyRover")
	var workshop: Node3D = level.get_node("Workshop")
	GS.drive(rover)
	_hide_huds()
	var heading: Vector3 = -workshop.global_basis.z
	heading = Vector3(heading.x, 0.0, heading.z).normalized()
	var start: Vector3 = workshop.to_global(Vector3(0.0, 0.0, -30.0))
	start.y = _ground(level, start.x, start.z) + 0.3
	await _side_run(level, rover, start, heading, 0.3, 14.0, "moon_side_cruise", false)
	await _side_run(level, rover, start, heading, 0.3, 14.0, "moon_trails", true)
	await _side_run(level, rover, start, heading, 1.0, 40.0, "moon_side_full", false)
	await _chase_run(rover, start, heading, 1.0, 5.0, "moon_chase")
	await _front_run(level, rover, start, heading, "moon_front")
	# Sun and the workshop's shadow (the sun is low in the east: the shadow lies west of it),
	# driving south past its west side at 40%, the chase camera behind: shot in the sun 20 m
	# before the building, then as soon as the sun is hidden from the rover (a ray towards it)
	var west: Vector3 = workshop.global_position + Vector3(-9.0, 0.0, 0.0)
	var from: Vector3 = west + Vector3(0.0, 0.0, -32.0)
	from.y = _ground(level, from.x, from.z) + 0.3
	await _shade_run(level, rover, from, Vector3(0.0, 0.0, 1.0))

	# --- Test level: open floor east of the sandbox ---
	if not (only.is_empty() or only.begins_with("test")):
		quit()
		return
	level = await _load("test_level")
	rover = level.get_node("ReadyRover")
	GS.drive(rover)
	_hide_huds()
	start = Vector3(30.0, 0.3, 50.0)
	heading = Vector3(0.0, 0.0, -1.0)
	await _side_run(level, rover, start, heading, 0.3, 14.0, "test_side_cruise", false)
	await _side_run(level, rover, start, heading, 0.3, 14.0, "test_trails", true)
	await _side_run(level, rover, start, heading, 1.0, 40.0, "test_side_full", false)
	await _chase_run(rover, start, heading, 1.0, 4.0, "test_chase")
	quit()


func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
