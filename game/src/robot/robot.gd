class_name Robot

extends RigidBody3D

@export var controller: RobotController
## Mount a full set of parts (six standard wheels, motor, battery, mast camera, antenna and
## tool turret) when the rover is ready, so it can be driven straight away
@export var start_assembled: bool = false
# The rover kit chassis model. HotswapSockets with an `anchor` are moved onto its socket_* nodes.
@export var body_model: Node3D
# The rover's collision shape. At _ready it takes the body model's imported "Collision" shape
# (the chassis -convcolonly box, see rover_kit_import.gd); the scene's box is an editor stand-in.
@export var body_collision: CollisionShape3D
@export var running_gear: RunningGear
@export var engine: RobotEngine

# First-person view from the mast head: RoverVisuals pans and tilts the head from the mouse
# look and puts the pivot on its pivot_camera every frame; the camera sits at the pivot. A ray
# from the camera finds props to pick up.
@export var pivot: Node3D
@export var camera: Camera3D
@export var raycast: RayCast3D

# Sockets that hold the wheel parts. Each wheel is placed by the running gear
# (suspension travel) and takes its radius from the mounted WheelPart.
@export_group("Wheel Sockets")
@export var front_left_socket: HotswapSocket
@export var front_right_socket: HotswapSocket
@export var middle_left_socket: HotswapSocket
@export var middle_right_socket: HotswapSocket
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

# Single fixed gear between each wheel motor and its wheel, used for both forward and
# reverse (no clutch).
@export var gear_ratio: float = 1.0
@export var final_drive: float = 5.0
# Rolling resistance at the ground (N), applied through the driven wheels. It is
# what finally stops the robot once the motor's back-EMF braking has faded out, and
# it pulls the loaded top speed a little below the motor's no-load speed.
@export var rolling_resistance_force: float = 12.0
# Rotational inertias (kg m^2) of the transmission output shaft and differential
@export var transmission_inertia: float = 0.004
@export var differential_inertia: float = 0.01


# Six-wheel drive, Curiosity style
const DRIVEN_WHEELS: Array = [
	RunningGear.Wheel.FRONT_LEFT, RunningGear.Wheel.FRONT_RIGHT,
	RunningGear.Wheel.MIDDLE_LEFT, RunningGear.Wheel.MIDDLE_RIGHT,
	RunningGear.Wheel.REAR_LEFT, RunningGear.Wheel.REAR_RIGHT,
]
# Rolling resistance fades in over 1 / this rad/s of wheel speed so it can't
# flip the wheel's direction at near-zero speed.
const ROLLING_RESISTANCE_SLIP_GAIN: float = 0.5

# Drivetrain state (one motor per driven wheel, see _step_drivetrain)
# Average signed motor speed (rad/s) of the wheel motors, positive = forward. Read by engine_sound.gd
var motor_angular_velocity: float = 0.0
# Total torque (Nm) of the wheel motors this step. Read by engine_sound.gd
var motor_torque: float = 0.0

var wheel_sockets: Dictionary = {}
# Physics wheel centre (robot space) per RunningGear.Wheel, updated every physics frame. Read by RoverVisuals
var wheel_centers: Dictionary = {}

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


const STARTING_PARTS: Dictionary = {
	"wheel": preload("res://src/robot/socket/wheel_part.tscn"),
	"motor": preload("res://src/robot/socket/motor_part.tscn"),
	"battery": preload("res://src/robot/socket/battery_part.tscn"),
	"mast_head": preload("res://src/robot/socket/mast_head_part.tscn"),
	"antenna": preload("res://src/robot/socket/antenna_part.tscn"),
	"arm_tool": preload("res://src/robot/socket/arm_tool_part.tscn"),
}
# The reset puts the rover's origin this far above the ground under it (it rests at 0.10)
const RESET_HEIGHT: float = 0.25

var _reset_pending: bool = false


func _ready() -> void:
	controller.robot = self
	controller.reset_requested.connect(func() -> void: _reset_pending = true)
	_snap_sockets_to_anchors()
	_adopt_body_collision()
	running_gear.update_wheel_properties()
	wheel_sockets = {
		RunningGear.Wheel.FRONT_LEFT: front_left_socket,
		RunningGear.Wheel.FRONT_RIGHT: front_right_socket,
		RunningGear.Wheel.MIDDLE_LEFT: middle_left_socket,
		RunningGear.Wheel.MIDDLE_RIGHT: middle_right_socket,
		RunningGear.Wheel.REAR_LEFT: rear_left_socket,
		RunningGear.Wheel.REAR_RIGHT: rear_right_socket,
	}

	# The robot is on the props layer, so the pickup ray must not pick up the robot itself
	raycast.add_exception(self)
	for socket in find_children("*", "HotswapSocket", true, false):
		socket.part_mounted.connect(func(_part) -> void: _update_ray_exceptions())
		socket.part_unmounted.connect(func(_part) -> void: _update_ray_exceptions())
	_update_ray_exceptions()
	holder = ObjectHolder.new(self, pivot, camera)
	controller.interact.connect(_on_controller_interact)
	controller.primary.connect(_on_controller_primary)

	GameState.state_changed.connect(_on_game_state_changed)
	if start_assembled:
		_mount_starting_parts.call_deferred()
	controller.altitude_limit = RoverVisuals.CAMERA_PITCH_LIMIT
	camera.transform = Transform3D.IDENTITY


# Moves every HotswapSocket child that names an `anchor` onto that socket_* node, with zero
# rotation (ROVER_KIT.md 2.3): the chassis model's sockets, or the mast's and arm's, which
# RoverVisuals has built by now (children are ready before their parent). A `follow_anchor`
# socket is parented to its anchor so it moves with it. Runs before anything reads the sockets.
func _snap_sockets_to_anchors() -> void:
	for child in get_children():
		var socket := child as HotswapSocket
		if socket == null or socket.anchor.is_empty():
			continue
		var anchor_node := find_child(socket.anchor, true, false) as Node3D
		if anchor_node == null:
			push_error('Robot: no "%s" on the rover for %s' % [socket.anchor, socket.name])
			continue
		if socket.follow_anchor:
			socket.reparent(anchor_node, false)
			socket.transform = Transform3D.IDENTITY
			continue
		var local: Transform3D = global_transform.affine_inverse() * anchor_node.global_transform
		socket.transform = Transform3D(Basis.IDENTITY, local.origin)


# Copies the body model's "Collision" shape onto the robot's own CollisionShape3D (a shape
# only counts as a direct child of the RigidBody3D) and removes the model's copy.
func _adopt_body_collision() -> void:
	if body_model == null or body_collision == null:
		return
	var source := body_model.find_child("Collision", true, false) as CollisionShape3D
	if source == null:
		push_error("Robot: the body model has no Collision shape (is rover_kit_import.gd set?)")
		return
	body_collision.shape = source.shape
	body_collision.transform = global_transform.affine_inverse() * source.global_transform
	source.get_parent().remove_child(source)
	source.queue_free()


# The pickup ray ignores this rover's empty sockets (their trigger boxes would block it; there
# is nothing to see) and its mast head socket (the camera sits right next to it). Mounted
# parts stay visible to it, so the tooltip works on them from the mast view.
func _update_ray_exceptions() -> void:
	for socket in find_children("*", "HotswapSocket", true, false):
		var trigger: InteractTrigger = socket.get_trigger()
		if socket.part == null or socket.name == "MastHeadSocket":
			raycast.add_exception(trigger)
		else:
			raycast.remove_exception(trigger)


## True while this rover is the one being driven (or was the last one, while paused)
func is_driven() -> bool:
	return GameState.robot == self


# Puts a new part in every socket (deferred: the parts are added next to the rover, to its
# parent, which is still being set up during _ready). A part taken out later stays in the level.
func _mount_starting_parts() -> void:
	var plan: Array = [
		[front_left_socket, "wheel"], [front_right_socket, "wheel"], [middle_left_socket, "wheel"],
		[middle_right_socket, "wheel"], [rear_left_socket, "wheel"], [rear_right_socket, "wheel"],
		[motor_socket, "motor"], [battery_socket, "battery"],
		[find_child("MastHeadSocket", true, false), "mast_head"],
		[find_child("AntennaSocket", true, false), "antenna"],
		[find_child("ArmToolSocket", true, false), "arm_tool"],
	]
	for entry in plan:
		var socket := entry[0] as HotswapSocket
		if socket == null or socket.part:
			continue
		var part: HotswapPart = STARTING_PARTS[entry[1]].instantiate()
		get_parent().add_child(part)
		part.global_position = socket.global_position
		socket.mount(part)


# The robot's camera only takes over while this rover is being driven; otherwise the
# player's (or the main menu's, or the other rover's) camera is the current one.
func _on_game_state_changed(old_state, new_state) -> void:
	if not is_driven():
		return
	if new_state == GameState.State.IN_GAME_ROBOT:
		camera.make_current()
		Debug.current_robot = self
	elif old_state == GameState.State.IN_GAME_ROBOT:
		# Don't keep carrying a prop around while parked (PAUSED etc. keep it)
		if new_state == GameState.State.IN_GAME_PLAYER:
			holder.release()
			if is_instance_valid(GameState.player):
				GameState.player.camera.make_current()


# Controller signals
## Picking up, holding and throwing aim with the mast camera, so only in the mast view
func is_aiming() -> bool:
	var rig := get_node_or_null("CameraRig") as RoverCamera
	return rig == null or rig.view == RoverCamera.View.MAST


func _on_controller_interact(value: bool) -> void:
	if not value or not is_aiming():
		return

	if holder.held_object:
		holder.release()
	elif raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider is RigidBody3D:
			holder.pickup(collider as RigidBody3D)


func _on_controller_primary(value: bool) -> void:
	if value and is_aiming():
		holder.throw()


func _physics_process(delta: float) -> void:
	looking_at_object = (holder.held_object if holder.held_object else raycast.get_collider()) if is_aiming() else null

	holder.update(delta)
	_update_wheel_parts()
	_update_power_parts()


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


# Reads the radius and grip of each mounted WheelPart into the running gear, records where
# the running gear says each wheel centre is (hanging from the suspension) in wheel_centers,
# and moves the mounted part there, turned by the wheel's steering angle. RoverVisuals then
# moves the parts onto the visual linkage.
# An empty socket falls back to the running gear's default wheel_radius and grip 1.
func _update_wheel_parts() -> void:
	var inverse_basis: Basis = global_transform.basis.inverse()
	for wheel in wheel_sockets:
		var properties: Dictionary = running_gear.wheel_properties[wheel]
		var wheel_part: WheelPart = null
		if wheel_sockets[wheel]:
			wheel_part = wheel_sockets[wheel].part as WheelPart

		var radius: float = wheel_part.radius if wheel_part else running_gear.wheel_radius
		properties[RunningGear.WheelProperty.EFFECTIVE_RADIUS] = radius
		properties[RunningGear.WheelProperty.GRIP] = wheel_part.grip if wheel_part else 1.0

		# Height of the ground under the wheel in robot space. Without contact the
		# suspension is fully extended, i.e. at the end of the suspension ray.
		var ground_height: float = -properties[RunningGear.WheelProperty.RIDE_HEIGHT]
		if running_gear.wheel_states[wheel][RunningGear.WheelState.IN_CONTACT]:
			ground_height = (inverse_basis * running_gear.wheel_states[wheel][RunningGear.WheelState.CONTACT_POINT]).y

		var wheel_position: Vector3 = properties[RunningGear.WheelProperty.POSITION]
		wheel_position.y = ground_height + radius
		wheel_centers[wheel] = wheel_position
		if not wheel_part:
			continue
		wheel_part.global_position = to_global(wheel_position)

		# Steer about the chassis' up axis, starting from the mount point's orientation
		# (the part's own basis is identity, so the parent is the unsteered pose).
		var mount_basis: Basis = (wheel_part.get_parent() as Node3D).global_basis
		var steer_angle: float = running_gear.get_steer_angle(wheel, controller.steer)
		wheel_part.global_basis = Basis(global_transform.basis.y.normalized(), steer_angle) * mount_basis


# F: lifts the rover to RESET_HEIGHT above the ground under it, upright, facing the way it
# faced (its heading), at rest.
func _reset_upright(state: PhysicsDirectBodyState3D) -> void:
	_reset_pending = false
	var basis: Basis = state.transform.basis
	var forward: Vector3 = -basis.z
	if Vector2(forward.x, forward.z).length() < 0.1:
		# Nose straight up or down: take the heading from the roof instead
		forward = basis.y * signf(-forward.y)
	var yaw: float = atan2(-forward.x, -forward.z)
	var origin: Vector3 = state.transform.origin
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 3.0, origin + Vector3.DOWN * 10.0, 1)
	var hit: Dictionary = state.get_space_state().intersect_ray(query)
	if hit:
		origin.y = (hit["position"] as Vector3).y + RESET_HEIGHT
	else:
		origin.y += RESET_HEIGHT
	state.transform = Transform3D(Basis(Vector3.UP, yaw), origin)
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	for wheel in running_gear.wheel_states:
		running_gear.wheel_states[wheel][RunningGear.WheelState.ANGULAR_VELOCITY] = 0.0


func _integrate_forces(state) -> void:
	if _reset_pending:
		_reset_upright(state)
		return
	running_gear.simulate_suspensions(state, controller.steer, _get_wheel_inertias())
	_step_drivetrain(state.step)
	_apply_wheel_forces(state)

# Six-wheel drive with a motor in every wheel, like Curiosity. Each driven wheel gets its
# share (1 / DRIVEN_WHEELS.size()) of the RobotEngine motor behind the single gear, and
# keeps its own speed. Driving straight the wheels turn together, which is the same as
# one motor on a shared shaft; in a turn each wheel follows its own path instead of
# scrubbing against the others. The controller input is the motor voltage: full input
# drives the motors towards their no-load speed, which sets the robot's top speed, and
# no input lets back-EMF slow them down.
func _step_drivetrain(step: float) -> void:
	var combined_gear_ratio: float = gear_ratio * final_drive
	var share: float = 1.0 / DRIVEN_WHEELS.size()

	# The battery limits the voltage: none (or empty) means no drive, a nearly empty
	# one sags. The motors then draw energy from it in proportion to voltage * torque.
	supply_voltage_factor = _get_supply_voltage_factor()
	var voltage: float = controller.desired_speed * supply_voltage_factor

	motor_angular_velocity = 0.0
	motor_torque = 0.0
	electrical_power = 0.0
	for wheel in DRIVEN_WHEELS:
		var wheel_state: Dictionary = running_gear.wheel_states[wheel]
		var wheel_speed: float = wheel_state[RunningGear.WheelState.ANGULAR_VELOCITY]
		var wheel_motor_speed: float = wheel_speed * combined_gear_ratio
		var wheel_motor_torque: float = engine.get_motor_torque(wheel_motor_speed, voltage) * share
		electrical_power += engine.get_electrical_power(wheel_motor_torque / share, voltage) * share
		motor_angular_velocity += wheel_motor_speed * share
		motor_torque += wheel_motor_torque

		# This wheel's share of the rolling resistance, plus the tyre's reaction torque
		var radius: float = running_gear.wheel_properties[wheel][RunningGear.WheelProperty.EFFECTIVE_RADIUS]
		var resistance_torque: float = (
			rolling_resistance_force * share * radius *
			clamp(wheel_speed * ROLLING_RESISTANCE_SLIP_GAIN, -1.0, 1.0) +
			wheel_state[RunningGear.WheelState.TORQUE]
		)
		wheel_state[RunningGear.WheelState.ANGULAR_VELOCITY] = wheel_speed + (
			(wheel_motor_torque * combined_gear_ratio - resistance_torque)
			/ _get_wheel_drivetrain_inertia(wheel) * step
		)

	if battery:
		battery.drain(electrical_power * step / 3600.0)

# Inertia (kg m^2) seen at one driven wheel: the wheel plus its share of the transmission,
# differential and motor rotor. The transmission output shaft spins at final_drive times
# wheel speed, so its inertia is reflected by final_drive squared; the rotor by the
# combined ratio squared. Summed over the driven wheels this equals one shared drivetrain.
func _get_wheel_drivetrain_inertia(wheel) -> float:
	var combined_gear_ratio: float = gear_ratio * final_drive
	var shared: float = (
		differential_inertia +
		transmission_inertia * final_drive * final_drive +
		engine.rotor_inertia * combined_gear_ratio * combined_gear_ratio
	) / DRIVEN_WHEELS.size()
	return shared + running_gear.wheel_properties[wheel][RunningGear.WheelProperty.INERTIA]

# Inertia each driven wheel's tyre torque really has to move. The running gear uses it to
# keep the tyre force stable at low speed, and leaves these wheels' speeds to the drivetrain.
func _get_wheel_inertias() -> Dictionary:
	var inertias: Dictionary = {}
	for wheel in DRIVEN_WHEELS:
		inertias[wheel] = _get_wheel_drivetrain_inertia(wheel)
	return inertias

# 0..1 multiplier on the motor voltage, from the mounted battery's charge
func _get_supply_voltage_factor() -> float:
	if battery:
		return battery.get_voltage_factor()
	return 0.0 if require_battery else 1.0

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
