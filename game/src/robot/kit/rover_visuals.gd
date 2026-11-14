class_name RoverVisuals

extends Node3D

## Visual-only rocker-bogie linkage of the rover (tools/blender/ROVER_KIT.md 5).
##
## Builds each side's rocker, bogie and two steer brackets from the rover kit models, chained
## through their socket empties from the chassis's socket_rocker_<side> anchor. Every physics
## frame (after the Robot) it poses them from the six physics wheel centres:
## - the bogie angle from the middle and rear wheel heights,
## - the rocker angle as the best fit for the front wheel and the bogie pivot,
## - both clamped to the clearance-checked range (rocker +-10, bogie +-15 degrees),
## - the steer brackets turned by each wheel's steering angle.
## Mounted wheel parts are moved onto their hub sockets on the linkage, and their models spin
## with the wheel speed. It also builds the fixed mast base and arm segments on their chassis
## sockets and drives the arm (stowed by default; R deploys / stows it, 1-5 pick a joint and
## Z / X turn it, never into the ground), and pans / tilts the mast head from the mouse
## look with the rover camera riding on its pivot_camera. Nothing here affects the physics.

# ROVER_KIT.md 5: the pose range the kit was clearance-checked for. Widen only after
# re-running tools/blender/scripts/make_rocker_bogie.py with the new range.
const ROCKER_LIMIT: float = deg_to_rad(10.0)
const BOGIE_LIMIT: float = deg_to_rad(15.0)

const MODELS: Dictionary = {
	"rocker_L": preload("res://res/models/rover_kit/rocker_L.glb"),
	"rocker_R": preload("res://res/models/rover_kit/rocker_R.glb"),
	"bogie_L": preload("res://res/models/rover_kit/bogie_L.glb"),
	"bogie_R": preload("res://res/models/rover_kit/bogie_R.glb"),
	"steer_bracket_L": preload("res://res/models/rover_kit/steer_bracket_L.glb"),
	"steer_bracket_R": preload("res://res/models/rover_kit/steer_bracket_R.glb"),
	"mast_base": preload("res://res/models/rover_kit/mast_base.glb"),
	"arm_shoulder": preload("res://res/models/rover_kit/arm_shoulder.glb"),
	"arm_upper": preload("res://res/models/rover_kit/arm_upper.glb"),
	"arm_forearm": preload("res://res/models/rover_kit/arm_forearm.glb"),
	"arm_wrist": preload("res://res/models/rover_kit/arm_wrist.glb"),
}

# ROVER_KIT.md 5: arm joint ranges (degrees) and the stowed pose
const ARM_RANGES: Dictionary = {"J1": Vector2(-20.0, 15.0), "J2": Vector2(-30.0, 90.0),
	"J3": Vector2(-90.0, 90.0), "J4": Vector2(-110.0, 110.0)}
# ROVER_KIT.md 3.3 / 5: mast head tilt range, and its rig when no head is mounted (the
# camera falls back to where the head's pivot_camera would be)
const MAST_TILT_LIMIT: float = deg_to_rad(30.0)
const MAST_TILT_AXIS_HEIGHT: float = 0.10
const PIVOT_CAMERA_FORWARD: float = 0.07

const ARM_STOWED: Dictionary = {"J1": 0.0, "J2": 90.0, "J3": 90.0, "J4": 90.0, "J5": 0.0}
# Deployed: upper arm forward, forearm angled down, turret level with the drill down
const ARM_DEPLOYED: Dictionary = {"J1": 0.0, "J2": 0.0, "J3": -45.0, "J4": 45.0, "J5": 0.0}
const ARM_JOINT_NAMES: Array[String] = ["J1", "J2", "J3", "J4", "J5"]
const ARM_JOINT_LABELS: Array[String] = ["yaw", "shoulder", "elbow", "wrist", "turret"]
# Degrees per second: all joints while deploying / stowing, the selected joint by hand
const ARM_DEPLOY_SPEED: float = 60.0
const ARM_JOINT_SPEED: float = 30.0
# The arm stops before any part of it gets this close (m) to the terrain below it. While the
# rover moves, the arm lifts itself if it would be that close ARM_LIFT_LOOKAHEAD seconds from
# now (the arm points moved by the rover's linear and angular velocity).
const ARM_GROUND_MARGIN: float = 0.02
const ARM_LIFT_LOOKAHEAD: float = 0.25
const ARM_LIFT_SPEED: float = 120.0
# Lowest vertices per arm mesh that are checked against the terrain
const ARM_GROUND_SAMPLES: int = 16
const GROUND_MASK: int = 1

const SIDE_WHEELS: Dictionary = {
	"L": [RunningGear.Wheel.FRONT_LEFT, RunningGear.Wheel.MIDDLE_LEFT, RunningGear.Wheel.REAR_LEFT],
	"R": [RunningGear.Wheel.FRONT_RIGHT, RunningGear.Wheel.MIDDLE_RIGHT, RunningGear.Wheel.REAR_RIGHT],
}

@onready var robot: Robot = get_parent() as Robot

# side -> {"rocker", "bogie", "front_bracket", "rear_bracket": Node3D, "hubs": [front, middle,
# rear] hub sockets, "rest": rest positions (robot space) of the bogie pivot and the hubs}
var sides: Dictionary = {}
# Current (clamped) rocker / bogie angles per side, radians. Read by tests and the debug HUD.
var rocker_angles: Dictionary = {"L": 0.0, "R": 0.0}
var bogie_angles: Dictionary = {"L": 0.0, "R": 0.0}

## Arm joint angles in degrees (J1 yaw, J2 shoulder, J3 elbow, J4 wrist, J5 tool turret),
## clamped to ARM_RANGES when applied. Stowed by default.
var arm_joints: Dictionary = ARM_STOWED.duplicate()
## True once R has asked for the deployed pose (also while still moving there)
var arm_deployed: bool = false
## Pose the arm is moving to (deploy / stow), empty when it's at rest or under manual control
var arm_target: Dictionary = {}
## True while the last attempted step was refused because it would touch the ground
var arm_blocked: bool = false
var _posed_tool: HotswapPart = null
# MeshInstance3D -> its mesh's vertex positions (local)
var _mesh_vertices: Dictionary = {}
# Joint name -> the arm model node it turns
var _arm_nodes: Dictionary = {}

## Current mast head pan / tilt (radians), from the mouse look
var mast_pan: float = 0.0
var mast_tilt: float = 0.0
var _mast_top: Node3D = null
var _posed_head: HotswapPart = null

var _spin: Dictionary = {}           # Wheel -> spin angle (rad)
var _spun_parts: Dictionary = {}     # Wheel -> WheelPart whose model is spun
var _model_rest: Dictionary = {}     # WheelPart -> its model's unspun rotation


func _ready() -> void:
	# Run after the Robot, which places the wheel parts at their physics positions first
	process_physics_priority = 10
	for side in SIDE_WHEELS:
		_build_side(side)
	_build_mast_and_arm()
	apply_arm_pose()
	robot.controller.arm_toggle.connect(_on_arm_toggle)
	_mast_top = find_child("socket_mast_head", true, false) as Node3D


func _build_side(side: String) -> void:
	var anchor := robot.body_model.find_child("socket_rocker_" + side, true, false) as Node3D
	var rocker: Node3D = _attach("rocker_" + side, self, robot.to_local(anchor.global_position))
	var bogie: Node3D = _attach("bogie_" + side, rocker, _socket_local(rocker, "socket_bogie"))
	var front: Node3D = _attach("steer_bracket_" + side, rocker, _socket_local(rocker, "socket_steer_front"))
	var rear: Node3D = _attach("steer_bracket_" + side, bogie, _socket_local(bogie, "socket_steer_rear"))
	var hubs: Array = [_socket(front, "socket_wheel_hub"), _socket(bogie, "socket_wheel_mid"), _socket(rear, "socket_wheel_hub")]
	sides[side] = {
		"rocker": rocker, "bogie": bogie, "front_bracket": front, "rear_bracket": rear, "hubs": hubs,
		"rest_bogie_pivot": robot.to_local(bogie.global_position),
		"rest_hubs": hubs.map(func(hub: Node3D) -> Vector3: return robot.to_local(hub.global_position)),
	}


# The fixed mast base on socket_mast, and the arm: the shoulder mount on socket_arm and each
# segment on the previous one's socket. A segment's model node has its origin on its joint.
func _build_mast_and_arm() -> void:
	var body: Node3D = robot.body_model
	_attach("mast_base", self, robot.to_local((body.find_child("socket_mast", true, false) as Node3D).global_position))
	var shoulder: Node3D = _attach("arm_shoulder", self, robot.to_local((body.find_child("socket_arm", true, false) as Node3D).global_position))
	var yaw := shoulder.find_child("arm_shoulder_yaw", true, false) as Node3D
	var upper := _model(_attach("arm_upper", yaw, _socket_local(yaw, "socket_arm_upper")), "arm_upper")
	var forearm := _model(_attach("arm_forearm", upper, _socket_local(upper, "socket_arm_forearm")), "arm_forearm")
	var wrist := _model(_attach("arm_wrist", forearm, _socket_local(forearm, "socket_arm_wrist")), "arm_wrist")
	_arm_nodes = {"J1": yaw, "J2": upper, "J3": forearm, "J4": wrist}


func _model(instance: Node3D, model_name: String) -> Node3D:
	return instance.find_child(model_name, true, false) as Node3D


func _on_arm_toggle() -> void:
	arm_deployed = not arm_deployed
	arm_target = (ARM_DEPLOYED if arm_deployed else ARM_STOWED).duplicate()


# Moves the arm one physics step: towards arm_target while deploying / stowing, else the
# selected joint by hand (deployed only). A step that would bring the arm or tool within
# ARM_GROUND_MARGIN of the terrain, and closer than it already is, is not taken.
func _update_arm(delta: float) -> void:
	var tool := _arm_tool()
	if tool != _posed_tool:
		if is_instance_valid(_posed_tool):
			(_posed_tool.get_node("Model") as Node3D).rotation = Vector3.ZERO
		_posed_tool = tool

	var next: Dictionary = arm_joints.duplicate()
	var active: bool = arm_deployed or not arm_target.is_empty()
	var clearance_now: float = arm_ground_clearance() if active else INF
	var clearance_ahead: float = arm_ground_clearance(ARM_LIFT_LOOKAHEAD) if active else INF
	if clearance_ahead < ARM_GROUND_MARGIN:
		# Terrain is coming up under the arm (the rover is driving onto something or pitching
		# down), also mid-deploy / stow: lift the shoulder, then the elbow once the shoulder is
		# at its limit; the deploy / stow carries on once it is clear
		var lift: float = ARM_LIFT_SPEED * delta
		if arm_joints["J2"] < ARM_RANGES["J2"].y:
			next["J2"] = minf(arm_joints["J2"] + lift, ARM_RANGES["J2"].y)
		else:
			next["J3"] = minf(arm_joints["J3"] + lift, ARM_RANGES["J3"].y)
	elif not arm_target.is_empty():
		for joint in ARM_JOINT_NAMES:
			next[joint] = move_toward(arm_joints[joint], arm_target[joint], ARM_DEPLOY_SPEED * delta)
	elif arm_deployed and robot.controller.arm_rotate != 0.0:
		var joint: String = ARM_JOINT_NAMES[robot.controller.arm_joint - 1]
		var angle: float = arm_joints[joint] + robot.controller.arm_rotate * ARM_JOINT_SPEED * delta
		next[joint] = wrapf(angle, -180.0, 180.0) if joint == "J5" else clampf(angle, ARM_RANGES[joint].x, ARM_RANGES[joint].y)
	if next == arm_joints:
		arm_blocked = false
		return

	var previous: Dictionary = arm_joints
	arm_joints = next
	apply_arm_pose()
	var clearance_next: float = arm_ground_clearance()
	if clearance_next < ARM_GROUND_MARGIN and clearance_next < clearance_now:
		arm_joints = previous
		apply_arm_pose()
		arm_blocked = true
		return
	arm_blocked = false
	if not arm_target.is_empty() and arm_joints == arm_target:
		arm_target = {}


func _arm_tool() -> HotswapPart:
	var socket := robot.find_child("ArmToolSocket", true, false) as HotswapSocket
	return socket.part if socket else null


## Smallest height (m) of the arm's forearm, wrist and mounted tool above the terrain under
## them: rays down from each mesh's ARM_GROUND_SAMPLES lowest vertices. Negative = inside the
## terrain; INF with no terrain within 2 m below. With `lookahead` (s) each point is also
## checked where the rover's motion will carry it by then.
func arm_ground_clearance(lookahead: float = 0.0) -> float:
	var meshes: Array = []
	for joint in ["J3", "J4"]:
		meshes += (_arm_nodes[joint] as Node).find_children("*", "MeshInstance3D", true, false)
		if _arm_nodes[joint] is MeshInstance3D:
			meshes.append(_arm_nodes[joint])
	var tool := _arm_tool()
	if tool:
		meshes += tool.get_node("Model").find_children("*", "MeshInstance3D", true, false)
	var space := get_world_3d().direct_space_state
	var lowest: float = INF
	var centre: Vector3 = robot.global_transform * robot.center_of_mass
	for mesh in meshes:
		var to_world: Transform3D = (mesh as MeshInstance3D).global_transform
		var points: Array = _vertices(mesh).map(func(v: Vector3) -> Vector3: return to_world * v)
		points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
		for point in points.slice(0, ARM_GROUND_SAMPLES):
			var checks: Array = [point]
			if lookahead > 0.0:
				var velocity: Vector3 = robot.linear_velocity + robot.angular_velocity.cross(point - centre)
				checks.append(point + velocity * lookahead)
			for p in checks:
				var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 2.0, GROUND_MASK)
				var hit: Dictionary = space.intersect_ray(query)
				if hit:
					lowest = minf(lowest, p.y - (hit["position"] as Vector3).y)
	return lowest


func _vertices(mesh: MeshInstance3D) -> Array:
	if not _mesh_vertices.has(mesh):
		var unique: Dictionary = {}
		var surfaces: int = mesh.mesh.get_surface_count() if mesh.mesh else 0
		for i in surfaces:
			for v in mesh.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				unique[v] = true
		_mesh_vertices[mesh] = unique.keys()
	return _mesh_vertices[mesh]


## Applies `arm_joints` (clamped to the checked ranges). Blender's X rotations map to Godot's
## X, the yaw (Blender Z) to Godot Y. J5 turns the tool turret, mounted in the arm tool socket.
func apply_arm_pose() -> void:
	for joint in _arm_nodes:
		var angle: float = clampf(arm_joints[joint], ARM_RANGES[joint].x, ARM_RANGES[joint].y)
		var node: Node3D = _arm_nodes[joint]
		if joint == "J1":
			node.rotation = Vector3(0.0, deg_to_rad(angle), 0.0)
		else:
			node.rotation = Vector3(deg_to_rad(angle), 0.0, 0.0)
	# J5 turns the mounted tool turret about its axis (Blender +Y = Godot -Z)
	var tool := _arm_tool()
	if tool:
		(tool.get_node("Model") as Node3D).rotation = Vector3(0.0, 0.0, -deg_to_rad(arm_joints["J5"]))


func _attach(model: String, parent: Node3D, position_in_parent: Vector3) -> Node3D:
	var node: Node3D = MODELS[model].instantiate()
	parent.add_child(node)
	node.position = position_in_parent
	return node


func _socket(part: Node3D, socket_name: String) -> Node3D:
	return part.find_child(socket_name, true, false) as Node3D


func _socket_local(part: Node3D, socket_name: String) -> Vector3:
	return part.to_local(_socket(part, socket_name).global_position)


func _physics_process(delta: float) -> void:
	if robot.wheel_centers.size() < RunningGear.Wheel.size():
		return
	for side in sides:
		_pose_side(side)
	_place_and_spin_wheels(delta)
	_update_mast_head()
	_update_arm(delta)


# Angle of the vector a -> b in the robot's side (z, y) plane. Rotating about +X by t changes
# it by -t, so a rotation that turns direction `from` into `to` is from - to.
static func _side_angle(a: Vector2, b: Vector2) -> float:
	return atan2(b.y - a.y, b.x - a.x)


static func _rotate_side(v: Vector2, angle_about_x: float) -> Vector2:
	return v.rotated(-angle_about_x)


func _pose_side(side: String) -> void:
	var data: Dictionary = sides[side]
	var wheels: Array = SIDE_WHEELS[side]
	# (z, y) of the rest hubs and of the physics wheel centres (same z, physics height)
	var rest: Array = data["rest_hubs"].map(func(p: Vector3) -> Vector2: return Vector2(p.z, p.y))
	var now: Array = []
	for i in 3:
		now.append(Vector2(rest[i].x, robot.wheel_centers[wheels[i]].y))
	var rest_pivot := Vector2(data["rest_bogie_pivot"].z, data["rest_bogie_pivot"].y)

	# Bogie: its world angle lines the middle and rear hubs up with their wheels; its pivot
	# then sits at the same offset from the middle of the two hubs as at rest
	var bogie_world: float = _side_angle(rest[1], rest[2]) - _side_angle(now[1], now[2])
	var rest_mid: Vector2 = (rest[1] + rest[2]) / 2.0
	var pivot_target: Vector2 = (now[1] + now[2]) / 2.0 + _rotate_side(rest_pivot - rest_mid, bogie_world)

	# Rocker: turns the front hub -> bogie pivot line onto the front wheel -> pivot target
	var rocker: float = _side_angle(rest[0], rest_pivot) - _side_angle(now[0], pivot_target)
	rocker = clampf(rocker, -ROCKER_LIMIT, ROCKER_LIMIT)
	var bogie: float = clampf(bogie_world - rocker, -BOGIE_LIMIT, BOGIE_LIMIT)
	rocker_angles[side] = rocker
	bogie_angles[side] = bogie

	(data["rocker"] as Node3D).rotation = Vector3(rocker, 0.0, 0.0)
	(data["bogie"] as Node3D).rotation = Vector3(bogie, 0.0, 0.0)
	var steer: float = robot.controller.steer
	(data["front_bracket"] as Node3D).rotation = Vector3(0.0, robot.running_gear.get_steer_angle(wheels[0], steer), 0.0)
	(data["rear_bracket"] as Node3D).rotation = Vector3(0.0, robot.running_gear.get_steer_angle(wheels[2], steer), 0.0)


# Pans (yoke about Y) and tilts (camera box about X) the mounted mast head from the mouse
# look, then puts the rover camera's pivot on its pivot_camera. Without a head the pivot
# goes where pivot_camera would be on the mast top.
func _update_mast_head() -> void:
	mast_pan = robot.controller.camera_azimuth
	mast_tilt = clampf(robot.controller.camera_altitude, -MAST_TILT_LIMIT, MAST_TILT_LIMIT)
	var socket := robot.get_node_or_null("MastHeadSocket") as HotswapSocket
	var head: HotswapPart = socket.part if socket else null
	if head != _posed_head:
		# A head that left the socket goes back to its unpanned pose
		if is_instance_valid(_posed_head):
			_pose_head(_posed_head, 0.0, 0.0)
		_posed_head = head
	if head:
		_pose_head(head, mast_pan, mast_tilt)
		robot.pivot.global_transform = (head.find_child("pivot_camera", true, false) as Node3D).global_transform
	elif _mast_top:
		robot.pivot.global_transform = _mast_top.global_transform * Transform3D(
			Basis(Vector3.UP, mast_pan) * Basis(Vector3.RIGHT, mast_tilt),
			Vector3(0.0, MAST_TILT_AXIS_HEIGHT, 0.0)) * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -PIVOT_CAMERA_FORWARD))


func _pose_head(head: HotswapPart, pan: float, tilt: float) -> void:
	var yoke := head.find_child("mast_head", true, false) as Node3D
	var camera_box := head.find_child("mast_head_camera", true, false) as Node3D
	if yoke and camera_box:
		yoke.rotation = Vector3(0.0, pan, 0.0)
		camera_box.rotation = Vector3(tilt, 0.0, 0.0)


# Moves each mounted wheel part onto its hub socket on the linkage (the bracket or bogie
# carries the steering and tilt) and spins its model with the wheel speed.
func _place_and_spin_wheels(delta: float) -> void:
	for side in sides:
		var wheels: Array = SIDE_WHEELS[side]
		for i in 3:
			var wheel: int = wheels[i]
			var socket: HotswapSocket = robot.wheel_sockets.get(wheel)
			var part := socket.part as WheelPart if socket else null
			_track_spun_part(wheel, part)
			if part == null:
				continue
			part.global_transform = (sides[side]["hubs"][i] as Node3D).global_transform
			# Positive wheel speed rolls forward (-Z), which is a negative turn about +X
			var speed: float = robot.running_gear.wheel_states[wheel][RunningGear.WheelState.ANGULAR_VELOCITY]
			_spin[wheel] = wrapf(_spin.get(wheel, 0.0) - speed * delta, -PI, PI)
			var model := part.get_node_or_null("Model") as Node3D
			if model:
				var rest_rotation: Vector3 = _model_rest[part]
				model.rotation = Vector3(rest_rotation.x + _spin[wheel], rest_rotation.y, rest_rotation.z)


# Remembers the unspun rotation of a newly mounted part's model, and gives it back to a part
# that left the socket.
func _track_spun_part(wheel: int, part: WheelPart) -> void:
	var previous: WheelPart = _spun_parts.get(wheel)
	if previous == part:
		return
	if is_instance_valid(previous) and _model_rest.has(previous):
		var old_model := previous.get_node_or_null("Model") as Node3D
		if old_model:
			old_model.rotation = _model_rest[previous]
		_model_rest.erase(previous)
	_spun_parts[wheel] = part
	_spin[wheel] = 0.0
	if part:
		var model := part.get_node_or_null("Model") as Node3D
		_model_rest[part] = model.rotation if model else Vector3.ZERO
