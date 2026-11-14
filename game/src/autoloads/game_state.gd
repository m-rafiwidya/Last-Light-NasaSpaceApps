extends Node

signal state_changed(old_state, new_state)

## IN_GAME_PLAYER: the first-person player is controlled (default in-game state).
## IN_GAME_ROBOT: the robot is driven instead.
enum State {MAIN_MENU, LOADING, IN_GAME_PLAYER, IN_GAME_ROBOT, PAUSED, IN_GAME_MENU, MISSION_CONSOLE}

var state: State = State.LOADING
## The in-game state we were last in; PAUSED / MISSION_CONSOLE return to it.
var last_in_game_state: State = State.IN_GAME_PLAYER

## The current Player, null while no gameplay level is loaded
var player: Player = null
## The rover being driven (or last driven), set by drive(). Only this rover takes input, the
## camera and the robot HUD; null while no gameplay level is loaded.
var robot: Robot = null

## Time scale the game runs at while not paused. The `timescale` console command
## changes it, so unpausing returns to it instead of always going back to 1.0.
var normal_time_scale: float = 1.0

var pause_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_in_game(s: State = state) -> bool:
	return s == State.IN_GAME_PLAYER or s == State.IN_GAME_ROBOT


## Takes control of `rover` (IN_GAME_ROBOT). Esc hands control back to the player.
func drive(rover: Robot) -> void:
	robot = rover
	change_state_to(State.IN_GAME_ROBOT)


## Leave a menu-like state (pause, mission console) and go back to whichever
## in-game state (player or robot) was active before it.
func return_to_game() -> void:
	change_state_to(last_in_game_state)


func change_state_to(new_state: State):
	var old_state: State = state
	_on_state_exit(state)
	state = new_state
	_on_state_enter(state)
	state_changed.emit(old_state, new_state)
	print_debug(State.keys()[state])


func _on_state_exit(_state: State):
	match _state:
		State.MAIN_MENU:
			pass
		State.LOADING:
			pass
		State.IN_GAME_PLAYER:
			pass
		State.IN_GAME_ROBOT:
			pass
		State.PAUSED:
			unpause_game()
		State.MISSION_CONSOLE:
			pass


func _on_state_enter(_state: State):
	apply_mouse_mode()
	match _state:
		State.IN_GAME_PLAYER, State.IN_GAME_ROBOT:
			last_in_game_state = _state
		State.PAUSED:
			pause_game()


## Mouse is captured while in game and visible everywhere else. LOADING keeps
## whatever the previous state had. Also used by the UI to restore the mode after
## the debug console closes.
func apply_mouse_mode() -> void:
	if is_in_game():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif state != State.LOADING:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func pause_game():
	if pause_tween:
		pause_tween.kill()
	pause_tween = create_tween()
	pause_tween.set_ignore_time_scale(true)
	pause_tween.set_ease(Tween.EASE_IN_OUT)
	pause_tween.set_trans(Tween.TRANS_CUBIC)
	pause_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	pause_tween.tween_property(Engine, "time_scale", 0.0, 0.5)
	pause_tween.tween_callback(get_tree().set_pause.bind(true))


func unpause_game():
	if pause_tween:
		pause_tween.kill()
	pause_tween = create_tween()
	pause_tween.set_ignore_time_scale(true)
	pause_tween.set_ease(Tween.EASE_IN_OUT)
	pause_tween.set_trans(Tween.TRANS_CUBIC)
	pause_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	get_tree().paused = false
	pause_tween.tween_property(Engine, "time_scale", normal_time_scale, 0.5)
