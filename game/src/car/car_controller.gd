class_name CarController

extends Node

## Car intent. Reads input and turns it into the smoothed ControlValue entries
## that Car / Engine / RunningGear consume. One-shot events are signals (emitted
## with `true` on press, `false` on release), like PlayerController.
## Shares the player's movement actions: move_forward = throttle,
## move_backward = brake, move_left / move_right = steering.
## Like PlayerController, input is only accepted while GameState is IN_GAME.

signal shift_up(value: bool)
signal shift_down(value: bool)
signal toggle_camera(value: bool)

enum ControlValue{
	ACCELERATE,
	BRAKE,
	CLUTCH,
	STEER,
	GEAR
}
var control_value: Dictionary = {
	ControlValue.ACCELERATE: 0.0,
	ControlValue.BRAKE: 0.0,
	ControlValue.CLUTCH: 0.0,
	ControlValue.STEER: 0.0,
	ControlValue.GEAR: 0,
}

var steer_speed: float = 2.0
var accelerate_speed: float = 4.0
var brake_speed: float = 4.0
var clutch_speed: float = 4.0

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
	var target_accelerate: float = 0.0
	var target_brake: float = 0.0
	var target_clutch: float = 0.0

	# Polled (not event driven) so releases during a lock can't leave keys stuck.
	if accept_input:
		target_steer = Input.get_axis("move_left", "move_right")
		target_accelerate = Input.get_action_strength("move_forward")
		target_brake = Input.get_action_strength("move_backward")
		target_clutch = float(Input.is_action_pressed("clutch"))

		_emit_action("shift_up", shift_up)
		_emit_action("shift_down", shift_down)
		_emit_action("camera", toggle_camera)
	else:
		_emit_releases()

	control_value[ControlValue.STEER] = move_toward(
		control_value[ControlValue.STEER], target_steer, steer_speed * delta
	)
	control_value[ControlValue.ACCELERATE] = move_toward(
		control_value[ControlValue.ACCELERATE], target_accelerate, accelerate_speed * delta
	)
	control_value[ControlValue.BRAKE] = move_toward(
		control_value[ControlValue.BRAKE], target_brake, brake_speed * delta
	)
	control_value[ControlValue.CLUTCH] = move_toward(
		control_value[ControlValue.CLUTCH], target_clutch, clutch_speed * delta
	)


func _emit_action(action: StringName, event: Signal) -> void:
	if Input.is_action_just_pressed(action):
		event.emit(true)
	elif Input.is_action_just_released(action):
		event.emit(false)


## While input is locked only let releases through; presses are ignored.
func _emit_releases() -> void:
	if Input.is_action_just_released("shift_up"):
		shift_up.emit(false)
	if Input.is_action_just_released("shift_down"):
		shift_down.emit(false)
	if Input.is_action_just_released("camera"):
		toggle_camera.emit(false)
