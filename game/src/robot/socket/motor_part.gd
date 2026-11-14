class_name MotorPart

extends HotswapPart

@export var max_torque: float = 100.0


func _init() -> void:
	part_type = PartType.MOTOR
