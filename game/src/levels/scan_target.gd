class_name ScanTarget

extends StaticBody3D

signal scanned(rover: Robot)

@export var target_id: String = ""
@export var scan_name: String = ""
@export_multiline var scan_report: String = ""

var is_scanned: bool = false


func _init() -> void:
	collision_layer = 2
	collision_mask = 0


func _ready() -> void:
	add_to_group(&"scan_target")


func mark_scanned(rover: Robot) -> void:
	if is_scanned:
		return
	is_scanned = true
	scanned.emit(rover)
