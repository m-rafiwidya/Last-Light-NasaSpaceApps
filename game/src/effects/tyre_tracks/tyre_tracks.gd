class_name TyreTracks

extends Node

## Tyre tracks that stay where the rovers drove for the whole session (nothing erases them on the
## Moon). RoverLevel adds one to the level (GraphicsSettings.surface_effects: High, Low; Off: none).
## Visual only: it reads the running gear's wheel states and writes nothing the physics uses.
##
## How it works (README "Tyre tracks"):
##   1. Every physics step, each rover wheel standing loaded on dusty ground (group `dusty_ground`,
##      like WheelDust) adds a point to the level's TrackLog every POINT_SPACING: where its tread
##      touches, how far along the wheel's own forward it has rolled, how deep it presses (load,
##      slip) and how sharp its grouser prints are (a spinning wheel smears them). A wheel off the
##      ground for more than a moment (GAP_TIME) starts a new run when it comes back.
##   2. TrackMap draws the log into textures (TrackRaster, on a worker thread): fine tiles near the
##      camera, a coarse map of the whole area.
##   3. The ground's own shader draws the tracks from those textures (tyre_tracks.gdshaderinc):
##      only materials of a `tyre_tracks_surface` (MoonTerrain's play tier, the test level's
##      TrackFloor) get them, so rovers, rocks and everything else never do.
## The log is kept per level scene for the session (TrackLog.for_level), so a level loaded again
## shows its tracks again. A save slot load or a new campaign empties it (SaveIndex): tracks aren't saved.

const POINT_SPACING: float = 0.08
## A wheel unloaded for a moment (a bump) keeps its run if it touches again within this long (s)
## and this near (m); longer, it was in the air, and starts a new run
const GAP_TIME: float = 0.15
const GAP_DISTANCE: float = 0.3
## A step this long (m) in one physics step isn't driving (at 240 steps a second 10 m/s is 4 cm):
## the rover was moved (reset, tests); a new run starts there
const JUMP: float = 0.5
## A wheel with this slip speed (m/s, tread over ground) or more leaves no grouser prints
const SMEAR_SLIP: float = 0.5
## Fine tiles: texels a side (with margins), how many at once, and how far from the camera (m)
const FINE_N: Dictionary = {GraphicsSettings.SurfaceEffects.HIGH: 512, GraphicsSettings.SurfaceEffects.LOW: 256}
const FINE_CAP: Dictionary = {GraphicsSettings.SurfaceEffects.HIGH: 48, GraphicsSettings.SurfaceEffects.LOW: 32}
const RADIUS: Dictionary = {GraphicsSettings.SurfaceEffects.HIGH: 40.0, GraphicsSettings.SurfaceEffects.LOW: 24.0}
## Coarse tiles (64 m): 0.25 m texels on High, 0.5 m on Low
const COARSE_N: Dictionary = {GraphicsSettings.SurfaceEffects.HIGH: 258, GraphicsSettings.SurfaceEffects.LOW: 130}
const RESIDENCY_INTERVAL: float = 0.25

var track_log: TrackLog
var map: TrackMap
var materials: Array[ShaderMaterial] = []
var rovers: Array = []
## Per rover, per wheel: [its last point (x, z, s), that point's index in the log, where it was a
## step ago (x, z), when it left the ground (s, or -1 on it)]
var _last: Dictionary = {}
var _time: float = 0.0
var _residency_at: float = 0.0
var _setting: GraphicsSettings.SurfaceEffects


func _init(setting: GraphicsSettings.SurfaceEffects = GraphicsSettings.SurfaceEffects.HIGH) -> void:
	name = "TyreTracks"
	_setting = setting
	# After the rovers' physics step, which finds where the wheels stand
	process_physics_priority = 20


func _ready() -> void:
	var level: Node = get_parent()
	var area := Rect2()
	for surface in get_tree().get_nodes_in_group(&"tyre_tracks_surface"):
		if not level.is_ancestor_of(surface):
			continue
		area = surface.tyre_tracks_area() if area.size == Vector2.ZERO else area.merge(surface.tyre_tracks_area())
		materials.append_array(surface.tyre_tracks_materials())
	if area.size == Vector2.ZERO:
		set_physics_process(false)
		set_process(false)
		return
	# Square, so the shader needs one size
	area.size = Vector2.ONE * maxf(area.size.x, area.size.y)
	track_log = TrackLog.for_level(level.scene_file_path, area.position, TrackMap.FINE_TILE)
	var gpu: bool = DisplayServer.get_name() != "headless"
	map = TrackMap.new(track_log, area, FINE_N[_setting], FINE_CAP[_setting], COARSE_N[_setting], RADIUS[_setting], gpu)
	for rover in level.find_children("*", "Robot", true, false):
		rovers.append(rover)
		_last[rover] = {}
	_bind_materials(gpu)


# The materials that draw the tracks: the textures (with a display), the area and tile sizes
func _bind_materials(gpu: bool) -> void:
	for material in materials:
		material.set_shader_parameter("tracks_enabled", gpu)
		if gpu:
			material.set_shader_parameter("tracks_fine", map.fine_texture)
			material.set_shader_parameter("tracks_coarse", map.coarse_texture)
			material.set_shader_parameter("tracks_pages", map.page_texture)
		material.set_shader_parameter("tracks_area", Vector3(map.area.position.x, map.area.position.y, map.area.size.x))
		material.set_shader_parameter("tracks_fine_info", Vector4(TrackMap.FINE_TILE, map.fine_n, map.fine_texel, map.pages_per_side))
		material.set_shader_parameter("tracks_coarse_info", Vector4(TrackMap.COARSE_TILE, map.coarse_n, map.coarse_texel, map.coarse_per_side))


## Turns the tracks off and on again (frame-rate comparisons: tools/measure_moon_fps.gd
## tracks_ab): off, the ground doesn't draw them and nothing is printed or drawn into the tiles
func set_active(on: bool) -> void:
	set_physics_process(on)
	set_process(on)
	for rover in _last:
		_last[rover].clear()
	for material in materials:
		material.set_shader_parameter("tracks_enabled", on and map.fine_texture != null)


func _physics_process(delta: float) -> void:
	_time += delta
	for rover in rovers:
		if is_instance_valid(rover):
			_sample(rover)


func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now >= _residency_at:
		_residency_at = now + RESIDENCY_INTERVAL
		map.update_residency(_focus())
	map.process(now)


# Where the fine tiles are kept around: the camera, else the first rover
func _focus() -> Vector2:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var at: Vector3 = camera.global_position if camera else (rovers[0].global_position if not rovers.is_empty() else Vector3.ZERO)
	return Vector2(at.x, at.z)


# One rover's wheels this physics step
func _sample(rover: Robot) -> void:
	var gear: RunningGear = rover.running_gear
	var up: Vector3 = rover.global_basis.y.normalized()
	var static_load: float = rover.mass * rover.get_gravity().length() / float(RunningGear.Wheel.size())
	var steer: float = rover.controller.steer if rover.controller else 0.0
	var last: Dictionary = _last[rover]
	for wheel in gear.wheel_states:
		var state: Dictionary = gear.wheel_states[wheel]
		var ground: Object = state[RunningGear.WheelState.GROUND_BODY]
		var wheel_load: float = (state[RunningGear.WheelState.LOAD] as Vector3).dot(up)
		if not (state[RunningGear.WheelState.IN_CONTACT] and wheel_load > 0.0 and is_instance_valid(ground)
				and ground is Node and (ground as Node).is_in_group(WheelDust.DUSTY_GROUP)):
			if last.has(wheel):
				if last[wheel][3] < 0.0:
					last[wheel][3] = _time
				elif _time - last[wheel][3] > GAP_TIME:
					last.erase(wheel)
			continue
		var contact: Vector3 = rover.global_position + state[RunningGear.WheelState.CONTACT_POINT]
		var here := Vector2(contact.x, contact.z)
		var axle: Vector3 = Basis(up, gear.get_steer_angle(wheel, steer)) * rover.global_basis.x.normalized()
		var forward: Vector3 = up.cross(axle)
		var radius: float = gear.wheel_properties[wheel][RunningGear.WheelProperty.EFFECTIVE_RADIUS]
		var hub_velocity: Vector3 = rover.linear_velocity + rover.angular_velocity.cross(contact - rover.global_position)
		var slip: float = absf(state[RunningGear.WheelState.ANGULAR_VELOCITY] * radius - hub_velocity.dot(forward))
		var depth: float = clampf(wheel_load / maxf(static_load, 0.001), 0.0, 1.5) / 1.5 * 0.8 + 0.2 * clampf(slip / SMEAR_SLIP, 0.0, 1.0)
		var lug: float = 1.0 - clampf(slip / SMEAR_SLIP, 0.0, 1.0)
		if last.has(wheel):
			var entry: Array = last[wheel]
			var from_step: float = here.distance_to(entry[2])
			var was_off: bool = entry[3] >= 0.0
			if from_step > JUMP or (was_off and (_time - entry[3] > GAP_TIME or here.distance_to(Vector2(entry[0].x, entry[0].y)) > GAP_DISTANCE)):
				last.erase(wheel)
			else:
				entry[2] = here
				entry[3] = -1.0
		if not last.has(wheel):
			var first: int = track_log.add_point(contact.x, contact.z, 0.0, depth, lug, -1)
			last[wheel] = [Vector3(contact.x, contact.z, 0.0), first, here, -1.0]
			continue
		var previous: Vector3 = last[wheel][0]
		var step := Vector2(contact.x - previous.x, contact.z - previous.y)
		if step.length() < POINT_SPACING:
			continue
		var s: float = previous.z + step.dot(Vector2(forward.x, forward.z).normalized())
		var index: int = track_log.add_point(contact.x, contact.z, s, depth, lug, last[wheel][1])
		map.on_segment(index)
		last[wheel][0] = Vector3(contact.x, contact.z, s)
		last[wheel][1] = index
