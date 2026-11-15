class_name ManualClaw

extends Node

## The arm by hand (plan v2 manual claw): R deploys the arm, and while it's out the claw follows the
## crosshair, the spot the camera looks at, with the tool pointing straight down; the mouse wheel
## sets how high above that spot it hangs. A click grabs the loose part under the claw or lets go
## of the held one, which then drops with real physics: into the storage tray when it's over it,
## onto the ground when it isn't. R again (or driving off) stows the arm; a part still held drops.
##
## The arm reaches forward over the ground and, with the shoulder past vertical (up to J2_MAX), back
## over the deck to the tray. Out of reach the arm stays where it was and the marker turns red.
## Needs an arm tool with a latch and an empty cargo mount (the arm stays stowed over cargo).
## The assisted pick (ClawPick, hold E) does the same job for players who'd rather not.

signal grabbed(part: HotswapPart)
signal released(part: HotswapPart)

## Hover above the aimed spot (m): default, limits and one wheel notch
const HOVER_DEFAULT: float = 0.15
const HOVER_MIN: float = 0.0
const HOVER_MAX: float = 0.45
const HOVER_STEP: float = 0.03
## How far the crosshair's ray reaches (m), and what it hits: terrain, Kite (its tray) and parts
const AIM_RANGE: float = 5.0
const AIM_MASK: int = 1 | 2 | 4
## A part is grabbed when its top is this close to the grip (m)
const GRAB_RADIUS: float = 0.08
## The shoulder may lean back this far (degrees) to reach the tray; manual joint control keeps 90
const J2_MAX: float = 135.0
## Reaching back, how far the tool may tilt off straight down (degrees) once the wrist is at its limit
const BACK_TILT: float = 20.0
## Joint speed while following the crosshair (degrees / s)
const JOINT_SPEED: float = 90.0
const GROUND_MARGIN: float = 0.01
## Driving faster than this (m/s) stows the arm
const DRIVE_SPEED: float = 0.3

@onready var robot: Robot = get_parent() as Robot
@onready var visuals: RoverVisuals = robot.get_node("Visuals")
@onready var delivery: CargoDelivery = robot.get_node("CargoDelivery")

var active: bool = false
var held: HotswapPart = null
var hover: float = HOVER_DEFAULT
## Where the grip is headed (world) and whether the arm can get there
var target: Vector3 = Vector3.ZERO
var reachable: bool = true
var _held_layers: Vector2i = Vector2i.ZERO
var _held_height: float = 0.0
var _marker: MeshInstance3D = null
var _marker_material := StandardMaterial3D.new()
## Seconds left showing why R didn't start the claw
var _why_not_time: float = 0.0


func _ready() -> void:
	robot.controller.arm_toggle.connect(_on_arm_toggle)
	robot.controller.primary.connect(func(pressed: bool) -> void:
		if pressed and active:
			toggle_grab())
	robot.controller.zoom.connect(func(steps: float) -> void:
		if active:
			hover = clampf(hover + steps * HOVER_STEP, HOVER_MIN, HOVER_MAX))
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.02
	sphere.height = 0.04
	sphere.material = _marker_material
	_marker.mesh = sphere
	_marker.top_level = true
	_marker.visible = false
	add_child(_marker)


## Joints putting the grip on `p` (kit frame: x right, y forward, z up), tool straight down, the
## shoulder up to `j2_max`; behind the arm's yaw axis it reaches back over the deck. {} if it can't.
static func ik_reach(p: Vector3, j2_max: float = J2_MAX) -> Dictionary:
	var rel := Vector2(p.x - CargoDelivery.YAW_AXIS.x, p.y - CargoDelivery.YAW_AXIS.y)
	if rel.y >= 0.0:
		return CargoDelivery.ik_down(p)
	var j1: float = rad_to_deg(atan2(rel.x, -rel.y))
	var v := Vector2(-rel.length(), p.z + CargoDelivery.WRIST_TO_LATCH - CargoDelivery.SHOULDER.y)
	var u: float = CargoDelivery.UPPER
	var f: float = CargoDelivery.FOREARM
	var c3: float = (v.length_squared() - u * u - f * f) / (2.0 * u * f)
	if absf(c3) > 1.0:
		return {}
	for sgn in [1.0, -1.0]:
		var t3: float = sgn * acos(c3)
		var j2: float = rad_to_deg(atan2(v.y, v.x) - atan2(f * sin(t3), u + f * cos(t3)))
		var j3: float = rad_to_deg(t3)
		var j4: float = wrapf(-90.0 - (j2 + j3), -180.0, 180.0)
		# Leaning back the wrist runs out of range first: let the tool tilt up to BACK_TILT off
		# vertical (the grip moves a few cm, fine for dropping into the tray)
		var limit: float = CargoDelivery.RANGES["J4"].y
		if absf(j4) > limit and absf(j4) <= limit + BACK_TILT:
			j4 = signf(j4) * limit
		var joints: Dictionary = {"J1": j1, "J2": j2, "J3": j3, "J4": j4, "J5": 0.0}
		var inside: bool = j2 >= CargoDelivery.RANGES["J2"].x and j2 <= j2_max
		for j in ["J1", "J3", "J4"]:
			inside = inside and joints[j] >= CargoDelivery.RANGES[j].x and joints[j] <= CargoDelivery.RANGES[j].y
		if inside:
			return joints
	return {}


## True when the claw can be used now (an arm tool, the cargo mount empty, nothing else moving the arm)
func available() -> bool:
	return delivery._latch() != null and not visuals.cargo_loaded() and not delivery.is_busy() \
		and not (robot.get_node_or_null("ClawPick") as ClawPick and (robot.get_node("ClawPick") as ClawPick).is_busy())


func activate() -> void:
	if active or not available():
		return
	active = true
	hover = HOVER_DEFAULT
	visuals.arm_scripted = true
	visuals.arm_target = {}
	_marker.visible = true


## Stows the arm; a held part drops where it is
func deactivate() -> void:
	if not active:
		return
	if held:
		release()
	active = false
	_marker.visible = false
	visuals.arm_scripted = false
	visuals.arm_deployed = false
	visuals.arm_target = visuals.stow_pose().duplicate()


func _on_arm_toggle() -> void:
	# Deploying is RoverVisuals' (the claw takes over once the arm is out); stowing is ours
	if active:
		deactivate()
	elif not available():
		_why_not_time = 4.0


## The world point the crosshair looks at (within AIM_RANGE), not counting the held part
func aim_point() -> Vector3:
	var cam: Camera3D = robot.camera
	var from: Vector3 = cam.global_position
	var to: Vector3 = from - cam.global_basis.z * AIM_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to, AIM_MASK)
	if held:
		query.exclude = [held.get_rid()]
	var hit: Dictionary = robot.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if hit else to


## The loose part whose top is closest to the grip, within GRAB_RADIUS, or null
func part_under_claw() -> HotswapPart:
	var latch: Node3D = delivery._latch()
	if latch == null:
		return null
	var shape := SphereShape3D.new()
	shape.radius = GRAB_RADIUS * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, latch.global_position)
	query.collision_mask = 4
	var best: HotswapPart = null
	var best_d: float = GRAB_RADIUS
	for hit in robot.get_world_3d().direct_space_state.intersect_shape(query, 16):
		var part := hit["collider"] as HotswapPart
		if part == null or part.is_mounted() or part == held:
			continue
		var d: float = (ClawPick.top_of(part) - latch.global_position).length()
		if d <= best_d:
			best = part
			best_d = d
	return best


## Grabs the part under the claw, or lets go of the held one. True when something happened
func toggle_grab() -> bool:
	if held:
		release()
		return true
	var part: HotswapPart = part_under_claw()
	if part == null:
		return false
	var latch: Node3D = delivery._latch()
	_held_height = ClawPick.top_of(part).y - part.global_position.y
	# The claw centres the part under its grip (within GRAB_RADIUS), so it hangs straight below it
	# however the arm turns: reaching back over the deck flips the claw round
	part.global_position += latch.global_position - ClawPick.top_of(part)
	var rel: Transform3D = latch.global_transform.affine_inverse() * part.global_transform
	_held_layers = Vector2i(part.collision_layer, part.collision_mask)
	part.collision_layer = 0
	part.collision_mask = 0
	part.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	part.freeze = true
	part.reparent(latch, true)
	part.transform = rel
	held = part
	grabbed.emit(part)
	return true


## Lets go of the held part: it drops with real physics, moving as Kite moves
func release() -> void:
	var part := held
	held = null
	part.reparent(robot.get_parent(), true)
	part.collision_layer = _held_layers.x
	part.collision_mask = _held_layers.y
	part.freeze = false
	part.sleeping = false
	part.linear_velocity = robot.linear_velocity
	released.emit(part)


## What the robot HUD should say ("" for nothing)
func get_hint() -> String:
	if not active:
		# R pressed but the claw can't take over: say why instead of leaving the player guessing
		if _why_not_time > 0.0 and GameState.robot == robot and not delivery.is_busy():
			if delivery._latch() == null:
				return "Claw: mount the arm tool turret first"
			if visuals.cargo_loaded():
				return "Claw: the cargo mount is full, the arm stays clear of it. Empty it to use the claw"
		return ""
	if not reachable:
		return "Claw: out of the arm's reach"
	if held:
		return "Holding the %s: click to let go · wheel: height · R: stow" % held.get_display_name().to_lower()
	var under: HotswapPart = part_under_claw()
	if under:
		return "Click to grab the %s" % under.get_display_name().to_lower()
	return "Claw: look to aim · wheel: height · click: grab · R: stow"


func _physics_process(delta: float) -> void:
	_why_not_time = maxf(_why_not_time - delta, 0.0)
	if not active:
		# The arm out (RoverVisuals deployed it and is done moving it): the claw takes over
		if visuals.arm_deployed and visuals.arm_target.is_empty() and available() \
				and GameState.robot == robot:
			activate()
		return
	# Driving off, losing the tool, or control leaving Kite (back to the workshop, or a human
	# carrying it home) stows the arm; anything held drops
	if absf(robot.controller.desired_speed) > 0.05 or robot.linear_velocity.length() > DRIVE_SPEED \
			or not is_instance_valid(delivery._latch()) or GameState.robot != robot \
			or GameState.state != GameState.State.IN_GAME_ROBOT:
		deactivate()
		return
	var aim: Vector3 = aim_point()
	target = aim + Vector3.UP * (hover + (_held_height if held else 0.0))
	var p: Vector3 = robot.to_local(target)
	var joints: Dictionary = ik_reach(Vector3(p.x, -p.z, p.y))
	reachable = not joints.is_empty()
	_marker.global_position = aim + Vector3.UP * hover
	_marker_material.albedo_color = Color(0.3, 1.0, 0.4) if reachable else Color(1.0, 0.3, 0.25)
	if not reachable:
		return
	var before: Dictionary = visuals.arm_joints.duplicate()
	for j in ["J1", "J2", "J3", "J4"]:
		visuals.arm_joints[j] = move_toward(visuals.arm_joints[j], joints[j], JOINT_SPEED * delta)
	visuals.arm_joints["J5"] = 0.0
	visuals.apply_arm_pose()
	# Don't push the arm into the terrain: step back if this step would
	if visuals.arm_ground_clearance() < GROUND_MARGIN:
		visuals.arm_joints = before
		visuals.apply_arm_pose()
