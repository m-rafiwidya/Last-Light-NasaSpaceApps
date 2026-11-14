class_name RobotController

extends Node

## Robot intent. Reads input and exposes smoothed values the Robot reads directly,
## like PlayerController. One-shot events are signals (emitted with `true` on
## press, `false` on release).
## Shares the player's actions: move_forward / move_backward = desired speed
## forward / backward (as a fraction of the robot's top speed; no input = 0, so
## the robot slows down), move_left / move_right = steering, mouse = look,
## interact_use = pick up / drop, interact_primary = throw.
## Unlike PlayerController, input is only accepted while GameState is IN_GAME_ROBOT.

signal interact(value: bool)
signal primary(value: bool)
## R: deploy / stow the arm (press only)
signal arm_toggle


## Desired speed as a fraction of the robot's top speed. The robot uses it as the
## motor voltage: -1 (full reverse) .. 1 (full forward), 0 = no input.
var desired_speed: float = 0.0
## -1 (full left) .. 1 (full right)
var steer: float = 0.0

## Accumulated look yaw / pitch in radians (pitch clamped to +-90 degrees),
## relative to the robot body.
var camera_azimuth: float = 0.0
var camera_altitude: float = 0.0
## Limit (radians) of camera_altitude either way. The Robot sets it to the mast head's tilt range.
var altitude_limit: float = PI / 2.0

## Arm joint picked with 1-5 (1 = J1 yaw .. 5 = J5 tool turret)
var arm_joint: int = 2
## -1 (Z, lower) .. 1 (X, raise) while held, 0 otherwise
var arm_rotate: float = 0.0

var steer_speed: float = 2.0
var desired_speed_rate: float = 2.0

var was_input_enabled: bool = false


func is_input_enabled() -> bool:
	return GameState.state == GameState.State.IN_GAME_ROBOT and not Debug.console_open


func _unhandled_input(event: InputEvent) -> void:
	if not is_input_enabled():
		return

	if event is InputEventMouseMotion:
		camera_altitude = clamp(camera_altitude - PlayerController.px_to_rad(event.relative.y), -altitude_limit, altitude_limit)
		camera_azimuth = fmod(camera_azimuth - PlayerController.px_to_rad(event.relative.x), 2.0 * PI)


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

		if Input.is_action_just_pressed("interact_use"):
			interact.emit(true)
		elif Input.is_action_just_released("interact_use"):
			interact.emit(false)

		if Input.is_action_just_pressed("interact_primary"):
			primary.emit(true)
		elif Input.is_action_just_released("interact_primary"):
			primary.emit(false)

		if Input.is_action_just_pressed("arm_toggle"):
			arm_toggle.emit()
		for joint in range(1, 6):
			if Input.is_action_just_pressed("arm_joint_%d" % joint):
				arm_joint = joint
		arm_rotate = Input.get_axis("arm_rotate_down", "arm_rotate_up")
	else:
		arm_rotate = 0.0
		# While locked only let releases through; presses are ignored.
		if Input.is_action_just_released("interact_use"):
			interact.emit(false)
		if Input.is_action_just_released("interact_primary"):
			primary.emit(false)

	steer = move_toward(steer, target_steer, steer_speed * delta)
	desired_speed = move_toward(desired_speed, target_desired_speed, desired_speed_rate * delta)
