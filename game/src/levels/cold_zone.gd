class_name ColdZone

extends Marker3D

## A shaded area on an M3 route (a vertical cylinder of `radius` around this marker). Kite inside
## an active zone without the thermal cover and heater fitted gets cold (MissionDirector).
## A night_only zone is active only when the cargo arrived late, putting M3 near nightfall; a
## day_only zone only when it didn't.
## With dtm_shade, only the part of the cylinder the terrain shadows from the level's sun (as
## LunarSky shows it) is cold: a mask of the play tier's 2 m posts, ray-marched towards the sun.

@export var radius: float = 30.0
@export var night_only: bool = false
@export var day_only: bool = false
@export var route_name: String = ""
@export var dtm_shade: bool = false
@export var terrain_path: NodePath = ^"../../Terrain"
@export var sky_path: NodePath = ^"../../WorldEnvironment"

const POST: float = 2.0
const MARCH_STEP: float = 1.0

var _mask := PackedByteArray()
var _mask_sun := Vector3.ZERO
var _cells: int = 0


func _ready() -> void:
	add_to_group(&"cold_zone")


func is_active() -> bool:
	var late: bool = CargoPlan.m3_near_nightfall()
	return not (night_only and not late) and not (day_only and late)


func contains(point: Vector3) -> bool:
	var offset := Vector2(point.x - global_position.x, point.z - global_position.z)
	if offset.length() > radius:
		return false
	if not dtm_shade:
		return true
	_refresh_mask()
	var i: int = clampi(roundi((offset.y + radius) / POST), 0, _cells - 1)
	var j: int = clampi(roundi((offset.x + radius) / POST), 0, _cells - 1)
	return _mask[i * _cells + j] == 1


## Shaded posts in the zone for the current sun
func shaded_area() -> float:
	_refresh_mask()
	return _mask.count(1) * POST * POST


func _sun() -> Vector3:
	var sky := get_node_or_null(sky_path) as LunarSky
	return sky.sun_direction() if sky else Vector3.UP


func _refresh_mask() -> void:
	var sun: Vector3 = _sun()
	if not _mask.is_empty() and sun.is_equal_approx(_mask_sun):
		return
	_mask_sun = sun
	var terrain: MoonTerrain = get_node(terrain_path)
	_cells = int(2.0 * radius / POST) + 1
	_mask.resize(_cells * _cells)
	_mask.fill(0)
	var flat := Vector2(sun.x, sun.z)
	if flat.length() < 0.001:
		return
	var rise: float = sun.y / flat.length()
	flat = flat.normalized()
	var top: float = _highest(terrain)
	for i in _cells:
		for j in _cells:
			var x: float = global_position.x - radius + j * POST
			var z: float = global_position.z - radius + i * POST
			if Vector2(x - global_position.x, z - global_position.z).length() > radius:
				continue
			var ground: float = terrain.height_at(x, z)
			var s: float = MARCH_STEP
			while ground + s * rise < top:
				if terrain.height_at(x + flat.x * s, z + flat.y * s) > ground + s * rise:
					_mask[i * _cells + j] = 1
					break
				s += MARCH_STEP


static var _top: float = NAN


# The play tier's highest post (a ray above it can't be shadowed any more)
static func _highest(terrain: MoonTerrain) -> float:
	if is_nan(_top):
		var heights: PackedFloat32Array = terrain.tiers[0]["heights"]
		_top = -INF
		for h in heights:
			_top = maxf(_top, h)
	return _top
