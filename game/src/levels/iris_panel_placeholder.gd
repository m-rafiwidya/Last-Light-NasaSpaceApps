extends ScanTarget

## Temporary: stands in for IRIS's service panel until Iris has its own target_id. Delete this
## node from moon_level.tscn and this script then.

const PANEL_SIZE := Vector3(0.70, 0.87, 0.02)

@export var iris: Node3D


func _ready() -> void:
	super()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = PANEL_SIZE
	shape.shape = box
	add_child(shape)
	var anchor := iris.find_child("scan_point", true, false) as Node3D if iris else null
	if anchor:
		global_transform = anchor.global_transform.orthonormalized()
