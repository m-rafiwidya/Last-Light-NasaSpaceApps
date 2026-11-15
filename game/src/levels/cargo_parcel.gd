extends "res://src/robot/socket/hotswap_part.gd"

## Stand-in for R2's carryable cargo crate (CargoPlan.CRATE_PART_SCENE): the delivered crate as one
## CARGO part that rides home on Kite's cargo mount. Its mass is the order's (MissionDirector sets
## it); its contents come from CargoPlan, not from this node.

const DECOR_CRATE: String = "res://res/models/decor_kit/dc_crate.glb"


func _ready() -> void:
	super()
	var model := get_node_or_null("Model") as MeshInstance3D
	var scene := load(DECOR_CRATE) as PackedScene
	if model == null or scene == null:
		return
	var decor: Node = scene.instantiate()
	var meshes: Array[Node] = decor.find_children("*", "MeshInstance3D", true, false)
	if not meshes.is_empty() and (meshes[0] as MeshInstance3D).mesh:
		model.material_override = (meshes[0] as MeshInstance3D).get_active_material(0)
	decor.free()


func get_display_name() -> String:
	return "Cargo crate"


func get_description() -> String:
	return "The delivered crate. Kite carries it home on its cargo mount; it is unpacked in the bay."


func get_mount_hint() -> String:
	return "Rides on the rover's cargo mount"
