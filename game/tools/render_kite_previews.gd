extends SceneTree
## Renders Kite and the cargo delivery in the Moon level into tools/previews/kite/ (repo root), to
## check them in the game's lighting (tools/blender/KITE_KIT.md). Needs a window (not --headless):
##
##     Godot --path game -s res://tools/render_kite_previews.gd --resolution 1920x1080
##
## Shots: Kite from the approach gate; the mast view scanning it (HUD on); the rover parked in the
## delivery window, chase camera (HUD on, the "In position" hint); the arm carrying the cartridge
## over, and the stroke into the port, from beside them; Kite afterwards, its light green. Prints a
## MEASURE line per shot: the mean brightness (0-1) of the middle of the screen and the share of
## nearly black pixels in it.

const OUT_DIR: String = "res://../tools/previews/kite"
const APPROACH := Vector2(0.637, -0.771)     # the heading into Kite (azimuth 39.6)
const YAW_AXIS := Vector2(-0.12, 0.53)       # the arm's yaw axis (right, forward) from the rover's origin
const PARK_D: float = 0.51

var GS: Node
var SL: Node
var level: Node3D
var rover: RigidBody3D
var kite: Node3D
var side_camera: Camera3D


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


## Off: both HUDs hidden. On: the robot HUD only, as when driving
func _huds(on: bool) -> void:
	for ui in ["HUD", "RobotHUD"]:
		var hud: Node = root.get_node("Main").find_child(ui, true, false)
		if hud:
			hud.visible = on and ui == "RobotHUD"


func _ground(x: float, z: float) -> float:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 50.0, z), Vector3(x, -50.0, z), 1)
	return level.get_world_3d().direct_space_state.intersect_ray(ray)["position"].y


## A free camera `height` m above the ground at (x, z), looking at `at`
func _side_view(x: float, z: float, height: float, at: Vector3) -> void:
	side_camera.global_position = Vector3(x, _ground(x, z) + height, z)
	side_camera.look_at(at)
	side_camera.current = true


func _aim_mast_at(world_point: Vector3) -> void:
	var local: Vector3 = rover.to_local(world_point)
	var cam: Vector3 = rover.to_local(rover.camera.global_position)
	var d: Vector3 = local - cam
	rover.controller.camera_azimuth = atan2(-d.x, -d.z)
	rover.controller.camera_altitude = atan2(d.y, Vector2(d.x, d.z).length())


## Puts the rover down `back` m behind its parking spot, heading into Kite
func _place_rover(back: float) -> void:
	var port := Vector2(kite.port.global_position.x, kite.port.global_position.z)
	var right := Vector2(-APPROACH.y, APPROACH.x)
	var spot: Vector2 = port - APPROACH * (PARK_D + YAW_AXIS.y + back) - right * YAW_AXIS.x
	var basis := Basis.looking_at(Vector3(APPROACH.x, 0.0, APPROACH.y), Vector3.UP)
	rover.global_transform = Transform3D(basis, Vector3(spot.x, _ground(spot.x, spot.y) + 0.3, spot.y))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO


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
	level = SL.current_scene
	kite = level.get_node("Kite")
	rover = level.get_node("ReadyRover")
	side_camera = Camera3D.new()
	side_camera.fov = 50.0
	level.add_child(side_camera)
	rover.get_node("CargoSocket").mount(level.get_node("Workshop").rack_stock.get_node("Slot17"))
	await _frames(30)

	# Kite from the approach gate (the gate's posts in front)
	_huds(false)
	var gate: Vector3 = (level.get_node("KiteGate/PostLeft").global_position + level.get_node("KiteGate/PostRight").global_position) / 2.0
	var back := Vector3(-APPROACH.x, 0.0, -APPROACH.y)
	_side_view(gate.x + back.x * 4.0, gate.z + back.z * 4.0, 1.6, kite.global_position + Vector3.UP * 0.3)
	await _frames(60)
	await _shot("kite_from_gate")

	# Scanning: 12 m out, mast view, HUD on
	_place_rover(11.5)
	GS.drive(rover)
	await _frames(120)
	rover.get_node("CameraRig")._switch(1)
	_aim_mast_at(kite.global_position + Vector3.UP * 0.35)
	_huds(true)
	await _frames(70)                        # about half the 1.5 s hold
	await _shot("mast_scanning")
	while not kite.is_scanned:
		await process_frame
	await _frames(10)
	await _shot("mast_scanned")

	# Parked in the window, chase camera, HUD on
	_place_rover(0.0)
	await _frames(180)
	rover.controller.camera_azimuth = 0.0
	rover.controller.camera_altitude = 0.0
	rover.get_node("CameraRig")._switch(0)
	await _frames(60)
	var m: Dictionary = rover.get_node("CargoDelivery").measure(kite.port)
	print("PLACE rover at %s heading %s, port at %s, d %.3f bearing %+.1f, hint \"%s\"" % [rover.global_position,
		-rover.global_basis.z, kite.port.global_position, m["d"], m["bearing"], rover.get_node("CargoDelivery").get_hint()])
	await _shot("parked_chase_hint")
	_huds(false)
	var pair: Vector3 = (rover.global_position + kite.global_position) / 2.0
	var side := Vector3(-APPROACH.y, 0.0, APPROACH.x)
	_side_view(pair.x + side.x * 3.0 - APPROACH.x * 2.0, pair.z + side.z * 3.0 - APPROACH.y * 2.0, 3.5, pair)
	await _shot("parked_above")
	side_camera.current = false
	rover.camera.current = true

	# The delivery, from beside it (Kite's right, looking across)
	var delivery: Node = rover.get_node("CargoDelivery")
	print("PLACE E starts the delivery: %s" % delivery.handle_interact())
	_huds(false)
	var port: Vector3 = kite.port.global_position
	var across := Vector3(-APPROACH.y, 0.0, APPROACH.x)          # the rover's right
	var mid: Vector3 = port - Vector3(APPROACH.x, 0.0, APPROACH.y) * 0.45
	_side_view(mid.x + across.x * 2.2, mid.z + across.z * 2.2, 0.9, mid + Vector3.UP * 0.45)
	while delivery.phase != delivery.Phase.TRANSIT:
		await process_frame
	await _frames(40)
	await _shot("delivery_transit_side")
	while delivery.phase != delivery.Phase.STROKE:
		await process_frame
	await _frames(50)
	_side_view(mid.x + across.x * 1.1 - APPROACH.x * 0.6, mid.z + across.z * 1.1 - APPROACH.y * 0.6, 1.1, port)
	await _shot("delivery_stroke_close")
	while delivery.is_busy():
		await process_frame
	await _frames(30)
	_side_view(mid.x + across.x * 2.2, mid.z + across.z * 2.2, 0.9, mid + Vector3.UP * 0.45)
	await _shot("delivered_side")
	_side_view(port.x + APPROACH.x * 1.2 + across.x * 0.8, port.z + APPROACH.y * 1.2 + across.z * 0.8, 1.2, port)
	await _shot("kite_green_light")
	print("RESULT kite previews: scanned %s, cartridge in %s" % [kite.is_scanned, kite.has_cartridge])
	quit()


func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
