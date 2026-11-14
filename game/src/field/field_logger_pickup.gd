class_name FieldLoggerPickup

extends Node3D

## M3's logger recovery at the far rim: lets Kite take Evan's logger (the level's FarLogger, a
## FieldLoggerPart) onto its cargo mount. MissionDirector completes m3.logger_recovered when the
## logger is mounted (MOUNT_OBJECTIVES); nothing here completes objectives.
##
## Simple version, no arm yet: Kite stopped with its cargo socket (the cradle) within PICKUP_RANGE
## of the logger and the mount empty; E (interact_use) while driving mounts the logger. In a
## campaign only during m3; outside a campaign (test levels) any time.
##
## On load: with m3.logger_recovered done, the save puts a logger back on Kite (KiteSave makes a new
## one), so the logger still lying in the level is removed and there's never two.
##
## Place it anywhere in the level; `logger_path` points at the logger (default: a sibling named
## FarLogger). Guidance can keep targeting the logger itself (`path:FarLogger`): the part has its own
## meshes, so it glows directly.

signal logger_loaded(logger: HotswapPart, rover: Robot)

const GROUP: StringName = &"field_logger_pickup"
const ACCEPTS: String = "field_logger"
const MISSION: String = "m3"
const RECOVERED_OBJECTIVE: String = "m3.logger_recovered"
## How far Kite's cargo socket may be from the logger (horizontal, m)
const PICKUP_RANGE: float = 1.5
## Within this distance (horizontal, m) of the logger, get_hint() starts talking
const HINT_RANGE: float = 8.0
const STOPPED_SPEED: float = 0.1

@export var logger_path: NodePath = ^"../FarLogger"
## The logger in the level, null once it's gone (removed after a load, or freed)
var logger: HotswapPart = null


func _ready() -> void:
	add_to_group(GROUP)
	logger = get_node_or_null(logger_path) as HotswapPart
	if logger == null:
		push_warning("FieldLoggerPickup: no logger at %s" % logger_path)
		return
	if not CampaignState.is_objective_done(RECOVERED_OBJECTIVE):
		return
	# Wait for MissionDirector to put the saved loadout back on Kite (it waits a physics frame)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if is_instance_valid(logger) and not logger.is_mounted():
		logger.queue_free()
		logger = null


## In a campaign only during m3; outside a campaign (test levels) any time
func campaign_allows() -> bool:
	var mission: String = CampaignState.current_mission()
	return mission.is_empty() or (mission == MISSION and not CampaignState.is_objective_done(RECOVERED_OBJECTIVE))


func _cargo_socket(rover: Robot) -> HotswapSocket:
	return rover.get_node_or_null("CargoSocket") as HotswapSocket if rover else null


## Horizontal distance from `rover`'s cargo socket to the logger (INF without either)
func pickup_distance(rover: Robot) -> float:
	var socket := _cargo_socket(rover)
	if socket == null or not is_instance_valid(logger):
		return INF
	var offset: Vector3 = logger.global_position - socket.global_position
	offset.y = 0.0
	return offset.length()


## True when E would load the logger now
func can_load(rover: Robot) -> bool:
	var socket := _cargo_socket(rover)
	return socket != null and socket.part == null and is_instance_valid(logger) and not logger.is_mounted() \
		and campaign_allows() and pickup_distance(rover) <= PICKUP_RANGE \
		and rover.linear_velocity.length() <= STOPPED_SPEED


## What the rover HUD could say near the logger ("" for nothing)
func get_hint(rover: Robot) -> String:
	if rover == null or not is_instance_valid(logger) or logger.is_mounted() or not campaign_allows():
		return ""
	var d: float = pickup_distance(rover)
	if d > HINT_RANGE:
		return ""
	if _cargo_socket(rover).part != null:
		return "The cargo mount is full: Evan's logger needs an empty mount"
	if d > PICKUP_RANGE:
		return "Evan's logger: bring the cargo mount %.1f m closer" % (d - PICKUP_RANGE)
	if rover.linear_velocity.length() > STOPPED_SPEED:
		return "Stop here"
	return "In position: press %s to load Evan's logger" % InputBindings.action_text(&"interact_use", "E")


## Mounts the logger on `rover`'s cargo mount when in position; true when it did
func try_load(rover: Robot) -> bool:
	if not can_load(rover):
		return false
	var socket := _cargo_socket(rover)
	logger.sleeping = false
	logger.freeze = false
	socket.mount(logger)
	if socket.part != logger:
		return false
	logger_loaded.emit(logger, rover)
	return true


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(logger) or logger.is_mounted() or not Input.is_action_just_pressed(&"interact_use"):
		return
	if GameState.state == GameState.State.IN_GAME_ROBOT and is_instance_valid(GameState.robot):
		try_load(GameState.robot)
