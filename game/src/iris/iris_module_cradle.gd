class_name IrisModuleCradle

extends Node3D

## IRIS's radio-power module bay (iris_module_socket, tools/blender/IRIS_KIT.md 6.2.1) as M2's
## install point. Iris places it on the seat (Iris.module_seat_transform()), so a seated module's
## origin is this node's origin.
##
## Simple version, no arm yet: Kite parked at the bay (its origin within PARK_RANGE of the model's
## `park_module` marker), stopped, with the module on its cargo mount; E (interact_use) while
## driving seats the module. In a campaign only during m2, once the objectives before it are done
## (campaign_allows). That completes m2.module_installed and m2.iris_activated and sets the
## `iris_online` flag; MissionDirector switches IRIS on from the flag, nothing here calls
## Iris.set_online.
##
## On load: if m2.module_installed is done or `iris_online` is set, the module is already seated.
## Guidance finds this node as `group:iris_module_cradle` and glows `highlight_node` (the bay).

signal module_installed(part: HotswapPart, rover: Robot)

const GROUP: StringName = &"iris_module_cradle"
const ACCEPTS: String = "radio_module"
const MODULE_SCENE: String = "res://src/robot/socket/radio_module_part.tscn"
const INSTALLED_OBJECTIVE: String = "m2.module_installed"
const ACTIVATED_OBJECTIVE: String = "m2.iris_activated"
const ONLINE_FLAG: String = "iris_online"
## How far Kite's origin may be from `park_module` (horizontal, m)
const PARK_RANGE: float = 1.5
## Within this distance (horizontal, m) of the bay, get_hint() starts talking
const HINT_RANGE: float = 6.0
const STOPPED_SPEED: float = 0.1

## What Guidance lights up: the bay's mesh in IRIS's model (set by Iris)
@export var highlight_node: Node3D
## Where Kite's origin stops for the bay (the model's `park_module`, set by Iris), or null
var park_marker: Node3D = null
## The seated module, null while the bay is empty
var occupant: HotswapPart = null


func _ready() -> void:
	add_to_group(GROUP)
	if CampaignState.is_objective_done(INSTALLED_OBJECTIVE) or CampaignState.has_flag(ONLINE_FLAG):
		var part := (load(MODULE_SCENE) as PackedScene).instantiate() as HotswapPart
		add_child(part)
		_seat(part)


func is_installed() -> bool:
	return occupant != null


## The module on `rover`'s cargo mount, or null
func module_on(rover: Robot) -> HotswapPart:
	var socket := rover.get_node_or_null("CargoSocket") as HotswapSocket if rover else null
	if socket == null or socket.part == null or socket.part.get_catalog_id() != ACCEPTS:
		return null
	return socket.part


## Horizontal distance from `rover`'s origin to where it should stop
func park_distance(rover: Robot) -> float:
	var target: Vector3 = park_marker.global_position if park_marker else global_position
	var offset: Vector3 = rover.global_position - target
	offset.y = 0.0
	return offset.length()


## In a campaign the module goes in only during m2, after the objectives before the install
## (m2.cargo_ordered, m2.module_loaded); outside a campaign (test levels) any time
func campaign_allows() -> bool:
	var mission: String = CampaignState.current_mission()
	if mission.is_empty():
		return true
	if mission != "m2":
		return false
	var objectives := CampaignState.mission_objectives(mission)
	var index: int = objectives.find(INSTALLED_OBJECTIVE)
	for k in maxi(index, 0):
		if not CampaignState.is_objective_done(objectives[k]):
			return false
	return index >= 0


## True when E would seat the module now
func can_install(rover: Robot) -> bool:
	return occupant == null and campaign_allows() and module_on(rover) != null \
		and park_distance(rover) <= PARK_RANGE and rover.linear_velocity.length() <= STOPPED_SPEED


## What the rover HUD could say near the bay ("" for nothing)
func get_hint(rover: Robot) -> String:
	if rover == null or occupant != null or not campaign_allows() or module_on(rover) == null \
			or park_distance(rover) > HINT_RANGE:
		return ""
	if park_distance(rover) > PARK_RANGE:
		return "IRIS's module bay: %.1f m closer" % (park_distance(rover) - PARK_RANGE)
	if rover.linear_velocity.length() > STOPPED_SPEED:
		return "Stop here"
	return "In position: press %s to install the radio-power module" % InputBindings.action_text(&"interact_use", "E")


## Seats the module from `rover`'s cargo mount when in position; true when it did
func try_install(rover: Robot) -> bool:
	if not can_install(rover):
		return false
	var socket := rover.get_node("CargoSocket") as HotswapSocket
	var part: HotswapPart = socket.unmount()
	part.reparent(self, false)
	_seat(part)
	module_installed.emit(part, rover)
	_complete()
	return true


# The part on the seat, frozen, with no collision (as CargoPort.accept)
func _seat(part: HotswapPart) -> void:
	occupant = part
	part.transform = Transform3D.IDENTITY
	part.linear_velocity = Vector3.ZERO
	part.angular_velocity = Vector3.ZERO
	part.collision_layer = 0
	part.collision_mask = 0
	part.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	part.freeze = true


func _complete() -> void:
	# campaign_allows() already checked the order; outside a campaign there are no objectives
	if CampaignState.current_mission() == "m2":
		CampaignState.complete_objective(INSTALLED_OBJECTIVE)
		CampaignState.complete_objective(ACTIVATED_OBJECTIVE)
	CampaignState.set_flag(ONLINE_FLAG)


func _physics_process(_delta: float) -> void:
	if occupant != null or not Input.is_action_just_pressed(&"interact_use"):
		return
	if GameState.state == GameState.State.IN_GAME_ROBOT and is_instance_valid(GameState.robot):
		try_install(GameState.robot)
