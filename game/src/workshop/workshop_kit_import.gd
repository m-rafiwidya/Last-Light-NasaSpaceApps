@tool
extends EditorScenePostImport

## Post-import script for the workshop kit GLBs in res://res/models/workshop_kit/
## (tools/blender/WORKSHOP_KIT.md 9.1).
##
## Godot imports each "-convcolonly" mesh as a StaticBody3D holding a convex CollisionShape3D,
## which is right for the static parts (walls, rack shelves, the console). The moving pieces
## (bay_door, personnel_door) carry their collider as a child: a static body there wouldn't push
## the player when the door moves, so it becomes an AnimatableBody3D that follows its door.

const MOVING_PIECES: Array[String] = ["bay_door", "personnel_door"]


func _post_import(scene: Node) -> Object:
	for body in scene.find_children("*", "StaticBody3D", true, false):
		var parent: Node = body.get_parent()
		if not String(parent.name) in MOVING_PIECES:
			continue
		var moving := AnimatableBody3D.new()
		var body_name: StringName = body.name
		moving.transform = body.transform
		moving.sync_to_physics = true
		for child in body.get_children():
			child.owner = null
			body.remove_child(child)
			moving.add_child(child)
		parent.remove_child(body)
		body.free()
		moving.name = body_name
		parent.add_child(moving)
		moving.owner = scene
		for child in moving.get_children():
			child.owner = scene
	return scene
