class_name WheelPart

extends HotswapPart

## Radius of the wheel (m). The placeholder model and collision shape follow it.
@export var radius: float = 0.15:
	set(value):
		radius = value
		if is_node_ready():
			_apply_radius()
@export var grip: float = 1.0

var _model_base_radius: float = 0.0


func _init() -> void:
	part_type = PartType.WHEEL


func _ready() -> void:
	super._ready()
	var model := get_node_or_null("Model") as MeshInstance3D
	if model and model.mesh is CylinderMesh:
		_model_base_radius = (model.mesh as CylinderMesh).bottom_radius
	_apply_radius()


func _apply_radius() -> void:
	# The cylinder's axis is local Y, so only X and Z (the radius) are scaled
	var model := get_node_or_null("Model") as MeshInstance3D
	if model and _model_base_radius > 0.0:
		var factor: float = radius / _model_base_radius
		model.scale = Vector3(factor, 1.0, factor)

	# Scaling collision shapes is unreliable in physics, so resize the shape itself.
	# The shape resource is shared by every WheelPart, so give this one its own copy.
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision and collision.shape is CylinderShape3D:
		var shape := collision.shape.duplicate() as CylinderShape3D
		shape.radius = radius
		collision.shape = shape
