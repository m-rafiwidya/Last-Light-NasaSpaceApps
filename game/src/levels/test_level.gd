extends Node3D

## Played when the player interacts with the DialogTrigger. Authored as a .tres resource.
@export var intro_dialog: DialogSequence


func _ready() -> void:
	$DialogTrigger.interacted.connect(_on_dialog_trigger_interacted)
	$MissionConsoleTrigger.interacted.connect(_on_mission_console_trigger_interacted)
	$ReadyRoverTrigger.interacted.connect(_on_robot_trigger_interacted.bind($ReadyRover))
	$BareRoverTrigger.interacted.connect(_on_robot_trigger_interacted.bind($BareRover))
	$RespawnPartsTrigger.interacted.connect(_on_respawn_parts_trigger_interacted)
	_record_parts_pile()


func _on_mission_console_trigger_interacted(_player: Player):
	if GameState.state == GameState.State.IN_GAME_PLAYER:
		GameState.change_state_to(GameState.State.MISSION_CONSOLE)


## Take control of the trigger's rover. Esc (ui_cancel, handled by UIManager) hands control
## back to the player.
func _on_robot_trigger_interacted(_player: Player, rover: Robot):
	if GameState.state == GameState.State.IN_GAME_PLAYER:
		GameState.drive(rover)


# --- Parts pile -----------------------------------------------------------------------------

## Pile parts' properties that are copied when the pile is respawned
const PILE_PROPERTIES: Array[String] = ["catalog_id", "tint", "radius", "grip"]

# One entry per part in PartsPile as the level starts: scene, transform and properties
var _pile_layout: Array = []


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


func _on_dialog_trigger_interacted(_player: Player):
	if intro_dialog == null:
		push_warning("TestLevel: no intro_dialog assigned.")
		return
	# The server ignores a new sequence while one is already playing, so
	# mashing E on the trigger can't start overlapping copies.
	await DialogServer.play_dialog_sequence(intro_dialog)
