extends RoverLevel

## The test level: the rovers, their Drive Robot triggers and the parts pile come from
## RoverLevel; this adds the intro dialog and the mission console.

## Played when the player interacts with the DialogTrigger. Authored as a .tres resource.
@export var intro_dialog: DialogSequence


func _ready() -> void:
	super()
	$DialogTrigger.interacted.connect(_on_dialog_trigger_interacted)
	$MissionConsoleTrigger.interacted.connect(_on_mission_console_trigger_interacted)


func _on_mission_console_trigger_interacted(_player: Player):
	if GameState.state == GameState.State.IN_GAME_PLAYER:
		GameState.change_state_to(GameState.State.MISSION_CONSOLE)


func _on_dialog_trigger_interacted(_player: Player):
	if intro_dialog == null:
		push_warning("TestLevel: no intro_dialog assigned.")
		return
	# The server ignores a new sequence while one is already playing, so
	# mashing E on the trigger can't start overlapping copies.
	await DialogServer.play_dialog_sequence(intro_dialog)
