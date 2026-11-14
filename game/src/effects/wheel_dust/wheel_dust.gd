class_name WheelDust

extends Node3D

## Lunar dust thrown up by a rover's wheels: one GPUParticles3D per wheel
## (wheel_dust_particles.gdshader, drawn by wheel_dust_grain.gdshader). Visual only: it reads the
## running gear's wheel states and never writes anything the physics uses.
##
## A wheel sprays only while it stands loaded on dusty ground (a body in the group `dusty_ground`:
## the Moon terrain's Ground, the test level's floor; not the workshop floor, rocks, Kite, ramps or
## other rovers). How much: the tread's speed plus SLIP_WEIGHT times its slip speed (the tread
## sliding over the ground, along and across), over FULL_SPRAY_SPEED, times the wheel's load over
## its share of the rover's weight; nothing under MIN_SPEED, so nothing from a parked rover.
## The grains fly under the level's gravity (the physics space's, read every frame), with no drag,
## and land on the ground (add_ground_collider) instead of falling through it.
##
## RoverLevel gives every rover one (GraphicsSettings.surface_effects: High, Low with
## LOW_RATE_SCALE of the grains and a coarser collision field; Off: none).

const DUSTY_GROUP: StringName = &"dusty_ground"
## Render layer the dust's collision field sees: only the dusty ground's meshes (the Moon's play
## area chunks, the test level's floor). The rocks share the terrain's layer 10 but not this one:
## their multimesh covers the whole area (1.6 M triangles), too much to draw into the field.
const GROUND_RENDER_LAYER: int = 11
## Particles a second from one wheel at full spray (each one a clump of grains)
const MAX_RATE: float = 1400.0
const LOW_RATE_SCALE: float = 0.4
## Tread speed + SLIP_WEIGHT * slip speed (m/s) for full spray
const FULL_SPRAY_SPEED: float = 6.0
const SLIP_WEIGHT: float = 2.0
## Below this (m/s, the same sum) a wheel throws nothing
const MIN_SPEED: float = 0.15
## Fastest a grain leaves the wheel (m/s; wheel_dust_particles.gdshader speed_cap). It sets the
## longest flight (4.9 s on the Moon), so the particle slots: the Apollo rover's top speed was
## 3.6 m/s, and grains leave slower than the tread
const SPEED_CAP: float = 4.0
## From landing to gone (s)
const SETTLE_TIME: float = 0.3
## The collision field around the camera (m) and its resolution per setting
const GROUND_FIELD_SIZE: Vector3 = Vector3(64.0, 40.0, 64.0)

const PARTICLES_SHADER: Shader = preload("res://src/effects/wheel_dust/wheel_dust_particles.gdshader")
const GRAIN_SHADER: Shader = preload("res://src/effects/wheel_dust/wheel_dust_grain.gdshader")

var robot: Robot
## RunningGear.Wheel -> GPUParticles3D
var emitters: Dictionary = {}
## RunningGear.Wheel -> 0..1, this frame's spray (fraction of MAX_RATE * rate_scale)
var rates: Dictionary = {}
## Grains a second from one wheel at full spray, with the setting's scale
var max_rate: float = MAX_RATE
## Gravity the grains fly under (the level's), and their lifetime: the longest flight at it
var gravity: Vector3 = Vector3.ZERO
var lifetime: float = 0.0

var _grain_material: ShaderMaterial


func _init(low: bool = false) -> void:
	name = "WheelDust"
	max_rate = MAX_RATE * (LOW_RATE_SCALE if low else 1.0)


func _ready() -> void:
	robot = get_parent() as Robot
	# After the Robot's _process, which places the visible wheels for this frame
	process_priority = 10
	_grain_material = ShaderMaterial.new()
	_grain_material.shader = GRAIN_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _grain_material
	for wheel in RunningGear.Wheel.values():
		var particles := GPUParticles3D.new()
		particles.name = "Dust%d" % wheel
		particles.local_coords = false
		particles.amount_ratio = 1.0
		particles.explosiveness = 0.0
		particles.fixed_fps = 0
		particles.interpolate = false
		particles.collision_base_size = 0.01
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particles.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
		# Grains fly up to about 20 m on the Moon: never culled while the rover is near the view
		particles.visibility_aabb = AABB(Vector3(-25.0, -10.0, -25.0), Vector3(50.0, 35.0, 50.0))
		var material := ShaderMaterial.new()
		material.shader = PARTICLES_SHADER
		material.set_shader_parameter("speed_cap", SPEED_CAP)
		material.set_shader_parameter("settle_time", SETTLE_TIME)
		material.set_shader_parameter("emit_ratio", 0.0)
		particles.process_material = material
		particles.draw_pass_1 = quad
		add_child(particles)
		emitters[wheel] = particles
		rates[wheel] = 0.0
	_update_gravity()


## Turns the dust off and on again (frame-rate comparisons: tools/measure_moon_fps.gd dust_ab):
## off, the emitters are hidden (neither drawn nor simulated) and the rates aren't worked out
func set_active(on: bool) -> void:
	set_process(on)
	for wheel in emitters:
		emitters[wheel].emitting = on
		emitters[wheel].visible = on
		rates[wheel] = 0.0


## Longest a grain can be in the air under gravity g (m/s^2), plus settling
static func flight_lifetime(g: float) -> float:
	return 2.0 * SPEED_CAP / maxf(g, 0.1) + SETTLE_TIME + 0.2


## How much a wheel sprays (0..1): from its tread speed, slip speed (m/s) and load / its share of
## the rover's weight
static func spray_rate(tread_speed: float, slip_speed: float, load_fraction: float) -> float:
	var speed: float = absf(tread_speed) + SLIP_WEIGHT * absf(slip_speed)
	if speed < MIN_SPEED:
		return 0.0
	return clampf(speed / FULL_SPRAY_SPEED, 0.0, 1.0) * clampf(load_fraction, 0.0, 1.0)


## The physics space's gravity (the level's, SceneLoader._apply_level_gravity); a change in
## strength re-sizes the emitters (their grains' lifetime)
func _update_gravity() -> void:
	var g: Vector3 = robot.get_gravity()
	if g.is_equal_approx(gravity):
		return
	var resize: bool = absf(g.length() - gravity.length()) > 0.01 * maxf(g.length(), 0.1)
	gravity = g
	if resize:
		lifetime = flight_lifetime(g.length())
		for wheel in emitters:
			var particles: GPUParticles3D = emitters[wheel]
			particles.lifetime = lifetime
			particles.amount = ceili(max_rate * lifetime)
	for wheel in emitters:
		(emitters[wheel].process_material as ShaderMaterial).set_shader_parameter("gravity", g)


func _process(_delta: float) -> void:
	_update_gravity()
	_grain_material.set_shader_parameter("viewport_height", float(get_viewport().get_visible_rect().size.y))
	var gear: RunningGear = robot.running_gear
	var up: Vector3 = robot.global_basis.y.normalized()
	var static_load: float = robot.mass * gravity.length() / float(RunningGear.Wheel.size())
	var steer: float = robot.controller.steer if robot.controller else 0.0
	for wheel in emitters:
		var state: Dictionary = gear.wheel_states[wheel]
		var properties: Dictionary = gear.wheel_properties[wheel]
		var radius: float = properties[RunningGear.WheelProperty.EFFECTIVE_RADIUS]
		var spin: float = state[RunningGear.WheelState.ANGULAR_VELOCITY]
		var axle: Vector3 = Basis(up, gear.get_steer_angle(wheel, steer)) * robot.global_basis.x.normalized()
		var forward: Vector3 = up.cross(axle)
		var centre: Vector3 = robot.visual_wheel_centers.get(wheel, robot.wheel_centers.get(wheel, properties[RunningGear.WheelProperty.POSITION]))
		var hub: Vector3 = robot.to_global(centre)
		var hub_velocity: Vector3 = robot.linear_velocity + robot.angular_velocity.cross(hub - robot.global_position)

		var rate: float = 0.0
		if _on_dusty_ground(state):
			var wheel_load: float = (state[RunningGear.WheelState.LOAD] as Vector3).dot(up)
			var slip: float = Vector2(spin * radius - hub_velocity.dot(forward), hub_velocity.dot(axle)).length()
			rate = spray_rate(spin * radius, slip, wheel_load / maxf(static_load, 0.001))
		rates[wheel] = rate

		var material := emitters[wheel].process_material as ShaderMaterial
		material.set_shader_parameter("emit_ratio", rate * max_rate * lifetime / float(emitters[wheel].amount))
		material.set_shader_parameter("hub_position", hub)
		material.set_shader_parameter("hub_velocity", hub_velocity)
		material.set_shader_parameter("axle", axle)
		material.set_shader_parameter("wheel_up", up)
		material.set_shader_parameter("radius", radius)
		material.set_shader_parameter("width", gear.wheel_width)
		material.set_shader_parameter("spin", spin)


## In contact, loaded, on a dusty body
func _on_dusty_ground(state: Dictionary) -> bool:
	if not state[RunningGear.WheelState.IN_CONTACT]:
		return false
	if (state[RunningGear.WheelState.LOAD] as Vector3).length_squared() <= 0.0:
		return false
	var ground: Object = state[RunningGear.WheelState.GROUND_BODY]
	return is_instance_valid(ground) and ground is Node and (ground as Node).is_in_group(DUSTY_GROUP)


## The field the grains land on: a height field around the camera of the dusty ground's render
## layer, redrawn as the camera moves
static func add_ground_collider(level: Node3D, low: bool) -> GPUParticlesCollisionHeightField3D:
	var field := GPUParticlesCollisionHeightField3D.new()
	field.name = "DustGround"
	field.size = GROUND_FIELD_SIZE
	field.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256 if low else GPUParticlesCollisionHeightField3D.RESOLUTION_512
	field.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	field.follow_camera_enabled = true
	field.heightfield_mask = 1 << (GROUND_RENDER_LAYER - 1)
	level.add_child(field)
	return field
