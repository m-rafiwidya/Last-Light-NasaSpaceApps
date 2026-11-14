class_name CarEngine

extends Node

@export var torque_curve: Curve
# Small electric drive motor sized for a ~80 kg rover. Speeds are rad/s (rpm * 0.1047).
@export var peak_torque: float = 9.0
@export var idle_speed: float = 500.0 * 0.1047
@export var lower_redline: float = 3800.0 * 0.1047
@export var upper_redline: float = 4000.0 * 0.1047
@export var inertia: float = 0.01

var is_disabled: bool = false


## Torque the engine produces at the given speed. `throttle` is 0..1; the
## rev limiter cuts torque between the upper and lower redline.
func get_engine_torque(engine_angular_velocity: float, throttle: float) -> float:
	if engine_angular_velocity >= upper_redline and not is_disabled:
		is_disabled = true
	if engine_angular_velocity <= lower_redline and is_disabled:
		is_disabled = false
	if is_disabled:
		return 0.0
	return peak_torque * torque_curve.sample(engine_angular_velocity / upper_redline) * throttle
