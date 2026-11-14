class_name HotswapPart

extends RigidBody3D

## Base class for anything that can be plugged into a HotswapSocket (wheels, motors,
## batteries...). While loose it is an ordinary pickup prop on the props layer. While
## mounted it is frozen, has no collision (so it can't push the robot around) and is
## parented to the socket's mount point, so it follows the robot without any lag.
## Concrete parts (WheelPart, MotorPart, BatteryPart) add the stats the robot reads; mast heads,
## arm tools and antennas are plain HotswapParts for now (no stats yet).

# New types are appended so the stored values of existing scenes stay valid
enum PartType { WHEEL, MOTOR, BATTERY, MAST_HEAD, ARM_TOOL, ANTENNA }

@export var part_type: PartType = PartType.WHEEL
@export var display_name: String = "Hotswap Part"
## Colour of the placeholder model (the child MeshInstance3D named "Model")
@export var tint: Color = Color(0.25, 0.25, 0.28)
## Local offset from the socket's mount point while mounted
@export var mount_offset: Vector3 = Vector3.ZERO

## The socket this part is plugged into, null while loose
var socket: HotswapSocket = null

var _free_layer: int = 0
var _free_mask: int = 0


func _ready() -> void:
	var model := get_node_or_null("Model") as MeshInstance3D
	if model:
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		model.material_override = material



func get_display_name() -> String:
	return display_name


## Why this part can't be mounted ("" if it can). Parts with limits, like the wheel envelope,
## override it; a socket refuses the part and shows the reason to the player.
func get_mount_problem() -> String:
	return ""


func is_mounted() -> bool:
	return socket != null


## Called by HotswapSocket after it has parented this part to its mount point.
func attach_to(new_socket: HotswapSocket) -> void:
	socket = new_socket
	_free_layer = collision_layer
	_free_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true


## Called by HotswapSocket after it has moved this part back into the world.
## The layers are restored here, so ObjectHolder.pickup() can be used right afterwards.
func detach() -> void:
	socket = null
	collision_layer = _free_layer
	collision_mask = _free_mask
	freeze = false
