extends SceneTree
## A scripted demo of the first-person spacesuit body (src/player/body/, PlayerBody) in the Moon
## workshop, for judging the animation: walking, sprinting, strafing, turning on the spot,
## crouching, grabbing the cartridge (one hand) and a wheel (both hands), carrying, throwing and
## dropping, and Moon jumps. First from the player's own camera, then the same moves from a
## chase camera (with the helmet drawn, which the player's camera never shows). A caption names
## each move. Everything goes through the real input actions (Input.action_press).
##
## Record it with Movie Maker (a window; Godot runs the frames at a fixed 60 fps):
##   Godot --path game --resolution 1280x720 --write-movie <out>.avi -s res://tools/record_player_body.gd
## then, e.g., ffmpeg -i <out>.avi -c:v libx264 -crf 20 -pix_fmt yuv420p <out>.mp4

const TICKS: int = 240

var GS: Node
var SL: Node
var player
var body
var workshop
var caption: Label
var chase: Camera3D = null
var _held_keys: Array[String] = []


func _initialize() -> void:
	# The recording runs in a window on a desktop someone may be using: it takes no focus, so no
	# real key, click or mouse movement reaches the game, and Esc / the console key do nothing
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	InputMap.action_erase_events("ui_cancel")
	InputMap.action_erase_events("console")
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _say(text: String) -> void:
	caption.text = text


func _hold(actions: Array) -> void:
	for a in actions:
		Input.action_press(a)
		_held_keys.append(a)


func _let_go() -> void:
	for a in _held_keys:
		Input.action_release(a)
	_held_keys.clear()


func _tap(action: String) -> void:
	Input.action_press(action)
	await _ticks(0.05)
	Input.action_release(action)
	await _ticks(0.05)


## Workshop kit coordinates (x east, y north, metres) to the world, on the floor
func _kit(x: float, y: float, z: float = 0.0) -> Vector3:
	return workshop.to_global(Vector3(x, z, -y))


## Turns the view smoothly to (azimuth, altitude) in degrees over `seconds`
func _look(azimuth: float, altitude: float, seconds: float) -> void:
	var c = player.controller
	var a0: float = c.camera_azimuth
	var a1: float = a0 + wrapf(deg_to_rad(azimuth) - a0, -PI, PI)
	var b0: float = c.camera_altitude
	var n: int = maxi(1, int(seconds * TICKS))
	for i in n:
		var t: float = smoothstep(0.0, 1.0, float(i + 1) / n)
		c.camera_azimuth = lerpf(a0, a1, t)
		c.camera_altitude = lerpf(b0, deg_to_rad(altitude), t)
		await physics_frame


## Azimuth and altitude (degrees) that look from the eye at `point`
func _aim(point: Vector3) -> Vector2:
	var d: Vector3 = point - player.camera.global_position
	var yaw: float = atan2(-d.x, -d.z) - player.global_basis.get_euler().y
	return Vector2(rad_to_deg(yaw), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))


func _walk_to(point: Vector3, keys: Array, timeout: float) -> void:
	var t: float = 0.0
	_hold(keys)
	while t < timeout:
		var d: Vector3 = point - player.global_position
		d.y = 0.0
		if d.length() < 0.35:
			break
		player.controller.camera_azimuth = lerp_angle(player.controller.camera_azimuth,
			atan2(-d.x, -d.z) - player.global_basis.get_euler().y, 0.05)
		await physics_frame
		t += 1.0 / TICKS
	_let_go()


func _pick_up(part: RigidBody3D) -> void:
	var aim: Vector2 = _aim(part.global_position)
	await _look(aim.x, aim.y, 0.6)
	await _ticks(0.2)
	await _tap("interact_use")
	if player.holder.held_object != part:
		player.holder.pickup(part)      # the ray missed: the demo goes on
	await _ticks(0.8)


func _show_helmet(shown: bool) -> void:
	body.helmet_mesh.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shown
		else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)


func _process(_delta: float) -> bool:
	# The game pauses if the window loses focus mid-recording; the recording carries on
	if GS and GS.state == GS.State.PAUSED:
		GS.change_state_to(GS.State.IN_GAME_PLAYER)
	# The chase camera: 2.4 m to the player's right and a little behind, above chest height,
	# pulled in short of any wall between it and the player
	if chase and player:
		var view: Basis = player.pivot.global_basis
		var target: Vector3 = player.global_position + Vector3.UP * 1.0
		var spot: Vector3 = target + view * Vector3(2.4, 0.5, 1.2)
		var ray := PhysicsRayQueryParameters3D.create(target, spot, 1)
		ray.exclude = [player.get_rid()]
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit:
			spot = target + (hit["position"] - target) * 0.85
		chase.global_position = chase.global_position.lerp(spot, 0.1)
		chase.look_at(target)
	return false


## Puts the player at kit (x, y), still, standing, facing `facing` degrees from kit north (+y,
## towards the bay door) clockwise, looking `altitude` degrees up
func _place(x: float, y: float, facing: float, altitude: float = -5.0) -> void:
	_let_go()
	if player.want_to_crouch:
		player._on_controller_crouch(false)
	var a: float = deg_to_rad(facing)
	var ahead: Vector3 = _kit(x + sin(a) * 5.0, y + cos(a) * 5.0, 1.5)
	player.global_position = _kit(x, y, 0.05)
	player.linear_velocity = Vector3.ZERO
	player.controller.camera_azimuth = deg_to_rad(_aim(ahead).x)
	player.controller.camera_altitude = deg_to_rad(altitude)
	await _ticks(0.6)


func _azimuth() -> float:
	return rad_to_deg(player.controller.camera_azimuth)


## The bay's open west lane (kit x -4.3 to -2.3, y -3.0 to 3.0) and the rack on its south wall
func _sequence(label: String) -> void:
	await _place(-3.3, -2.2, 0.0)
	var az: float = _azimuth()
	_say(label + "Looking down: chest, legs and boots under the camera (no helmet, no shoulders in view)")
	await _look(az, -60.0, 1.0)
	await _ticks(1.0)
	await _look(az, -88.0, 0.8)
	await _ticks(1.2)
	await _look(az, -5.0, 0.8)
	_say(label + "Walking 2 m/s (boots planted, no camera bob)")
	_hold(["move_forward"])
	await _ticks(0.9)
	_say(label + "Walking, looking down at the boots")
	await _look(az, -65.0, 0.5)
	await _ticks(1.0)
	await _look(az, -5.0, 0.4)
	_let_go()
	await _ticks(0.5)
	_say(label + "Walking backwards (its own clip: the toe lands first)")
	await _look(az, -40.0, 0.4)
	_hold(["move_backward"])
	await _ticks(2.0)
	_let_go()
	await _ticks(0.4)
	_say(label + "Strafing: the legs turn, the waist bearing twists")
	await _look(az + 90.0, -45.0, 0.6)
	_hold(["move_left"])
	await _ticks(1.4)
	_let_go()
	await _ticks(0.4)

	await _place(-3.3, -3.0, 0.0)
	az = _azimuth()
	_say(label + "Sprinting 3 m/s")
	_hold(["move_forward", "move_sprint"])
	await _ticks(1.5)
	_let_go()
	await _ticks(0.6)
	_say(label + "Turning on the spot: the boots step round once the view is 50 degrees off")
	await _look(az - 120.0, -45.0, 1.6)
	await _ticks(1.2)

	await _place(-3.3, -2.6, 0.0, -20.0)
	az = _azimuth()
	_say(label + "Crouching (the eye drops to 0.75 m)")
	_hold(["move_crouch"])
	await _ticks(1.4)
	_say(label + "Crouch walking 1 m/s")
	_hold(["move_forward"])
	await _ticks(2.0)
	_let_go()
	await _ticks(1.0)

	# Grabbing at the rack (its fronts face north, into the bay)
	var cartridge: RigidBody3D = null
	var wheel: RigidBody3D = null
	for slot in workshop.rack_stock.get_children():
		if slot.is_queued_for_deletion():
			continue
		if slot.get("catalog_id") == "cartridge":
			cartridge = slot
		elif not wheel and slot.get("part_type") == 0 and slot.get("radius") != null:
			wheel = slot
	var north: Vector3 = (_kit(0.0, 1.0) - _kit(0.0, 0.0)).normalized()
	_say(label + "Grabbing the cartridge: one hand")
	player.global_position = cartridge.global_position + north * 0.85
	player.global_position.y = _kit(0.0, 0.0, 0.05).y
	player.linear_velocity = Vector3.ZERO
	await _ticks(0.4)
	await _pick_up(cartridge)
	_say(label + "Turning round with it")
	await _look(_azimuth() + 180.0, -25.0, 1.2)
	_say(label + "Carrying it")
	_hold(["move_forward"])
	await _ticks(1.0)
	_let_go()
	await _ticks(0.4)
	_say(label + "Throwing it: the arm follows through")
	await _look(_azimuth(), 10.0, 0.4)
	await _tap("interact_primary")
	await _ticks(1.4)
	_say(label + "Grabbing a wheel: both hands")
	player.global_position = wheel.global_position + north * 0.85
	player.global_position.y = _kit(0.0, 0.0, 0.05).y
	player.linear_velocity = Vector3.ZERO
	await _ticks(0.4)
	await _pick_up(wheel)
	await _look(_azimuth() + 180.0, -35.0, 1.2)
	_say(label + "Carrying it, looking down")
	_hold(["move_forward"])
	await _ticks(0.6)
	await _look(_azimuth(), -60.0, 0.5)
	await _ticks(0.8)
	_let_go()
	await _look(_azimuth(), -30.0, 0.5)
	_say(label + "Dropping it: the hands open")
	await _tap("interact_use")
	await _ticks(1.4)

	# Moon jumps, in the open lane
	await _place(-3.3, -1.8, 0.0, -35.0)
	_say(label + "Jumping on the Moon (2.3 s in the air), looking down")
	await _tap("move_jump")
	await _ticks(2.8)
	await _place(-3.3, -2.8, 0.0, -20.0)
	_say(label + "Jumping while walking")
	_hold(["move_forward"])
	await _ticks(0.4)
	await _tap("move_jump")
	await _ticks(2.6)
	_let_go()
	await _ticks(0.8)
	# Put the parts back on the rack for the next pass
	workshop.restock_trigger.interacted.emit(player)
	await _ticks(1.0)


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	await _ticks(2.0)
	workshop = SL.current_scene.get_node("Workshop")
	player = GS.player
	body = player.get_node("Body")
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	caption.position = Vector2(-560, 24)
	caption.size = Vector2(1120, 40)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(caption)

	await _sequence("Player's view: ")
	_say("")
	chase = Camera3D.new()
	chase.fov = 60.0
	SL.current_scene.add_child(chase)
	chase.global_position = player.global_position + Vector3(2.0, 1.5, 2.0)
	chase.make_current()
	_show_helmet(true)
	await _sequence("Chase camera: ")
	_say("")
	await _ticks(0.5)
	quit()
