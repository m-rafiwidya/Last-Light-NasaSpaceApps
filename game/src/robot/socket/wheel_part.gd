class_name WheelPart

extends HotswapPart

## A swappable wheel. One pickup fits any wheel socket: "Model" holds both rover kit wheels,
## WheelL and WheelR (mirror images, hub connector on the inner side), and shows the one for
## the side of the socket it is mounted in (its anchor ends in "_L" / "_R"), or WheelL while
## loose. The axle is the part's local X; RoverVisuals spins "Model" about it.

## Radius of the kit wheel models (m), tools/blender/ROVER_KIT.md 3.1
const MODEL_RADIUS: float = 0.15

## Radius of the wheel (m). The model and the collision cylinder follow it.
@export var radius: float = 0.15:
	set(value):
		radius = value
		if is_node_ready():
			_apply_radius()
@export var grip: float = 1.0

@onready var _wheel_left: Node3D = $Model/WheelL
@onready var _wheel_right: Node3D = $Model/WheelR


func _init() -> void:
	part_type = PartType.WHEEL


func _ready() -> void:
	super._ready()
	# The kit models carry their own "Collision" shapes; this part collides through its
	# cylinder (a shape only counts as a direct child of the body anyway)
	for shape in $Model.find_children("Collision", "CollisionShape3D", true, false):
		shape.get_parent().remove_child(shape)
		shape.queue_free()
	_show_side("L")
	_apply_radius()


func attach_to(new_socket: HotswapSocket) -> void:
	super.attach_to(new_socket)
	_show_side("R" if String(new_socket.anchor).ends_with("_R") else "L")


func detach() -> void:
	super.detach()
	_show_side("L")


## Shows the wheel model for the given side ("L" / "R").
func _show_side(side: String) -> void:
	_wheel_left.visible = side != "R"
	_wheel_right.visible = side == "R"


func _apply_radius() -> void:
	# The axle is local X, so only Y and Z (the radius) are scaled; the width stays
	var factor: float = radius / MODEL_RADIUS
	$Model.scale = Vector3(1.0, factor, factor)

	# Scaling collision shapes is unreliable in physics, so resize the shape itself.
	# The shape resource is shared by every WheelPart, so give this one its own copy.
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision and collision.shape is CylinderShape3D:
		var shape := collision.shape.duplicate() as CylinderShape3D
		shape.radius = radius
		collision.shape = shape
