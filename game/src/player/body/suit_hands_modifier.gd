class_name SuitHandsModifier

extends SkeletonModifier3D

## Last skeleton modifier of the player's suit (PlayerBody), after the arm IK (TwoBoneIK3D
## places the wrists but doesn't turn the hands). Turns each hand to its grip and curls the
## fingers round it. Per side ("Left" / "Right"):
## - `hand_basis`: the hand's wanted orientation in world space (bone Y along the fingers,
##   bone Z out of the back of the hand, so the palm faces -Z);
## - `weight`: 0 keeps the animation's hand and fingers, 1 uses `hand_basis` and `curl`;
## - `curl`: finger curl towards the palm (radians; the far segments curl 1.3 times as much).

const FINGERS: Array[String] = ["Index", "Middle", "Ring", "Little"]

var hand_basis: Dictionary = {"Left": Basis.IDENTITY, "Right": Basis.IDENTITY}
var weight: Dictionary = {"Left": 0.0, "Right": 0.0}
var curl: Dictionary = {"Left": 0.0, "Right": 0.0}

# side -> [hand bone, [[finger bone, share of the curl], ...]]
var _bones: Dictionary = {}


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton:
		return
	if _bones.is_empty():
		for side in ["Left", "Right"]:
			var fingers: Array = []
			for finger in FINGERS:
				fingers.append([skeleton.find_bone(side + finger + "Proximal"), 1.0])
				fingers.append([skeleton.find_bone(side + finger + "Intermediate"), 1.3])
			fingers.append([skeleton.find_bone(side + "ThumbProximal"), 0.5])
			fingers.append([skeleton.find_bone(side + "ThumbDistal"), 0.7])
			_bones[side] = [skeleton.find_bone(side + "Hand"), fingers]
	var to_skeleton: Basis = skeleton.global_transform.basis.orthonormalized().inverse()
	for side in ["Left", "Right"]:
		var w: float = weight[side]
		if w <= 0.0:
			continue
		var hand: int = _bones[side][0]
		var pose: Transform3D = skeleton.get_bone_global_pose(hand)
		var from: Quaternion = pose.basis.get_rotation_quaternion()
		var to: Quaternion = (to_skeleton * (hand_basis[side] as Basis).orthonormalized()).get_rotation_quaternion()
		skeleton.set_bone_global_pose(hand, Transform3D(Basis(from.slerp(to, w)), pose.origin))
		for entry in _bones[side][1]:
			var bone: int = entry[0]
			# Bone Y runs along the finger and Z out of the back of the hand: a turn about -X
			# brings the tip towards the palm
			var curled: Quaternion = (skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
				* Quaternion(Vector3.RIGHT, -float(curl[side]) * float(entry[1])))
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(curled, w))
