class_name ClawPick

extends Node

## The arm's assisted pick (plan v2 G3): with Kite stopped next to a loose part in group
## `claw_target` (the delivery crate, ...), E has the arm reach over it, come down, latch it, lift
## it and stow it on Kite: loose in the storage tray when it fits, else on the cargo mount. Reuses
## CargoDelivery's arm geometry (ik_down, poses). Visual only like the delivery: the arm has no
## collision and the part rides the latch frozen.
##
## shortcut: the tray is behind the arm's yaw range, so the arm carries the part to the latch pose
## over the cargo mount and the part is then let go just above the tray, where it drops in; the
## manual claw will place it there itself.
##
## Parts lower than MIN_GRAB_HEIGHT say so in the hint.
##
## The rover moving, driving input, or the arm getting within 20 mm of the terrain aborts the pick.
## Before the latch the arm just stows; after it the part drops where it is (careful driving).

signal pick_started(part: HotswapPart)
signal pick_aborted(part: HotswapPart, reason: String)
## `into` is the cargo mount (HotswapSocket) or the storage tray (StorageTray)
signal pick_finished(part: HotswapPart, into: Node)

enum Phase { IDLE, REACH, DOWN, UP, CARRY, STOW }

const GROUP: StringName = &"claw_target"
## How far above the part's top the arm lines up before coming straight down (m)
const STROKE: float = 0.12
const SEAT_GAP: float = 0.006
## Parts within this distance (horizontal, m) of the arm's yaw axis get a hint
const HINT_RANGE: float = 3.0
## Lowest top (m above the ground under it) the latch can grab without the arm touching the ground
## (measured: a 3 cm top leaves 35 mm, a 10 cm jar 105 mm; the old 0.22 m limit came from the tool
## socket's hidden marker mesh, which the clearance check used to count)
const MIN_GRAB_HEIGHT: float = 0.03

@onready var robot: Robot = get_parent() as Robot
@onready var visuals: RoverVisuals = robot.get_node("Visuals")
@onready var delivery: CargoDelivery = robot.get_node("CargoDelivery")

var phase: Phase = Phase.IDLE
## The part being picked
var part: HotswapPart = null
var _destination: Node = null                # the cargo mount or the storage tray
var _top: Vector3 = Vector3.ZERO               # the part's top centre, kit frame, at the start
var _approach: Dictionary = {}
var _stroke_s: float = 0.0
var _targets: Array = []
var _layers: Vector2i = Vector2i.ZERO
var _start: Transform3D = Transform3D.IDENTITY
var _message: String = ""
var _message_time: float = 0.0


func is_busy() -> bool:
	return phase != Phase.IDLE


## The top centre of a part's meshes (world)
static func top_of(target: HotswapPart) -> Vector3:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var aabb: AABB = mesh.global_transform * mesh.get_aabb()
		box = aabb if first else box.merge(aabb)
		first = false
	if first:
		return target.global_position
	return Vector3(box.get_center().x, box.end.y, box.get_center().z)


## Where on Kite `target` would go: the storage tray when it fits, else the free cargo mount; null
## when neither takes it
func destination_for(target: HotswapPart) -> Node:
	var tray := robot.get_node_or_null("StorageBox") as StorageTray
	if tray and tray.fits(target):
		return tray
	var cargo := robot.get_node_or_null("CargoSocket") as HotswapSocket
	if cargo and cargo.part == null and cargo.can_accept(target):
		return cargo
	return null


## Where `target` is from the arm: {d, bearing (degrees, + = left), low (too short to grab),
## approach, grab (joints, {} out of reach)}
func measure(target: HotswapPart) -> Dictionary:
	var world_top: Vector3 = top_of(target)
	var query := PhysicsRayQueryParameters3D.create(world_top, world_top + Vector3.DOWN * 2.0, 1)
	query.exclude = [target.get_rid()]
	var hit: Dictionary = robot.get_world_3d().direct_space_state.intersect_ray(query)
	var height: float = world_top.y - (hit["position"] as Vector3).y if hit else INF
	var top: Vector3 = delivery._kit(world_top)
	var rel := Vector2(top.x - CargoDelivery.YAW_AXIS.x, top.y - CargoDelivery.YAW_AXIS.y)
	return {
		"d": rel.length(), "bearing": rad_to_deg(atan2(-rel.x, rel.y)), "top": top, "low": height < MIN_GRAB_HEIGHT,
		"approach": CargoDelivery.ik_down(top + Vector3(0.0, 0.0, SEAT_GAP + STROKE)),
		"grab": CargoDelivery.ik_down(top + Vector3(0.0, 0.0, SEAT_GAP)),
	}


## The nearest loose claw_target part within HINT_RANGE of the arm, or null
func nearest_part() -> HotswapPart:
	var best: HotswapPart = null
	var best_d: float = HINT_RANGE
	var yaw_world: Vector3 = robot.to_global(Vector3(CargoDelivery.YAW_AXIS.x, 0.0, -CargoDelivery.YAW_AXIS.y))
	for node in get_tree().get_nodes_in_group(GROUP):
		var p := node as HotswapPart
		if p == null or p.is_mounted() or not p.is_inside_tree():
			continue
		var d: float = Vector2(p.global_position.x - yaw_world.x, p.global_position.z - yaw_world.z).length()
		if d < best_d:
			best = p
			best_d = d
	return best


## True when E would start picking `target` now
func ready_for(target: HotswapPart) -> bool:
	if target == null or delivery._latch() == null or delivery.is_busy() or destination_for(target) == null:
		return false
	var manual := robot.get_node_or_null("ManualClaw") as ManualClaw
	if manual and manual.active:
		return false
	if robot.linear_velocity.length() > CargoDelivery.STOPPED_SPEED:
		return false
	var m: Dictionary = measure(target)
	return not m["low"] and not m["approach"].is_empty() and not m["grab"].is_empty()


## What the robot HUD should say ("" for nothing): near a loose claw_target part
func get_hint() -> String:
	if _message_time > 0.0:
		return _message
	if phase != Phase.IDLE:
		return "Picking up the %s" % part.get_display_name().to_lower() if is_instance_valid(part) else ""
	var target: HotswapPart = nearest_part()
	if target == null:
		return ""
	var name: String = target.get_display_name()
	if delivery._latch() == null:
		return "%s: mount the arm tool turret to pick it up" % name
	if destination_for(target) == null:
		return "%s: no free spot on Kite for it" % name
	var m: Dictionary = measure(target)
	if m["low"]:
		return "%s: too low for the arm's turret to grab" % name
	if m["approach"].is_empty() or m["grab"].is_empty():
		if m["bearing"] > CargoDelivery.WINDOW_BEARING.y:
			return "%s: turn %d degrees left" % [name, ceili(m["bearing"] - CargoDelivery.WINDOW_BEARING.y)]
		if m["bearing"] < CargoDelivery.WINDOW_BEARING.x:
			return "%s: turn %d degrees right" % [name, ceili(CargoDelivery.WINDOW_BEARING.x - m["bearing"])]
		var middle: float = (CargoDelivery.WINDOW_D.x + CargoDelivery.WINDOW_D.y) / 2.0
		if m["d"] > middle:
			return "%s: %.2f m closer" % [name, m["d"] - middle]
		return "%s: back up %.2f m" % [name, middle - m["d"]]
	if robot.linear_velocity.length() > CargoDelivery.STOPPED_SPEED:
		return "Stop here"
	return "In position: press %s to pick up the %s" % [InputBindings.action_text(&"interact_use", "E"), name.to_lower()]


## Robot hook (E): starts a pick when in reach of a part. True when E was used here
func handle_interact() -> bool:
	if phase != Phase.IDLE:
		return true
	var target: HotswapPart = nearest_part()
	if not ready_for(target):
		return false
	part = target
	_destination = destination_for(part)
	var m: Dictionary = measure(part)
	_top = m["top"]
	_approach = m["approach"]
	_start = robot.global_transform
	visuals.arm_scripted = true
	visuals.arm_deployed = false
	visuals.arm_target = {}
	_set_phase(Phase.REACH, [CargoDelivery.LIFT_POSE, _approach])
	pick_started.emit(part)
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
		var next: float = move_toward(now, to, CargoDelivery.JOINT_SPEED * delta)
		visuals.arm_joints[j] = next
		if absf(next - to) > 0.01:
			reached = false
	visuals.apply_arm_pose()
	if reached:
		_targets.pop_front()
	return _targets.is_empty()


# Straight down (s 0 -> 1) or up over the part's top
func _pose_stroke(s: float) -> void:
	var joints: Dictionary = CargoDelivery.ik_down(_top + Vector3(0.0, 0.0, SEAT_GAP + STROKE * (1.0 - s)))
	if joints.is_empty():
		return
	for j in joints:
		visuals.arm_joints[j] = joints[j]
	visuals.apply_arm_pose()


## Why the pick must stop ("" to go on). `ground` off on the lift straight up from the grab: the
## latched part counts as arm there and still sits on the ground
func _moved(ground: bool = true) -> String:
	var drift: float = (robot.global_position - _start.origin).length()
	var turn: float = rad_to_deg(robot.global_basis.z.angle_to(_start.basis.z))
	if drift > CargoDelivery.DRIFT_LIMIT or turn > CargoDelivery.TURN_LIMIT:
		return "the rover moved"
	if robot.controller and (absf(robot.controller.desired_speed) > 0.05 or absf(robot.controller.steer) > 0.05):
		return "the rover moved"
	if ground and visuals.arm_ground_clearance() < CargoDelivery.GROUND_MARGIN:
		return "the arm came too close to the ground"
	return ""


func _physics_process(delta: float) -> void:
	_message_time = maxf(_message_time - delta, 0.0)
	if phase == Phase.IDLE:
		return
	if not is_instance_valid(part):
		_set_phase(Phase.STOW, [visuals.stow_pose()])
	elif phase in [Phase.REACH, Phase.DOWN, Phase.UP, Phase.CARRY]:
		var reason: String = _moved(phase != Phase.UP)
		if not reason.is_empty():
			_abort(reason)
			return
	match phase:
		Phase.REACH:
			if _move(delta):
				_stroke_s = 0.0
				_set_phase(Phase.DOWN)
		Phase.DOWN:
			_stroke_s = minf(_stroke_s + CargoDelivery.STROKE_SPEED * delta / STROKE, 1.0)
			_pose_stroke(_stroke_s)
			if _stroke_s >= 1.0:
				_grab()
				_set_phase(Phase.UP)
		Phase.UP:
			_stroke_s = maxf(_stroke_s - CargoDelivery.STROKE_SPEED * delta / STROKE, 0.0)
			_pose_stroke(_stroke_s)
			if _stroke_s <= 0.0:
				_set_phase(Phase.CARRY, [CargoDelivery.LIFT_POSE, RoverVisuals.ARM_LATCH])
		Phase.CARRY:
			if _move(delta):
				var socket := _destination
				_release()
				_set_phase(Phase.STOW, [visuals.stow_pose()])
				pick_finished.emit(part, socket)
		Phase.STOW:
			if _move(delta):
				_finish()


func _grab() -> void:
	var latch: Node3D = delivery._latch()
	var rel: Transform3D = latch.global_transform.affine_inverse() * part.global_transform
	_layers = Vector2i(part.collision_layer, part.collision_mask)
	part.collision_layer = 0
	part.collision_mask = 0
	part.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	part.freeze = true
	part.reparent(latch, true)
	part.transform = rel


func _holding() -> bool:
	return is_instance_valid(part) and part.get_parent() == delivery._latch()


# Lets go: into the destination socket, or (null) dropped where it is
func _release(into: bool = true) -> void:
	part.reparent(robot.get_parent(), true)
	part.collision_layer = _layers.x
	part.collision_mask = _layers.y
	if into and _destination is StorageTray:
		part.global_position = (_destination as StorageTray).drop_point()
		part.freeze = false
		part.sleeping = false
	elif into and _destination is HotswapSocket and (_destination as HotswapSocket).part == null:
		(_destination as HotswapSocket).mount(part)
	else:
		part.freeze = false
		part.sleeping = false


func _abort(reason: String) -> void:
	var dropped: bool = _holding()
	_message = "Pick interrupted: %s.%s" % [reason, " The part dropped." if dropped else " Park again and press E."]
	_message_time = CargoDelivery.MESSAGE_TIME
	pick_aborted.emit(part, reason)
	if dropped:
		_release(false)
	_set_phase(Phase.STOW, [CargoDelivery.LIFT_POSE, visuals.stow_pose()])


func _finish() -> void:
	_set_phase(Phase.IDLE)
	visuals.arm_scripted = false
	visuals.arm_target = {}
	part = null
	_destination = null
