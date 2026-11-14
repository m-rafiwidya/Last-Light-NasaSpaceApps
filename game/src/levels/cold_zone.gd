class_name ColdZone

extends Marker3D

## A shaded area on an M3 route (a vertical cylinder of `radius` around this marker). Kite inside
## an active zone without the thermal cover and heater fitted gets cold (MissionDirector).
## A night_only zone is active only when the cargo arrived late, putting M3 near nightfall.

@export var radius: float = 30.0
@export var night_only: bool = false
@export var route_name: String = ""


func _ready() -> void:
	add_to_group(&"cold_zone")


func is_active() -> bool:
	return not night_only or CargoPlan.m3_near_nightfall()


func contains(point: Vector3) -> bool:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length() <= radius
