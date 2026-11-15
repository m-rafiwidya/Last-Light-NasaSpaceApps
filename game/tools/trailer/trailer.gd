extends SceneTree
## Renders one clip of the LAST LIGHT trailer with Movie Maker; render.sh runs it per clip:
##     Godot --path game --write-movie <out>/clip_5.avi --fixed-fps 30 --resolution 1920x1080 \
##         -s res://tools/trailer/trailer.gd -- clip=5
## The clip is the last (end - start + xfade) seconds of the movie; everything before is setup.

const FPS: float = 30.0
const TIMELINE: String = "res://tools/trailer/timeline.json"
const PARTS: String = "res://src/robot/socket/%s.tscn"
const SLOT: String = "slot_3"
const M1_DONE: Array = ["m1.workshop_entered", "m1.kite_prepared", "m1.iris_scanned", "m1.kite_docked", "m1.inspection_sent"]
const M2_DONE: Array = ["m2.cargo_ordered", "m2.cargo_retrieved", "m2.module_loaded", "m2.module_installed",
	"m2.iris_activated", "m2.kite_docked", "m2.telemetry_received"]
const BUILDS: Dictionary = {
	"crater": {"battery": "battery_part", "wheels": "wheel_high_grip_part", "thermal": true, "turret": true},
	"standard": {"battery": "battery_part", "wheels": "", "thermal": false, "turret": false},
}

var GS: Node
var SL: Node
var CS: Node
var SI: GDScript
var level: Node3D
var rover: RigidBody3D
var director: Node
var routes: Node
var cam: Camera3D
var clip: String = ""
var length: float = 0.0
var driving: bool = false
var general: Variant


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("clip="):
			clip = arg.trim_prefix("clip=")
	var timeline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TIMELINE))
	var clips: Array = timeline["clips"]
	for i in clips.size():
		if clips[i]["id"] == clip:
			length = clips[i]["end"] - clips[i]["start"] + (timeline["xfade"] if i < clips.size() - 1 else 0.0)
	if length <= 0.0:
		push_error("trailer: unknown clip '%s'" % clip)
		quit(1)
		return
	Engine.max_physics_steps_per_frame = 16
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	SI = load("res://src/save/save_index.gd")
	general = load("res://src/settings/general_settings.gd").section
	general.path = "user://trailer_settings.cfg"
	general.set_value("guidance", false)
	general.set_value("subtitles", false)
	for bus in ["Music", "Voice", "UI"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), true)
	await Callable(self, "_clip_" + clip).call()
	print("TRAILER clip %s done" % clip)
	quit()


# --- Setup ---------------------------------------------------------------------------------------

func _m3_state(iris_online: bool = true) -> Dictionary:
	return {"current": "m3", "objectives": M1_DONE + M2_DONE, "missions_done": ["m1", "m2"],
		"flags": ["iris_online", "cargo_delivered"] if iris_online else ["cargo_delivered"],
		"items": {"cargo.service.freighter": 1, "cargo.thermal_kit": 1, "cargo.grip_wheels": 1, "cargo.radio_module": 1},
		"play_time_sec": 2400.0}


## Loads the Moon level: a new campaign (m1) or a campaign state
func _boot(state: Dictionary = {}) -> void:
	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	CS.reset()
	if state.is_empty():
		SI.start_new_campaign(SLOT)
	else:
		CS.load_state(state)
		SI.current_slot = SLOT
		SL.load_scene("moon_level")
	while not (SL.current_level_id == "moon_level" and SL.loading_scene_id.is_empty() and GS.state == GS.State.IN_GAME_PLAYER):
		await process_frame
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	director = level.get_node("MissionDirector")
	routes = level.get_node("RouteMarkers")
	director.apply_mission_sun()
	cam = Camera3D.new()
	cam.name = "TrailerCam"
	level.add_child(cam)
	cam.far = maxf(GS.player.camera.far, 4000.0) if is_instance_valid(GS.player) else 4000.0
	await _wait(1.0)


func _frame_rate() -> float:
	return 240.0 if DisplayServer.get_name() == "headless" else FPS


func _wait(seconds: float) -> void:
	for i in int(seconds * _frame_rate()):
		_hide_ui()
		await process_frame


func _hide_ui() -> void:
	for layer: CanvasLayer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible:
			layer.visible = false


## Runs the recorded part: `step` gets the clip time each frame
func _record(step: Callable) -> void:
	for f in int(round(length * FPS)) + 1:
		_hide_ui()
		step.call(f / FPS)
		await process_frame


func _ground(x: float, z: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -300.0, z), 1)
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if hit else 0.0


func _on_ground(x: float, z: float, height: float) -> Vector3:
	return Vector3(x, _ground(x, z) + height, z)


func _shoot(pos: Vector3, look: Vector3, fov: float, t: float = 0.0, handheld: float = 0.0) -> void:
	if handheld > 0.0:
		pos += Vector3(sin(t * 0.83 + 0.4), sin(t * 1.21 + 1.7) * 0.6, sin(t * 0.67 + 2.9)) * handheld
		look += Vector3(sin(t * 0.51 + 0.9), sin(t * 0.77 + 0.2) * 0.5, sin(t * 0.61 + 1.3)) * handheld * 1.5
	cam.global_position = pos
	cam.look_at(look)
	cam.fov = fov
	if not cam.current:
		cam.make_current()


func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _part(scene: String) -> Node3D:
	var part: Node3D = (load(PARTS % scene) as PackedScene).instantiate()
	level.add_child(part)
	return part


func _remove(socket: Node) -> void:
	var old: RigidBody3D = socket.unmount()
	if old:
		old.freeze = true
		old.global_position = Vector3(0.0, 500.0 + old.get_index(), 0.0)


func _swap(socket: Node, scene: String) -> void:
	_remove(socket)
	var part: Node3D = _part(scene)
	part.global_position = socket.global_position
	socket.mount(part)


func _fit(build: Dictionary) -> void:
	_swap(rover.battery_socket, build["battery"])
	if build["wheels"]:
		for socket in _sockets():
			if socket.part and socket.part.part_type == 0:
				_swap(socket, build["wheels"])
	for pair in [["ThermalCoverSocket", "thermal_cover_part"], ["HeaterSocket", "thermal_heater_part"]]:
		var socket: Node = rover.get_node(pair[0])
		if build["thermal"]:
			_swap(socket, pair[1])
		else:
			_remove(socket)
	if build["turret"]:
		_swap(rover.find_child("ArmToolSocket", true, false), "arm_tool_thermal_part")
	rover.battery.charge = rover.battery.capacity


func _sockets() -> Array:
	return rover.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.has_method("mount") and n.has_method("unmount"))


func _place(at: Vector2, toward: Vector2) -> void:
	var look := Vector3(toward.x - at.x, 0.0, toward.y - at.y).normalized()
	rover.global_transform = Transform3D(Basis.looking_at(look), _on_ground(at.x, at.y, 0.4))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO


func _release() -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(a)


## Drives through world waypoints (x, z) at `speed` until the last or until `driving` is cleared
func _drive(points: Array, speed: float) -> void:
	driving = true
	for i in points.size():
		var target: Vector2 = points[i]
		var last: bool = i == points.size() - 1
		while driving:
			await physics_frame
			var forward: Vector3 = -rover.global_basis.z
			var v: float = rover.linear_velocity.dot(forward)
			var to := Vector2(target.x - rover.global_position.x, target.y - rover.global_position.z)
			var passed: bool = Vector2(forward.x, forward.z).dot(to) < 0.0 and to.length() < 2.0
			if to.length() < 1.5 or (passed and not last):
				break
			var steer: float = clampf(Vector2(forward.x, forward.z).normalized().angle_to(to.normalized()) / 0.25, -1.0, 1.0)
			_release()
			if v > speed + 0.15:
				Input.action_press("move_backward", clampf((v - speed) * 0.6, 0.05, 0.6))
			elif v < speed:
				Input.action_press("move_forward", clampf(0.06 + (speed - v) * 0.3, 0.05, 0.5))
			if steer > 0.05:
				Input.action_press("move_right", steer)
			elif steer < -0.05:
				Input.action_press("move_left", -steer)
	_release()
	driving = false


## Kite's heading as a yaw-only basis, eased so the chase camera doesn't shake with the chassis
var _yaw: float = NAN
func _follow_basis(rate: float = 0.08) -> Basis:
	var f: Vector3 = -rover.global_basis.z
	var yaw: float = atan2(-f.x, -f.z)
	_yaw = yaw if is_nan(_yaw) else lerp_angle(_yaw, yaw, rate)
	return Basis(Vector3.UP, _yaw)


func _press(action: String) -> void:
	Input.action_press(action)
	await _wait(0.1)
	Input.action_release(action)


# --- Clips ---------------------------------------------------------------------------------------

## Low dolly across Head crater at the Apollo 12 EVA 2 sun (16.7 degrees, east)
func _clip_1() -> void:
	await _boot()
	var a := _on_ground(-78.0, 22.0, 1.3)
	var b := _on_ground(-60.0, 26.0, 1.1)
	var look := _on_ground(-40.0, -70.0, 6.0)
	await _record(func(t: float) -> void:
		var k := t / length
		_shoot(a.lerp(b, k), look + Vector3(8.0, 0.0, 0.0) * k, 52.0, t, 0.02))


## The crew lander from the opening, no walk cycle on screen (the astronaut is moved by script in a
## still pose; the lander has no interior to film the hatch from). C: chest-up from a low angle
## against the stars, the astronaut gliding forward from the ramp foot. B: tight on the visor, the
## sun glinting on it, a slow push-in while the astronaut turns slightly toward the horizon.
func _clip_2() -> void:
	await _boot()
	var lander: Node3D = level.get_node("Lander")
	var hatch: Node3D = lander.get_node("Hatch")
	var foot: Node3D = lander.get_node("RampFoot")
	var out: Vector3 = -hatch.global_basis.z
	out.y = 0.0
	out = out.normalized()
	var astronaut: Node3D = load("res://res/models/astronaut_kit/astronaut_fp.glb").instantiate()
	level.add_child(astronaut)
	var animations: AnimationPlayer = astronaut.find_children("*", "AnimationPlayer", true, false)[0]
	animations.play("idle")
	animations.speed_scale = 0.0
	var c_from: Vector3 = foot.global_position + out * 0.6
	c_from.y = _ground(c_from.x, c_from.z)
	var c_to: Vector3 = c_from + out * 1.4
	c_to.y = _ground(c_to.x, c_to.z)
	var sun: Vector3 = level.find_child("WorldEnvironment", true, false).sun_direction()
	var sun_flat := Vector3(sun.x, 0.0, sun.z).normalized()
	var stand: Vector3 = foot.global_position + out * 4.0
	stand.y = _ground(stand.x, stand.z)
	var face_from: Vector3 = sun_flat.rotated(Vector3.UP, deg_to_rad(-35.0))
	var face_to: Vector3 = sun_flat.rotated(Vector3.UP, deg_to_rad(-12.0))
	var cut_at: float = 1.8
	await _record(func(t: float) -> void:
		if t < cut_at:
			var k := t / cut_at
			var at: Vector3 = c_from.lerp(c_to, k) + Vector3.UP * sin(t * 3.0) * 0.015
			astronaut.global_basis = Basis(Vector3.UP, atan2(out.x, out.z)).scaled(Vector3.ONE * 0.95)
			astronaut.global_position = at
			var cam_at: Vector3 = at + out * lerpf(2.0, 1.65, _ease(k)) + Vector3(out.z, 0.0, -out.x) * 0.35
			cam_at.y = _ground(cam_at.x, cam_at.z) + 1.1
			_shoot(cam_at, at + Vector3.UP * 1.5, 30.0, t, 0.008)
		else:
			var k := _ease((t - cut_at) / (length - cut_at))
			var facing: Vector3 = face_from.slerp(face_to, k)
			astronaut.global_basis = Basis(Vector3.UP, atan2(facing.x, facing.z)).scaled(Vector3.ONE * 0.95)
			astronaut.global_position = stand + Vector3.UP * sin(t * 2.6) * 0.008
			var visor: Vector3 = stand + Vector3.UP * 1.55 + face_from * 0.12
			var cam_dir: Vector3 = face_from.rotated(Vector3.UP, deg_to_rad(-25.0))
			_shoot(visor + cam_dir * lerpf(0.95, 0.7, k) + Vector3.UP * 0.02, visor, 30.0, t, 0.004))


## First person, crouched in the bay: the battery goes into Kite's rear socket
func _clip_3a() -> void:
	await _boot()
	var socket: Node = rover.battery_socket
	var battery: RigidBody3D = null
	for part in level.find_children("*", "RigidBody3D", true, false):
		if not part.has_method("get_catalog_id") or not part.get_catalog_id().begins_with("battery") or part.get_parent().has_method("mount"):
			continue
		if battery == null or part.get_catalog_id().contains("light"):
			battery = part
	var back: Vector3 = rover.global_basis.z
	await _hand_in(battery, socket, socket.global_position + Vector3(back.x, 0.0, back.z).normalized() * 0.8, -0.45, 0.8)
	print("TRAILER battery mounted: ", socket.part == battery)


## First person, crouched: a high-grip wheel onto the front-left wheel socket
func _clip_3b() -> void:
	await _boot(_m3_state())
	_fit(BUILDS["crater"])
	var socket: Node = rover.front_left_socket
	_remove(socket)
	var wheel: RigidBody3D = _part("wheel_high_grip_part")
	var side: Vector3 = -rover.global_basis.x
	await _hand_in(wheel, socket, socket.global_position + Vector3(side.x, 0.0, side.z).normalized() * 0.75, -0.5, 0.5)
	print("TRAILER grip wheel mounted: ", socket.part == wheel)


## The player crouches at `stand` facing `socket`, holding `part`; lets go at `release_at` s into
## the clip, then eases the part into the socket's capture if the drop alone missed it
func _hand_in(part: RigidBody3D, socket: Node, stand: Vector3, pitch: float, release_at: float) -> void:
	var player: RigidBody3D = GS.player
	player.global_position = Vector3(stand.x, player.global_position.y, stand.z)
	player.linear_velocity = Vector3.ZERO
	var to: Vector3 = socket.global_position - stand
	player.controller.camera_azimuth = atan2(-to.x, -to.z)
	player.controller.camera_altitude = pitch
	Input.action_press("move_crouch")
	part.global_position = player.camera.global_position - player.camera.global_basis.z * 0.5
	player.holder.pickup(part)
	await _wait(1.5)
	var once: Dictionary = {}
	await _record(func(t: float) -> void:
		if t >= release_at and not once.has("released"):
			once["released"] = true
			player.holder.release()
		if t >= release_at + 0.15 and socket.part != part and t < release_at + 0.45:
			if not once.has("from"):
				once["from"] = part.global_position
				print("TRAILER eased into the socket")
			part.global_position = (once["from"] as Vector3).lerp(socket.global_position + Vector3.UP * 0.04, _ease((t - release_at - 0.15) / 0.25))
			part.linear_velocity = Vector3.ZERO)
	Input.action_release("move_crouch")


## Low dolly along the parts rack in the bay's dim light, shallow focus, then a cut to Kite under the bay lights
func _clip_4() -> void:
	await _boot(_m3_state())
	GS.player.visible = false
	var ws: Node3D = level.get_node("Workshop")
	var along: Vector3 = ws.global_basis.x
	var out: Vector3 = -ws.global_basis.z
	var from: Vector3 = ws.find_child("slot_12", true, false).global_position
	var to: Vector3 = ws.find_child("slot_07", true, false).global_position
	var kite: Vector3 = rover.global_position + Vector3.UP * 0.35
	var attributes: CameraAttributesPractical = _attributes()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_amount = 0.14
	cam.attributes = attributes
	var ahead: Vector3 = -rover.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var cut_at: float = 1.75
	await _record(func(t: float) -> void:
		var pos: Vector3
		var look: Vector3
		var near: float = 0.3
		if t < cut_at:
			var k := t / cut_at
			look = from.lerp(to, k) + along * -0.15
			pos = from.lerp(to, k) + out * 0.7 + along * 0.25 + Vector3.UP * 0.12
		else:
			var k := _ease((t - cut_at) / (length - cut_at))
			look = kite
			pos = kite + ahead * lerpf(2.9, 2.5, k) + Vector3.UP * lerpf(0.05, 0.1, k)
			near = 0.9
		_shoot(pos, look, 42.0 if t < cut_at else 46.0, t, 0.004)
		var focus: float = pos.distance_to(look)
		attributes.dof_blur_far_distance = focus + near
		attributes.dof_blur_far_transition = 0.6 + focus * 0.4
		attributes.dof_blur_near_distance = maxf(focus - near, 0.05)
		attributes.dof_blur_near_transition = 0.2)


## The level's camera attributes (exposure follows the sun) copied, so DOF can be added on top
func _attributes() -> CameraAttributesPractical:
	var env: WorldEnvironment = level.find_child("WorldEnvironment", true, false)
	if env and env.camera_attributes is CameraAttributesPractical:
		return env.camera_attributes.duplicate()
	return CameraAttributesPractical.new()


## Low chase: Kite on grip wheels, headlights on, up the loose rim climb out of Head crater at dusk
func _clip_5() -> void:
	await _boot(_m3_state())
	_fit(BUILDS["crater"])
	GS.drive(rover)
	rover.headlights_on = true
	_place(Vector2(-63.0, -74.0), Vector2(-58.0, -80.0))
	await _wait(1.0)
	_drive([Vector2(-58.0, -80.0), Vector2(-44.0, -83.0), Vector2(-30.0, -86.0)], 3.2)
	await _wait(0.8)
	await _record(func(t: float) -> void:
		var b := _follow_basis(0.05)
		var at: Vector3 = rover.global_position
		_shoot(at + b * Vector3(1.2, 0.35, 3.0), at + b * Vector3(-0.2, 0.6, -6.0), 54.0, t, 0.03))
	driving = false


## Kite without the thermal kit rolls into Head's shade and shuts down. The shutdown staging
## (cold timer shortened, headlights off, power_down.wav) is only here: _stage_shutdown().
func _clip_6() -> void:
	await _boot(_m3_state())
	_fit(BUILDS["standard"])
	GS.drive(rover)
	var path: Array = Array(routes.route("short")).slice(2, 10)
	var entry := Vector2.INF
	var before := Vector2.ZERO
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		for s in int(a.distance_to(b) * 2.0):
			var p: Vector2 = a.lerp(b, s / (a.distance_to(b) * 2.0))
			if director.cold_zone_at(Vector3(p.x, _ground(p.x, p.y), p.y)) != null:
				entry = p
				before = a
				break
		if entry != Vector2.INF:
			break
	if entry == Vector2.INF:
		push_error("trailer: no shade on the short route")
		return
	var dir: Vector2 = (entry - before).normalized()
	var rest: Array = path.filter(func(p: Vector2) -> bool: return (p - entry).dot(dir) > 2.0)
	_place(entry - dir * 9.0, entry)
	rover.headlights_on = true
	await _wait(1.0)
	_drive([entry] + rest, 2.6)
	await _wait(1.4)
	var shutdown_at: float = 0.9
	var once: Dictionary = {}
	var cam_pos: Array = []
	await _record(func(t: float) -> void:
		if not once.has("staged") and director.cold_time > 0.0:
			once["staged"] = true
			_stage_shutdown(t, shutdown_at)
		var b := _follow_basis(0.05)
		var at: Vector3 = rover.global_position
		var want: Vector3 = at + b * Vector3(0.9, 1.3, 4.2)
		cam_pos.append(want if cam_pos.is_empty() else (cam_pos[-1] as Vector3).lerp(want, 0.12))
		_shoot(cam_pos[-1], at + b * Vector3(0.0, 0.3, -2.0), 50.0, t, 0.02))


func _stage_shutdown(t: float, shutdown_at: float) -> void:
	var zone: Node = director.cold_zone_at(rover.global_position)
	director.cold_time = zone.shutdown_s - maxf(shutdown_at - t, 0.05)
	director.recovery_started.connect(func(_r: Node) -> void:
		driving = false
		_release()
		rover.headlights_on = false
		var sound := AudioStreamPlayer.new()
		sound.stream = load("res://res/audio/sfx/power_down.wav")
		sound.bus = &"SFX"
		level.add_child(sound)
		sound.play(), CONNECT_ONE_SHOT)


## Close on Kite at the far logger, logger loaded and the sun / shade pair recorded; then the camera
## pulls out as Kite heads home at dusk
func _clip_7() -> void:
	await _boot(_m3_state())
	_fit(BUILDS["crater"])
	GS.drive(rover)
	var logger: Node3D = level.get_node("FarLogger")
	var spot := Vector2(logger.global_position.x + 1.0, logger.global_position.z)
	_place(spot, spot + Vector2(0.0, -1.0))
	await _wait(2.0)
	await _press("interact_use")
	await _wait(0.5)
	_place(spot, Vector2(-6.0, -68.0))
	await _wait(1.5)
	var sensor: Node = level.get_node("ThermalSensor")
	var pair: Array = _pair_points(sensor)
	if pair.size() == 2:
		sensor.record(pair[0])
	await _wait(0.5)
	var b := _follow_basis(1.0)
	var at: Vector3 = rover.global_position
	var close: Vector3 = at + b * Vector3(2.1, 0.8, 0.2)
	var far: Vector3 = at + b * Vector3(3.5, 0.0, 9.0)
	var wide: Vector3 = _on_ground(far.x, far.z, 3.0)
	var once: Dictionary = {}
	await _record(func(t: float) -> void:
		if t > 0.15 and not once.has("shade") and pair.size() == 2:
			once["shade"] = true
			sensor.record(pair[1])
		if t > 1.7 and not once.has("go"):
			once["go"] = true
			_drive([Vector2(-6.0, -68.0), Vector2(-18.0, -80.0), Vector2(-30.0, -86.0)], 3.0)
		var k := _ease((t - 1.2) / 2.8)
		var look: Vector3 = rover.global_position + Vector3.UP * 0.45
		_shoot(close.lerp(wide, k), look, lerpf(44.0, 36.0, k), t, 0.02))
	driving = false
	print("TRAILER pair: %s, logger on Kite: %s" % [sensor.has_pair(), rover.get_node("CargoSocket").part == logger])


## A sunlit and a shaded ground point near Kite (Kite's own shadow counts, as in the game)
func _pair_points(sensor: Node) -> Array:
	var found: Dictionary = {}
	for r in [1.5, 2.5, 3.5, 5.0, 7.0, 10.0, 14.0]:
		for k in 24:
			var p: Vector3 = rover.global_position + Vector3(cos(k * TAU / 24.0), 0.0, sin(k * TAU / 24.0)) * r
			p.y = _ground(p.x, p.z)
			var kind: String = sensor.kind_at(p)
			if not found.has(kind):
				found[kind] = p
	return [found.get("sun"), found.get("shade")].filter(func(p: Variant) -> bool: return p != null)


## IRIS at dusk: low under its dish against the stars as it comes online (the game's iris_online
## flag: indicator pulse, antenna to tracking), Kite parked small beside it, then a slow pull back
func _clip_8() -> void:
	await _boot(_m3_state(false))
	var iris: Node3D = level.get_node("Iris")
	var front: Vector3 = iris.global_basis.z
	var side: Vector3 = iris.global_basis.x
	var base: Vector3 = iris.global_position
	var kite_at: Vector3 = base + side * -3.6 + front * 1.2
	_place(Vector2(kite_at.x, kite_at.z), Vector2(base.x, base.z))
	await _wait(1.5)
	var near: Vector3 = base + front * 2.0 + side * 0.9 + Vector3.UP * 0.35
	var far: Vector3 = base + front * 9.5 + side * 2.5
	far.y = _ground(far.x, far.z) + 1.4
	var once: Dictionary = {}
	await _record(func(t: float) -> void:
		if t > 0.3 and not once.has("on"):
			once["on"] = true
			CS.set_flag("iris_online")
		var k := _ease((t - 0.9) / 2.6)
		var look: Vector3 = (base + Vector3.UP * 3.3).lerp(base + side * -1.2 + Vector3.UP * 1.3, k)
		_shoot(near.lerp(far, k), look, lerpf(48.0, 40.0, k), t, 0.01))
	print("TRAILER iris online: ", iris.is_online)


## Behind the title: looking west across Head crater into the low dusk sun
func _clip_9() -> void:
	await _boot(_m3_state())
	var a := _on_ground(-8.0, -46.0, 2.6)
	var b := _on_ground(-12.0, -46.5, 2.4)
	var look := Vector3(-300.0, a.y + 300.0 * tan(deg_to_rad(6.0)), -40.0)
	await _record(func(t: float) -> void:
		_shoot(a.lerp(b, _ease(t / length)), look, 58.0, t, 0.0))
