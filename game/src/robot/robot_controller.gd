class_name RobotController

extends Node

## Robot intent. Reads input and exposes smoothed values the Robot reads directly,
## like PlayerController. One-shot events are signals (emitted with `true` on
## press, `false` on release).
## Shares the player's movement actions: move_forward / move_backward = desired
## speed forward / backward (as a fraction of the robot's top speed; no input = 0,
## so the robot slows down), move_left / move_right = steering.
## Like PlayerController, input is only accepted while GameState is IN_GAME.

signal toggle_camera(value: bool)


## Desired speed as a fraction of the robot's top speed. The robot uses it as the
## motor voltage: -1 (full reverse) .. 1 (full forward), 0 = no input.
var desired_speed: float = 0.0
## -1 (full left) .. 1 (full right)
var steer: float = 0.0

var steer_speed: float = 2.0
var desired_speed_rate: float = 2.0

var was_input_enabled: bool = false


func is_input_enabled() -> bool:
	return GameState.state == GameState.State.IN_GAME


func _physics_process(delta: float) -> void:
	var enabled: bool = is_input_enabled()
	# Treat the first tick after unlocking as locked so a click/key used to close
	# a UI screen isn't read as a fresh press.
	var accept_input: bool = enabled and was_input_enabled
	was_input_enabled = enabled

	var target_steer: float = 0.0
	var target_desired_speed: float = 0.0

	# Polled (not event driven) so releases during a lock can't leave keys stuck.
	if accept_input:
		target_steer = Input.get_axis("move_left", "move_right")
		target_desired_speed = Input.get_axis("move_backward", "move_forward")

		if Input.is_action_just_pressed("camera"):
			toggle_camera.emit(true)
		elif Input.is_action_just_released("camera"):
			toggle_camera.emit(false)
	elif Input.is_action_just_released("camera"):
		# While locked only let releases through; presses are ignored.
		toggle_camera.emit(false)

	steer = move_toward(steer, target_steer, steer_speed * delta)
	desired_speed = move_toward(desired_speed, target_desired_speed, desired_speed_rate * delta)
