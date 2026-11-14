class_name Car

extends RigidBody3D

@export var controller: CarController
@export var running_gear: RunningGear
@export var engine: CarEngine

# Single fixed gear, used for both forward and reverse. The engine is rigidly
# coupled to the driven wheels (no clutch).
@export var gear_ratio: float = 1.56
@export var final_drive: float = 4.26
# Top speed in both directions, in units per second. The controller's input is a
# fraction of this (1 = full speed forward, -1 = full speed backward, 0 = stop).
@export var max_speed: float = 20.0
# Speed error (units/s) at which the drivetrain applies full torque. Smaller
# values chase the target speed harder; larger values are gentler.
@export var speed_control_band: float = 4.0
var transmission_inertia: float = 0.5
var differential_inertia: float = 0.5

const DRIVEN_WHEELS: Array = [RunningGear.Wheel.REAR_LEFT, RunningGear.Wheel.REAR_RIGHT]

# Drivetrain state
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
	$FollowCameraPivot/FollowCamera.transform.origin.z = 6.0
	$FollowCameraPivot/FollowCamera.transform.origin.y = 2.0 * (1.0 + sin(camera_rotation.x))

	$FollowCamera.global_transform = $FollowCamera.global_transform.interpolate_with($FollowCameraPivot/FollowCamera.global_transform, delta * 20.0)


func _integrate_forces(state) -> void:
	_sync_driven_wheels()
	running_gear.simulate_suspensions(state, controller.steer)
	_step_drivetrain(state)
	_apply_wheel_forces(state)

# Forces driven wheels to the differential speed (can be unstable at low speeds)
func _sync_driven_wheels() -> void:
	for wheel in DRIVEN_WHEELS:
		running_gear.wheel_states[wheel][RunningGear.WheelState.ANGULAR_VELOCITY] = differential_angular_velocity

# Integrates the differential speed. The engine is rigidly coupled to the driven
# wheels through the single gear, so its speed follows the wheels (never below
# idle). The controller input is a desired speed: the drivetrain applies torque
# proportional to the error between it and the current forward speed, so it
# accelerates toward the target, and brakes (engine braking) when the target is
# lower, including when there is no input.
func _step_drivetrain(state) -> void:
	var step: float = state.step
	var combined_gear_ratio: float = gear_ratio * final_drive

	var forward_speed: float = state.linear_velocity.dot(-state.transform.basis.z)
	var target_speed: float = controller.desired_speed * max_speed
	# -1..1: how hard to push, and in which direction
	var throttle: float = clamp((target_speed - forward_speed) / speed_control_band, -1.0, 1.0)

	engine_angular_velocity = clamp(
		abs(differential_angular_velocity) * combined_gear_ratio,
		engine.idle_speed,
		engine.upper_redline
	)
	var engine_output_torque: float = engine.get_engine_torque(engine_angular_velocity, abs(throttle))
	var drive_torque: float = engine_output_torque * combined_gear_ratio * sign(throttle)

	# Resistance from the tyres on the driven wheels
	var driven_wheel_resistance_torque: float = 0.0

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
