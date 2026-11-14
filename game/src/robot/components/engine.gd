class_name RobotEngine

extends Node

## Brushed DC motor. Torque falls linearly with speed as back-EMF builds:
##     torque = stall_torque * (voltage - speed / no_load_speed)
## so the top speed is set by the motor (voltage * no_load_speed, minus whatever
## the load takes), and letting go of the input (voltage 0) brakes the motor
## with back-EMF, strongest at speed and fading towards standstill.
##
## The values set on this node are the robot's built-in motor. While a MotorPart
## is mounted in the robot's motor socket, `use_motor_part()` swaps its values in;
## with the socket empty the built-in values are used again.
##
## Sizing (for the 80 kg rover with a total ratio of 5, 0.15 m wheels and all six
## wheels driven):
##   no_load_speed ~ (top speed / wheel radius) * total ratio, a few percent
##     higher because rolling resistance pulls the loaded top speed down to it.
##   stall_torque ~ ((mass + reflected drivetrain inertia / radius^2) * launch
##     acceleration + rolling resistance) * radius / total ratio.
## That gives ~10 units/s and ~3.5 m/s^2 from rest.

## Torque at standstill with full voltage (Nm)
@export var stall_torque: float = 10.7
## Speed where back-EMF cancels full voltage and torque reaches zero (rad/s)
@export var no_load_speed: float = 345.0
## Rotor inertia (kg m^2)
@export var rotor_inertia: float = 0.01
## Electrical power drawn at standstill with full voltage (W)
@export var stall_power: float = 1500.0
## Optional shape multiplier on the torque, sampled at |speed| / no_load_speed
## (0..1). Leave empty for a plain linear DC motor.
@export var torque_curve: Curve

var _default_stall_torque: float
var _default_no_load_speed: float
var _default_rotor_inertia: float
var _default_stall_power: float
var _default_torque_curve: Curve


func _ready() -> void:
	_default_stall_torque = stall_torque
	_default_no_load_speed = no_load_speed
	_default_rotor_inertia = rotor_inertia
	_default_stall_power = stall_power
	_default_torque_curve = torque_curve


## Takes the motor values from `part`, or goes back to the built-in motor when null.
func use_motor_part(part: MotorPart) -> void:
	if part:
		stall_torque = part.stall_torque
		no_load_speed = part.no_load_speed
		rotor_inertia = part.rotor_inertia
		stall_power = part.stall_power
		torque_curve = part.torque_curve
	else:
		stall_torque = _default_stall_torque
		no_load_speed = _default_no_load_speed
		rotor_inertia = _default_rotor_inertia
		stall_power = _default_stall_power
		torque_curve = _default_torque_curve


## Torque (Nm) at the motor shaft. `voltage` is -1..1 (negative = reverse),
## `motor_angular_velocity` is signed (rad/s). The current limit keeps the
## result within +-stall_torque, so reversing at speed ("plugging") can't
## produce more torque than a standing start.
func get_motor_torque(motor_angular_velocity: float, voltage: float) -> float:
	var torque: float = stall_torque * (
		clamp(voltage, -1.0, 1.0) - motor_angular_velocity / no_load_speed
	)
	if torque_curve:
		torque *= torque_curve.sample(clamp(abs(motor_angular_velocity) / no_load_speed, 0.0, 1.0))
	return clamp(torque, -stall_torque, stall_torque)


## Electrical power (W) the motor draws from the battery. Current follows torque
## and the supply follows voltage, so power is voltage * torque / stall_torque
## scaled by `stall_power`. Braking never gives energy back (it is clamped to 0).
func get_electrical_power(motor_torque: float, voltage: float) -> float:
	var current_fraction: float = motor_torque / maxf(stall_torque, 0.001)
	return maxf(0.0, stall_power * clamp(voltage, -1.0, 1.0) * current_fraction)
