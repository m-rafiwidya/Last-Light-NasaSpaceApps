class_name RobotController

extends Node

## Robot intent. Reads input and exposes smoothed values the Robot reads directly,
## like PlayerController. One-shot events are signals (emitted with `true` on
## press, `false` on release).
## Shares the player's actions: move_forward / move_backward = desired speed
## forward / backward (as a fraction of the robot's top speed; no input = 0, so
## the robot slows down), move_left / move_right = steering, mouse = look,
## interact_use = pick up / drop, interact_primary = throw.
## Unlike PlayerController, input is only accepted while GameState is IN_GAME_ROBOT and its
## robot is the one being driven (GameState.robot), so each rover in a level is independent.

signal interact(value: bool)
signal primary(value: bool)
## R: deploy / stow the arm (press only)
signal arm_toggle
## F: put the rover back upright where it is (press only)
signal reset_requested
## Zoom, in wheel notches: + zooms in, - out. Fractional for trackpad scroll / pinch and the
## held zoom keys (see _unhandled_input / _physics_process)
signal zoom(steps: float)
## C: next camera view (press only)
signal camera_next

## The Robot this controller drives (set by the Robot)
var robot: Node = null


## Desired speed as a fraction of the robot's top speed. The robot uses it as the
## motor voltage: -1 (full reverse) .. 1 (full forward), 0 = no input.
var desired_speed: float = 0.0
## -1 (full left) .. 1 (full right)
var steer: float = 0.0

## Accumulated look yaw / pitch in radians (pitch clamped to +-90 degrees),
## relative to the robot body.
var camera_azimuth: float = 0.0
var camera_altitude: float = 0.0
## Limit (radians) of camera_altitude either way, set by the Robot
var altitude_limit: float = PI / 2.0
## Mouse look sensitivity multiplier; lowered while the camera is zoomed in
var look_scale: float = 1.0

## Arm joint picked with 1-5 (1 = J1 yaw .. 5 = J5 tool turret)
var arm_joint: int = 2
## -1 (Z, lower) .. 1 (X, raise) while held, 0 otherwise
var arm_rotate: float = 0.0

## Trackpad two-finger scroll: notches per unit of InputEventPanGesture.delta (macOS sends
## precise scrolling as pan gestures, about 0.03 per pixel scrolled, not as wheel buttons)
var pan_zoom_steps: float = 0.5
## Trackpad pinch: notches per natural log of the InputEventMagnifyGesture factor
## (4.5 = 1 / -ln(0.8): spreading the fingers to twice their distance zooms about 2x)
var pinch_zoom_steps: float = 4.5
## Zoom keys (= / -) held: notches per second
var key_zoom_rate: float = 4.0

var steer_speed: float = 2.0
var desired_speed_rate: float = 2.0

var was_input_enabled: bool = false
# The last trackpad gesture (type, value, frame): Godot 4.7 dispatches each gesture event
# twice, so a repeat within the same frame is dropped
var _last_gesture: Array = []


func is_input_enabled() -> bool:
	return (
		GameState.state == GameState.State.IN_GAME_ROBOT and not Debug.console_open
		and (robot == null or GameState.robot == robot)
	)


func _unhandled_input(event: InputEvent) -> void:
	if not is_input_enabled():
		return

	if event is InputEventMouseMotion:
		camera_altitude = clamp(camera_altitude - PlayerController.px_to_rad(event.relative.y) * look_scale, -altitude_limit, altitude_limit)
		camera_azimuth = fmod(camera_azimuth - PlayerController.px_to_rad(event.relative.x) * look_scale, 2.0 * PI)
	elif event is InputEventMouseButton and event.pressed:
		# One step per wheel notch (not event.factor: on macOS it includes scroll acceleration)
		if event.is_action("camera_zoom_in"):
			zoom.emit(1.0)
		elif event.is_action("camera_zoom_out"):
			zoom.emit(-1.0)
	elif event is InputEventPanGesture:
		# Two-finger scroll, same direction as the wheel: scrolling up (delta.y < 0) zooms in
		if event.delta.y != 0.0 and _is_new_gesture(event, event.delta):
			zoom.emit(-event.delta.y * pan_zoom_steps)
	elif event is InputEventMagnifyGesture:
		# Pinch: spreading the fingers (factor > 1) zooms in
		if event.factor > 0.0 and _is_new_gesture(event, event.factor):
			zoom.emit(log(event.factor) * pinch_zoom_steps)


func _is_new_gesture(event: InputEventGesture, value: Variant) -> bool:
	var gesture: Array = [event.get_class(), value, Engine.get_process_frames()]
	if gesture == _last_gesture:
		return false
	_last_gesture = gesture
	return true


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
		if Input.is_action_just_pressed("robot_reset"):
			reset_requested.emit()
		if Input.is_action_just_pressed("camera_next"):
			camera_next.emit()
		for joint in range(1, 6):
			if Input.is_action_just_pressed("arm_joint_%d" % joint):
				arm_joint = joint
		arm_rotate = Input.get_axis("arm_rotate_down", "arm_rotate_up")
		# The zoom keys zoom smoothly while held (the actions' wheel buttons are handled as
		# notches in _unhandled_input; a wheel press is released again before this poll)
		var key_zoom: float = Input.get_axis("camera_zoom_out", "camera_zoom_in")
		if key_zoom != 0.0:
			zoom.emit(key_zoom * key_zoom_rate * delta)
	else:
		arm_rotate = 0.0
		# While locked only let releases through; presses are ignored.
		if Input.is_action_just_released("interact_use"):
			interact.emit(false)
		if Input.is_action_just_released("interact_primary"):
			primary.emit(false)

	steer = move_toward(steer, target_steer, steer_speed * delta)
	desired_speed = move_toward(desired_speed, target_desired_speed, desired_speed_rate * delta)
