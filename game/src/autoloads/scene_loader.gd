extends Node

signal request_transition(no_fade_in)
signal level_loaded(level_name)
signal level_unloaded(level_name)

const PLAYER_PACKED_SCENE: PackedScene = preload("res://src/player/player.tscn")

const MAIN_MENU_ID = "main_menu"
# Every path is checked in _ready(), so a typo shows up as an error at startup
const LEVEL_PATHS: Dictionary = {
	"test_level": "res://src/levels/test_level.tscn",
	"moon_level": "res://src/levels/moon_level.tscn",
	# An empty level: the menu draws its own starfield and Moon (UI, own SubViewport)
	MAIN_MENU_ID: "res://src/levels/menu_backdrop.tscn",
}
## Player properties a level can set by having a property of the same name on its root
const PLAYER_LEVEL_SETTINGS: Array[String] = ["jump_height", "ground_friction", "player_lifts_rovers"]
## The levels the pause menu offers ("Switch to ..."), in menu order: id -> display name. The main
## menu's PLAY starts the campaign (SaveIndex.CAMPAIGN_LEVEL) instead.
const PLAYABLE_LEVELS: Dictionary = {
	"test_level": "Test level",
	"moon_level": "Moon",
}

## Longest wait (s) for a level's content (MoonTerrain's meshes) before starting it anyway
const CONTENT_TIMEOUT: float = 120.0

## The main menu plays its opening sequence the first time it opens and clears this
var is_first_main_menu_load: bool = true

# Set by Game (root node)
var main_node: Node = null

var current_scene: Node = null
## Id (LEVEL_PATHS key) of the level in current_scene, "" while none is loaded
var current_level_id: String = ""
var progress: Array = [0.0]
var loading_scene_id: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	for level_name in LEVEL_PATHS:
		if not ResourceLoader.exists(LEVEL_PATHS[level_name]):
			push_error('SceneLoader: level "%s" points at a missing file: %s' % [level_name, LEVEL_PATHS[level_name]])
	for level_name in PLAYABLE_LEVELS:
		if not LEVEL_PATHS.has(level_name):
			push_error('SceneLoader: playable level "%s" is not in LEVEL_PATHS' % level_name)


func load_scene(level_name: String, no_fade_in: bool = false) -> void:
	# Load and setup new level
	if not loading_scene_id.is_empty():  # LevelManager currently loading level
		return
	if not LEVEL_PATHS.has(level_name):  # ID not found
		push_error("LevelManager: Invalid level name: " + level_name)
		return

	loading_scene_id = level_name

	progress = [0.0]
	# Hey, I need to load the level, set the state to loading
	GameState.change_state_to(GameState.State.LOADING)
	# If it's the first time I'm loading main menu though, set it to intro
	# And don't let anything happen
	# I'll wait for the screen to fade first before loading
	request_transition.emit(no_fade_in)
	# TODO: I have no idea if the loading screen has even begun yet
	# I have no right to call start loading
	if no_fade_in:
		_on_finished_fade_in()


func _on_finished_fade_in() -> void:
	# OK, I'm now allowed to start loading resources
	# Unload current level if it exists
	# Nothing may keep pointing into the old level: the player, the driven rover (camera and
	# robot HUD follow it) and the robot the HUD reads. Held props, cameras and rovers are
	# freed with the level.
	if current_scene:
		GameState.player = null
		GameState.robot = null
		Debug.current_robot = null
		current_scene.queue_free()
		level_unloaded.emit(current_scene.name)
		current_scene = null
		current_level_id = ""

	# Make loading thread
	var err = ResourceLoader.load_threaded_request(LEVEL_PATHS[loading_scene_id])

	if err != OK:
		push_error("Threaded loading failed with error: " + str(err))
		_on_load_failed()
		return

	# Start checking continuously
	set_process(true)


func _process(_delta: float) -> void:
	var status = ResourceLoader.load_threaded_get_status(LEVEL_PATHS[loading_scene_id], progress)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_setup_scene()
		set_process(false)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("Threaded loading FAILED.")
		set_process(false)
		_on_load_failed()


# The old level is already gone, so fall back to the main menu. If the main menu
# itself failed there is nothing to fall back to; stay on the loading screen.
func _on_load_failed() -> void:
	var failed_id: String = loading_scene_id
	loading_scene_id = ""
	if failed_id != MAIN_MENU_ID:
		load_scene(MAIN_MENU_ID, true)


func _setup_scene() -> void:
	var level_scene = ResourceLoader.load_threaded_get(LEVEL_PATHS[loading_scene_id])
	current_scene = level_scene.instantiate()
	current_level_id = loading_scene_id
	_apply_level_gravity(current_scene)
	main_node.add_child(current_scene)
	# Content still being built (MoonTerrain's meshes, on worker threads): the loading screen
	# stays up and the player spawns once it's there
	for node in get_tree().get_nodes_in_group(&"loading_content"):
		if current_scene.is_ancestor_of(node) and not node.is_ready_to_play():
			await _content_ready_or_timeout(node)

	# Can accomodate gamemodes for future projects
	if loading_scene_id == MAIN_MENU_ID:
		_setup_main_menu()
	else:
		_setup_level()
	loading_scene_id = ""

	level_loaded.emit(current_scene.name)


## Sets the world's gravity for `level` before it enters the tree: the root's `gravity`
## property (m/s^2) if it has one (RoverLevel exports it), else the project's default. Every
## level sets it, so none inherits the previous level's. Bodies fall with it; scripts that
## need the value read it back with Node3D.get_gravity() (Player, FrictionCircles).
func _apply_level_gravity(level: Node) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var level_gravity = level.get("gravity")
	if level_gravity is float:
		gravity = level_gravity
	PhysicsServer3D.area_set_param(main_node.get_viewport().find_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, gravity)


func _setup_level():
	var spawn_transform: Transform3D = Transform3D.IDENTITY
	var spawn_point: Marker3D = current_scene.get_node_or_null("SpawnPoint")
	if spawn_point:
		spawn_transform = spawn_point.transform
	else:
		push_error('No "SpawnPoint" marker node found in level, spawning at the origin.')

	_setup_player(spawn_transform)

	# Hey GameState, I finished loading, please start transition to IN_GAME_PLAYER
	# (the robot, if the level has one, is placed manually in the level)
	GameState.change_state_to(GameState.State.IN_GAME_PLAYER)


# Spawn the first-person player at the designated spawn point
func _setup_player(spawn_transform: Transform3D) -> void:
	var player_controller = PlayerController.new()
	current_scene.add_child(player_controller)

	var player = PLAYER_PACKED_SCENE.instantiate()
	GameState.player = player
	player.transform = spawn_transform
	player.controller = player_controller
	# The level's player settings (RoverLevel exports them); the player's defaults otherwise
	for property in PLAYER_LEVEL_SETTINGS:
		var value = current_scene.get(property)
		if value != null:
			player.set(property, value)
	current_scene.add_child(player)
	var camera_far = current_scene.get("camera_far")
	if camera_far is float:
		player.camera.far = camera_far
		player.camera.near = RoverLevel.near_for_far(player.camera.near, camera_far)
	# The robot's cameras are not current by default; make sure the player's is
	player.camera.make_current()


func _setup_main_menu():
	# A backdrop level with a CameraMarker is viewed through a camera there; the default
	# backdrop is empty (the menu draws everything itself) and gets no camera, so the main
	# viewport renders no 3D while the menu is up
	var camera_marker: Marker3D = current_scene.get_node_or_null("CameraMarker")
	if camera_marker:
		var camera = Camera3D.new()
		camera.fov = 90.0
		camera.transform = camera_marker.transform
		current_scene.add_child(camera)
		# The level may contain a robot with its own cameras; make sure the menu camera wins
		camera.make_current()

	# Hey GameState, I finished loading, please start transition to MAIN_MENU
	GameState.change_state_to(GameState.State.MAIN_MENU)


## Waits for a node's content_ready, giving up after CONTENT_TIMEOUT seconds (logged), so a
## problem building content can't leave the loading screen up for good
func _content_ready_or_timeout(node: Node) -> void:
	var timer := get_tree().create_timer(CONTENT_TIMEOUT, true, false, true)
	var state: Dictionary = {"done": false}
	node.content_ready.connect(func() -> void: state["done"] = true, CONNECT_ONE_SHOT)
	while not state["done"] and timer.time_left > 0.0 and is_instance_valid(node):
		await get_tree().process_frame
	if not state["done"]:
		push_error("SceneLoader: %s wasn't ready after %d s; starting the level anyway" % [node.get_path(), CONTENT_TIMEOUT])
