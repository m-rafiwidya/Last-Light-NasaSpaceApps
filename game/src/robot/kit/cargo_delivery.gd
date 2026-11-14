class_name CargoDelivery

extends Node

## The rover's automatic cargo delivery (tools/blender/IRIS_KIT.md 8): with cargo on the cargo
## mount, parked in a CargoPort's window, E has the arm latch the cargo, carry it over, lower it
## straight down into the port and stow again. Visual only: the arm has no collision, the cargo
## rides it frozen and the port takes it by script.
##
## Parking window (from the arm's yaw axis to the port's top centre): 0.45-0.57 m, the port -18
## to +13 degrees off straight ahead (positive = left), stopped, and both the approach and the
## seated pose within the arm's joint ranges (the port's height). get_hint() says how to get
## there; the robot HUD shows it (CargoHint).
##
## The rover moving (0.03 m or 2 degrees from where it started), driving input, or the arm
## getting within 20 mm of the terrain aborts the delivery before the release: the arm carries
## the cargo back onto the mount and stows. Leaving the rover doesn't stop it.

signal delivery_started(port: CargoPort)
signal delivery_aborted(port: CargoPort, reason: String)
signal delivery_finished(port: CargoPort)

enum Phase { IDLE, LATCH, LIFT, TRANSIT, TURN, STROKE, RETRACT, RETURN, ABORT_UP, ABORT_RETURN }

# The arm's geometry (ROVER_KIT.md 3.3), in the kit frame (x right, y forward, z up, rover origin)
const YAW_AXIS: Vector2 = Vector2(-0.12, 0.53)
const TOOL_OFFSET_X: float = -0.005          # the turret's line beside the yaw axis
const SHOULDER: Vector2 = Vector2(0.53, 0.345) # (forward, up)
const UPPER: float = 0.36
const FOREARM: float = 0.33
const WRIST_TO_LATCH: float = 0.12            # wrist joint to the hub's end (wrist 0.07 + hub 0.05)
const RANGES: Dictionary = {"J1": Vector2(-20.0, 15.0), "J2": Vector2(-30.0, 90.0), "J3": Vector2(-90.0, 90.0),
	"J4": Vector2(-110.0, 110.0)}
const LIFT_POSE: Dictionary = {"J1": 0.0, "J2": 90.0, "J3": 70.0, "J4": 110.0, "J5": 0.0}

const WINDOW_D: Vector2 = Vector2(0.45, 0.57)
const WINDOW_BEARING: Vector2 = Vector2(-18.0, 13.0)
const STOPPED_SPEED: float = 0.05
const HINT_RANGE: float = 4.0
const STROKE: float = 0.10
const SEAT_GAP: float = 0.006                 # released this far above the port's floor
const JOINT_SPEED: float = 45.0               # degrees / s
const STROKE_SPEED: float = 0.07              # m / s
const DRIFT_LIMIT: float = 0.03
const TURN_LIMIT: float = 2.0                 # degrees
const GROUND_MARGIN: float = 0.02
const MESSAGE_TIME: float = 4.0

@onready var robot: Robot = get_parent() as Robot
@onready var visuals: RoverVisuals = robot.get_node("Visuals")
@onready var cargo_socket: HotswapSocket = robot.get_node("CargoSocket")

var phase: Phase = Phase.IDLE
## The port being delivered to (or the nearest one in range while idle)
var port: CargoPort = null
var cargo: HotswapPart = null
var _targets: Array = []                     # joint poses still to reach in this phase
var _approach: Dictionary = {}
var _stroke_s: float = 0.0
var _rel: Transform3D = Transform3D.IDENTITY # the cargo on the latch
var _free_layers: Vector2i = Vector2i.ZERO
var _start: Transform3D = Transform3D.IDENTITY
var _message: String = ""
var _message_time: float = 0.0


func is_busy() -> bool:
	return phase != Phase.IDLE


func _latch() -> Node3D:
	var socket := robot.find_child("ArmToolSocket", true, false) as HotswapSocket
	if socket == null or socket.part == null:
		return null
	return socket.part.find_child("pivot_latch", true, false) as Node3D


## The kit frame (x right, y forward, z up) position of a world point
func _kit(global_point: Vector3) -> Vector3:
	var p: Vector3 = robot.to_local(global_point)
	return Vector3(p.x, -p.z, p.y)


## Joints that put the turret hub's end on `p` (kit frame), pointing straight down; {} if out of reach
static func ik_down(p: Vector3) -> Dictionary:
	var rel := Vector2(p.x - YAW_AXIS.x, p.y - YAW_AXIS.y)
	var dist: float = rel.length()
	var r: float = sqrt(maxf(dist * dist - TOOL_OFFSET_X * TOOL_OFFSET_X, 0.0))
	var j1: float = rad_to_deg(atan2(-rel.x, rel.y) - atan2(-TOOL_OFFSET_X, r))
	var w := Vector2(SHOULDER.x + r, p.z + WRIST_TO_LATCH)
	var v: Vector2 = w - SHOULDER
	var d: float = v.length()
	var c3: float = (d * d - UPPER * UPPER - FOREARM * FOREARM) / (2.0 * UPPER * FOREARM)
	if absf(c3) > 1.0:
		return {}
	for sgn in [1.0, -1.0]:
		var t3: float = sgn * acos(c3)
		var t2: float = atan2(v.y, v.x) - atan2(FOREARM * sin(t3), UPPER + FOREARM * cos(t3))
		var j2: float = rad_to_deg(t2)
		var j3: float = rad_to_deg(t3)
		var j4: float = wrapf(-90.0 - (j2 + j3), -180.0, 180.0)
		var joints: Dictionary = {"J1": j1, "J2": j2, "J3": j3, "J4": j4, "J5": 0.0}
		var inside := true
		for j in RANGES:
			if joints[j] < RANGES[j].x or joints[j] > RANGES[j].y:
				inside = false
		if inside:
			return joints
	return {}


## Where `port` is from the arm: {d, bearing (degrees, + = left), approach, seated (joints, {} out of reach)}
func measure(target: CargoPort) -> Dictionary:
	var top: Vector3 = _kit(target.global_position)
	var rel := Vector2(top.x - YAW_AXIS.x, top.y - YAW_AXIS.y)
	var up: Vector3 = Vector3(0.0, 0.0, 1.0)
	return {
		"d": rel.length(), "bearing": rad_to_deg(atan2(-rel.x, rel.y)),
		"approach": ik_down(top + up * (SEAT_GAP + STROKE)), "seated": ik_down(top + up * SEAT_GAP),
	}


func _nearest_port() -> CargoPort:
	var best: CargoPort = null
	var best_d: float = HINT_RANGE
	var yaw_world: Vector3 = robot.to_global(Vector3(YAW_AXIS.x, 0.0, -YAW_AXIS.y))
	for node in get_tree().get_nodes_in_group(&"cargo_port"):
		var p := node as CargoPort
		var d: float = Vector2(p.global_position.x - yaw_world.x, p.global_position.z - yaw_world.z).length()
		if d < best_d:
			best = p
			best_d = d
	return best


## True when E would start a delivery to `target` now
func ready_for(target: CargoPort) -> bool:
	if target == null or cargo_socket.part == null or not target.fits(cargo_socket.part) or target.needs_scan():
		return false
	if _latch() == null or robot.linear_velocity.length() > STOPPED_SPEED:
		return false
	var m: Dictionary = measure(target)
	return m["d"] >= WINDOW_D.x and m["d"] <= WINDOW_D.y and m["bearing"] >= WINDOW_BEARING.x \
		and m["bearing"] <= WINDOW_BEARING.y and not m["approach"].is_empty() and not m["seated"].is_empty()


## What the robot HUD should say ("" for nothing): within HINT_RANGE of a port that fits the cargo
func get_hint() -> String:
	if _message_time > 0.0:
		return _message
	match phase:
		Phase.LATCH, Phase.LIFT, Phase.TRANSIT, Phase.TURN, Phase.STROKE:
			return "Inserting the cartridge"
		Phase.RETRACT, Phase.RETURN:
			return "Cartridge inserted"
		Phase.ABORT_UP, Phase.ABORT_RETURN:
			return "Insert interrupted: the rover moved. Park again and press E."
	var target: CargoPort = _nearest_port()
	var part: HotswapPart = cargo_socket.part
	if target == null or part == null or not target.fits(part):
		return ""
	if target.needs_scan():
		return "Scan IRIS first (mast camera)"
	if _latch() == null:
		return "Mount the arm tool turret"
	var m: Dictionary = measure(target)
	var middle: float = (WINDOW_D.x + WINDOW_D.y) / 2.0
	if m["bearing"] > WINDOW_BEARING.y:
		return "IRIS's port: turn %d degrees left" % ceili(m["bearing"] - WINDOW_BEARING.y)
	if m["bearing"] < WINDOW_BEARING.x:
		return "IRIS's port: turn %d degrees right" % ceili(WINDOW_BEARING.x - m["bearing"])
	if m["d"] > WINDOW_D.y:
		return "IRIS's port: %.2f m closer" % (m["d"] - middle)
	if m["d"] < WINDOW_D.x:
		return "IRIS's port: back up %.2f m" % (middle - m["d"])
	if m["approach"].is_empty() or m["seated"].is_empty():
		return "IRIS's port is out of the arm's reach from here"
	if robot.linear_velocity.length() > STOPPED_SPEED:
		return "Stop here"
	return "In position: press E to insert the cartridge"


## Robot hook (E): starts a delivery when in a port's window. True when E was used here (also while
## a delivery runs, so nothing else picks it up)
func handle_interact() -> bool:
	if phase != Phase.IDLE:
		return true
	var target: CargoPort = _nearest_port()
	if target == null or cargo_socket.part == null or not target.fits(cargo_socket.part):
		return false
	if not ready_for(target):
		return target.needs_scan() or _latch() == null
	port = target
	cargo = cargo_socket.part
	var m: Dictionary = measure(port)
	_approach = m["approach"]
	_start = robot.global_transform
	visuals.arm_scripted = true
	visuals.arm_deployed = false
	visuals.arm_target = {}
	_set_phase(Phase.LATCH, [RoverVisuals.ARM_LATCH])
	delivery_started.emit(port)
	return true


func _set_phase(next: Phase, targets: Array = []) -> void:
	phase = next
	_targets = targets.duplicate()


# Moves the arm towards the first target; true when all targets are reached
func _move(delta: float) -> bool:
	if _targets.is_empty():
		return true
	var target: Dictionary = _targets[0]
	var reached := true
	for j in RoverVisuals.ARM_JOINT_NAMES:
		var to: float = target[j]
		var now: float = visuals.arm_joints[j]
		if j == "J5":
			to = now + wrapf(to - now, -180.0, 180.0)
		var next: float = move_toward(now, to, JOINT_SPEED * delta)
		visuals.arm_joints[j] = next
		if absf(next - to) > 0.01:
			reached = false
	visuals.apply_arm_pose()
	if reached:
		_targets.pop_front()
	return _targets.is_empty()


func _moved() -> String:
	var drift: float = (robot.global_position - _start.origin).length()
	var turn: float = rad_to_deg(robot.global_basis.z.angle_to(_start.basis.z))
	if drift > DRIFT_LIMIT or turn > TURN_LIMIT:
		return "the rover moved"
	if robot.controller and (absf(robot.controller.desired_speed) > 0.05 or absf(robot.controller.steer) > 0.05):
		return "the rover moved"
	if visuals.arm_ground_clearance() < GROUND_MARGIN:
		return "the arm came too close to the ground"
	return ""


func _physics_process(delta: float) -> void:
	_message_time = maxf(_message_time - delta, 0.0)
	if phase == Phase.IDLE:
		return
	var carrying: bool = phase in [Phase.LIFT, Phase.TRANSIT, Phase.TURN, Phase.STROKE]
	if phase in [Phase.LATCH, Phase.LIFT, Phase.TRANSIT, Phase.TURN, Phase.STROKE]:
		var reason: String = _moved()
		if not reason.is_empty():
			_abort(reason, carrying)
			return
	match phase:
		Phase.LATCH:
			if _move(delta):
				_take_cargo()
				_set_phase(Phase.LIFT, [LIFT_POSE])
		Phase.LIFT:
			if _move(delta):
				var approach: Dictionary = _approach.duplicate()
				approach["J5"] = 0.0
				_set_phase(Phase.TRANSIT, [approach])
		Phase.TRANSIT:
			if _move(delta):
				var approach: Dictionary = _approach.duplicate()
				approach["J5"] = _turn_to_port()
				_approach = approach
				_set_phase(Phase.TURN, [approach])
		Phase.TURN:
			if _move(delta):
				_stroke_s = 0.0
				_set_phase(Phase.STROKE)
		Phase.STROKE:
			_stroke_s = minf(_stroke_s + STROKE_SPEED * delta / STROKE, 1.0)
			_pose_stroke(_stroke_s)
			if _stroke_s >= 1.0:
				port.accept(cargo, robot)
				cargo = null
				_set_phase(Phase.RETRACT)
		Phase.RETRACT:
			_stroke_s = maxf(_stroke_s - STROKE_SPEED * delta / STROKE, 0.0)
			_pose_stroke(_stroke_s)
			if _stroke_s <= 0.0:
				var approach: Dictionary = _approach.duplicate()
				approach["J5"] = 0.0
				_set_phase(Phase.RETURN, [approach, LIFT_POSE, RoverVisuals.ARM_STOWED])
		Phase.RETURN:
			if _move(delta):
				_finish()
				delivery_finished.emit(port)
		Phase.ABORT_UP:
			_stroke_s = maxf(_stroke_s - STROKE_SPEED * delta / STROKE, 0.0)
			_pose_stroke(_stroke_s)
			if _stroke_s <= 0.0:
				var approach: Dictionary = _approach.duplicate()
				approach["J5"] = 0.0
				_set_phase(Phase.ABORT_RETURN, [approach, LIFT_POSE, RoverVisuals.ARM_LATCH])
		Phase.ABORT_RETURN:
			if _move(delta):
				if cargo:
					# Back at the latch pose over the mount: the cargo goes back on, then stow
					_put_back()
					_targets = [RoverVisuals.ARM_STOWED]
				else:
					_finish()


# Down (s 0 -> 1) or up the stroke, square over the port: IK every frame
func _pose_stroke(s: float) -> void:
	var top: Vector3 = _kit(port.global_position)
	var joints: Dictionary = ik_down(top + Vector3(0.0, 0.0, SEAT_GAP + STROKE * (1.0 - s)))
	if joints.is_empty():
		return
	joints["J5"] = _approach["J5"]
	for j in joints:
		visuals.arm_joints[j] = joints[j]
	visuals.apply_arm_pose()


# The J5 that turns the held cargo's long side (its X) along the port's
func _turn_to_port() -> float:
	var latch: Node3D = _latch()
	var want: Vector3 = port.global_basis.x
	var best := Vector2(1e9, 0.0)
	var saved: float = visuals.arm_joints["J5"]
	for j5 in range(-90, 91):
		visuals.arm_joints["J5"] = float(j5)
		visuals.apply_arm_pose()
		var x: Vector3 = (latch.global_transform * _rel).basis.x
		var err: float = absf(rad_to_deg(Vector2(x.x, x.z).angle_to(Vector2(want.x, want.z))))
		err = minf(err, 180.0 - err)
		if err < best.x:
			best = Vector2(err, float(j5))
	visuals.arm_joints["J5"] = saved
	visuals.apply_arm_pose()
	return best.y


func _take_cargo() -> void:
	var latch: Node3D = _latch()
	_rel = latch.global_transform.affine_inverse() * cargo.global_transform
	cargo_socket.unmount()
	_free_layers = Vector2i(cargo.collision_layer, cargo.collision_mask)
	cargo.collision_layer = 0
	cargo.collision_mask = 0
	cargo.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	cargo.freeze = true
	cargo.reparent(latch, true)
	cargo.transform = _rel


func _put_back() -> void:
	cargo.collision_layer = _free_layers.x
	cargo.collision_mask = _free_layers.y
	cargo.reparent(robot.get_parent(), true)
	cargo_socket.mount(cargo)
	cargo = null


func _abort(reason: String, carrying: bool) -> void:
	_message = "Insert interrupted: %s. Park again and press E." % reason
	_message_time = MESSAGE_TIME
	delivery_aborted.emit(port, reason)
	if phase == Phase.STROKE:
		_set_phase(Phase.ABORT_UP)
	elif carrying:
		_set_phase(Phase.ABORT_RETURN, [LIFT_POSE, RoverVisuals.ARM_LATCH])
	else:
		cargo = null                         # still on the mount
		_set_phase(Phase.ABORT_RETURN, [RoverVisuals.ARM_STOWED])


func _finish() -> void:
	_set_phase(Phase.IDLE)
	visuals.arm_scripted = false
	visuals.arm_target = {}
