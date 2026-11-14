extends SceneTree
## Renders the three mission images the PLAY popup's save cards show (SaveIndex.MISSION_IMAGE_DIR,
## res/ui/missions/<mission id>.png, 960x540) from the Moon level, with no UI. Needs a window (not
## --headless); re-run it to refresh them after the art changes:
##
##     Godot --path game -s res://tools/render_mission_images.gd --resolution 960x540
##
## wake_kite: the rover on the workshop's pad, the parts rack and the sample bench behind it, in the
## workshop's warm light. first_signal: the rover parked beside IRIS, IRIS online (indicator lit,
## antenna tracking). beyond_the_rim: the rover by the far rim marker on Head crater's east rim,
## the far logger nearby and the shadow line behind it.
## Pass `-- --only=<id>` to render one image, `-- --dir=<dir>` to write elsewhere.

const OUT_DIR: String = "res://res/ui/missions"
const SIZE := Vector2i(960, 540)

var GS: Node
var SL: Node
var level: Node3D
var rover: RigidBody3D
var camera: Camera3D
var only: String = ""
var out_dir: String = OUT_DIR


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		elif arg.begins_with("--dir="):
			out_dir = arg.trim_prefix("--dir=")
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
	if image.get_size() != SIZE:
		image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	var path: String = ProjectSettings.globalize_path(out_dir + "/" + name + ".png")
	image.save_png(path)
	print("SHOT %s -> %s" % [name, path])


func _hide_huds() -> void:
	for ui in ["HUD", "RobotHUD"]:
		var hud: Node = root.get_node("Main").find_child(ui, true, false)
		if hud:
			hud.visible = false


func _ground(x: float, z: float) -> float:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -80.0, z), 1)
	return level.get_world_3d().direct_space_state.intersect_ray(ray)["position"].y


func _view(from: Vector3, at: Vector3, fov: float = 55.0) -> void:
	camera.fov = fov
	camera.global_position = from
	camera.look_at(at)
	camera.current = true


## A camera `height` m above the ground at (x, z)
func _view_ground(x: float, z: float, height: float, at: Vector3, fov: float = 55.0) -> void:
	_view(Vector3(x, _ground(x, z) + height, z), at, fov)


func _put_rover(spot: Vector3, heading: Vector3) -> void:
	var h := Vector3(heading.x, 0.0, heading.z).normalized()
	rover.global_transform = Transform3D(Basis.looking_at(h, Vector3.UP), Vector3(spot.x, _ground(spot.x, spot.z) + 0.3, spot.z))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO


func _wanted(id: String) -> bool:
	return only.is_empty() or only == id


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	DisplayServer.window_move_to_foreground()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await process_frame
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	camera = Camera3D.new()
	level.add_child(camera)
	_hide_huds()
	await _frames(60)

	if _wanted("wake_kite"):
		await _wake_kite()
	if _wanted("first_signal"):
		await _first_signal()
	if _wanted("beyond_the_rim"):
		await _beyond_the_rim()
	print("RESULT mission images done")
	quit()


func _wake_kite() -> void:
	var workshop: Node3D = level.get_node("Workshop")
	rover.global_transform = workshop.get_dock_transform()
	rover.linear_velocity = Vector3.ZERO
	await _frames(120)
	# Kit axes (x, y, up) -> the workshop's local (x, up, -y)
	var from: Vector3 = workshop.to_global(Vector3(0.9, 1.5, -2.0))
	var at: Vector3 = workshop.to_global(Vector3(-0.3, -0.7, 2.6))
	_view(from, at, 65.0)
	await _shot("wake_kite")


func _first_signal() -> void:
	var iris: Node3D = level.get_node("Iris")
	var front: Vector3 = -iris.global_basis.z
	var right: Vector3 = iris.global_basis.x
	var base: Vector3 = iris.global_position
	level.get_node("IrisGate").visible = false   # its posts and signs would stand in front of the rover
	var spot: Vector3 = base + front * 3.0 + right * 3.2
	_put_rover(spot, front * 0.5 - right)
	await _frames(180)
	iris.set_online(true)
	await create_timer(iris.ANTENNA_TIME + 0.5).timeout
	var from: Vector3 = base + front * 7.0 - right * 4.5
	_view_ground(from.x, from.z, 1.2, base.lerp(spot, 0.5) + Vector3.UP * 1.0, 45.0)
	await _shot("first_signal")


func _beyond_the_rim() -> void:
	var marker: Vector3 = level.get_node("FarRimMarker").global_position
	var logger: Vector3 = level.get_node("FarLogger").global_position
	# The sun is in the east (+x): stand east of the rim, so the rover and the logger are lit and
	# the crater's shadow lies ahead, to the west
	var spot: Vector3 = logger + Vector3(4.0, 0.0, -1.0)
	_put_rover(spot, logger - spot)
	await _frames(180)
	var from: Vector3 = logger + Vector3(3.5, 0.0, 6.5)
	_view_ground(from.x, from.z, 1.4, logger + Vector3(-1.5, 0.3, -2.0), 60.0)
	await _shot("beyond_the_rim")


func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
