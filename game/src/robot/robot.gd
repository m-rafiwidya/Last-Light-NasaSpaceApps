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
## Two spotlights on the chassis front (hidden = off); L toggles them while driving
@export var headlights: Node3D

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
# Mass and rolling resistance (sources in docs/SCIENCE_AND_DATA.md, "Rover mass and driving").
# Total mass = CHASSIS_MASS + every mounted part's own mass; the standard kit (six 3 kg wheels,
# five 5 kg parts) makes REFERENCE_MASS, which the motor, springs and inertia were tuned for.
const CHASSIS_MASS: float = 37.0
const REFERENCE_MASS: float = 80.0
const REFERENCE_INERTIA: Vector3 = Vector3(8.0, 13.0, 8.0)
# Rolling resistance coefficient (force / weight): loose regolith (RoverLevel.loose_regolith),
# else a hard floor. A lugged (high-grip) tread multiplies it.
const ROLLING_RESISTANCE_REGOLITH: float = 0.12
const ROLLING_RESISTANCE_HARD_FLOOR: float = 0.0153
const LUGGED_TREAD_ROLLING_FACTOR: float = 1.6
# Always-on electronics (avionics, radio, cameras, thermal control), W: drawn from the battery
# whenever one is mounted and charged and Kite isn't on the charging pad, moving or not
const ELECTRONICS_POWER: float = 240.0
# Electronics-bay heater, W: drawn on top while heater_requested (MissionDirector: Kite in an
# active cold zone with the heater fitted) and the battery powers Kite
const HEATER_POWER: float = 500.0
# Rolling resistance, applied through the driven wheels as a Coulomb friction torque (each
# wheel: coefficient * its tread factor * a sixth of the weight): it opposes the wheels' turning
# and holds them still while the other torques on them are smaller (a parked rover stays put up
# to about atan(coefficient)). It is what finally stops the robot once back-EMF braking has
# faded out, and it pulls the top speed below the motor's no-load speed, more so when loaded.
var rolling_resistance_coefficient: float = ROLLING_RESISTANCE_HARD_FLOOR
# Automatic brake: once there is no throttle (|desired_speed| under brake_input_deadzone) and the
# rover is slower than brake_speed (m/s), or rolls back against the way it was last driven (hill
# hold), every wheel is held by a Coulomb brake of up to brake_torque (Nm per wheel: 25, about 3
# times what a 45 degree slope needs on Earth). It stays on until there is throttle again, also
# if something knocks the rover faster (it starts on, like a parked car), so a parked rover can't
# run away; coasting on in the direction it was driven is unchanged until it slows to brake_speed.
@export var auto_brake: bool = true
@export var brake_torque: float = 25.0
@export var brake_speed: float = 0.3
@export var brake_input_deadzone: float = 0.02
# Traction control (see _update_traction_factors): while a wheel's drive torque pushes its
# normalized slip (RunningGear.WheelState.NORMALIZED_SLIP, tyre force peaks near 2.7) past
# traction_slip_target, the torque is scaled down linearly, to nothing at traction_slip_limit,
# per axle, eased by traction_response. Past the peak the tyre loses force and sideways grip,
# so the rover would spin round; on Earth the motors rarely get there.
@export var traction_control: bool = true
@export var traction_slip_target: float = 1.0
@export var traction_slip_limit: float = 2.0
# How fast (1/s) each wheel's torque factor follows its target
@export var traction_response: float = 60.0
# Rotational inertias (kg m^2) of the transmission output shaft and differential
@export var transmission_inertia: float = 0.004
@export var differential_inertia: float = 0.01


# Six-wheel drive, Curiosity style
const DRIVEN_WHEELS: Array = [
	RunningGear.Wheel.FRONT_LEFT, RunningGear.Wheel.FRONT_RIGHT,
	RunningGear.Wheel.MIDDLE_LEFT, RunningGear.Wheel.MIDDLE_RIGHT,
	RunningGear.Wheel.REAR_LEFT, RunningGear.Wheel.REAR_RIGHT,
]
# Left / right pairs, for traction control's select-low
const AXLES: Array = [
	[RunningGear.Wheel.FRONT_LEFT, RunningGear.Wheel.FRONT_RIGHT],
	[RunningGear.Wheel.MIDDLE_LEFT, RunningGear.Wheel.MIDDLE_RIGHT],
	[RunningGear.Wheel.REAR_LEFT, RunningGear.Wheel.REAR_RIGHT],
]
# Drivetrain state (one motor per driven wheel, see _step_drivetrain)
# Traction control: 0..1 multiplier on each driven wheel's motor torque. Read by the HUD.
var traction_factors: Dictionary = {}
# Average signed motor speed (rad/s) of the wheel motors, positive = forward. Read by engine_sound.gd
var motor_angular_velocity: float = 0.0
# Total torque (Nm) of the wheel motors this step. Read by engine_sound.gd
var motor_torque: float = 0.0
## The nearest the camera's near plane may be for its far plane (RoverCamera keeps to it)
var min_camera_near: float = 0.0
## True while the automatic brake holds the wheels (see auto_brake). Read by the robot HUD.
var braking: bool = true
# The direction (+1 forwards, -1 backwards) of the last throttle, for the brake's hill hold
var _last_drive_sign: float = 1.0
# Moving back against the last throttle faster than this (m/s) counts as rolling back
const ROLL_BACK_SPEED: float = 0.05

var wheel_sockets: Dictionary = {}
# Physics wheel centre (robot space) per RunningGear.Wheel, from the last physics step's ground
# check, updated every physics frame (consistent with the wheels' IN_CONTACT)
var wheel_centers: Dictionary = {}
# Where the visible wheels go (robot space): the same ground check, run every frame from the
# rover's pose after the physics step, so the wheels match the ground as it is drawn (also
# moving ground, like the see-saw). Read by RoverVisuals.
var visual_wheel_centers: Dictionary = {}

# Power state
# Mounted battery / motor parts, null while their sockets are empty. Read by robot_hud.gd
var battery: BatteryPart = null
var motor_part: MotorPart = null
# Fraction (0..1) of the controller's input that reaches the motor as voltage this step
var supply_voltage_factor: float = 1.0
# Electrical power (W) the motor drew this step, and the motors' shaft power (W, driving only)
var electrical_power: float = 0.0
var mechanical_power: float = 0.0
# The electronics' draw this step (W), and whether the charging pad powers them instead (set by ChargingPad)
var electronics_power: float = 0.0
var external_power: bool = false
var heater_power: float = 0.0
var heater_requested: bool = false
# Mounted part mass (kg) and the part on the cargo mount's (kg). Read by robot_hud.gd
var parts_mass: float = 0.0
var cargo_mass: float = 0.0
var _sockets: Array = []

# Object pickup (shared with the player, see ObjectHolder)
var holder: ObjectHolder
## Whether the mast camera picks things up here (the level's rover_pickup: off on the Moon,
## where the rover only carries what's on its cargo mount)
var pickup_enabled: bool = true
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
# A wheel-sized collision cylinder per wheel on the rover body: the wheel at the top of its
# travel (centred at RunningGear.suspension_top above its attachment point), i.e. the end-of-
# travel stop. The ground check finds anything lower than that from above, so the stops only
# meet faces taller than the wheel can reach and keep the wheels out of them; they never touch
# during normal suspension travel (at 0.12 m they hit the foot of the ramp whenever the front
# suspension compressed 7 cm). Mass, centre of mass and inertia are set explicitly, so the
# shapes don't change them.

var _reset_pending: bool = false

## True while the headlights are on
var headlights_on: bool = false:
	set(value):
		headlights_on = value
		if headlights:
			headlights.visible = value


func _ready() -> void:
	controller.robot = self
	controller.reset_requested.connect(func() -> void: _reset_pending = true)
	controller.lights_toggle.connect(func() -> void: headlights_on = not headlights_on)
	headlights_on = headlights_on
	_add_wheel_bump_stops()
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
	_sockets = find_children("*", "HotswapSocket", true, false)
	for socket in _sockets:
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
	# The level's camera range (RoverLevel.camera_far)
	var level: Node = get_parent()
	while level and not level.get("camera_far") is float:
		level = level.get_parent()
	if level:
		camera.far = level.camera_far
		min_camera_near = RoverLevel.near_for_far(0.0, camera.far)
		camera.near = maxf(camera.near, min_camera_near)
		# and its suspension (RoverLevel.rover_suspension)
		if level.get("rover_suspension") is Dictionary:
			apply_suspension(level.rover_suspension)
		# and whether the mast camera may pick things up (RoverLevel.rover_pickup)
		if level.get("rover_pickup") is bool:
			pickup_enabled = level.rover_pickup
		if level.get("loose_regolith") is bool and level.loose_regolith:
			rolling_resistance_coefficient = ROLLING_RESISTANCE_REGOLITH
	_update_mass()


## Sets the running gear's suspension to the scene's values with `overrides` (RunningGear
## property name: value, e.g. a level's rover_suspension) on top
func apply_suspension(overrides: Dictionary) -> void:
	running_gear.apply_suspension(overrides)


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


func _add_wheel_bump_stops() -> void:
	running_gear.update_wheel_properties()
	for wheel in running_gear.wheel_properties:
		var properties: Dictionary = running_gear.wheel_properties[wheel]
		var cylinder := CylinderShape3D.new()
		cylinder.radius = properties[RunningGear.WheelProperty.EFFECTIVE_RADIUS]
		cylinder.height = running_gear.wheel_width
		var stop := CollisionShape3D.new()
		stop.name = "WheelBumpStop%d" % wheel
		stop.shape = cylinder
		var position: Vector3 = properties[RunningGear.WheelProperty.POSITION]
		# Cylinder axis (Y) along the axle (X)
		stop.transform = Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(position.x, running_gear.suspension_top, position.z))
		add_child(stop)


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
	if not value:
		return
	# Cargo delivery first (IRIS_KIT.md 8): E in a port's window
	var delivery := get_node_or_null("CargoDelivery") as CargoDelivery
	if delivery and delivery.handle_interact():
		return
	if not is_aiming() or not pickup_enabled:
		return

	if holder.held_object:
		holder.release()
	elif raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider is RigidBody3D:
			holder.pickup(collider as RigidBody3D)


func _on_controller_primary(value: bool) -> void:
	if value and is_aiming() and pickup_enabled:
		holder.throw()


func _physics_process(delta: float) -> void:
	looking_at_object = (holder.held_object if holder.held_object else raycast.get_collider()) if is_aiming() else null

	holder.update(delta)
	_update_wheel_parts()
	_update_power_parts()
	_update_mass()


# Total mass follows the mounted parts (mounted parts are frozen, so the engine ignores theirs);
# the inertia scales with it
func _update_mass() -> void:
	var total: float = 0.0
	var cargo: float = 0.0
	for socket in _sockets:
		var part := socket.part as HotswapPart
		if part:
			total += part.mass
			if part.part_type == HotswapPart.PartType.CARGO:
				cargo += part.mass
	parts_mass = total
	cargo_mass = cargo
	var new_mass: float = CHASSIS_MASS + total
	if not is_equal_approx(mass, new_mass):
		mass = new_mass
		inertia = REFERENCE_INERTIA * (new_mass / REFERENCE_MASS)


# Visible wheel centres for this frame: the physics' ground check, run from where the rover is
# now (after the physics step), for each wheel
func _process(_delta: float) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	for wheel in running_gear.wheel_properties:
		var centre: Vector3 = running_gear.wheel_properties[wheel][RunningGear.WheelProperty.POSITION]
		var ground: Dictionary = running_gear.find_ground(wheel, global_transform, controller.steer, space, exclude)
		centre.y = ground["centre_height"] if ground["hit"] else running_gear.full_extension_height(wheel)
		visual_wheel_centers[wheel] = centre


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
	for wheel in wheel_sockets:
		var properties: Dictionary = running_gear.wheel_properties[wheel]
		var wheel_part: WheelPart = null
		if wheel_sockets[wheel]:
			wheel_part = wheel_sockets[wheel].part as WheelPart

		var radius: float = wheel_part.radius if wheel_part else running_gear.wheel_radius
		properties[RunningGear.WheelProperty.EFFECTIVE_RADIUS] = radius
		properties[RunningGear.WheelProperty.GRIP] = wheel_part.grip if wheel_part else 1.0

		# Physics wheel centre: where the step's ground check stopped, or fully extended
		var wheel_position: Vector3 = properties[RunningGear.WheelProperty.POSITION]
		wheel_position.y = running_gear.full_extension_height(wheel)
		if running_gear.wheel_states[wheel][RunningGear.WheelState.IN_CONTACT]:
			wheel_position.y = running_gear.wheel_states[wheel][RunningGear.WheelState.CENTER_HEIGHT]
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
	running_gear.simulate_suspensions(state, controller.steer, _get_wheel_inertias(), [get_rid()])
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
	mechanical_power = 0.0
	var weight_share: float = mass * get_gravity().length() * share
	var throttle: bool = absf(controller.desired_speed) >= brake_input_deadzone
	if throttle:
		_last_drive_sign = signf(controller.desired_speed)
	var rolling_back: bool = linear_velocity.dot(-global_basis.z) * _last_drive_sign < -ROLL_BACK_SPEED
	braking = auto_brake and not throttle and (braking or rolling_back or linear_velocity.length() < brake_speed)
	var torques: Dictionary = {}
	for wheel in DRIVEN_WHEELS:
		var wheel_motor_speed: float = running_gear.wheel_states[wheel][RunningGear.WheelState.ANGULAR_VELOCITY] * combined_gear_ratio
		torques[wheel] = engine.get_motor_torque(wheel_motor_speed, voltage) * share
	_update_traction_factors(torques, step)
	for wheel in DRIVEN_WHEELS:
		var wheel_state: Dictionary = running_gear.wheel_states[wheel]
		var wheel_speed: float = wheel_state[RunningGear.WheelState.ANGULAR_VELOCITY]
		var wheel_motor_speed: float = wheel_speed * combined_gear_ratio
		var wheel_motor_torque: float = torques[wheel] * traction_factors[wheel]
		electrical_power += engine.get_electrical_power(wheel_motor_torque / share, wheel_motor_speed) * share
		mechanical_power += maxf(0.0, wheel_motor_torque * wheel_motor_speed)
		motor_angular_velocity += wheel_motor_speed * share
		motor_torque += wheel_motor_torque

		# The motor and the tyre's reaction turn the wheel; this wheel's share of the rolling
		# resistance and the brake are Coulomb friction: they stop the wheel within the step if
		# they can, and otherwise take off their full torque against its turning
		var radius: float = running_gear.wheel_properties[wheel][RunningGear.WheelProperty.EFFECTIVE_RADIUS]
		var inertia: float = _get_wheel_drivetrain_inertia(wheel)
		var free_speed: float = wheel_speed + (
			(wheel_motor_torque * combined_gear_ratio - wheel_state[RunningGear.WheelState.TORQUE])
			/ inertia * step
		)
		var wheel_part: WheelPart = wheel_sockets[wheel].part as WheelPart if wheel_sockets.get(wheel) else null
		var tread: float = LUGGED_TREAD_ROLLING_FACTOR if wheel_part and wheel_part.lugged else 1.0
		var rolling_force: float = rolling_resistance_coefficient * tread * weight_share
		var friction_torque: float = rolling_force * radius + (brake_torque if braking else 0.0)
		var friction_change: float = friction_torque / inertia * step
		wheel_state[RunningGear.WheelState.ANGULAR_VELOCITY] = (
			0.0 if absf(free_speed) <= friction_change else free_speed - signf(free_speed) * friction_change
		)

	var powered: bool = battery != null and not battery.is_empty() and not external_power
	electronics_power = ELECTRONICS_POWER if powered else 0.0
	heater_power = HEATER_POWER if powered and heater_requested else 0.0
	if battery:
		battery.drain((electrical_power + electronics_power + heater_power) * step / 3600.0)

# Traction control. Each driven wheel's target factor: while its motor drives it (torque the
# way the wheel turns, or from a standstill) and that torque adds to the slip, from 1 at
# traction_slip_target down to 0 at traction_slip_limit; otherwise 1. Braking torque (back-EMF,
# reverse throttle against the wheel's turning) is never limited, so a parked rover holds on a
# slope as before. Both wheels of an axle then take the lower target of the two that are on
# the ground (select-low), so left and right push equally and uneven grip (a lifting front
# wheel under hard acceleration) can't yaw the rover. Factors ease towards their targets.
func _update_traction_factors(torques: Dictionary, step: float) -> void:
	var targets: Dictionary = {}
	for wheel in DRIVEN_WHEELS:
		var state: Dictionary = running_gear.wheel_states[wheel]
		var slip: float = state[RunningGear.WheelState.NORMALIZED_SLIP]
		var torque: float = torques[wheel]
		targets[wheel] = 1.0
		if traction_control and slip * torque > 0.0 and torque * state[RunningGear.WheelState.ANGULAR_VELOCITY] >= 0.0:
			targets[wheel] = clampf((traction_slip_limit - absf(slip)) / (traction_slip_limit - traction_slip_target), 0.0, 1.0)
	for axle in AXLES:
		var target: float = 1.0
		for wheel in axle:
			if running_gear.wheel_states[wheel][RunningGear.WheelState.IN_CONTACT]:
				target = minf(target, targets[wheel])
		for wheel in axle:
			traction_factors[wheel] = move_toward(traction_factors.get(wheel, 1.0), target, traction_response * step)


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

		# Push back on a movable body the wheel stands on (the see-saw plank, a crate)
		var ground := running_gear.wheel_states[wheel][RunningGear.WheelState.GROUND_BODY] as RigidBody3D
		if ground and not ground.freeze:
			var contact: Vector3 = state.transform.origin + running_gear.wheel_states[wheel][RunningGear.WheelState.CONTACT_POINT]
			PhysicsServer3D.body_apply_force(ground.get_rid(),
				-(running_gear.wheel_states[wheel][RunningGear.WheelState.LOAD] + running_gear.wheel_states[wheel][RunningGear.WheelState.FORCE]),
				contact - ground.global_position)
