class_name Robot

extends RigidBody3D

@export var controller: RobotController
@export var running_gear: RunningGear
@export var engine: RobotEngine

# First-person view, same setup as the player: yaw on the pivot, pitch on the camera,
# and a ray from the camera that finds props to pick up.
@export var pivot: Node3D
@export var camera: Camera3D
@export var raycast: RayCast3D

# Sockets that hold the wheel parts. Each wheel is placed by the running gear
# (suspension travel) and takes its radius from the mounted WheelPart.
@export_group("Wheel Sockets")
@export var front_left_socket: HotswapSocket
@export var front_right_socket: HotswapSocket
@export var rear_left_socket: HotswapSocket
@export var rear_right_socket: HotswapSocket
@export_group("")

# Sockets for the motor and the battery. A mounted MotorPart replaces the engine's
# torque / speed values, a mounted BatteryPart supplies (and runs out of) charge.
@export_group("Power Sockets")
@export var motor_socket: HotswapSocket
@export var battery_socket: HotswapSocket
# When true the motor only gets voltage while a charged battery is mounted.
# When false an empty battery socket behaves as an unlimited supply (for testing).
@export var require_battery: bool = true
@export_group("")

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

var wheel_sockets: Dictionary = {}

# Power state
# Mounted battery / motor parts, null while their sockets are empty. Read by robot_hud.gd
var battery: BatteryPart = null
var motor_part: MotorPart = null
# Fraction (0..1) of the controller's input that reaches the motor as voltage this step
var supply_voltage_factor: float = 1.0
# Electrical power (W) the motor drew this step
var electrical_power: float = 0.0

# Object pickup (shared with the player, see ObjectHolder)
var holder: ObjectHolder
# Held object or whatever the pickup ray is aiming at (used by the robot HUD crosshair)
var looking_at_object: Node3D = null


func _ready() -> void:
	Debug.current_robot = self
	running_gear.update_wheel_properties()
	wheel_sockets = {
		RunningGear.Wheel.FRONT_LEFT: front_left_socket,
		RunningGear.Wheel.FRONT_RIGHT: front_right_socket,
		RunningGear.Wheel.REAR_LEFT: rear_left_socket,
		RunningGear.Wheel.REAR_RIGHT: rear_right_socket,
	}

	# The robot is on the props layer, so the pickup ray must not pick up the robot itself
	raycast.add_exception(self)
	holder = ObjectHolder.new(self, pivot, camera)
	controller.interact.connect(_on_controller_interact)
	controller.primary.connect(_on_controller_primary)

	GameState.state_changed.connect(_on_game_state_changed)


# The robot's camera only takes over while it is being driven; otherwise the
# player's (or the main menu's) camera is the current one.
func _on_game_state_changed(old_state, new_state) -> void:
	if new_state == GameState.State.IN_GAME_ROBOT:
		camera.make_current()
	elif old_state == GameState.State.IN_GAME_ROBOT:
		# Don't keep carrying a prop around while parked (PAUSED etc. keep it)
		if new_state == GameState.State.IN_GAME_PLAYER:
			holder.release()
			if is_instance_valid(GameState.player):
				GameState.player.camera.make_current()


# Controller signals
func _on_controller_interact(value: bool) -> void:
	if not value:
		return

	if holder.held_object:
		holder.release()
	elif raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider is RigidBody3D:
			holder.pickup(collider as RigidBody3D)


func _on_controller_primary(value: bool) -> void:
	if value:
		holder.throw()


func _physics_process(delta: float) -> void:
	looking_at_object = holder.held_object if holder.held_object else raycast.get_collider()

	holder.update(delta)
	_update_wheel_parts()
	_update_power_parts()

	camera.rotation.x = controller.camera_altitude
	pivot.rotation.y = controller.camera_azimuth


# Picks up the mounted motor and battery. The motor's values are copied into the
# engine only when the mounted part changes; the battery is read directly.
# An empty motor socket falls back to the engine's built-in values.
func _update_power_parts() -> void:
	var new_motor: MotorPart = null
	if motor_socket:
		new_motor = motor_socket.part as MotorPart
	if new_motor != motor_part:
		motor_part = new_motor
		engine.use_motor_part(motor_part)

	battery = null
	if battery_socket:
		battery = battery_socket.part as BatteryPart


# Reads the radius of each mounted WheelPart into the running gear and moves the
# part to where the running gear says its wheel is (hanging from the suspension),
# turned by the wheel's steering angle.
# An empty socket falls back to the running gear's default wheel_radius.
func _update_wheel_parts() -> void:
	var inverse_basis: Basis = global_transform.basis.inverse()
	for wheel in wheel_sockets:
		var properties: Dictionary = running_gear.wheel_properties[wheel]
		var wheel_part: WheelPart = null
		if wheel_sockets[wheel]:
			wheel_part = wheel_sockets[wheel].part as WheelPart

		var radius: float = wheel_part.radius if wheel_part else running_gear.wheel_radius
		properties[RunningGear.WheelProperty.EFFECTIVE_RADIUS] = radius
		if not wheel_part:
			continue

		# Height of the ground under the wheel in robot space. Without contact the
		# suspension is fully extended, i.e. at the end of the suspension ray.
		var ground_height: float = -properties[RunningGear.WheelProperty.RIDE_HEIGHT]
		if running_gear.wheel_states[wheel][RunningGear.WheelState.IN_CONTACT]:
			ground_height = (inverse_basis * running_gear.wheel_states[wheel][RunningGear.WheelState.CONTACT_POINT]).y

		var wheel_position: Vector3 = properties[RunningGear.WheelProperty.POSITION]
		wheel_position.y = ground_height + radius
		wheel_part.global_position = to_global(wheel_position)

		# Steer about the chassis' up axis, starting from the mount point's orientation
		# (the part's own basis is identity, so the parent is the unsteered pose).
		var mount_basis: Basis = (wheel_part.get_parent() as Node3D).global_basis
		var steer_angle: float = running_gear.get_steer_angle(wheel, controller.steer)
		wheel_part.global_basis = Basis(global_transform.basis.y.normalized(), steer_angle) * mount_basis


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

	# The battery limits the voltage: none (or empty) means no drive, a nearly empty
	# one sags. The motor then draws energy from it in proportion to voltage * torque.
	supply_voltage_factor = _get_supply_voltage_factor()
	var voltage: float = controller.desired_speed * supply_voltage_factor
	motor_torque = engine.get_motor_torque(motor_angular_velocity, voltage)
	var drive_torque: float = motor_torque * combined_gear_ratio

	electrical_power = engine.get_electrical_power(motor_torque, voltage)
	if battery:
		battery.drain(electrical_power * step / 3600.0)

	# Resistance on the driven wheels: rolling resistance plus tyre reaction torque.
	# The rolling resistance acts at the average radius of the mounted driven wheels.
	var driven_wheel_resistance_torque: float = (
		rolling_resistance_force * _get_driven_wheel_radius() *
		clamp(differential_angular_velocity * ROLLING_RESISTANCE_SLIP_GAIN, -1.0, 1.0)
	)

	# Inertia seen at the differential/wheel speed. The transmission output shaft
	# spins at final_drive times wheel speed, so its inertia is reflected by
	# final_drive squared; the engine by the combined ratio squared. Only driven
	# wheels are coupled to the drivetrain.
	var total_drivetrain_inertia: float = (
		differential_inertia +
		transmission_inertia * final_drive * final_drive +
		engine.rotor_inertia * combined_gear_ratio * combined_gear_ratio
	)
	for wheel in DRIVEN_WHEELS:
		driven_wheel_resistance_torque += running_gear.wheel_states[wheel][RunningGear.WheelState.TORQUE]
		total_drivetrain_inertia += running_gear.wheel_properties[wheel][RunningGear.WheelProperty.INERTIA]

	differential_angular_velocity += (drive_torque - driven_wheel_resistance_torque) / total_drivetrain_inertia * step

# 0..1 multiplier on the motor voltage, from the mounted battery's charge
func _get_supply_voltage_factor() -> float:
	if battery:
		return battery.get_voltage_factor()
	return 0.0 if require_battery else 1.0

# Average effective radius (m) of the driven wheels, set from the mounted WheelParts
func _get_driven_wheel_radius() -> float:
	var total: float = 0.0
	for wheel in DRIVEN_WHEELS:
		total += running_gear.wheel_properties[wheel][RunningGear.WheelProperty.EFFECTIVE_RADIUS]
	return total / DRIVEN_WHEELS.size()

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
