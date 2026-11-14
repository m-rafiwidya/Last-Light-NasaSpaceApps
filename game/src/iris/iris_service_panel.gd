class_name IrisServicePanel

extends ScanTarget

## IRIS's service panel S-1 as M1's scan target (tools/blender/IRIS_KIT.md 6.1, 6.3): a thin box
## collider over the panel, placed by Iris on the model's `scan_point` (50 mm in front of the
## panel's middle), layer 2 like IRIS's own colliders, so the mast camera's ray stops on it before
## IRIS's body. MissionDirector completes m1.iris_scanned from its `target_id` "iris_panel";
## Guidance finds it as `scan:iris_panel`. It has no mesh: the panel itself is part of iris.glb, so
## `highlight_node` points Guidance's glow at the model's `iris_service_panel` (panel, door, labels).

const PANEL_SIZE := Vector3(0.70, 0.87, 0.02)

## What to light up when this is the guidance target (set by Iris: the panel's mesh in the model)
@export var highlight_node: Node3D


func _ready() -> void:
	super()
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = PANEL_SIZE
	shape.shape = box
	add_child(shape)
