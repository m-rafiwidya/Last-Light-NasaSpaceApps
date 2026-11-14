extends Node


func _ready() -> void:
	GameState.state_changed.connect(_on_game_state_changed)
	
	SceneLoader.request_transition.connect(_on_request_transition)
	SceneLoader.level_loaded.connect(_on_level_loaded)
	
	$LoadingScreen.finished_fade_in.connect(SceneLoader._on_finished_fade_in)
	#$MainMenu.offset = Vector2(-1920.0, 0.0)
	#$PauseMenu.offset = Vector2(-1920.0, 0.0)

func _process(_delta: float) -> void:
	# The popup closes itself on Esc, so remember whether it was open at the start
	# of this frame: that Esc must not also pause the game or leave the robot.
	var console_was_open: bool = Debug.console_open
	if Input.is_action_just_pressed("console"):
		if $Console.visible:
			$Console.hide()
		else:
			$Console.popup()
	_sync_console_state()
	if console_was_open or Debug.console_open:
		return
	if Input.is_action_just_pressed("ui_cancel"):
		match GameState.state:
			GameState.State.IN_GAME_PLAYER:
				GameState.change_state_to(GameState.State.PAUSED)
			GameState.State.IN_GAME_ROBOT:
				# Esc leaves the robot and gives control back to the player
				GameState.change_state_to(GameState.State.IN_GAME_PLAYER)
			GameState.State.PAUSED, GameState.State.MISSION_CONSOLE:
				GameState.return_to_game()

## Frees the mouse while the console is open and restores the state's mouse mode
## once it closes (however it was closed: backtick, Esc or the window's X).
func _sync_console_state() -> void:
	if $Console.visible == Debug.console_open:
		return
	Debug.console_open = $Console.visible
	if Debug.console_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		GameState.apply_mouse_mode()


func _on_game_state_changed(old_state, new_state):
	if new_state == GameState.State.MAIN_MENU:
		$MainMenu.fade_in()
	else:
		$MainMenu.fade_out()
	
	if new_state == GameState.State.PAUSED:
		$PauseMenu.fade_in()
	else:
		$PauseMenu.fade_out()
	
	if new_state == GameState.State.IN_GAME_PLAYER:
		$HUD.fade_in()
	else:
		$HUD.fade_out()
	
	if new_state == GameState.State.IN_GAME_ROBOT:
		$RobotHUD.fade_in()
	else:
		$RobotHUD.fade_out()
	
	if new_state == GameState.State.MISSION_CONSOLE:
		$MissionConsole.fade_in()
	else:
		$MissionConsole.fade_out()
	
	$LoadingScreen.visible = (
		new_state == GameState.State.LOADING or old_state == GameState.State.LOADING
	)


func _on_request_transition(no_fade_in):
	if no_fade_in:
		$LoadingScreen.reset()
	else:
		$LoadingScreen.fade_in()


func _on_level_loaded(_level_name: String):
	$LoadingScreen.fade_out()
