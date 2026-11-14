extends Node

signal request_transition(no_fade_in)
signal level_loaded(level_name)
signal level_unloaded(level_name)

const PLAYER_PACKED_SCENE: PackedScene = preload("res://src/player/player.tscn")

const MAIN_MENU_ID = "main_menu"
# Every path is checked in _ready(), so a typo shows up as an error at startup
const LEVEL_PATHS: Dictionary = {
	"test_level": "res://src/levels/test_level.tscn",
	MAIN_MENU_ID: "res://src/levels/test_level.tscn",
}

# For later to show intro like CS2
var is_first_main_menu_load: bool = true

# Set by Game (root node)
var main_node: Node = null

var current_scene: Node = null
var progress: Array = [0.0]
var loading_scene_id: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	for level_name in LEVEL_PATHS:
		if not ResourceLoader.exists(LEVEL_PATHS[level_name]):
			push_error('SceneLoader: level "%s" points at a missing file: %s' % [level_name, LEVEL_PATHS[level_name]])


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
	if current_scene:
		GameState.player = null
		current_scene.queue_free()
		level_unloaded.emit(current_scene.name)
		current_scene = null

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
	main_node.add_child(current_scene)

	# Can accomodate gamemodes for future projects
	if loading_scene_id == MAIN_MENU_ID:
		_setup_main_menu()
	else:
		_setup_level()
	loading_scene_id = ""

	level_loaded.emit(current_scene.name)


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
	current_scene.add_child(player)
	# The robot's cameras are not current by default; make sure the player's is
	player.camera.make_current()


func _setup_main_menu():
	var camera = Camera3D.new()
	camera.fov = 90.0

	var camera_marker: Marker3D = current_scene.get_node_or_null("CameraMarker")
	if camera_marker:
		camera.transform = camera_marker.transform
	else:
		push_error('No "CameraMarker" marker node found in level, using the origin.')
	current_scene.add_child(camera)
	# The level may contain a robot with its own cameras; make sure the menu camera wins
	camera.make_current()

	# Hey GameState, I finished loading, please start transition to MAIN_MENU
	GameState.change_state_to(GameState.State.MAIN_MENU)
