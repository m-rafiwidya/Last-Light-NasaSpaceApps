class_name Car

extends RigidBody3D

@export var controller: Controller
@export var running_gear: RunningGear
@export var engine: CarEngine

@export var gear_ratios: Array[float] = [
	-2.00,  # Reverse gear
	2.07,
	1.56,
	1.20,
	0.95,
	0.77,
	0.63
]
@export var final_drive: float = 4.26
@export var clutch_torque_capacity: float = 621.0
@export var clutch_engagement_rate: float = 5.0
@export var brake_capacity: float = 1500.0
var transmission_inertia: float = 0.5
var differential_inertia: float = 0.5

const DRIVEN_WHEELS: Array = [RunningGear.Wheel.REAR_LEFT, RunningGear.Wheel.REAR_RIGHT]
const BRAKE_SLIP_GAIN: float = 5.0

# Drivetrain state
var current_gear: int = 1
var engine_angular_velocity: float = 0.0
var differential_angular_velocity: float = 0.0

var camera_mode: CameraMode = CameraMode.FOLLOW
var camera_rotation: Vector3 = Vector3.ZERO
var follow_camera_start_align: bool = true
var camera_shake: Vector3 = Vector3.ZERO

enum CameraMode{
	FOLLOW,
	BUMPER
}
@onready var camera: Dictionary = {
	CameraMode.FOLLOW : $FollowCameraPivot/FollowCamera,
	CameraMode.BUMPER : $BumperCamera
}

func _ready() -> void:
	$FollowCamera.set_as_top_level(true)
	Debug.current_car = self
	running_gear.update_wheel_properties()
	controller.discrete_callbacks["shift_up"] = func() -> void:
		if current_gear < gear_ratios.size() - 1:
			current_gear += 1
			running_gear.update_wheel_properties()

	controller.discrete_callbacks["shift_down"] = func() -> void:
		if current_gear > 0:
			current_gear -= 1
			running_gear.update_wheel_properties()

func _input(event) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask == MOUSE_BUTTON_MASK_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			follow_camera_start_align = false
			$FollowCameraReset.start()
			camera_rotation.y += event.relative.x * -0.005
			camera_rotation.x += event.relative.y * -0.005
			camera_rotation.y = wrapf(camera_rotation.y, -PI, PI)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta) -> void:
	camera_rotation.x = clamp(camera_rotation.x, -PI/2.0, 0)
	if follow_camera_start_align:
		camera_rotation *= pow(32, -delta)
	$FollowCameraPivot.rotation.y = camera_rotation.y
	$FollowCameraPivot.rotation.x = camera_rotation.x
	$FollowCameraPivot/FollowCamera.transform.origin = Vector3.ZERO
	$FollowCameraPivot/FollowCamera.transform.origin.z = 6.0
	$FollowCameraPivot/FollowCamera.transform.origin.y = 2.0 * (1.0 + sin(camera_rotation.x))
	var just_changed_camera: bool = false
	if Input.is_action_just_pressed("camera"):
		just_changed_camera = true
		camera_mode = CameraMode.values()[(int(camera_mode) + 1) % CameraMode.size()]
	if just_changed_camera:
		match camera_mode:
			CameraMode.FOLLOW:
				$BumperCamera.current = false
				$FollowCamera.current = true
			CameraMode.BUMPER:
				$FollowCamera.current = false
				$BumperCamera.current = true
	$FollowCamera.global_transform = $FollowCamera.global_transform.interpolate_with($FollowCameraPivot/FollowCamera.global_transform, delta * 20.0)


func _integrate_forces(state) -> void:
	var brake_torque: float = _sync_driven_wheels_and_get_brake_torque(state.step)
	running_gear.simulate_suspensions(state, controller)
	_step_drivetrain(state.step, brake_torque)
	_apply_wheel_forces(state)

# Brake torque for a single wheel, scaled by brake input and a speed-based ramp
# so the brake doesn't flip the wheel's direction at near-zero speed.
func _wheel_brake_torque(wheel: RunningGear.Wheel, step: float) -> float:
	return brake_capacity * controller.control_value[Controller.ControlValue.BRAKE] * \
			clamp(running_gear.wheel_states[wheel][RunningGear.WheelState.ANGULAR_VELOCITY] * step * BRAKE_SLIP_GAIN, -1.0, 1.0)

# Forces driven wheels to the differential speed (can be unstable at low speeds)
# and returns the combined brake torque acting on them.
func _sync_driven_wheels_and_get_brake_torque(step: float) -> float:
	var brake_torque: float = 0.0
	for wheel in DRIVEN_WHEELS:
		running_gear.wheel_states[wheel][RunningGear.WheelState.ANGULAR_VELOCITY] = differential_angular_velocity
		brake_torque += _wheel_brake_torque(wheel, step)
	return brake_torque

# Integrates engine and differential speeds through the clutch. Also brakes
# the undriven wheels directly, since they aren't part of the drivetrain.
func _step_drivetrain(step: float, brake_torque: float) -> void:
	var engine_output_torque = engine.get_engine_torque(engine_angular_velocity, controller, step)
	var driven_wheel_resistance_torque = brake_torque

	# Inertia seen at the differential/wheel speed. The transmission output shaft
	# spins at final_drive times wheel speed, so its inertia is reflected by
	# final_drive squared. Only driven wheels are coupled to the drivetrain.
	var total_drivetrain_inertia = differential_inertia + transmission_inertia * final_drive * final_drive
	for wheel in RunningGear.Wheel.values():
		if wheel in DRIVEN_WHEELS:
			driven_wheel_resistance_torque += running_gear.wheel_states[wheel][RunningGear.WheelState.TORQUE]
			total_drivetrain_inertia += running_gear.wheel_properties[wheel][RunningGear.WheelProperty.INERTIA]
		else:
			var free_wheel_resistance_torque = _wheel_brake_torque(wheel, step)
			running_gear.wheel_states[wheel][RunningGear.WheelState.ANGULAR_VELOCITY] -= free_wheel_resistance_torque / running_gear.wheel_properties[wheel][RunningGear.WheelProperty.INERTIA] * step

	# Clutch simulation parameters and calculations
	var combined_gear_ratio = gear_ratios[current_gear] * final_drive
	var clutch_speed_difference: float = engine_angular_velocity - differential_angular_velocity * combined_gear_ratio
	var clutch_engagement_factor: float = 1.0 - controller.control_value[Controller.ControlValue.CLUTCH]

	# Calculate clutch torque based on engagement and speed difference
	var max_clutch_torque: float = clutch_torque_capacity * clutch_engagement_factor * \
								clamp(abs(clutch_speed_difference) * step * clutch_engagement_rate, 0.0, 1.0)
	var max_transferable_torque: float = max(abs(engine_output_torque), abs(driven_wheel_resistance_torque))
	var actual_clutch_torque: float = sign(clutch_speed_difference) * min(max_transferable_torque, max_clutch_torque)

	# Update engine and differential angular velocities
	var engine_acceleration = (engine_output_torque - actual_clutch_torque) / engine.inertia * step
	var differential_acceleration = (actual_clutch_torque * combined_gear_ratio - driven_wheel_resistance_torque) / \
								(total_drivetrain_inertia) * step

	engine_angular_velocity += engine_acceleration
	differential_angular_velocity += differential_acceleration

# Applies suspension load and ground contact force for each wheel in contact
func _apply_wheel_forces(state) -> void:
	for wheel in RunningGear.Wheel.values():
		if not running_gear.wheel_states[wheel][RunningGear.WheelState.IN_CONTACT]:
			continue

		var wheel_position_offset = state.transform.basis * running_gear.wheel_properties[wheel][RunningGear.WheelProperty.POSITION]

		# Apply suspension load force
		state.apply_force(
			running_gear.wheel_states[wheel][RunningGear.WheelState.LOAD],
			wheel_position_offset
		)

		# Apply ground contact force
		state.apply_force(
			running_gear.wheel_states[wheel][RunningGear.WheelState.FORCE],
			running_gear.wheel_states[wheel][RunningGear.WheelState.CONTACT_POINT]
		)

func _on_follow_camera_reset_timeout():
	follow_camera_start_align = true
