class_name Robot

extends RigidBody3D

@export var controller: RobotController
@export var running_gear: RunningGear
@export var engine: RobotEngine

# Single fixed gear, used for both forward and reverse. The engine is rigidly
# coupled to the driven wheels (no clutch).
@export var gear_ratio: float = 1.0
@export var final_drive: float = 5.0
# Rolling resistance at the ground (N), applied through the driven wheels. It is
# what finally stops the robot once the motor's back-EMF braking has faded out, and
# it pulls the loaded top speed a little below the motor's no-load speed.
@export var rolling_resistance_force: float = 12.0
# Rotational inertias (kg m^2) of the transmission output shaft and differential
@export var transmission_inertia: float = 0.004
@export var differential_inertia: float = 0.01

# Follow camera offset behind the robot, scaled to the robot's size
@export var follow_camera_distance: float = 2.5
@export var follow_camera_height: float = 0.8

const DRIVEN_WHEELS: Array = [RunningGear.Wheel.REAR_LEFT, RunningGear.Wheel.REAR_RIGHT]
# Rolling resistance fades in over 1 / this rad/s of wheel speed so it can't
# flip the wheel's direction at near-zero speed.
const ROLLING_RESISTANCE_SLIP_GAIN: float = 0.5

# Drivetrain state
# Signed motor shaft speed (rad/s), positive = forward. Read by engine_sound.gd
var motor_angular_velocity: float = 0.0
# Torque at the motor shaft (Nm) this step. Read by engine_sound.gd
var motor_torque: float = 0.0
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
	Debug.current_robot = self
	running_gear.update_wheel_properties()
	controller.toggle_camera.connect(_on_controller_toggle_camera)


# Controller signals
func _on_controller_toggle_camera(value: bool) -> void:
	if not value:
		return
	camera_mode = CameraMode.values()[(int(camera_mode) + 1) % CameraMode.size()]
	match camera_mode:
		CameraMode.FOLLOW:
			$BumperCamera.current = false
			$FollowCamera.current = true
		CameraMode.BUMPER:
			$FollowCamera.current = false
			$BumperCamera.current = true


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
	$FollowCameraPivot/FollowCamera.transform.origin.z = follow_camera_distance
	$FollowCameraPivot/FollowCamera.transform.origin.y = follow_camera_height * (1.0 + sin(camera_rotation.x))

	$FollowCamera.global_transform = $FollowCamera.global_transform.interpolate_with($FollowCameraPivot/FollowCamera.global_transform, delta * 20.0)


func _integrate_forces(state) -> void:
	_sync_driven_wheels()
	running_gear.simulate_suspensions(state, controller.steer)
	_step_drivetrain(state.step)
	_apply_wheel_forces(state)

# Forces driven wheels to the differential speed (can be unstable at low speeds)
func _sync_driven_wheels() -> void:
	for wheel in DRIVEN_WHEELS:
		running_gear.wheel_states[wheel][RunningGear.WheelState.ANGULAR_VELOCITY] = differential_angular_velocity

# Integrates the differential speed. The DC motor is rigidly coupled to the driven
# wheels through the single gear, so its speed follows the wheels. The controller
# input is the motor voltage: full input drives the motor towards its no-load
# speed, which sets the robot's top speed, and no input lets back-EMF slow it down.
func _step_drivetrain(step: float) -> void:
	var combined_gear_ratio: float = gear_ratio * final_drive

	motor_angular_velocity = differential_angular_velocity * combined_gear_ratio
	motor_torque = engine.get_motor_torque(motor_angular_velocity, controller.desired_speed)
	var drive_torque: float = motor_torque * combined_gear_ratio

	# Resistance on the driven wheels: rolling resistance plus tyre reaction torque
	var driven_wheel_resistance_torque: float = (
		rolling_resistance_force * running_gear.wheel_radius *
		clamp(differential_angular_velocity * ROLLING_RESISTANCE_SLIP_GAIN, -1.0, 1.0)
	)

	# Inertia seen at the differential/wheel speed. The transmission output shaft
	# spins at final_drive times wheel speed, so its inertia is reflected by
	# final_drive squared; the engine by the combined ratio squared. Only driven
	# wheels are coupled to the drivetrain.
	var total_drivetrain_inertia: float = (
		differential_inertia +
		transmission_inertia * final_drive * final_drive +
		engine.inertia * combined_gear_ratio * combined_gear_ratio
	)
	for wheel in DRIVEN_WHEELS:
		driven_wheel_resistance_torque += running_gear.wheel_states[wheel][RunningGear.WheelState.TORQUE]
		total_drivetrain_inertia += running_gear.wheel_properties[wheel][RunningGear.WheelProperty.INERTIA]

	differential_angular_velocity += (drive_torque - driven_wheel_resistance_torque) / total_drivetrain_inertia * step

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
