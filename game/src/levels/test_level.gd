extends Node3D

## Played when the player interacts with the DialogTrigger. Authored as a .tres resource.
@export var intro_dialog: DialogSequence


func _ready() -> void:
	$DialogTrigger.interacted.connect(_on_dialog_trigger_interacted)
	$MissionConsoleTrigger.interacted.connect(_on_mission_console_trigger_interacted)
	$RobotTrigger.interacted.connect(_on_robot_trigger_interacted)


func _on_mission_console_trigger_interacted(_player: Player):
	if GameState.state == GameState.State.IN_GAME_PLAYER:
		GameState.change_state_to(GameState.State.MISSION_CONSOLE)


## Take control of the robot. Esc (ui_cancel, handled by UIManager) hands control back to the player.
func _on_robot_trigger_interacted(_player: Player):
	if GameState.state == GameState.State.IN_GAME_PLAYER:
		GameState.change_state_to(GameState.State.IN_GAME_ROBOT)


func _on_dialog_trigger_interacted(_player: Player):
	if intro_dialog == null:
		push_warning("TestLevel: no intro_dialog assigned.")
		return
	# The server ignores a new sequence while one is already playing, so
	# mashing E on the trigger can't start overlapping copies.
	await DialogServer.play_dialog_sequence(intro_dialog)
