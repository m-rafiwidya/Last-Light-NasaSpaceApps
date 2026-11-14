extends Node

## The launch's load of the main menu shows no loading screen: the screen stays black (the
## main menu's opening sequence covers it) until the sequence starts. Later loads show it.
var _launching: bool = true
## Whether the main menu's PLAY popup or the pause menu's settings were open at the end of the last
## frame. They close themselves on Esc (in _input, before this script's _process), so that Esc
## must not act here too.
var _popup_was_open: bool = false


func _ready() -> void:
	GameState.state_changed.connect(_on_game_state_changed)
	
	SceneLoader.request_transition.connect(_on_request_transition)
	SceneLoader.level_loaded.connect(_on_level_loaded)
	
	$LoadingScreen.finished_fade_in.connect(SceneLoader._on_finished_fade_in)
	# Settings > General > Show FPS Counter, above every screen
	add_child(FpsCounter.new())
	#$MainMenu.offset = Vector2(-1920.0, 0.0)
	#$PauseMenu.offset = Vector2(-1920.0, 0.0)

## F11 / Alt+Enter toggle fullscreen anywhere. In _input, before the GUI, so Alt+Enter doesn't
## also press the focused button (Enter is ui_accept).
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen") and not event.is_echo():
		get_viewport().set_input_as_handled()
		DisplaySettings.toggle_fullscreen()


func _process(_delta: float) -> void:
	# The popup closes itself on Esc, so remember whether it was open at the start
	# of this frame: that Esc must not also pause the game or leave the robot.
	var console_was_open: bool = Debug.console_open
	# (Not a key a settings key slab just took to rebind)
	if Input.is_action_just_pressed("console") and not KeyBindSlab.took_key_this_frame():
		if $Console.visible:
			$Console.hide()
		else:
			$Console.popup()
	_sync_console_state()
	var popup_was_open: bool = _popup_was_open
	_popup_was_open = $MainMenu.is_popup_open() or $PauseMenu.is_settings_open()
	if console_was_open or Debug.console_open or popup_was_open or _popup_was_open:
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
	) and not _launching
	if new_state == GameState.State.MAIN_MENU:
		_launching = false


func _on_request_transition(no_fade_in):
	if no_fade_in:
		$LoadingScreen.reset()
	else:
		$LoadingScreen.fade_in()


func _on_level_loaded(_level_name: String):
	$LoadingScreen.fade_out()
