@tool
extends EditorScenePostImport

## Post-import script for the rover kit GLBs in res://res/models/rover_kit/ (ROVER_KIT.md 7).
##
## Godot imports a "-convcolonly" mesh as a StaticBody3D holding a convex CollisionShape3D.
## A static body can't live inside the rover's RigidBody3D (it collides with the rover
## itself and throws it around), so each one is replaced by a plain CollisionShape3D named
## "Collision" in the same place. The physics body that uses the part copies that shape
## onto itself (see Robot._adopt_body_collision).


func _post_import(scene: Node) -> Object:
	for body in scene.find_children("*", "StaticBody3D", true, false):
		var parent: Node = body.get_parent()
		for child in body.get_children():
			var source := child as CollisionShape3D
			if source == null:
				continue
			var collision := CollisionShape3D.new()
			collision.name = "Collision"
			collision.shape = source.shape
			collision.transform = body.transform * source.transform
			parent.add_child(collision)
			collision.owner = scene
		parent.remove_child(body)
		body.free()
	return scene
