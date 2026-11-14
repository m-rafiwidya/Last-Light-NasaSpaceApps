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
## Entry in PartCatalog (name, description, where it mounts); empty = the default for part_type
@export var catalog_id: String = ""
## Recolours the part's main kit material (ROVER_KIT.md 6.3), e.g. to mark a variant. Only
## surfaces using `tint_material` change; the rest keep the kit palette. Alpha 0 = no tint.
@export var tint: Color = Color(0.0, 0.0, 0.0, 0.0)
## The kit material the tint replaces: rover_body for most parts, rover_dark for wheels,
## the motor and the power unit
@export var tint_material: StringName = &"rover_body"
## Local offset from the socket's mount point while mounted
@export var mount_offset: Vector3 = Vector3.ZERO

## The socket this part is plugged into, null while loose
var socket: HotswapSocket = null

var _free_layer: int = 0
var _free_mask: int = 0


func _ready() -> void:
	_adopt_model_collision()
	_apply_tint()


# Gives every surface that uses `tint_material` (in any mesh under "Model") one tinted copy
# of that material, as a surface override, so the shared kit material stays untouched.
func _apply_tint() -> void:
	var model := get_node_or_null("Model")
	if model == null or tint.a <= 0.0:
		return
	var tinted: StandardMaterial3D = null
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	for mesh_instance in meshes:
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i) as StandardMaterial3D
			if material == null or material.resource_name != tint_material:
				continue
			if tinted == null:
				tinted = material.duplicate() as StandardMaterial3D
				tinted.albedo_color = Color(tint, 1.0)
			mesh_instance.set_surface_override_material(i, tinted)



# Rover kit models carry their convex collider as a "Collision" shape (rover_kit_import.gd).
# A shape only counts as a direct child of the body, so it replaces this part's own
# CollisionShape3D shape and the model's copy is removed.
func _adopt_model_collision() -> void:
	var model := get_node_or_null("Model")
	var own := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if model == null or own == null:
		return
	var found: Array = model.find_children("Collision", "CollisionShape3D", true, false)
	if found.is_empty():
		return
	var source := found[0] as CollisionShape3D
	own.shape = source.shape
	own.transform = _transform_in_part(source)
	for shape in found:
		shape.get_parent().remove_child(shape)
		shape.queue_free()


# The node's transform relative to this part (works before the part is in the tree)
func _transform_in_part(node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != self and parent is Node3D:
		result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result


func get_catalog_id() -> String:
	return catalog_id if not catalog_id.is_empty() else PartCatalog.default_id(part_type)


func get_display_name() -> String:
	return PartCatalog.entry(get_catalog_id())["name"]


## One line on what the part does (PartCatalog)
func get_description() -> String:
	return PartCatalog.entry(get_catalog_id())["description"]


## Where the part mounts (PartCatalog)
func get_mount_hint() -> String:
	return PartCatalog.entry(get_catalog_id())["mounts"]


## Stat lines for the tooltip; parts with stats override it
func get_stat_lines() -> PackedStringArray:
	return PackedStringArray()


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
