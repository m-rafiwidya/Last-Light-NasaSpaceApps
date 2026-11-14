class_name ObjectHolder

extends RefCounted

## Picks up, holds and throws `RigidBody3D` props in front of a first-person camera.
## Shared by the Player and the Robot so both handle props identically.
##
## A held prop is moved to the "held" collision layer and loses the owner's layer
## (layer 2, used by both the player and the robot) from its mask, so it can't push
## its holder around. While held it is pulled by a PID-style controller to a point
## PICKUP_DISTANCE in front of the camera.

## A prop was picked up / let go of / thrown (for sounds, see Sfx)
signal picked_up(object: RigidBody3D)
signal dropped(object: RigidBody3D)
signal thrown(object: RigidBody3D)

const PICKUP_DISTANCE: float = 2.0
const PICKUP_TRANSLATE_KI: float = 0.0
const PICKUP_ROTATE_KI: float = 0.0

const HELD_LAYER: int = 4
const HOLDER_LAYER: int = 2

## Body that holds the objects (receives the reaction force, if enabled)
var body: RigidBody3D
## Yaw node the camera sits under
var pivot: Node3D
## Camera whose pitch (rotation.x) and position define where the object is held
var camera: Camera3D

var held_object: RigidBody3D = null
## Push the holder back with the force that pulls the object towards it
var apply_reaction_force: bool = false

var _original_layer: int = 0
var _original_mask: int = 0
var _original_orientation: Quaternion = Quaternion.IDENTITY
var _translation_integral: Vector3 = Vector3.ZERO
var _angular_integral: Vector3 = Vector3.ZERO


func _init(p_body: RigidBody3D, p_pivot: Node3D, p_camera: Camera3D) -> void:
	body = p_body
	pivot = p_pivot
	camera = p_camera


func pickup(object: RigidBody3D) -> void:
	held_object = object

	_original_layer = object.collision_layer
	_original_mask = object.collision_mask
	_original_orientation = (
		camera.global_transform.basis.inverse().get_rotation_quaternion()
		* object.global_transform.basis.get_rotation_quaternion()
	)

	# Put held object on its own layer and exclude the holder's layer
	object.collision_layer = 1 << (HELD_LAYER - 1)
	object.collision_mask &= ~(1 << (HOLDER_LAYER - 1))
	# The robot is also on the props layer (3), so dropping layer 2 isn't enough for it
	object.add_collision_exception_with(body)

	_translation_integral = Vector3.ZERO
	_angular_integral = Vector3.ZERO
	picked_up.emit(object)


func release() -> void:
	var object: RigidBody3D = held_object
	_let_go()
	if object:
		dropped.emit(object)


func _let_go() -> void:
	if not held_object:
		return
	held_object.collision_layer = _original_layer
	held_object.collision_mask = _original_mask
	held_object.remove_collision_exception_with(body)

	held_object = null
	_translation_integral = Vector3.ZERO
	_angular_integral = Vector3.ZERO


## Releases the held object and throws it along the camera's forward vector.
func throw() -> void:
	if not held_object:
		return
	var thrown_object: RigidBody3D = held_object
	_let_go()
	# TODO: Properly tune this
	var throw_force: float = 10.0 * log(thrown_object.mass / 10.0 + 1.0) * 20.0
	var throw_direction: Vector3 = -camera.global_transform.basis.z
	thrown_object.apply_central_impulse(throw_direction * throw_force)
	thrown.emit(thrown_object)


## Call every physics step.
func update(delta: float) -> void:
	if not held_object:
		return

	# Calculate target position in front of camera
	# Limit angle so the holder can't pull itself up by the bootstraps
	var clamped_camera_basis: Basis = Basis.IDENTITY.rotated(
		Vector3.RIGHT,
		clamp(camera.rotation.x, -PI / 2.0 + 60.0 / 180.0 * PI, PI / 2.0)
	)
	clamped_camera_basis = pivot.global_transform.basis * clamped_camera_basis
	var target_pos: Vector3 = (
		camera.global_position - clamped_camera_basis.z * PICKUP_DISTANCE
	)

	# Translation PID
	var translation_error: Vector3 = target_pos - held_object.global_position
	_translation_integral += translation_error * delta
	var translation_derivative: Vector3 = -held_object.linear_velocity

	var translate_kp: float = 10.0 * log(held_object.mass / 10.0 + 1.0) * 100.0
	var translate_kd: float = 10.0 * log(held_object.mass / 10.0 + 1.0) * 10.0

	var force: Vector3 = (
		translation_error * translate_kp
		+ _translation_integral * PICKUP_TRANSLATE_KI
		+ translation_derivative * translate_kd
	)

	held_object.apply_central_force(force)
	if apply_reaction_force: # Push back holder
		body.apply_central_force(-force)

	# Angular PID
	var current_quat: Quaternion = held_object.global_transform.basis.get_rotation_quaternion()
	var target_quat: Quaternion = clamped_camera_basis.get_rotation_quaternion() * _original_orientation
	var error_quat: Quaternion = (target_quat * current_quat.inverse()).normalized()
	if error_quat.w < 0:
		error_quat = -error_quat

	var error_angle_axis: Vector3 = error_quat.get_angle() * error_quat.get_axis()
	_angular_integral += error_angle_axis * delta
	var derivative_angular: Vector3 = -held_object.angular_velocity

	var rotate_kp: float = held_object.mass * 10.0
	var rotate_kd: float = held_object.mass * 1.0

	var torque: Vector3 = (
		error_angle_axis * rotate_kp
		+ _angular_integral * PICKUP_ROTATE_KI
		+ derivative_angular * rotate_kd
	)

	held_object.apply_torque(torque)
