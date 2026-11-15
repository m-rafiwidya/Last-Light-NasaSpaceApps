class_name ThermalSensor

extends Node3D

## The temperature pair (plan item D): Kite's thermal turret (catalog `arm_tool_thermal` on its
## ArmToolSocket) is a radiometer, so it reads the ground where the mast camera aims, up to RANGE m
## away. E (interact_use) in the mast view takes a reading: SHADE when the surface faces away from the
## sun (LunarSky.sun_direction()) or a ray from that spot toward it is blocked by natural ground
## (terrain, rocks; man-made objects never count), otherwise SUN.
##
## It completes no objective: MissionDirector listens to `reading_taken` and, through `message_source`,
## writes what the subtitle says after the temperature. Readings live on this node only (not saved)
## and are cleared when a mission starts.
## Place one anywhere in the Moon level; it finds the sky itself. `highlight_node` is for Guidance.

signal reading_taken(kind: String, celsius: float, point: Vector3)
signal pair_completed

const GROUP: StringName = &"thermal_sensor"
const TURRET: String = "arm_tool_thermal"
const RANGE: float = 8.0
const AIM_MASK: int = 1 | 2           # ground and IRIS (Kite itself is excluded from the aim)
const SHADOW_MASK: int = 1            # world; only its natural colliders cast shade (is_natural)
# Simulated values, swap for real data here. Sunlit ground: radiative equilibrium,
# T = (S (1 - A) sin(elevation) / (emissivity sigma))^(1/4)
const SOLAR_CONSTANT: float = 1361.0  # W/m2
const ALBEDO: float = 0.12
const EMISSIVITY: float = 0.95
const STEFAN_BOLTZMANN: float = 5.670374e-8
const SHADE_CELSIUS: float = -150.0   # simulated: regolith cools fast once shaded

## What Guidance lights up for the "take readings" step (set by whoever places this)
@export var highlight_node: Node3D
## The latest reading of each kind: {"sun": celsius, "shade": celsius}
var readings: Dictionary = {}
## (kind, point) -> the line after the temperature; unset: the sensor's own sun / shade prompt
var message_source: Callable
var _sky: Node = null


func _ready() -> void:
	add_to_group(GROUP)
	CampaignState.mission_started.connect(_on_mission_started)


func _on_mission_started(_id: String) -> void:
	readings.clear()


func has_pair() -> bool:
	return readings.has("sun") and readings.has("shade")


func _sun_direction() -> Vector3:
	if not is_instance_valid(_sky):
		for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			if node.has_method("sun_direction"):
				_sky = node
				break
	return _sky.sun_direction() if _sky else Vector3.UP


## Sunlit ground temperature (degrees C) for the sun `elevation_deg` above the horizon
static func sun_celsius(elevation_deg: float) -> float:
	var flux: float = SOLAR_CONSTANT * (1.0 - ALBEDO) * maxf(sin(deg_to_rad(elevation_deg)), 0.0)
	return pow(flux / (EMISSIVITY * STEFAN_BOLTZMANN), 0.25) - 273.15


func has_turret(rover: Robot) -> bool:
	var socket := rover.find_child("ArmToolSocket", true, false) as HotswapSocket if rover else null
	return socket != null and socket.part != null and socket.part.get_catalog_id() == TURRET


## The spot the mast camera aims at within RANGE: {position, normal}, or {}
func aim_point(rover: Robot) -> Dictionary:
	if rover == null or rover.camera == null:
		return {}
	var from: Vector3 = rover.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - rover.camera.global_basis.z * RANGE, AIM_MASK)
	query.exclude = [rover.get_rid()]
	return rover.get_world_3d().direct_space_state.intersect_ray(query)


## Terrain or a natural rock (MoonTerrain's ground, RockField rocks), not a man-made object
static func is_natural(collider: Object) -> bool:
	var parent: Node = (collider as Node).get_parent() if collider is Node else null
	return parent is MoonTerrain or parent is RockField


## "shade" or "sun" at a world point on a surface (with its normal): shade when the surface faces
## away from the sun (attached shadow) or natural ground blocks the ray to the sun (cast shadow)
func kind_at(point: Vector3, normal: Vector3 = Vector3.UP, natural_surface: bool = true) -> String:
	var sun: Vector3 = _sun_direction()
	if natural_surface and normal.dot(sun) <= 0.0:
		return "shade"
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(point + normal * 0.02, point + sun * 200.0, SHADOW_MASK)
	var excluded: Array[RID] = []
	for i in 16:
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return "sun"
		if is_natural(hit["collider"]):
			return "shade"
		excluded.append(hit["rid"])
		query.exclude = excluded
	return "sun"


## Takes a reading at `point`; returns the kind
func record(point: Vector3, normal: Vector3 = Vector3.UP, natural_surface: bool = true) -> String:
	var kind: String = kind_at(point, normal, natural_surface)
	var had_pair: bool = has_pair()
	var elevation: float = rad_to_deg(asin(clampf(_sun_direction().y, -1.0, 1.0)))
	var celsius: float = SHADE_CELSIUS if kind == "shade" else sun_celsius(elevation)
	readings[kind] = celsius
	reading_taken.emit(kind, celsius, point)
	var follow: String = str(message_source.call(kind, point)) if message_source.is_valid() else \
		("Sun and shade pair recorded." if has_pair() else "Now take a %s reading." % ("sun" if kind == "shade" else "shade"))
	var line := Dialog.new()
	line.speaker = "Kite"
	line.subtitle = "Radiometer: %+d °C, %s (simulated). %s" % [roundi(celsius),
		"in shade" if kind == "shade" else "in sunlight", follow]
	line.min_duration = 5.0
	DialogServer.play_dialog(line)
	if has_pair() and not had_pair:
		pair_completed.emit()
	return kind


## Takes a reading where `rover` aims; true when it did
func try_read(rover: Robot) -> bool:
	if not has_turret(rover) or not rover.is_aiming():
		return false
	var hit: Dictionary = aim_point(rover)
	if hit.is_empty():
		return false
	record(hit["position"], hit["normal"], is_natural(hit["collider"]))
	return true


## What the rover HUD could say ("" for nothing): only with the thermal turret fitted
func get_hint(rover: Robot) -> String:
	if rover == null or not has_turret(rover):
		return ""
	if not rover.is_aiming():
		return "Thermal turret: switch to the mast view to aim"
	var hit: Dictionary = aim_point(rover)
	if hit.is_empty():
		return "Thermal turret: aim at the ground within %d m" % RANGE
	return "Thermal turret: %s here. Press %s to read" % [kind_at(hit["position"], hit["normal"], is_natural(hit["collider"])).to_upper(),
		InputBindings.action_text(&"interact_use", "E")]


func _physics_process(_delta: float) -> void:
	if not Input.is_action_just_pressed(&"interact_use"):
		return
	if GameState.state == GameState.State.IN_GAME_ROBOT and is_instance_valid(GameState.robot):
		try_read(GameState.robot)
