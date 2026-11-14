class_name SuitPoseModifier

extends SkeletonModifier3D

## First skeleton modifier of the player's suit (PlayerBody), after the animation. Turns the
## lower body under the upper body: the whole skeleton turns by `lower_yaw` about the body's
## vertical axis (Root), and the waist bearing (Spine) turns the upper body back, so the chest
## keeps facing the view while the legs walk the way the player moves. A hard suit's waist
## bearing is a real rotating joint, so the twist reads as the suit, not as a broken spine.
## `lean` bends the upper body forward at the waist (radians), for reaching low.

## Lower body yaw relative to the view (radians, Godot's sense: positive turns left)
var lower_yaw: float = 0.0
## Forward bend at the waist (radians)
var lean: float = 0.0

var _root: int = -1
var _spine: int = -1


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton:
		return
	if _root < 0:
		_root = skeleton.find_bone("Root")
		_spine = skeleton.find_bone("Spine")
	# The clips don't key Root, so its pose is set from the rest, not from last frame's
	skeleton.set_bone_pose_rotation(
		_root, Quaternion(Vector3.UP, lower_yaw) * skeleton.get_bone_rest(_root).basis.get_rotation_quaternion())
	# Skeleton space: the suit faces +Z, so a positive turn about +X tips the chest forward
	var spine: Transform3D = skeleton.get_bone_global_pose(_spine)
	var back: Basis = Basis(Vector3.RIGHT, lean) * Basis(Vector3.UP, -lower_yaw)
	skeleton.set_bone_global_pose(_spine, Transform3D(back * spine.basis, spine.origin))
