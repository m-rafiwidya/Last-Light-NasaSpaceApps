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
## with the wheel speed. Nothing here affects the physics.

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
}

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

var _spin: Dictionary = {}           # Wheel -> spin angle (rad)
var _spun_parts: Dictionary = {}     # Wheel -> WheelPart whose model is spun
var _model_rest: Dictionary = {}     # WheelPart -> its model's unspun rotation


func _ready() -> void:
	# Run after the Robot, which places the wheel parts at their physics positions first
	process_physics_priority = 10
	for side in SIDE_WHEELS:
		_build_side(side)


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
