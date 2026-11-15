class_name LanderPlume

extends Node3D

## The descent engine's blast on the ground (lander_plume_particles.gdshader, drawn with the wheel
## dust's grains). Lander turns it on and off (active); it sprays only below START_ALTITUDE of
## ground under the bell, more and faster as the lander comes down. Off, nothing new leaves the
## ground and the grains in flight land within max_flight_time(): there is no air to hold them.

const START_ALTITUDE: float = 10.0
const FULL_ALTITUDE: float = 1.2
const MAX_RATE: float = 30000.0
const SPEED_MIN: float = 8.0
const SPEED_MAX: float = 26.0
const ANGLE_MIN: float = 1.0
const ANGLE_MAX: float = 6.0
const SETTLE_TIME: float = 0.3
## The fallback ground plane sits this far under the fitted one, so the collision field catches
## grains first where it reaches
const PLANE_DROP: float = 0.1
const FIT_RADIUS: float = 40.0
const FIT_STEP: float = 8.0

const PARTICLES_SHADER: Shader = preload("res://src/effects/lander_plume/lander_plume_particles.gdshader")
const GRAIN_SHADER: Shader = preload("res://src/effects/wheel_dust/wheel_dust_grain.gdshader")

var active: bool = false:
	set(on):
		active = on
		if not on and _material:
			rate = 0.0
			_material.set_shader_parameter("emit_ratio", 0.0)
## 0..1 this frame (fraction of MAX_RATE)
var rate: float = 0.0
## Bell exit to the ground under it (m)
var altitude: float = INF
var gravity: float = 1.62
var particles: GPUParticles3D
var _material: ShaderMaterial
var _grain_material: ShaderMaterial
var _terrain: Node
var _normal: Vector3 = Vector3.UP
var _plane_point: Vector3


func _ready() -> void:
	_terrain = _find_terrain()
	_grain_material = ShaderMaterial.new()
	_grain_material.shader = GRAIN_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _grain_material
	_material = ShaderMaterial.new()
	_material.shader = PARTICLES_SHADER
	var fixed: Dictionary = {"speed_min": SPEED_MIN, "speed_max": SPEED_MAX, "angle_min": ANGLE_MIN,
		"angle_max": ANGLE_MAX, "settle_time": SETTLE_TIME}
	for key in fixed:
		_material.set_shader_parameter(key, fixed[key])
	_material.set_shader_parameter("emit_ratio", 0.0)
	particles = GPUParticles3D.new()
	particles.name = "Grains"
	particles.local_coords = false
	particles.collision_base_size = 0.01
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-90.0, -20.0, -90.0), Vector3(180.0, 40.0, 180.0))
	particles.process_material = _material
	particles.draw_pass_1 = quad
	add_child(particles)
	_set_gravity(_space_gravity())
	fit_ground.call_deferred(global_position)


## Longest a grain can be in the air (s) under gravity g
static func max_flight_time(g: float) -> float:
	return 2.0 * SPEED_MAX * sin(deg_to_rad(ANGLE_MAX)) / maxf(g, 0.1) + 0.3


## Spray (0..1) at a bell-to-ground altitude
static func rate_at(h: float) -> float:
	return pow(clampf((START_ALTITUDE - h) / (START_ALTITUDE - FULL_ALTITUDE), 0.0, 1.0), 1.5)


func ground_height(x: float, z: float) -> float:
	if _terrain:
		return _terrain.height_at(x, z)
	return _plane_point.y - (_normal.x * (x - _plane_point.x) + _normal.z * (z - _plane_point.z)) / _normal.y


## Least-squares plane through the ground around `around` (the lander's landing spot)
func fit_ground(around: Vector3) -> void:
	_plane_point = Vector3(around.x, around.y - 0.35, around.z)
	if _terrain == null:
		return
	var sx := 0.0; var sz := 0.0; var sy := 0.0; var sxx := 0.0; var szz := 0.0; var sxz := 0.0; var sxy := 0.0; var szy := 0.0
	var count := 0.0
	var steps: int = int(FIT_RADIUS / FIT_STEP)
	for i in range(-steps, steps + 1):
		for j in range(-steps, steps + 1):
			var x: float = i * FIT_STEP
			var z: float = j * FIT_STEP
			var y: float = _terrain.height_at(around.x + x, around.z + z)
			sx += x; sz += z; sy += y; sxx += x * x; szz += z * z; sxz += x * z; sxy += x * y; szy += z * y
			count += 1.0
	var mean_y: float = sy / count
	# The grid is symmetric about `around`, so the slopes separate
	var gx: float = (sxy - sx * mean_y) / maxf(sxx - sx * sx / count, 1e-6)
	var gz: float = (szy - sz * mean_y) / maxf(szz - sz * sz / count, 1e-6)
	_normal = Vector3(-gx, 1.0, -gz).normalized()
	_plane_point = Vector3(around.x, mean_y - PLANE_DROP / _normal.y, around.z)
	_material.set_shader_parameter("ground_point", _plane_point)
	_material.set_shader_parameter("ground_normal", _normal)


func _process(_delta: float) -> void:
	var g: float = _space_gravity()
	if not is_equal_approx(g, gravity):
		_set_gravity(g)
	var at: Vector3 = global_position
	var ground: float = ground_height(at.x, at.z)
	altitude = at.y - ground
	rate = rate_at(altitude) if active else 0.0
	var h: float = clampf(altitude, 0.0, START_ALTITUDE)
	_material.set_shader_parameter("emit_ratio", rate * MAX_RATE * particles.lifetime / float(particles.amount))
	_material.set_shader_parameter("centre", Vector3(at.x, ground, at.z))
	_material.set_shader_parameter("ring_min", 0.4 + 0.08 * h)
	_material.set_shader_parameter("ring_max", 1.6 + 0.35 * h)
	_material.set_shader_parameter("speed_max", SPEED_MAX * lerpf(1.0, 0.6, h / START_ALTITUDE))
	_grain_material.set_shader_parameter("viewport_height", VideoSettings.render_height_3d(get_viewport()))


func _set_gravity(g: float) -> void:
	gravity = g
	particles.lifetime = max_flight_time(g) + SETTLE_TIME
	particles.amount = ceili(MAX_RATE * particles.lifetime)
	_material.set_shader_parameter("gravity", Vector3.DOWN * g)


func _space_gravity() -> float:
	if not is_inside_tree():
		return gravity
	var space: RID = get_world_3d().space
	return float(PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY))


func _find_terrain() -> Node:
	var node: Node = get_parent()
	while node:
		var terrain: Node = node.get_node_or_null("Terrain")
		if terrain and terrain.has_method("height_at"):
			return terrain
		node = node.get_parent()
	return null
