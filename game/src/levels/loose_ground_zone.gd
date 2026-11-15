class_name LooseGroundZone

extends Marker3D

## Loose regolith on an M3 route (a vertical cylinder of `radius` around this marker). Simulated:
## the 2 m DTM can't show it (SCIENCE_AND_DATA.md). While Kite is inside, MissionDirector sets
## Robot.ground_traction to `traction` (only when the rover has that property) and restores 1.0
## when it leaves.

@export var radius: float = 16.0
@export_range(0.05, 1.0) var traction: float = 0.5
@export var label: String = "loose ground"
@export var routes: PackedStringArray = []
## What gets through it, for the forecast and the report's why line
@export var needs: String = "grip_wheels"


func _ready() -> void:
	add_to_group(&"loose_ground_zone")


func contains(point: Vector3) -> bool:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length() <= radius
