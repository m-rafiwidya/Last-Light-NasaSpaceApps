class_name BatteryPart

extends HotswapPart

## Energy store for the robot. The charge lives on the part, so a hot-swapped
## battery keeps its own charge. The robot drains it through `drain()` (see
## Robot._step_drivetrain) and the motor only gets voltage while it has charge.

## Energy the battery holds when full (Wh)
@export var capacity: float = 100.0
## Charge the battery starts with, as a fraction of `capacity`
@export_range(0.0, 1.0) var initial_charge: float = 1.0
## Below this charge fraction the available voltage sags linearly to zero, so a
## dying battery gives less speed and torque instead of cutting out abruptly
@export_range(0.01, 1.0) var sag_threshold: float = 0.1

## Energy left (Wh)
var charge: float = 0.0


func _init() -> void:
	part_type = PartType.BATTERY


func _ready() -> void:
	super._ready()
	charge = capacity * initial_charge


## Charge as a fraction of capacity, 0..1
func get_charge_fraction() -> float:
	if capacity <= 0.0:
		return 0.0
	return clampf(charge / capacity, 0.0, 1.0)


func is_empty() -> bool:
	return charge <= 0.0


## Multiplier (0..1) on the voltage the motor can get. 1 until the charge falls
## below `sag_threshold`, then it drops to 0 when the battery is empty.
func get_voltage_factor() -> float:
	return clampf(get_charge_fraction() / sag_threshold, 0.0, 1.0)


## Takes energy (Wh) out of the battery. It never goes below empty.
func drain(energy: float) -> void:
	charge = clampf(charge - energy, 0.0, capacity)


## Puts energy (Wh) into the battery, e.g. from a charging station. It never goes above capacity.
func add_charge(energy: float) -> void:
	charge = clampf(charge + energy, 0.0, capacity)
