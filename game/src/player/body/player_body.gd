class_name PlayerBody

extends Node3D

## The player's own spacesuit, seen from inside (tools/blender/ASTRONAUT_KIT.md 13). Purely
## visual: no collision, no forces, no input. It reads the Player (its parent) and never writes
## to it, except one opt-in link: `player.holder.hold_point`, which makes ObjectHolder pull a held
## part into the suit's hands (about 0.5 m in front of the chest) instead of 2 m in front of
## the camera.
##
## - The suit is the astronaut kit's rig and mesh (astronaut_fp.glb), scaled to 0.95 so its eyes
##   are at the 1.5 m camera. The helmet (and neck ring) is drawn as a shadow only: it casts its
##   shadow, but no camera sees it, so the player never looks at the inside of it.
## - The camera is the player's and is never moved by the body: no bob, no landing dip. The
##   body moves under it.
## - The upper body faces the view; the legs face the way the player moves and the waist
##   bearing turns between them (SuitPoseModifier). Standing still, the legs stay put while the
##   view turns, and step round once it is 50 degrees away.
## - Animation (AnimationTree, built in code below): idle, walk / sprint blended by speed and
##   played at speed / stride cycles a second so the boots don't slide, crouch (following the
##   camera's own crouch height), in the air (by vertical speed over take-off speed, so the same
##   poses fit a 0.8 s Earth jump and a 2.3 s Moon jump) and a landing scaled by impact speed.
## - Hands (TwoBoneIK3D on each arm, then SuitHandsModifier): a held part is gripped with the
##   right hand (small parts) or both hands (wheels, boxes); the hands follow the part, which
##   physics still moves. Parts too big to carry (a rover) keep the old floating hold, with the
##   arms reaching towards them. Throwing pushes the arms out after the release; dropping opens
##   the hands.

const SUIT_SCALE: float = 0.95
## Render layer 11: the suit, left out of the helmet light's shadows (the light is inside it)
const BODY_LAYER: int = 1 << 10
## World metres per locomotion cycle (two steps), from make_astronaut_anims.py at SUIT_SCALE
const WALK_STRIDE: float = 1.3333
const SPRINT_STRIDE: float = 1.80
const CROUCH_STRIDE: float = 0.90
## Locomotion clips authored at these speeds (Player.SPEED_WALK / SPEED_SPRINT)
const WALK_SPEED: float = 2.0
const SPRINT_SPEED: float = 3.0
## Standing still, the legs step round when the view is this far from them
const TURN_START: float = deg_to_rad(50.0)
## Moving more than this far from the view's direction walks backwards
const BACKWARDS_FROM: float = deg_to_rad(100.0)
## Looking down, the body slides back this far so the chest doesn't fill the view
const LOOK_DOWN_SLIDE: float = 0.16
## Parts up to this size (largest side, m) go in the right hand; up to CARRY_MAX in both
const ONE_HAND_MAX: float = 0.27
const CARRY_MAX: float = 0.8
## From the wrist joint to the middle of the palm's surface (hand bone frame, scaled)
const PALM_ALONG: float = 0.075 * SUIT_SCALE
const PALM_BELOW: float = 0.03 * SUIT_SCALE
## Below this drop under the capsule (crouching, a step down) the boots stay on the ground
const MAX_DROP: float = 0.6
## Not ground for the boots: the boundary walls and the pressure curtain (layers 7, 8)
const GROUND_IGNORE: int = (1 << 6) | (1 << 7)
## How far (m, world) each clip's eyes are ahead of the suit's origin on average
## (make_astronaut_anims.py prints them). Blended like the clips, they keep the eyes under the
## camera without following a stride's sway, which would drag the planted boots.
const CLIP_EYE: Dictionary = {
	"idle": 0.118, "walk": 0.150, "walk_back": 0.105, "sprint": 0.198, "crouch_idle": 0.411, "crouch_walk": 0.416,
	"turn_step": 0.114, "air_rise": 0.138, "air_apex": 0.147, "air_fall": 0.105, "land": 0.217,
}
## Where a held part's centre is pulled to: (camera pitch in degrees, forward, up) in the view's
## frame from the camera, interpolated by pitch
const HOLD_TABLE: Array = [[-60.0, 0.48, -0.80], [-30.0, 0.47, -0.57], [0.0, 0.45, -0.36], [60.0, 0.40, -0.10]]

enum Grip { NONE, ONE_HAND, TWO_HANDS, OVERSIZE }

@export var player: Player

var suit: Node3D
var skeleton: Skeleton3D
var tree: AnimationTree
var body_mesh: MeshInstance3D
var helmet_mesh: MeshInstance3D
## Where ObjectHolder pulls a held part (top level, moved every physics step)
var hold_point: Marker3D

var pose_modifier: SuitPoseModifier
var hands_modifier: SuitHandsModifier
var arm_ik: Dictionary = {}         # side -> TwoBoneIK3D
var _ik_target: Dictionary = {}     # side -> Marker3D (the wrist)
var _ik_pole: Dictionary = {}       # side -> Marker3D (the elbow points towards it)

# Locomotion state
var feet_yaw: float = 0.0           # world yaw the legs face (Godot sense)
var _backwards: bool = false
var _back: float = 0.0              # blend to walk_back (0 forwards, 1 backwards)
var _turning: bool = false
var _turn_amount: float = 0.0
var _air_time: float = 0.0
var _air: float = 0.0
var _fall_speed: float = 0.0
var _land_time: float = 10.0
var _land_strength: float = 0.0
var _move: float = 0.0
var _jumped: bool = false

# Hands
var grip: Grip = Grip.NONE
var _held: RigidBody3D = null
var _grip_local: Dictionary = {}    # side -> grip point in the part's frame
var _normal_local: Dictionary = {}  # side -> outward normal there, in the part's frame
var _hold_offset: Vector3 = Vector3.ZERO   # extra (right, up, forward) for this part
var _box_centre: Vector3 = Vector3.ZERO    # middle of the held part's collision, in its frame
var _arm_weight: Dictionary = {"Left": 0.0, "Right": 0.0}
var _arm_goal: Dictionary = {"Left": 0.0, "Right": 0.0}
var _closed: Dictionary = {"Left": 0.0, "Right": 0.0}
var _closed_curl: float = deg_to_rad(60.0)
# After a drop or a throw the hands keep their place in the view's frame while they fade out
var _release_time: float = -1.0
var _thrown: bool = false
var _release_wrist: Dictionary = {}       # side -> wrist in the view frame
var _release_basis: Dictionary = {}       # side -> hand basis in the view frame
# The wrists as last drawn (after the IK; the skeleton only has the final pose while it updates)
var _drawn_wrist: Dictionary = {"Left": Vector3.INF, "Right": Vector3.INF}


func _ready() -> void:
	if not player:
		player = get_parent() as Player
	# A child is ready before its parent: the Player makes its holder in its own _ready
	if not player.is_node_ready():
		set_process(false)
		set_physics_process(false)
		await player.ready
		set_process(true)
		set_physics_process(true)
	suit = $Suit
	skeleton = suit.find_children("*", "Skeleton3D", true, false)[0]
	body_mesh = skeleton.get_node("astronaut_body")
	helmet_mesh = skeleton.get_node("astronaut_helmet")
	body_mesh.layers = BODY_LAYER
	helmet_mesh.layers = BODY_LAYER
	helmet_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	if player.helmet_light:
		player.helmet_light.shadow_caster_mask &= ~BODY_LAYER
	_build_tree()
	_build_modifiers()
	skeleton.skeleton_updated.connect(_on_skeleton_updated)
	hold_point = Marker3D.new()
	hold_point.name = "HoldPoint"
	hold_point.top_level = true
	add_child(hold_point)
	feet_yaw = _view_yaw()
	_place_hold_point()
	if player.holder:
		player.holder.hold_point = hold_point
		player.holder.picked_up.connect(_on_picked_up)
		player.holder.dropped.connect(_on_released.bind(false))
		player.holder.thrown.connect(_on_released.bind(true))
	GameState.state_changed.connect(_on_game_state_changed)
	_on_game_state_changed(GameState.state, GameState.state)


func _on_game_state_changed(_old, new_state) -> void:
	# While driving (and paused from driving), the console's seated operator is the player's
	# body (Workshop), and the player stands at the console where it sits
	var menu: bool = (new_state == GameState.State.PAUSED or new_state == GameState.State.IN_GAME_MENU
			or new_state == GameState.State.CREDITS or new_state == GameState.State.CUTSCENE)
	visible = not (new_state == GameState.State.IN_GAME_ROBOT
		or (menu and GameState.last_in_game_state == GameState.State.IN_GAME_ROBOT))


# --- Animation tree ---------------------------------------------------------------------------

func _clip(clip: String, cycle: bool = false) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	if cycle:
		# Every locomotion cycle lasts one second on the tree's clock, so walk and sprint blend in
		# step and one TimeScale (cycles a second) drives them
		node.use_custom_timeline = true
		node.timeline_length = 1.0
		node.stretch_time_scale = true
		node.loop_mode = Animation.LOOP_LINEAR
	return node


func _blend2(bt: AnimationNodeBlendTree, node_name: String, a: String, b: String) -> void:
	var blend := AnimationNodeBlend2.new()
	blend.sync = true
	bt.add_node(node_name, blend)
	bt.connect_node(node_name, 0, a)
	bt.connect_node(node_name, 1, b)


func _build_tree() -> void:
	var source: AnimationPlayer = suit.find_children("*", "AnimationPlayer", true, false)[0]
	var library: AnimationLibrary = source.get_animation_library("")
	for clip in ["idle", "crouch_idle", "turn_step"]:
		library.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	source.active = false
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("idle", _clip("idle"))
	var gait := AnimationNodeBlendSpace1D.new()
	gait.max_space = SPRINT_SPEED
	gait.min_space = WALK_SPEED
	gait.sync = true
	gait.add_blend_point(_clip("walk", true), WALK_SPEED, -1, &"walk")
	gait.add_blend_point(_clip("sprint", true), SPRINT_SPEED, -1, &"sprint")
	bt.add_node("gait", gait)
	bt.add_node("rate", AnimationNodeTimeScale.new())
	bt.connect_node("rate", 0, "gait")
	# Walking backwards has its own clip (the boot lands on its toe and leaves over its heel), not
	# the walk played in reverse
	bt.add_node("walk_back", _clip("walk_back", true))
	bt.add_node("back_rate", AnimationNodeTimeScale.new())
	bt.connect_node("back_rate", 0, "walk_back")
	_blend2(bt, "back", "rate", "back_rate")
	_blend2(bt, "move", "idle", "back")
	bt.add_node("turn_step", _clip("turn_step"))
	_blend2(bt, "turn", "move", "turn_step")
	bt.add_node("crouch_idle", _clip("crouch_idle"))
	bt.add_node("crouch_walk", _clip("crouch_walk", true))
	bt.add_node("crouch_rate", AnimationNodeTimeScale.new())
	bt.connect_node("crouch_rate", 0, "crouch_walk")
	_blend2(bt, "crouch_move", "crouch_idle", "crouch_rate")
	_blend2(bt, "crouch", "turn", "crouch_move")
	bt.add_node("land_pose", _clip("land"))
	_blend2(bt, "land", "crouch", "land_pose")
	var air := AnimationNodeBlendSpace1D.new()
	air.min_space = -1.0
	air.max_space = 1.0
	air.add_blend_point(_clip("air_fall"), -1.0, -1, &"fall")
	air.add_blend_point(_clip("air_apex"), 0.0, -1, &"apex")
	air.add_blend_point(_clip("air_rise"), 1.0, -1, &"rise")
	bt.add_node("air_pose", air)
	_blend2(bt, "air", "land", "air_pose")
	bt.connect_node("output", 0, "air")

	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.add_animation_library("", library)
	tree.tree_root = bt
	# Advanced by _process, so the pose always matches this frame's player state
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	suit.add_child(tree)
	tree.root_node = tree.get_path_to(suit)
	tree.active = true


func _build_modifiers() -> void:
	pose_modifier = SuitPoseModifier.new()
	pose_modifier.name = "SuitPose"
	skeleton.add_child(pose_modifier)
	for side in ["Left", "Right"]:
		var target := Marker3D.new()
		target.name = side + "WristTarget"
		target.top_level = true
		add_child(target)
		var pole := Marker3D.new()
		pole.name = side + "ElbowPole"
		pole.top_level = true
		add_child(pole)
		var ik := TwoBoneIK3D.new()
		ik.name = side + "ArmIK"
		ik.setting_count = 1
		skeleton.add_child(ik)
		ik.set("settings/0/root_bone_name", side + "UpperArm")
		ik.set("settings/0/middle_bone_name", side + "LowerArm")
		ik.set("settings/0/end_bone_name", side + "Hand")
		ik.set("settings/0/target_node", ik.get_path_to(target))
		ik.set("settings/0/pole_node", ik.get_path_to(pole))
		ik.influence = 0.0
		arm_ik[side] = ik
		_ik_target[side] = target
		_ik_pole[side] = pole
	hands_modifier = SuitHandsModifier.new()
	hands_modifier.name = "SuitHands"
	skeleton.add_child(hands_modifier)


# --- Frames -------------------------------------------------------------------------------------

func _view_yaw() -> float:
	return player.pivot.global_basis.get_euler().y


## The view's frame without pitch: -Z forward, +X right, +Y up
func _view_basis() -> Basis:
	return Basis(Vector3.UP, _view_yaw())


func _pitch() -> float:
	return player.camera.rotation.x


func _hold_position() -> Vector3:
	var pitch: float = clampf(rad_to_deg(_pitch()), HOLD_TABLE[0][0], HOLD_TABLE[-1][0])
	var forward: float = HOLD_TABLE[0][1]
	var up: float = HOLD_TABLE[0][2]
	for i in range(HOLD_TABLE.size() - 1):
		var a: Array = HOLD_TABLE[i]
		var b: Array = HOLD_TABLE[i + 1]
		if pitch >= a[0] and pitch <= b[0]:
			var t: float = (pitch - a[0]) / (b[0] - a[0])
			forward = lerpf(a[1], b[1], t)
			up = lerpf(a[2], b[2], t)
	var local := Vector3(_hold_offset.x, up + _hold_offset.y, -forward - _hold_offset.z)
	return player.camera.global_position + _view_basis() * local


func _place_hold_point() -> void:
	# ObjectHolder pulls the part's origin; kit parts have it at their connector, so aim the
	# middle of the part at the hands instead
	var centre: Vector3 = _held.global_basis * _box_centre if _held else Vector3.ZERO
	hold_point.global_position = _hold_position() - centre


func _physics_process(_delta: float) -> void:
	# ObjectHolder reads it in the Player's next physics step
	_place_hold_point()


# --- Every frame --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible or not player.controller:
		return
	var view := _view_basis()
	var velocity: Vector3 = player.linear_velocity
	var local: Vector3 = view.inverse() * velocity
	var flat := Vector2(local.x, local.z)
	var speed: float = flat.length()

	# Where the boots stand. Crouching shrinks the capsule round its centre, so the player sinks
	# 0.5 m (on the Moon slowly, in the air for most of a second): the boots stay on the ground
	# under it unless the player really jumped or the ground is far below.
	var shape: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	var bottom: float = player.global_position.y + 1.0 - shape.height / 2.0
	var ground: float = _probe_ground()
	var on_floor: bool = player.is_on_floor
	if on_floor:
		_jumped = false
	elif velocity.y > 0.5 and _air_time < 0.1:
		_jumped = true
	var grounded: bool = on_floor or (not _jumped and not is_nan(ground) and bottom - ground < MAX_DROP)
	var feet: float = ground if grounded and not is_nan(ground) else bottom
	# Crouch from how high the eye is over the boots: 1.5 m standing, 0.75 m crouched
	var crouch: float = clampf((1.5 - (player.camera.global_position.y - feet)) / 0.75, 0.0, 1.0)

	_update_legs(delta, speed, flat, grounded)
	_update_air(delta, velocity, grounded)
	tree.set("parameters/crouch/blend_amount", crouch)
	tree.set("parameters/land/blend_amount", _land_amount())
	tree.set("parameters/air/blend_amount", _air)
	tree.advance(delta)

	# The suit faces the view and stands on `feet`. Horizontally its eyes stay under the camera
	# (a deep crouch leans the head 0.4 m ahead of the boots); looking down it slides back so the
	# chest doesn't fill the view.
	var down: float = smoothstep(deg_to_rad(-20.0), deg_to_rad(-75.0), _pitch())
	var offset: Vector3 = view * Vector3(0.0, 0.0, LOOK_DOWN_SLIDE * down + _eye_ahead(crouch))
	offset.y = feet - player.global_position.y
	suit.transform = Transform3D(
		Basis(Vector3.UP, _view_yaw() - player.global_basis.get_euler().y + PI).scaled(Vector3.ONE * SUIT_SCALE),
		player.global_basis.inverse() * offset)
	_update_hands(delta)


## How far ahead of the suit's origin its eyes are now: CLIP_EYE blended like the clips
func _eye_ahead(crouch: float) -> float:
	var gait: float = clampf(float(tree.get("parameters/gait/blend_position")) - WALK_SPEED, 0.0, 1.0)
	var move: float = float(tree.get("parameters/move/blend_amount"))
	var back: float = float(tree.get("parameters/back/blend_amount"))
	var forward: float = lerpf(CLIP_EYE["walk"], CLIP_EYE["sprint"], gait)
	var standing: float = lerpf(CLIP_EYE["idle"], lerpf(forward, CLIP_EYE["walk_back"], back), move)
	var crouched: float = lerpf(CLIP_EYE["crouch_idle"], CLIP_EYE["crouch_walk"], move)
	var eye: float = lerpf(lerpf(standing, crouched, crouch), CLIP_EYE["land"], _land_amount())
	var air: float = clampf(float(tree.get("parameters/air_pose/blend_position")), -1.0, 1.0)
	var in_air: float = lerpf(CLIP_EYE["air_apex"], CLIP_EYE["air_rise"] if air > 0.0 else CLIP_EYE["air_fall"], absf(air))
	return lerpf(eye, in_air, _air)


## World height of the ground under the player (NAN if nothing within reach)
func _probe_ground() -> float:
	var from: Vector3 = player.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.2, player.collision_mask & ~GROUND_IGNORE)
	query.exclude = [player.get_rid()]
	if _held:
		query.exclude.append(_held.get_rid())
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if hit else NAN


func _update_legs(delta: float, speed: float, flat: Vector2, on_floor: bool) -> void:
	var view_yaw: float = _view_yaw()
	var moving: bool = speed > 0.3 and on_floor
	var rate: float = 6.0
	if moving:
		# Godot's yaw of the movement (positive left): forward is -Z
		var move_yaw: float = view_yaw + atan2(-flat.x, -flat.y)
		var off: float = wrapf(move_yaw - view_yaw, -PI, PI)
		var limit: float = BACKWARDS_FROM - (deg_to_rad(20.0) if _backwards else 0.0)
		_backwards = absf(off) > limit
		var target: float = move_yaw + (PI if _backwards else 0.0)
		feet_yaw = view_yaw + _approach(wrapf(feet_yaw - view_yaw, -PI, PI), wrapf(target - view_yaw, -PI, PI), rate * delta)
		_turning = false
	else:
		var rel: float = wrapf(feet_yaw - view_yaw, -PI, PI)
		if absf(rel) > TURN_START:
			_turning = true
		if _turning:
			rel = _approach(rel, 0.0, 3.5 * delta)
			if absf(rel) < deg_to_rad(2.0):
				_turning = false
		feet_yaw = view_yaw + rel
	pose_modifier.lower_yaw = wrapf(feet_yaw - view_yaw, -PI, PI)
	_turn_amount = move_toward(_turn_amount, 1.0 if _turning else 0.0, delta / 0.15)

	_move = move_toward(_move, smoothstep(0.15, 0.7, speed) if on_floor else _move, delta / 0.1)
	var stride: float = lerpf(WALK_STRIDE, SPRINT_STRIDE, clampf(speed - WALK_SPEED, 0.0, 1.0))
	var direction: float = -1.0 if _backwards else 1.0
	_back = move_toward(_back, 1.0 if _backwards else 0.0, delta / 0.15)
	tree.set("parameters/gait/blend_position", clampf(speed, WALK_SPEED, SPRINT_SPEED))
	tree.set("parameters/rate/scale", maxf(speed, 0.6) / stride)
	tree.set("parameters/back_rate/scale", maxf(speed, 0.6) / WALK_STRIDE)
	tree.set("parameters/back/blend_amount", _back)
	tree.set("parameters/move/blend_amount", _move)
	tree.set("parameters/turn/blend_amount", _turn_amount * (1.0 - _move))
	tree.set("parameters/crouch_rate/scale", direction * maxf(speed, 0.4) / CROUCH_STRIDE)
	tree.set("parameters/crouch_move/blend_amount", _move)


static func _approach(from: float, to: float, step: float) -> float:
	return move_toward(from, to, maxf(step, absf(to - from) * step))


func _update_air(delta: float, velocity: Vector3, grounded: bool) -> void:
	if grounded:
		if _air_time > 0.2:
			# Landing: harder the faster it came down (4 m/s is an Earth jump)
			_land_strength = clampf(_fall_speed / 4.0, 0.2, 1.0)
			_land_time = 0.0
		_air_time = 0.0
	else:
		_air_time += delta
		_fall_speed = maxf(-velocity.y, 0.0)
	var airborne: bool = _air_time > 0.08
	_air = move_toward(_air, 1.0 if airborne else 0.0, delta / (0.15 if airborne else 0.06))
	var take_off: float = sqrt(2.0 * player.jump_height * maxf(player.gravity, 0.1))
	tree.set("parameters/air_pose/blend_position", clampf(velocity.y / take_off, -1.0, 1.0))
	_land_time += delta


func _land_amount() -> float:
	# In fast (0.07 s), out slowly (0.4 s)
	var t: float = _land_time
	var envelope: float = t / 0.07 if t < 0.07 else maxf(0.0, 1.0 - (t - 0.07) / 0.4)
	return _land_strength * smoothstep(0.0, 1.0, envelope)


# --- Hands --------------------------------------------------------------------------------------

func _on_picked_up(object: RigidBody3D) -> void:
	_held = object
	_box_centre = Vector3.ZERO
	_release_time = -1.0
	var box: AABB = _local_aabb(object)
	var size: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if size > CARRY_MAX:
		grip = Grip.OVERSIZE
		player.holder.hold_point = null      # the old floating hold, 2 m out
		return
	player.holder.hold_point = hold_point
	grip = Grip.ONE_HAND if size <= ONE_HAND_MAX else Grip.TWO_HANDS
	# Grip the part's sides: its axis closest to the view's right
	var axes: Basis = object.global_basis.orthonormalized()
	var right: Vector3 = _view_basis().x
	var best: int = 0
	for i in 3:
		if absf(axes[i].dot(right)) > absf(axes[best].dot(right)):
			best = i
	var axis := Vector3.ZERO
	axis[best] = signf(axes[best].dot(right))
	var half: float = box.size[best] / 2.0
	var centre: Vector3 = box.get_center()
	_box_centre = centre
	_grip_local = {"Right": centre + axis * half, "Left": centre - axis * half}
	_normal_local = {"Right": axis, "Left": -axis}
	# Depth of the part towards the camera: keep it off the chest
	var forward: Vector3 = -_view_basis().z
	var depth: float = 0.0
	for i in 3:
		depth += absf(axes[i].dot(forward)) * box.size[i] / 2.0
	# Closer in for two hands, the more the wider the part: gripping its sides, the wrists are
	# further out than its middle and the arms reach less far forward
	if grip == Grip.ONE_HAND:
		_hold_offset = Vector3(0.21 - half, 0.0, maxf(0.0, depth - 0.12) - 0.05)
		_closed_curl = deg_to_rad(70.0)
	else:
		_hold_offset = Vector3(0.0, 0.0, maxf(0.0, depth - 0.16) - 0.06 - clampf((half - 0.08) * 1.2, 0.0, 0.10))
		_closed_curl = deg_to_rad(35.0)


func _on_released(_object: RigidBody3D, thrown: bool) -> void:
	_held = null
	_box_centre = Vector3.ZERO
	_thrown = thrown
	_release_time = 0.0
	_hold_offset = Vector3.ZERO
	player.holder.hold_point = hold_point
	var view := Transform3D(_view_basis(), player.camera.global_position)
	for side in ["Left", "Right"]:
		_release_wrist[side] = view.affine_inverse() * (_ik_target[side] as Marker3D).global_position
		_release_basis[side] = view.basis.inverse() * (hands_modifier.hand_basis[side] as Basis)
	grip = Grip.NONE


func _on_skeleton_updated() -> void:
	for side in ["Left", "Right"]:
		_drawn_wrist[side] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(side + "Hand")).origin


static func _local_aabb(object: RigidBody3D) -> AABB:
	var box := AABB()
	var first: bool = true
	var inverse: Transform3D = object.global_transform.affine_inverse()
	for node in object.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node.disabled or not shape_node.shape:
			continue
		var part: AABB = (inverse * shape_node.global_transform) * shape_node.shape.get_debug_mesh().get_aabb()
		box = part if first else box.merge(part)
		first = false
	return AABB(Vector3.ONE * -0.1, Vector3.ONE * 0.2) if first else box


func _shoulder(side: String) -> Vector3:
	var bone: int = skeleton.find_bone(side + "UpperArm")
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


func _update_hands(delta: float) -> void:
	var view := _view_basis()
	var camera: Vector3 = player.camera.global_position
	for side in ["Left", "Right"]:
		var s: float = -1.0 if side == "Left" else 1.0      # the view's right is +X
		var target: Marker3D = _ik_target[side]
		var uses: bool = grip == Grip.TWO_HANDS or grip == Grip.OVERSIZE or (grip == Grip.ONE_HAND and side == "Right")
		var close: float = 0.0
		if _held and uses and grip != Grip.OVERSIZE:
			var xf: Transform3D = _held.global_transform
			var g: Vector3 = xf * (_grip_local[side] as Vector3)
			var n: Vector3 = (xf.basis.orthonormalized() * (_normal_local[side] as Vector3)).normalized()
			var f: Vector3 = -view.z - n * (-view.z).dot(n)
			if f.length() < 0.2:
				f = Vector3.DOWN - n * Vector3.DOWN.dot(n)
			f = f.normalized()
			hands_modifier.hand_basis[side] = Basis(f.cross(n), f, n)
			var wrist: Vector3 = g - f * PALM_ALONG + n * (PALM_BELOW + 0.006)
			target.global_position = wrist
			_arm_goal[side] = 1.0
			# Close the hand once the wrist (as last drawn) is on its place by the part
			close = 1.0 if _arm_weight[side] > 0.95 and _drawn_wrist[side].distance_to(wrist) < 0.03 else 0.0
		elif _held and grip == Grip.OVERSIZE:
			# Reach towards the part's middle, hands open
			var shoulder: Vector3 = _shoulder(side)
			var to: Vector3 = (_held.global_position - shoulder).normalized()
			target.global_position = shoulder + to * 0.6 + view.x * s * 0.08
			hands_modifier.hand_basis[side] = Basis(to.cross(view.x * s), to, view.x * s).orthonormalized()
			_arm_goal[side] = 0.8
		elif _release_time >= 0.0 and _arm_weight[side] > 0.0:
			var frame := Transform3D(view, camera)
			var wrist: Vector3 = _release_wrist[side]
			if _thrown:
				# Follow-through: the arms push out along the view
				var out := Vector3(s * 0.17, -0.22, -0.62)
				wrist = wrist.lerp(out, smoothstep(0.0, 0.15, _release_time))
			target.global_position = frame * wrist
			hands_modifier.hand_basis[side] = view * (_release_basis[side] as Basis)
			_arm_goal[side] = 1.0 if _release_time < (0.2 if _thrown else 0.05) else 0.0
		else:
			_arm_goal[side] = 0.0
		var fade: float = 0.25 if _arm_goal[side] > _arm_weight[side] else (0.3 if _thrown else 0.35)
		_arm_weight[side] = move_toward(_arm_weight[side], _arm_goal[side], delta / fade)
		_closed[side] = move_toward(_closed[side], close, delta / 0.12)
		var w: float = smoothstep(0.0, 1.0, _arm_weight[side])
		(arm_ik[side] as TwoBoneIK3D).influence = w
		hands_modifier.weight[side] = w
		hands_modifier.curl[side] = lerpf(deg_to_rad(6.0), _closed_curl, _closed[side])
		# Elbows point down and out, a little back
		(_ik_pole[side] as Marker3D).global_position = _shoulder(side) + view * Vector3(s * 0.45, -0.6, 0.25)
	if _release_time >= 0.0:
		_release_time += delta
