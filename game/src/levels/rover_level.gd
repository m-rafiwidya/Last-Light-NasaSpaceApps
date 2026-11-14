class_name RoverLevel

extends Node3D

## Shared by levels with drivable rovers and a parts pile (the test level extends it, the Moon
## level uses it as is). Found by name:
##   <Rover>Trigger       an InteractTrigger next to each Robot child <Rover>: E drives that rover
##   PartsPile            loose HotswapParts, recorded as the level starts
##   RespawnPartsTrigger  E clears the loose pile parts and lays out the recorded pile again


## Gravity in this level (m/s^2), applied by SceneLoader as the level loads: Earth's 9.8 (the
## project default) unless the level sets its own, e.g. 1.62 on the Moon
@export var gravity: float = 9.8
## How high the player jumps here (m), whatever the gravity (handed to the Player by
## SceneLoader); the Moon caps it at 1.2 m, still floaty: 2.4 s in the air
@export var jump_height: float = Player.JUMP_HEIGHT

## Pile parts' properties that are copied when the pile is respawned
const PILE_PROPERTIES: Array[String] = ["catalog_id", "tint", "radius", "grip"]

# One entry per part in PartsPile as the level starts: scene, transform and properties
var _pile_layout: Array = []


func _ready() -> void:
	for rover in get_children():
		if rover is Robot:
			var trigger := get_node_or_null(NodePath(rover.name + "Trigger")) as InteractTrigger
			if trigger:
				trigger.interacted.connect(_on_robot_trigger_interacted.bind(rover))
	if has_node("PartsPile"):
		_record_parts_pile()
	if has_node("RespawnPartsTrigger"):
		$RespawnPartsTrigger.interacted.connect(_on_respawn_parts_trigger_interacted)


## Take control of the trigger's rover. Esc (ui_cancel, handled by UIManager) hands control
## back to the player.
func _on_robot_trigger_interacted(_player: Player, rover: Robot):
	if GameState.state == GameState.State.IN_GAME_PLAYER:
		GameState.drive(rover)


# --- Parts pile -----------------------------------------------------------------------------

func _record_parts_pile() -> void:
	for part in $PartsPile.get_children():
		if not part is HotswapPart:
			continue
		var properties: Dictionary = {}
		for property in PILE_PROPERTIES:
			if property in part:
				properties[property] = part.get(property)
		_pile_layout.append({"scene": load(part.scene_file_path), "transform": part.transform, "properties": properties})


## Clears the loose pile parts (parts mounted on a rover stay) and lays out a fresh full pile.
func _on_respawn_parts_trigger_interacted(_player: Player) -> void:
	var holders: Array = [GameState.player] + find_children("*", "Robot", true, false)
	for part in $PartsPile.get_children():
		if not part is HotswapPart or part.is_mounted():
			continue
		for holder_owner in holders:
			if is_instance_valid(holder_owner) and holder_owner.holder and holder_owner.holder.held_object == part:
				holder_owner.holder.release()
		part.queue_free()
	for entry in _pile_layout:
		var part: HotswapPart = entry["scene"].instantiate()
		part.transform = entry["transform"]
		for property in entry["properties"]:
			part.set(property, entry["properties"][property])
		$PartsPile.add_child(part)
