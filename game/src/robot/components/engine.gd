class_name RobotEngine

extends Node

## Brushed DC motor. Torque falls linearly with speed as back-EMF builds:
##     torque = stall_torque * (voltage - speed / no_load_speed)
## so the top speed is set by the motor (voltage * no_load_speed, minus whatever
## the load takes), and letting go of the input (voltage 0) brakes the motor
## with back-EMF, strongest at speed and fading towards standstill.
##
## Sizing (for the 80 kg rover with a total ratio of 5 and 0.15 m wheels):
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
@export var inertia: float = 0.01
## Optional shape multiplier on the torque, sampled at |speed| / no_load_speed
## (0..1). Leave empty for a plain linear DC motor.
@export var torque_curve: Curve


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
