extends SceneTree
## Slow-motion close-up of the first-person suit's feet (src/player/body/, PlayerBody) on the test
## level's flat floor, for checking the ankles (ASTRONAUT_KIT.md 13: the boot cuff, the ankle
## bellows and the shin's sleeve) and the planted boots: quarter speed, the camera at ankle height.
##   1. Side, tracking the walker: four walk cycles.
##   2. A fixed camera the walker passes: the boots against the floor.
##   3. Three-quarter front, tracking: two walk cycles.
##   4. Side, tracking: two sprint cycles.
##
##   Godot --path game --resolution 1280x720 --write-movie <out>.avi -s res://tools/record_feet_closeup.gd

const SLOW: float = 0.25

var GS: Node
var SL: Node
var player
var camera: Camera3D
var caption: Label
## (right, up, back) from the player's feet in the view's frame; null = the camera stays put
var follow = null


func _initialize() -> void:
	# The recording runs in a window on a desktop someone may be using: it takes no focus, so no
	# real key, click or mouse movement reaches the game, and Esc / the console key do nothing
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	InputMap.action_erase_events("ui_cancel")
	InputMap.action_erase_events("console")
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


## Game seconds (slowed down, so a second here is four in the video). Counted from the physics
## steps' own time: with a time scale, Movie Maker runs fewer steps where a plain run runs shorter ones.
func _ticks(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds - 1e-6:
		await physics_frame
		elapsed += root.get_physics_process_delta_time()


func _process(_delta: float) -> bool:
	# The game pauses when its window loses focus; the recording carries on regardless
	if GS and GS.state == GS.State.PAUSED:
		GS.unpause_game()
	if follow != null and player:
		var view: Basis = player.pivot.global_basis
		var feet: Vector3 = player.global_position
		camera.global_position = feet + view * (follow as Vector3)
		camera.look_at(feet + Vector3.UP * 0.3 + view * Vector3(0.0, 0.0, -0.1))
	return false


## A spot on the floor with nothing within `radius` (walls, props, rovers)
func _open_floor(radius: float) -> Vector3:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	for ring in range(0, 60, 2):
		for k in 16:
			var at: Vector3 = player.global_position + Vector3(cos(TAU * k / 16.0), 0.0, sin(TAU * k / 16.0)) * ring
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = sphere
			query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (radius + 0.2))
			query.collision_mask = 1 | 2 | 4 | 16
			query.exclude = [player.get_rid()]
			query.collide_with_areas = true
			if not space.intersect_shape(query, 1).is_empty():
				continue
			var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 0.5, 1)
			var hit: Dictionary = space.intersect_ray(ray)
			if not hit.is_empty():
				return hit["position"]
	return player.global_position


## Puts the player at the start of the open stretch, still, facing along it
func _start() -> void:
	Engine.time_scale = 1.0
	player.global_position = _start_point
	player.linear_velocity = Vector3.ZERO
	player.controller.camera_azimuth = 0.0
	player.controller.camera_altitude = 0.0
	await _ticks(1.0)
	Engine.time_scale = SLOW


var _start_point: Vector3


func _shot(text: String, keys: Array, seconds: float, at) -> void:
	caption.text = text + "   (x%d slow motion)" % int(1.0 / SLOW)
	follow = at
	for k in keys:
		Input.action_press(k)
	await _ticks(seconds)
	for k in keys:
		Input.action_release(k)
	Engine.time_scale = 1.0
	await _ticks(1.0)


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	SL.load_scene("test_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "test_level"):
		await physics_frame
	await _ticks(1.5)
	player = GS.player
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.02
	SL.current_scene.add_child(camera)
	camera.make_current()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	caption.position = Vector2(24, 20)
	layer.add_child(caption)
	Engine.time_scale = SLOW

	# Every shot starts at the same open stretch of floor (nothing within 7 m: 5.5 m of walking)
	Engine.time_scale = 1.0
	_start_point = _open_floor(7.0) - (Basis(Vector3.UP, player.global_basis.get_euler().y) * Vector3(0.0, 0.0, -3.0))
	# A walk cycle is 0.67 s: the speed-up from rest takes 0.2 s first
	await _start()
	await _shot("1. Walk, side, tracking", ["move_forward"], 0.2 + 4 * 0.667, Vector3(1.3, 0.3, 0.0))
	await _start()
	# A fixed camera 2 m to the side of the path, 2.6 m along it
	var view: Basis = player.pivot.global_basis
	follow = null
	camera.global_position = player.global_position + view * Vector3(2.0, 0.3, -2.6)
	camera.look_at(player.global_position + view * Vector3(0.0, 0.25, -2.6))
	await _shot("2. Walk, fixed camera", ["move_forward"], 4 * 0.667, null)
	await _start()
	await _shot("3. Walk, three-quarter front, tracking", ["move_forward"], 0.2 + 2 * 0.667, Vector3(0.9, 0.35, -1.0))
	await _start()
	await _shot("4. Sprint, side, tracking", ["move_forward", "move_sprint"], 0.3 + 2 * 0.6, Vector3(1.5, 0.3, 0.0))
	Engine.time_scale = 1.0
	quit()
