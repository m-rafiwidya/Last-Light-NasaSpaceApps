class_name MotorPart

extends HotswapPart

## A swappable brushed DC motor. The values mean the same as on RobotEngine; while
## this part is mounted the robot's engine uses them instead of its own defaults
## (see RobotEngine.use_motor_part). A motor with a higher `stall_torque` accelerates
## harder, a higher `no_load_speed` gives a higher top speed.

## Torque at standstill with full voltage (Nm)
@export var stall_torque: float = 10.7
## Speed where back-EMF cancels full voltage and torque reaches zero (rad/s)
@export var no_load_speed: float = 345.0
## Rotor inertia (kg m^2). Named `rotor_inertia` because RigidBody3D already has `inertia`.
@export var rotor_inertia: float = 0.01
## Electrical power drawn from the battery at standstill with full voltage (W).
## The draw scales with voltage and torque, so cruising costs far less than launching.
@export var stall_power: float = 1500.0
## Optional shape multiplier on the torque, see RobotEngine.torque_curve
@export var torque_curve: Curve


func _init() -> void:
	part_type = PartType.MOTOR


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([
		"Stall torque %.1f Nm" % stall_torque,
		"No-load speed %.0f rad/s" % no_load_speed,
		"Stall power %.0f W" % stall_power,
	])
