class_name BatteryPart

extends HotswapPart

@export var capacity: float = 100.0


func _init() -> void:
	part_type = PartType.BATTERY
