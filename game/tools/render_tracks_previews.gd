extends SceneTree
## Renders the tyre tracks (TyreTracks) into tools/previews/tracks/ (repo root): the rover drives a
## course on open ground on the Moon (60 m straight, an S-bend, a few metres in reverse), then the
## views below; then the test level's floor. Needs a window (not --headless):
##
##     Godot --path game -s res://tools/render_tracks_previews.gd --resolution 1920x1080
##     (append `-- surface_effects=low` for the Low setting; the files then start with low_)
##
## Shots: moon_close (1.4 m up, looking down at the prints: treads, grousers, berms), moon_reverse
## (where it backed up: the grousers point the other way), moon_chase (the game's chase camera,
## parked at the end), moon_long (low, looking back along the 60 m straight to the workshop),
## moon_mast (the mast camera looking back), moon_parked (the rover standing on its tracks: nothing
## painted on it), test_floor (the test level's floor after a drive). Also prints which materials
## draw tracks (only the ground's: not the rocks', not a rover's).

const OUT_DIR: String = "res://../tools/previews/tracks"
const CHASE: int = 0
const MAST: int = 1

var GS: Node
var SL: Node
var prefix: String = ""
var camera: Camera3D


func _initialize() -> void:
	_watchdog(600.0)
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _frames(count: int) -> void:
	DisplayServer.window_move_to_foreground()
	for i in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames(20)
	var image: Image = root.get_texture().get_image()
	image.save_jpg(ProjectSettings.globalize_path(OUT_DIR + "/" + prefix + name + ".jpg"), 0.9)
	print("SHOT %s" % (prefix + name))


func _hide_huds() -> void:
	for ui in ["HUD", "RobotHUD"]:
		var hud: Node = root.get_node("Main").find_child(ui, true, false)
		if hud:
			hud.visible = false


func _ground(level: Node, x: float, z: float) -> float:
	var terrain: Node = level.get_node_or_null("Terrain")
	return terrain.height_at(x, z) if terrain else 0.0


func _look(level: Node, eye: Vector3, at: Vector3) -> void:
	camera.global_transform = Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye)
	camera.make_current()


# Drives with `throttle` and `steer` (-1 left .. 1 right) for `seconds`
func _drive(throttle: float, steer: float, seconds: float) -> void:
	if throttle > 0.0:
		Input.action_press("move_forward", throttle)
	elif throttle < 0.0:
		Input.action_press("move_backward", -throttle)
	if steer < 0.0:
		Input.action_press("move_left", -steer)
	elif steer > 0.0:
		Input.action_press("move_right", steer)
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < seconds * 1000.0:
		await process_frame
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(a)


func _stop(rover: Node) -> void:
	var started: int = Time.get_ticks_msec()
	while rover.linear_velocity.length() > 0.02 and Time.get_ticks_msec() - started < 8000:
		await process_frame


func _load(level_id: String) -> Node:
	SL.load_scene(level_id)
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == level_id):
		await process_frame
	await _frames(30)
	var level: Node = SL.current_scene
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.far = 3000.0
	camera.near = 0.02
	level.add_child(camera)
	return level


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	DisplayServer.window_move_to_foreground()
	root.get_node("Main").throttle_when_unfocused = false
	Engine.max_fps = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if OS.get_cmdline_user_args().has("surface_effects=low"):
		prefix = "low_"
	while GS.state != GS.State.MAIN_MENU:
		await process_frame

	# --- Moon ---
	var level: Node = await _load("moon_level")
	var rover: Node = level.get_node("ReadyRover")
	var workshop: Node3D = level.get_node("Workshop")
	var terrain: Node = level.get_node("Terrain")
	var tracks: Node = level.get_node("TyreTracks")
	print("CHECK materials drawing tracks: %d, the play tier's: %s, the rocks' draw them: %s" % [
		tracks.materials.size(), tracks.materials == [terrain.materials["play"]],
		terrain.materials["rocks"].get_shader_parameter("tracks_enabled")])
	var heading: Vector3 = -workshop.global_basis.z
	heading = Vector3(heading.x, 0.0, heading.z).normalized()
	var side: Vector3 = heading.cross(Vector3.UP).normalized()
	var start: Vector3 = workshop.to_global(Vector3(0.0, 0.0, -24.0))
	start.y = _ground(level, start.x, start.z) + 0.3
	rover.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), start)
	GS.drive(rover)
	_hide_huds()
	await _frames(60)
	# The course: 60 m straight, an S-bend, then back a few metres
	var straight_end: Vector3 = start + heading * 60.0
	Input.action_press("move_forward", 0.35)
	var started: int = Time.get_ticks_msec()
	while (rover.global_position - start).dot(heading) < 60.0 and Time.get_ticks_msec() - started < 60000:
		await process_frame
	Input.action_release("move_forward")
	await _drive(0.3, -0.8, 3.0)
	await _drive(0.3, 0.8, 3.0)
	await _drive(0.3, 0.0, 2.0)
	await _stop(rover)
	var reverse_from: Vector3 = rover.global_position
	await _drive(-0.3, 0.0, 2.5)
	await _stop(rover)
	tracks.map.update_residency(Vector2(rover.global_position.x, rover.global_position.z))
	print("INFO %d points in the log, %d fine tiles held" % [tracks.track_log.point_count(), tracks.map.tiles.size()])

	# Close up on the straight, 20 m in: 1.4 m up beside the right-hand track, the sun to the side
	var at: Vector3 = start + heading * 20.0 + side * 0.5
	at.y = _ground(level, at.x, at.z)
	var eye: Vector3 = at + side * 1.2 - heading * 1.0
	eye.y = _ground(level, eye.x, eye.z) + 1.4
	tracks.map.update_residency(Vector2(at.x, at.z))
	await _frames(40)
	_look(level, eye, at)
	await _shot("moon_close")
	# Where it backed up
	at = reverse_from - (rover.global_basis.z * -1.0).normalized() * 0.0
	at.y = _ground(level, at.x, at.z)
	eye = at + rover.global_basis.x.normalized() * 1.6 + Vector3.UP * 1.6
	tracks.map.update_residency(Vector2(at.x, at.z))
	await _frames(40)
	_look(level, eye, at)
	await _shot("moon_reverse")
	# The rover parked on its tracks, the chase camera
	tracks.map.update_residency(Vector2(rover.global_position.x, rover.global_position.z))
	await _frames(40)
	rover.camera.make_current()
	rover.get_node("CameraRig")._switch(CHASE)
	await _shot("moon_chase")
	# Low, looking back along the straight to the workshop
	eye = straight_end - heading * 2.0 + side * 0.9
	eye.y = _ground(level, eye.x, eye.z) + 0.6
	_look(level, eye, start - heading * 10.0 + Vector3.UP * (start.y - 0.3))
	tracks.map.update_residency(Vector2(eye.x, eye.z))
	await _frames(40)
	await _shot("moon_long")
	# The mast camera looking back
	rover.camera.make_current()
	rover.get_node("CameraRig")._switch(MAST)
	rover.controller.camera_azimuth = PI
	rover.controller.camera_altitude = deg_to_rad(-15.0)
	await _shot("moon_mast")
	# From beside the parked rover: the body and wheels clean
	eye = rover.global_position + rover.global_basis.x.normalized() * 2.2 + Vector3.UP * 0.9
	_look(level, eye, rover.global_position)
	await _shot("moon_parked")

	# --- Test level ---
	level = await _load("test_level")
	rover = level.get_node("ReadyRover")
	GS.drive(rover)
	_hide_huds()
	rover.global_transform = Transform3D(Basis.IDENTITY, Vector3(30.0, 0.3, 40.0))
	await _frames(60)
	await _drive(0.35, 0.0, 3.0)
	await _drive(0.35, -0.7, 3.0)
	await _drive(0.35, 0.0, 2.0)
	await _stop(rover)
	tracks = level.get_node("TyreTracks")
	var floor_node: Node = level.get_node("NavigationRegion3D/CSGBox3D")
	print("INFO test level: %d points, %d fine tiles held, floor draws tracks: %s" % [tracks.track_log.point_count(), tracks.map.tiles.size(),
		floor_node.material_override.get_shader_parameter("tracks_enabled")])
	# Behind the rover, looking down at the turn it drove
	var back: Vector3 = rover.global_position + rover.global_basis.z.normalized() * 4.0
	_look(level, back + Vector3(1.5, 2.2, 0.0), rover.global_position + rover.global_basis.z.normalized() * 1.0)
	tracks.map.update_residency(Vector2(rover.global_position.x, rover.global_position.z))
	await _frames(40)
	await _shot("test_floor")
	quit()


func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
