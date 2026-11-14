class_name PlayerCarController

extends Controller

## Keyboard driven car controller. Reads input and turns it into the smoothed
## ControlValue entries that Car / Engine / RunningGear consume.
## Like PlayerController, input is only accepted while GameState is IN_GAME.

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
		target_steer = Input.get_axis("steer_left", "steer_right")
		target_accelerate = float(Input.is_action_pressed("accelerate"))
		target_brake = float(Input.is_action_pressed("brake"))
		target_clutch = float(Input.is_action_pressed("clutch"))

		if Input.is_action_just_pressed("shift_up"):
			_call_discrete("shift_up")
		if Input.is_action_just_pressed("shift_down"):
			_call_discrete("shift_down")

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


func _call_discrete(action: String) -> void:
	var callback: Variant = discrete_callbacks.get(action)
	if callback is Callable and callback.is_valid():
		callback.call()
