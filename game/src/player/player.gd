class_name Player


extends RigidBody3D


# Physical movement constants
const ACCEL_GROUND: float = 12.0
const ACCEL_AIR: float = 3.0

const SPEED_WALK: float = 2.0
const SPEED_SPRINT: float = 3.0
const SPEED_CROUCH: float = 1.0
const SPEED_AIR: float = 1.0

const FRICTION: float = 0.5
const JUMP_HEIGHT: float = 0.8
const LEAP_SPEED: float = 0.0
const CROUCH_TIME: float = 0.5
const JUMP_SPEED_PENALTY: float = 0.5

const STEP_SIZE_WALK: float = 0.6
const STEP_SIZE_SPRINT: float = 1.0


# Node references
@export var pivot: Node3D
@export var camera: Camera3D
@export var raycast: RayCast3D
@export var viewmodel_controller: Node3D
@export var controller: PlayerController
## A spotlight on the helmet, above the eyes, aimed with the view (hidden = off); L toggles it
## on foot. The player keeps it as it is while driving a rover (L then works the headlights).
@export var helmet_light: SpotLight3D

## True while the helmet light is on
var helmet_light_on: bool = false:
	set(value):
		helmet_light_on = value
		if helmet_light:
			helmet_light.visible = value

# Object pickup (shared with the robot, see ObjectHolder)
var looking_at_object: Node3D = null
var holder: ObjectHolder
var held_object: RigidBody3D:
	get:
		return holder.held_object if holder else null


var is_on_floor: bool = false
var is_crouching: bool = false

var is_rotating_held_object = false

var camera_last_transform: Transform3D
var camera_lock: bool = false
var move_lock: bool = false
var hide_crosshair = false
var is_looking_at_map = false

#var inventory: Array[Item] = []
var active_item_index: int = -1
# -1 should mean not holding anything
# anything else is fair game

## Gravity where the player is (m/s^2; the level's, see SceneLoader), updated every physics
## step: ground friction and the slope compensation scale with it
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@onready var gravity_vector: Vector3 = (
	ProjectSettings.get_setting("physics/3d/default_gravity_vector")
)
## How high a jump goes (m) under the current gravity; the level sets it (SceneLoader). The
## take-off speed follows from it, so the time in the air grows as gravity drops (0.8 m:
## 0.8 s on Earth; the Moon's 1.2 m: 2.4 s).
var jump_height: float = JUMP_HEIGHT
## Ground friction coefficient (stopping and turning on foot decelerate at gravity * this);
## the level sets it (SceneLoader). The Moon raises it so a walk still stops within a metre.
var ground_friction: float = FRICTION
## Whether the player can pick up and throw a rover here (the level's player_lifts_rovers: the
## test level's sandbox yes, the Moon no; IRIS_KIT.md 10)
var player_lifts_rovers: bool = true


var want_to_crouch: bool = false


# TODO: Abstract this away from player
var camera_tween: Tween
func bind_camera():
	camera.top_level = false
	# Tween to original transform
	if camera_tween:
		camera_tween.kill()
	camera_tween = create_tween()
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)
	camera_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	camera_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	camera_tween.tween_property(camera, "transform", camera_last_transform, CROUCH_TIME)
	camera_tween.parallel().tween_property(camera, "fov", VideoSettings.fov(), CROUCH_TIME)
	camera_tween.tween_callback(func(): camera_lock = false)
	camera_tween.tween_callback(func(): move_lock = false)
	camera_tween.tween_callback(func(): hide_crosshair = false)


# Weird behavior while crouching
# While crouching in progress, new transform takes on the transient value which is incorrect
# While crouching in state, update move input doesnt realize crouching has been released, causing the player to be stuck crouching
# TODO: Await until crouch state settles
func release_camera(new_transform, fov=90.0):
	# camera.transform can be in the middle of tweening
	# TODO: set this to just look at the target instead of last position
	if camera_tween:
		if not camera_tween.is_running():
			camera_last_transform = camera.transform
		camera_tween.kill()
	else:
		camera_last_transform = camera.transform

	if is_crouching:
		camera_last_transform.origin.y = 1.25
	else:
		camera_last_transform.origin.y = 1.5

	camera.top_level = true
	camera_lock = true
	move_lock = true
	hide_crosshair = true
	# Tween to target transform
	camera_tween = create_tween()
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)
	camera_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	camera_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	camera_tween.set_parallel()
	camera_tween.tween_property(camera, "transform", new_transform, CROUCH_TIME)
	camera_tween.tween_property(camera, "fov", fov, CROUCH_TIME)



func set_crouch(value: bool) -> void:
	var shape: CapsuleShape3D = $CollisionShape3D.shape
	if crouch_tween:
		crouch_tween.kill()
	crouch_tween = create_tween()
	crouch_tween.set_ease(Tween.EASE_IN_OUT)
	crouch_tween.set_trans(Tween.TRANS_QUAD)
	crouch_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	crouch_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	crouch_tween.set_parallel()
	if value:
		is_crouching = true
		crouch_tween.tween_property(shape, "height", 1.0, CROUCH_TIME)
		crouch_tween.tween_property(camera, "transform:origin:y", 1.25, CROUCH_TIME)
		crouch_tween.tween_property($CrouchCheck, "transform:origin:y", 0.5, CROUCH_TIME)
	else:
		is_crouching = false
		crouch_tween.tween_property(shape, "height", 2.0, CROUCH_TIME)
		crouch_tween.tween_property(camera, "transform:origin:y", 1.5, CROUCH_TIME)
		crouch_tween.tween_property($CrouchCheck, "transform:origin:y", 0.0, CROUCH_TIME)


func _ready() -> void:
	holder = ObjectHolder.new(self, pivot, camera)
	controller.crouch.connect(_on_controller_crouch)
	controller.interact.connect(_on_controller_interact)
	controller.primary.connect(_on_controller_primary)
	controller.secondary.connect(_on_controller_secondary)
	controller.lights_toggle.connect(func() -> void: helmet_light_on = not helmet_light_on)
	helmet_light_on = helmet_light_on
	# Settings > Video > Field Of View, at once (not while the camera is away, see release_camera)
	camera.fov = VideoSettings.fov()
	VideoSettings.section.changed.connect(_on_video_setting_changed)


func _on_video_setting_changed(key: String) -> void:
	if key == "fov" and not camera_lock:
		camera.fov = VideoSettings.fov()


# Controller signals
var crouch_tween: Tween
func _on_controller_crouch(value: bool) -> void:
	want_to_crouch = value
	if want_to_crouch or not $CrouchCheck.is_colliding():
		set_crouch(want_to_crouch)


func _on_controller_interact(value: bool) -> void:
	if not value:
		return
	
	if held_object:
		holder.release()
	elif raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider is RigidBody3D:
			if collider is Robot and not player_lifts_rovers:
				return
			holder.pickup(collider as RigidBody3D)
		elif collider is InteractTrigger:
			collider.interact(self)


func _on_controller_primary(value: bool) -> void:
	if not value:
		return
	
	holder.throw()


func _on_controller_secondary(value: bool) -> void:
	if held_object:
		is_rotating_held_object = value

# TODO: Write custom integrator
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	gravity = state.total_gravity.length()
	var contact_count: int = state.get_contact_count()
	var max_floor_cosine: float = cos(PI/4.0)
	var normal: Vector3 = Vector3.ZERO
	var local_velocity: Vector3 = Vector3.ZERO
	#var contact_impulse: Vector3 = Vector3.ZERO
	#var rigidbody_floor: RigidBody3D = null
	#var contact_point: Vector3 = Vector3.ZERO

	is_on_floor = false

	for contact_id in range(contact_count):
		normal = state.get_contact_local_normal(contact_id)
		if normal.dot(Vector3.UP) >= max_floor_cosine:
			is_on_floor = true
			#if state.get_contact_collider_object(contact_id) is RigidBody3D:
				#rigidbody_floor = state.get_contact_collider_object(contact_id)
			local_velocity = state.get_contact_collider_velocity_at_position(contact_id)
			#contact_point = state.get_contact_local_position(contact_id)
			#contact_impulse = state.get_contact_impulse(contact_id)
			break

	var move_direction = pivot.transform.basis * controller.move_direction
	var rotated_move_direction: Vector3

	var speed: float
	var accel: float
	if is_on_floor:
		if is_crouching:
			speed = SPEED_CROUCH
			#viewmodel_controller.step_size = 1.0
		else:
			if controller.is_sprinting:
				speed = SPEED_SPRINT
				#viewmodel_controller.step_size = 1.5
			else:
				speed = SPEED_WALK
				#viewmodel_controller.step_size = 1.5
		accel = ACCEL_GROUND
	else:
		speed = SPEED_AIR
		accel = ACCEL_AIR

	if is_on_floor:
		# Custom friction to avoid halting after landing
		# Negate friction in direction of movement
		var relative_velocity = state.linear_velocity - local_velocity
		# TODO: Doesnt work when walking then crouching
		# Friction acts only on the velocity that is not along the move direction
		# (capped by the target speed), and is clamped so it can never overshoot.
		var move_dir_unit: Vector3 = move_direction.normalized()
		var target_speed: float = move_direction.length() * speed
		var excess: Vector3 = relative_velocity - clampf(relative_velocity.dot(move_dir_unit), 0.0, target_speed) * move_dir_unit
		excess.y = 0.0
		var friction_dv: float = gravity * ground_friction * state.step

		if excess.length() <= friction_dv:
			# Friction can stop the excess within this step (static)
			state.apply_central_impulse(-excess * mass)
		else:
			# Kinetic
			state.apply_central_force(-excess.normalized() * gravity * ground_friction * mass)

		# Compensation force on slope
		var rotation_axis: Vector3 = normal.cross(Vector3.UP)
		var angle: float = normal.signed_angle_to(Vector3.UP, rotation_axis.normalized())

		if is_zero_approx(angle) or rotation_axis.is_zero_approx(): # On floor
			rotated_move_direction = move_direction
		else: # On slope
			rotated_move_direction = move_direction.rotated(rotation_axis.normalized(), -angle)
			var slope_compensation_force: Vector3 = -normal * mass * gravity
			var scale_factor = 1.0 / normal.dot(Vector3.UP)
			slope_compensation_force *= scale_factor
			# Negate vertical component
			slope_compensation_force -= slope_compensation_force.dot(Vector3.UP) * Vector3.UP
			state.apply_force(slope_compensation_force)
	else: # In air
		rotated_move_direction = move_direction

	var accel_move: Vector3 = accel * rotated_move_direction
	var speed_target: float = rotated_move_direction.length() * speed

	if (state.linear_velocity + accel_move * state.step).dot(rotated_move_direction) > speed_target:
		var speed_delta: float = speed_target - state.linear_velocity.dot(rotated_move_direction)
		state.apply_central_impulse(mass * rotated_move_direction * max(speed_delta, 0.0))
	else:
		state.apply_central_force(mass * accel_move)

	# Jumping
	if is_on_floor and controller.request_jump:
		var epsilon: float = 0.05
		var jump_vector: Vector3 = -gravity_vector
		if state.linear_velocity.dot(rotated_move_direction) <= speed * 1.2:
			jump_vector += 0.0 * rotated_move_direction
		state.apply_central_impulse(jump_vector * mass * sqrt(2.0 * jump_height * gravity))
		state.transform.origin.y += epsilon
		controller.request_jump = false


var crouch_check_was_colliding: bool = false

func _physics_process(delta: float) -> void:
	looking_at_object = held_object if held_object else raycast.get_collider()
	
	holder.update(delta)
	
	# Update rotation and viewmodel lag
	var prev_altitude = camera.rotation.x
	camera.rotation.x = controller.camera_altitude
	var altitude_delta = camera.rotation.x - prev_altitude
	
	var prev_azimuth = pivot.rotation.y
	pivot.rotation.y = controller.camera_azimuth
	var azimuth_delta = pivot.rotation.y - prev_azimuth
	
	if azimuth_delta > PI:
		azimuth_delta -= 2.0 * PI
	elif azimuth_delta < -PI:
		azimuth_delta += 2.0 * PI
	
	#viewmodel_controller.offset += Vector2(azimuth_delta, -altitude_delta) / 32.0
	# TODO: Add viewmodel implementation
	var crouch_check_is_colliding = $CrouchCheck.is_colliding()
	if crouch_check_is_colliding != crouch_check_was_colliding:
		crouch_check_was_colliding = crouch_check_is_colliding
		if crouch_check_is_colliding:
			set_crouch(true)
		elif not want_to_crouch:
			set_crouch(false)
	
	# TODO: Possibly object reorientation stuff?
	#if is_rotating_held_object:
		#pass
		##held_object_original_orientation = new_basis.get_rotation_quaternion() * held_object_original_orientation
		#controller.queued_rotation = Quaternion.IDENTITY
	# TODO: Remove this relic of an old idea
	#if Input.is_action_just_pressed("interact_inventory"):
		#is_looking_at_map = !is_looking_at_map
		#viewmodel_controller.show_map(is_looking_at_map)
		#if is_looking_at_map:
			#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			#GameState.player.release_camera($Pivot/Marker3D.global_transform, 45.0)
			#GameState.player.viewmodel_controller.set_holstered(true)
		#else:
			#Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			#GameState.player.bind_camera()
			#GameState.player.viewmodel_controller.set_holstered(false)
