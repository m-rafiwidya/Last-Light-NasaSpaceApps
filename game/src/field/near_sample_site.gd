class_name NearSampleSite

extends Node3D

## M2's optional near sample (plan item S): the reference patch by IRIS (its own sample_site_near.glb,
## in IRIS's frame, so this scene goes where IRIS is, replacing the level's SampleSiteNear). Kite brings
## the empty sample container S-1 on its cargo mount, stops at the patch and presses E (interact_use):
## the container fills (its model swaps to the full one) and m2.near_sample_collected completes.
## Optional: nothing here blocks M2. In a campaign only during m2; outside a campaign any time.
##
## Simple version, no scoop animation: the container on the cargo mount is the whole requirement
## (the scoop is a cargo part too, so Kite can't carry both).

signal sample_collected(container: HotswapPart, rover: Robot)

const GROUP: StringName = &"near_sample_site"
const CONTAINER_ID: String = "sample_container"
const MISSION: String = "m2"
const OBJECTIVE: String = "m2.near_sample_collected"
const FULL_MODEL: String = "res://res/models/rover_kit/sample_container_full.glb"
## How far Kite's origin may be from the patch's centre (horizontal, m): park_sample is about 1.3 m
## from it, so stopping anywhere around the patch counts
const SAMPLE_RANGE: float = 2.5
## Within this distance (horizontal, m) of the patch, get_hint() starts talking
const HINT_RANGE: float = 8.0
const STOPPED_SPEED: float = 0.1

## What Guidance lights up (`group:near_sample_site`): the patch with its corner marks
@export var highlight_node: Node3D
@onready var anchor: Node3D = find_child("anchor_sample", true, false)
var _cued: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	highlight_node = $Site


func campaign_allows() -> bool:
	var mission: String = CampaignState.current_mission()
	return mission.is_empty() or (mission == MISSION and not CampaignState.is_objective_done(OBJECTIVE))


## The empty S-1 container on `rover`'s cargo mount, or null
func _container(rover: Robot) -> HotswapPart:
	var socket := rover.get_node_or_null("CargoSocket") as HotswapSocket if rover else null
	var part: HotswapPart = socket.part if socket else null
	return part if part and part.get_catalog_id() == CONTAINER_ID and not part.has_meta(&"sample") else null


## Horizontal distance from `rover` to the patch's centre
func site_distance(rover: Robot) -> float:
	var offset: Vector3 = anchor.global_position - rover.global_position
	offset.y = 0.0
	return offset.length()


func can_collect(rover: Robot) -> bool:
	return rover != null and campaign_allows() and _container(rover) != null \
		and site_distance(rover) <= SAMPLE_RANGE and rover.linear_velocity.length() <= STOPPED_SPEED


## What the rover HUD could say near the patch ("" for nothing)
func get_hint(rover: Robot) -> String:
	if rover == null or not campaign_allows() or site_distance(rover) > HINT_RANGE:
		return ""
	if _container(rover) == null:
		return "Near sample site: bring the empty sample container S-1 on the cargo mount"
	if site_distance(rover) > SAMPLE_RANGE:
		return "Near sample site: drive %.1f m closer" % (site_distance(rover) - SAMPLE_RANGE)
	if rover.linear_velocity.length() > STOPPED_SPEED:
		return "Stop here"
	return "In position: press %s to take the near sample" % InputBindings.action_text(&"interact_use", "E")


## Fills the container on `rover`'s cargo mount and completes the objective; true when it did
func try_collect(rover: Robot) -> bool:
	if not can_collect(rover):
		return false
	var container := _container(rover)
	container.set_meta(&"sample", "near")
	# shortcut: only the model shows it's full; a loaded save gets an empty-looking S-1 back (the objective stays done)
	var kit := container.get_node_or_null("Model/Kit") as Node3D
	if kit:
		var full: Node3D = (load(FULL_MODEL) as PackedScene).instantiate()
		full.transform = kit.transform
		kit.get_parent().remove_child(kit)
		kit.queue_free()
		container.get_node("Model").add_child(full)
		full.name = "Kit"
	sample_collected.emit(container, rover)
	CampaignState.complete_objective(OBJECTIVE)
	return true


## Guidance never shows an optional step, so the site says once (per case) what to do when Kite
## arrives: "need" without S-1, "ready" with it
func _cue(rover: Robot) -> void:
	if not campaign_allows() or site_distance(rover) > SAMPLE_RANGE + 2.0:
		return
	var key: String = "ready" if _container(rover) else "need"
	if _cued.has(key):
		return
	_cued[key] = true
	var line := Dialog.new()
	line.speaker = "Kite"
	line.subtitle = "Near sample site. Stop by the patch and press %s to take a sample." % InputBindings.action_text(&"interact_use", "E") \
		if key == "ready" else "Near sample site (optional). The cargo mount carries one part: bring sample container S-1 to take a sample here."
	line.min_duration = 5.0
	line.repeat_id = "kite_near_sample_" + key
	DialogServer.play_dialog(line)


func _physics_process(_delta: float) -> void:
	if GameState.state != GameState.State.IN_GAME_ROBOT or not is_instance_valid(GameState.robot):
		return
	_cue(GameState.robot)
	if Input.is_action_just_pressed(&"interact_use"):
		try_collect(GameState.robot)
