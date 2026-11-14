class_name RunningGear

extends Node

# Fraction of the slip one physics step may remove through the tyre force. Below 1
# keeps the explicit wheel integration from overshooting the ground speed.
const LONGITUDINAL_STABILITY_FACTOR: float = 0.5

@export_group("Tire Model")
@export_subgroup("Pacejka Magic Formula")
@export var pacejka_b: float = 0.714
@export var pacejka_c: float = 1.40
@export var pacejka_d: float = 1.00
@export var pacejka_e: float = -0.20

@export_subgroup("Friction and Stiffness")
@export var longitudinal_friction_coefficient: float = 1.0
@export var lateral_friction_coefficient: float = 1.0
# Newtons per unit of slip, per wheel. These are absolute, so they must scale with the
# load on each wheel (the tyre saturates when stiffness * slip > friction * load). Tuned
# for 4 wheels (1250 / 1000) and scaled by 4/6 for 6 wheels, so grip is unchanged.
@export var longitudinal_stiffness: float = 833.3
@export var cornering_stiffness: float = 666.7
# Below this ground speed (m/s) the slip ratio and slip angle are computed as if the
# wheel were moving at this speed. This removes the 1/speed singularity, so near a
# standstill the tyre acts like smooth viscous friction instead of flipping its
# force every tick. Higher = calmer at low speed, but weaker grip there.
@export var low_speed_threshold: float = 1.5

@export_group("Chassis")
@export var wheel_base: float = 1.0
@export var track_width: float = 1.0

@export_group("Running Gear")
@export var wheel_radius: float = 0.15
@export var wheel_inertia: float = 0.03
@export_subgroup("Suspension")
# Per wheel. Tuned for 4 wheels (4000 N/m, 400 Ns/m) and scaled by 4/6 for 6 wheels, so
# the rest height (49 mm sag), frequency and damping ratio are unchanged.
@export var front_spring_stiffness: float = 2666.7
@export var middle_spring_stiffness: float = 2666.7
@export var rear_spring_stiffness: float = 2666.7
# TODO: Implement variable damping (rebound and bump stiffness)
@export var front_shock_damping: float = 266.7
@export var middle_shock_damping: float = 266.7
@export var rear_shock_damping: float = 266.7
@export var front_ride_height: float = 0.15
@export var middle_ride_height: float = 0.15
@export var rear_ride_height: float = 0.15
@export_subgroup("Ground contact")
# Each wheel's ground check is a cylinder the size of the wheel (wheel radius x wheel_width,
# axle along the steered axle) cast straight down the rover's -Y, from its centre at
# suspension_top above the wheel's attachment point (the steering actuator / rocker horn
# height, above the suspension's whole travel) down to full extension. Starting above the
# travel means kerbs and ramp edges up to that height are found from above instead of the
# check starting inside them, and the wheel-sized shape finds edges it touches off-centre.
@export var wheel_width: float = 0.24
@export var suspension_top: float = 0.30
# World (layer 1) and props (layer 3: the see-saw plank, crates, loose parts, other rovers)
@export_flags_3d_physics var ground_mask: int = 1 | 4
# Below this up-component the touched surface is a wall: the wheel is in contact but not held up
const WALL_NORMAL_LIMIT: float = 0.3
# The check reaches this far past full extension, so a wheel resting on the ground at full
# extension still counts as touching it (with no load)
const CONTACT_TOLERANCE: float = 0.01
@export_subgroup("Steering")
@export var max_steer_angle_degrees: float = 30.0
# Rear wheels counter-steer (Curiosity style), which halves the turning radius
@export var rear_steer_bias: float = -1.0

# Six wheels: front and rear pairs steer, the middle pair is fixed. MIDDLE_* come last so
# the original four keep their values.
enum Wheel{
	FRONT_LEFT,
	FRONT_RIGHT,
	REAR_LEFT,
	REAR_RIGHT,
	MIDDLE_LEFT,
	MIDDLE_RIGHT,
}

enum WheelState{
	ANGULAR_VELOCITY,
	LOAD,
	FORCE,
	IN_CONTACT,
	CONTACT_POINT,
	TORQUE,
	IS_SLIPPING,
	# Wheel centre height (robot space Y) where the ground check stopped
	CENTER_HEIGHT,
	# The body the wheel stands on (null if none)
	GROUND_BODY,
	# Longitudinal slip relative to what the tyre can carry (slip ratio * longitudinal
	# stiffness / (friction * load)); + = the wheel turns faster than the ground passes.
	# The tyre force peaks near 2.7 (pacejka_b / c / e); 0 without a loaded contact.
	# Read by the Robot's traction control.
	NORMALIZED_SLIP,
}

var wheel_states: Dictionary = {}


func _init() -> void:
	for wheel in Wheel.values():
		wheel_states[wheel] = {
			WheelState.ANGULAR_VELOCITY: 0.0,
			WheelState.LOAD: Vector3.ZERO,
			WheelState.FORCE: Vector3.ZERO,
			WheelState.IN_CONTACT: false,
			WheelState.CONTACT_POINT: Vector3.ZERO,
			WheelState.TORQUE: 0.0,
			WheelState.IS_SLIPPING: false,
			WheelState.CENTER_HEIGHT: 0.0,
			WheelState.GROUND_BODY: null,
			WheelState.NORMALIZED_SLIP: 0.0,
		}

enum WheelProperty{
	POSITION,
	SPRING_STIFFNESS,
	SHOCK_DAMPING,
	RIDE_HEIGHT,
	EFFECTIVE_RADIUS,
	MAX_STEER_ANGLE,
	STEER_BIAS,
	INERTIA,
	# Multiplier on both friction coefficients (from the mounted WheelPart's grip)
	GRIP,
}

var wheel_properties: Dictionary

func update_wheel_properties() -> void:
	# (side x, axle z, spring, damping, ride height, steer bias) per wheel
	var half_track: float = track_width / 2.0
	var half_base: float = wheel_base / 2.0
	var layout: Dictionary = {
		Wheel.FRONT_LEFT: [-half_track, -half_base, front_spring_stiffness, front_shock_damping, front_ride_height, 1.0],
		Wheel.FRONT_RIGHT: [half_track, -half_base, front_spring_stiffness, front_shock_damping, front_ride_height, 1.0],
		Wheel.MIDDLE_LEFT: [-half_track, 0.0, middle_spring_stiffness, middle_shock_damping, middle_ride_height, 0.0],
		Wheel.MIDDLE_RIGHT: [half_track, 0.0, middle_spring_stiffness, middle_shock_damping, middle_ride_height, 0.0],
		Wheel.REAR_LEFT: [-half_track, half_base, rear_spring_stiffness, rear_shock_damping, rear_ride_height, rear_steer_bias],
		Wheel.REAR_RIGHT: [half_track, half_base, rear_spring_stiffness, rear_shock_damping, rear_ride_height, rear_steer_bias],
	}
	wheel_properties = {}
	for wheel in layout:
		var entry: Array = layout[wheel]
		wheel_properties[wheel] = {
			WheelProperty.POSITION: Vector3(entry[0], 0, entry[1]),
			WheelProperty.SPRING_STIFFNESS: entry[2],
			WheelProperty.SHOCK_DAMPING: entry[3],
			WheelProperty.RIDE_HEIGHT: entry[4],
			WheelProperty.EFFECTIVE_RADIUS: wheel_radius,
			WheelProperty.MAX_STEER_ANGLE: deg_to_rad(max_steer_angle_degrees),
			WheelProperty.STEER_BIAS: entry[5],
			WheelProperty.INERTIA: wheel_inertia,
			WheelProperty.GRIP: 1.0,
		}

# A wheel with no ground contact produces no load, force or ground torque.
# Angular velocity is left alone so the wheel keeps spinning.
func _clear_wheel_contact(wheel: Wheel) -> void:
	wheel_states[wheel][WheelState.IN_CONTACT] = false
	wheel_states[wheel][WheelState.LOAD] = Vector3.ZERO
	wheel_states[wheel][WheelState.FORCE] = Vector3.ZERO
	wheel_states[wheel][WheelState.TORQUE] = 0.0
	wheel_states[wheel][WheelState.GROUND_BODY] = null
	wheel_states[wheel][WheelState.NORMALIZED_SLIP] = 0.0


# Touching the ground without being held up by it (a wall, or the spring extending faster
# than the damper allows): in contact, no load and no tyre force.
func _set_unloaded_contact(wheel: Wheel, contact_point: Vector3, centre_height: float, ground_body: Object) -> void:
	_clear_wheel_contact(wheel)
	wheel_states[wheel][WheelState.IN_CONTACT] = true
	wheel_states[wheel][WheelState.CONTACT_POINT] = contact_point
	wheel_states[wheel][WheelState.CENTER_HEIGHT] = centre_height
	wheel_states[wheel][WheelState.GROUND_BODY] = ground_body


## Wheel centre height (robot space Y) with the spring fully extended
func full_extension_height(wheel: Wheel) -> float:
	return wheel_properties[wheel][WheelProperty.EFFECTIVE_RADIUS] - wheel_properties[wheel][WheelProperty.RIDE_HEIGHT]

func calculate_suspension_load(spring_compression_delta, suspension_velocity, spring_stiffness, shock_damping):
	var spring_force: Vector3 = (
		spring_stiffness *
		-spring_compression_delta
	)
	var shock_force: Vector3 = (
		shock_damping *
		-suspension_velocity
	)
	return spring_force + shock_force

## Steering angle (rad, about the chassis' up axis) of a wheel. `steer` is -1 (full left) .. 1 (full right).
func get_steer_angle(wheel: Wheel, steer: float) -> float:
	return (
		-steer *
		wheel_properties[wheel][WheelProperty.MAX_STEER_ANGLE] *
		wheel_properties[wheel][WheelProperty.STEER_BIAS]
	)

## Friction coefficients of a wheel, including its grip multiplier
func get_longitudinal_friction(wheel: Wheel) -> float:
	return longitudinal_friction_coefficient * wheel_properties[wheel][WheelProperty.GRIP]

func get_lateral_friction(wheel: Wheel) -> float:
	return lateral_friction_coefficient * wheel_properties[wheel][WheelProperty.GRIP]

## `steer` is -1 (full left) .. 1 (full right).
## `wheel_inertias` optionally maps a Wheel to the inertia (kg m^2) that its tyre torque
## really has to move (e.g. a driven wheel with its share of the drivetrain). Those wheels'
## speeds are left to the caller's drivetrain; wheels not in it use their own inertia and
## are spun up and down by the ground here. `exclude` are bodies the ground check ignores (the
## rover itself).
var _ground_shape := CylinderShape3D.new()
var _ground_query := PhysicsShapeQueryParameters3D.new()


## The wheel's ground check for the rover at `rover_transform`: a cylinder the size of the
## wheel (axle along the steered axle) cast down the rover's -Y from its centre at
## suspension_top above the wheel's attachment point to CONTACT_TOLERANCE past full extension.
## Returns {hit, centre_height (robot space Y where it first touches), point, normal, velocity,
## body, started_inside (already touching at the top)}. Used by the physics every step and by
## the Robot to place the visible wheels where the rover is after the step.
func find_ground(wheel: Wheel, rover_transform: Transform3D, steer: float,
		space_state: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> Dictionary:
	var basis: Basis = rover_transform.basis
	var y_basis: Vector3 = basis.y
	var position: Vector3 = wheel_properties[wheel][WheelProperty.POSITION]
	var attach: Vector3 = rover_transform.origin + basis.x * position.x + basis.z * position.z
	var radius: float = wheel_properties[wheel][WheelProperty.EFFECTIVE_RADIUS]
	var full_extension: float = full_extension_height(wheel)
	var top: float = maxf(suspension_top, full_extension)
	var wheel_steer_angle: float = get_steer_angle(wheel, steer)
	var wheel_direction: Vector3 = -basis.z.rotated(y_basis, wheel_steer_angle)
	var axle: Vector3 = basis.x.rotated(y_basis, wheel_steer_angle)

	_ground_shape.radius = radius
	_ground_shape.height = wheel_width
	var cast_basis := Basis(wheel_direction, axle, wheel_direction.cross(axle))
	_ground_query.shape = _ground_shape
	_ground_query.collision_mask = ground_mask
	_ground_query.exclude = exclude
	_ground_query.transform = Transform3D(cast_basis, attach + y_basis * top)
	var reach: float = top - full_extension + CONTACT_TOLERANCE
	_ground_query.motion = -y_basis * reach
	var fractions: PackedFloat32Array = space_state.cast_motion(_ground_query)
	if fractions[1] >= 1.0:
		return {"hit": false}
	# The wheel stands where the cast first touches the ground (the same place the old ray hit
	# on flat ground); the surface is read there too
	var centre_height: float = top - reach * fractions[1]
	_ground_query.transform = Transform3D(cast_basis, attach + y_basis * centre_height)
	_ground_query.motion = Vector3.ZERO
	var info: Dictionary = space_state.get_rest_info(_ground_query)
	var centre: Vector3 = attach + y_basis * centre_height
	return {
		"hit": true,
		"centre_height": centre_height,
		"point": info.get("point", centre - y_basis * radius),
		"normal": info.get("normal", y_basis),
		"velocity": info.get("linear_velocity", Vector3.ZERO),
		"body": instance_from_id(info["collider_id"]) if info.has("collider_id") else null,
		"started_inside": fractions[0] <= 0.0,
	}


func simulate_suspensions(state, steer: float, wheel_inertias: Dictionary = {}, exclude: Array[RID] = []) -> void:
	var origin = state.transform.origin
	var x_basis = state.transform.basis.x
	var y_basis = state.transform.basis.y
	var z_basis = state.transform.basis.z

	for wheel in Wheel.values():
		#LGTM
		var offset = (
			x_basis * wheel_properties[wheel][WheelProperty.POSITION].x +
			z_basis * wheel_properties[wheel][WheelProperty.POSITION].z
		)

		var wheel_steer_angle: float = get_steer_angle(wheel, steer)
		var wheel_direction: Vector3 = -z_basis.rotated(y_basis, wheel_steer_angle)
		var ground: Dictionary = find_ground(wheel, state.transform, steer, state.get_space_state(), exclude)
		if not ground["hit"]:
			# Nothing within the suspension's travel
			_clear_wheel_contact(wheel)
			continue
		var centre_height: float = ground["centre_height"]
		var collision_point: Vector3 = ground["point"]
		var ground_normal: Vector3 = ground["normal"]
		var ground_velocity: Vector3 = ground["velocity"]
		var ground_body: Object = ground["body"]
		var full_extension: float = full_extension_height(wheel)

		if ground["started_inside"] and ground_normal.dot(y_basis) < WALL_NORMAL_LIMIT:
			# Already against a face taller than the suspension reaches: touching, not held up
			# (the wheel's bump stop on the rover body keeps it out of the face)
			_set_unloaded_contact(wheel, collision_point - origin, centre_height, ground_body)
			continue
		if centre_height <= full_extension:
			# Resting on the ground at full extension: touching, unloaded
			_set_unloaded_contact(wheel, collision_point - origin, full_extension, ground_body)
			continue

		var rotation_radius: Vector3 = (
			collision_point - (origin + state.transform.basis * state.center_of_mass)
		)
		# Velocity of the contact point relative to the ground under it (moving see-saw etc.)
		var contact_velocity: Vector3 = (
			state.linear_velocity + state.angular_velocity.cross(rotation_radius) - ground_velocity
		)
		var suspension_load: Vector3 = calculate_suspension_load(
			-y_basis * (centre_height - full_extension),  # Spring compression
			contact_velocity.project(y_basis),            # Vertical velocity component for damping
			wheel_properties[wheel][WheelProperty.SPRING_STIFFNESS],
			wheel_properties[wheel][WheelProperty.SHOCK_DAMPING]
		)

		if not suspension_load.dot(y_basis) > 0.0:
			# The damper outpulls the spring (wheel dropping away fast): touching, unloaded
			_set_unloaded_contact(wheel, collision_point - origin, centre_height, ground_body)
			continue

		wheel_states[wheel][WheelState.IN_CONTACT] = true

		wheel_states[wheel][WheelState.LOAD] = suspension_load
		wheel_states[wheel][RunningGear.WheelState.CONTACT_POINT] = collision_point - origin
		wheel_states[wheel][WheelState.CENTER_HEIGHT] = centre_height
		wheel_states[wheel][WheelState.GROUND_BODY] = ground_body

		var wheel_speed: float = (
			wheel_states[wheel][WheelState.ANGULAR_VELOCITY] *
			wheel_properties[wheel][WheelProperty.EFFECTIVE_RADIUS]
		)

		var free_rolling_speed: float = contact_velocity.dot(wheel_direction)

		# Slip ratio. The denominator is floored so it stays finite (and smooth) at a
		# standstill, where a spinning wheel on a stopped body used to give a hard 2.0.
		var slip_velocity: float = wheel_speed - free_rolling_speed
		var slip_ratio: float = slip_velocity / max(abs(free_rolling_speed), low_speed_threshold)

		var velocity_longitudinal = contact_velocity.dot(wheel_direction)
		var velocity_lateral = contact_velocity.dot(wheel_direction.rotated(y_basis, -PI/2.0))

		# lateral / |longitudinal| (the same for forwards and backwards), with the
		# denominator floored like the slip ratio. Zero speed gives zero slip angle.
		var slip_angle_gradient: float = velocity_lateral / max(abs(velocity_longitudinal), low_speed_threshold)

		# Both coefficients scale with the wheel's grip, so their ratio (mu_zero) is unchanged
		var longitudinal_friction: float = get_longitudinal_friction(wheel)
		var lateral_friction: float = get_lateral_friction(wheel)

		var normalized_slip_ratio: float = (
			longitudinal_stiffness *
			slip_ratio / (
				longitudinal_friction *
				suspension_load.dot(y_basis)
			)
		)
		var normalized_slip_angle: float = (
			cornering_stiffness *
			slip_angle_gradient / (
				lateral_friction *
				suspension_load.dot(y_basis)
			)
		)
		wheel_states[wheel][WheelState.NORMALIZED_SLIP] = normalized_slip_ratio
		var normalized_combined_slip: float = (
			sqrt(
				normalized_slip_ratio*normalized_slip_ratio +
				normalized_slip_angle*normalized_slip_angle
			)
		)

		var mu_zero: float = (
			cornering_stiffness *
			longitudinal_friction / (
				longitudinal_stiffness *
				lateral_friction
			)
		)
		var multiplier_value: float		= multiplier(normalized_combined_slip, mu_zero)
		var pacejka_value: float		= pacejka(normalized_combined_slip, pacejka_b, pacejka_c, pacejka_d, pacejka_e)
		var combined_slip_scaling_factor: float		= (
			pacejka_value
			/ max(
				sqrt(
					slip_ratio*slip_ratio +
					multiplier_value*multiplier_value *
					slip_angle_gradient*slip_angle_gradient
				),
				0.001
			)
		)

		var normalized_lateral_force: float = (
			multiplier_value
			* slip_angle_gradient
			* combined_slip_scaling_factor
		)
		var normalized_longitudinal_force: float = (
			slip_ratio
			* combined_slip_scaling_factor
		)

		var longitudinal_force_magnitude: float = (
			suspension_load.dot(y_basis) *
			longitudinal_friction *
			normalized_longitudinal_force
		)

		# The wheel is integrated explicitly (wheel speed -= torque / inertia * step), and
		# the tyre force grows as 1/speed, so a light wheel overshoots the ground speed
		# on every tick and the force flips sign (the jitter). Cap the force so a single
		# step can at most close part of the slip, never cross it.
		var wheel_radius_now: float = max(wheel_properties[wheel][WheelProperty.EFFECTIVE_RADIUS], 0.01)
		var wheel_inertia_now: float = wheel_inertias.get(wheel, wheel_properties[wheel][WheelProperty.INERTIA])
		var max_longitudinal_force: float = (
			LONGITUDINAL_STABILITY_FACTOR * wheel_inertia_now * abs(slip_velocity)
			/ (wheel_radius_now * wheel_radius_now * max(state.step, 0.0001))
		)
		longitudinal_force_magnitude = clamp(
			longitudinal_force_magnitude, -max_longitudinal_force, max_longitudinal_force
		)
		var longitudinal_force: Vector3 = wheel_direction * longitudinal_force_magnitude
		var lateral_force: Vector3 = (
			wheel_direction.rotated(y_basis, PI/2.0) *
			suspension_load.dot(y_basis) *
			lateral_friction *
			normalized_lateral_force
		)
		var total_force: Vector3 = (
			longitudinal_force + lateral_force
		)

		wheel_states[wheel][WheelState.FORCE] = total_force

		var wheel_torque = longitudinal_force.dot(wheel_direction) * wheel_properties[wheel][WheelProperty.EFFECTIVE_RADIUS]

		wheel_states[wheel][WheelState.TORQUE] = wheel_torque

		# Wheels listed in wheel_inertias are driven; the robot's drivetrain integrates them
		if not wheel_inertias.has(wheel):
			wheel_states[wheel][WheelState.ANGULAR_VELOCITY] -= (
				wheel_torque
				/ wheel_properties[wheel][WheelProperty.INERTIA]
				* state.step
			)


func multiplier(combined_normalized_slip: float, mu_zero: float) -> float:
	var result: float = 1.0
	if abs(combined_normalized_slip) <= 2.0*PI:
		result = 0.5*(1.0 + mu_zero) - 0.5*(1.0 - mu_zero) * cos(combined_normalized_slip / 2.0)
	return result

func pacejka(x: float, b: float, c: float, d: float, e: float) -> float:
	return d * sin(c * atan(b * x - e * (b * x - atan(b * x))))
