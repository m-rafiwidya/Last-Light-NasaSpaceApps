@tool
class_name LunarSky

extends WorldEnvironment

## The Moon level's sky and sun, as seen from the lunar south pole: the stars of NASA's Deep Star
## Maps 2020 with the south ecliptic pole straight overhead (the Moon's spin axis is only 1.5
## degrees from it), so the ecliptic, and with it the sun and Earth, runs along the horizon.
## Places the `sun` light at `sun_elevation` / `sun_azimuth` and Earth along the level's
## `earth_direction` (RoverLevel: the rovers' antennas track the same direction), and feeds both
## to lunar_sky.gdshader, which lights Earth with the sun, so its phase is right.
## Azimuths are degrees from -Z towards +X.

## After the sun moved (MoonTerrain's shader follows it)
signal sun_changed

## The light that is the sun
@export var sun: DirectionalLight3D:
	set(value):
		sun = value
		_update()
## Sun height above the horizon (degrees). At the south pole it is never more than about 1.5
## (the Moon's axis is tilted 1.54 degrees); higher, e.g. 9, trades realism for visibility
@export_range(0.0, 90.0, 0.1) var sun_elevation: float = 1.5:
	set(value):
		sun_elevation = value
		_update()
@export_range(-180.0, 180.0, 0.1) var sun_azimuth: float = 160.0:
	set(value):
		sun_azimuth = value
		_update()
## Ecliptic longitude (degrees) on the horizon towards -Z. At the pole the stars turn round the
## zenith once a sidereal month, so any value is some moment of it
@export_range(-180.0, 180.0, 0.1) var forward_ecliptic_longitude: float = 0.0:
	set(value):
		forward_ecliptic_longitude = value
		_update()
## Earth's angular diameter from the Moon (degrees): 1.9 (its 6371 km radius at 384400 km)
@export var earth_angular_diameter: float = 1.9:
	set(value):
		earth_angular_diameter = value
		_update()
## Geographic longitude (degrees east) at the middle of Earth's disc
@export_range(-180.0, 180.0, 0.1) var earth_facing_longitude: float = 20.0:
	set(value):
		earth_facing_longitude = value
		_update()

## How bright the stars look on screen, whatever the exposure (the shader's star_energy is
## this over the exposure): a higher exposure for a low sun would otherwise turn the star map's
## faint background into grain
@export var star_brightness: float = 0.6:
	set(value):
		star_brightness = value
		_update()
## Sets the environment's exposure from the sun's height (see exposure_for_elevation), so
## either sun height reads well; off, the environment's own exposure stays
@export var auto_exposure: bool = true:
	set(value):
		auto_exposure = value
		_update()
## Sets the environment's ambient (fill) energy from the sun's height (see fill_for_elevation):
## the fill stands for light scattered off sunlit ground, so it falls with the sunlight on it and
## shadows stay as dark beside sunlit ground at any sun height; off, the environment's own stays
@export var auto_fill: bool = true:
	set(value):
		auto_fill = value
		_update()

## Earth's tilt: the angle between the ecliptic and the celestial equator
const OBLIQUITY: float = deg_to_rad(23.44)
## auto_exposure: the exposure at EXPOSURE_ELEVATION (with the AgX tonemapper and the sun at
## energy 2), and how much of the change in flat ground's brightness (sin of the sun's
## elevation) it makes up for, in stops: 0.6, so a lower sun still looks darker but the ground
## stays readable while upright faces in full sun stay short of white
const REFERENCE_EXPOSURE: float = 2.0
const EXPOSURE_ELEVATION: float = 9.0
const EXPOSURE_COMPENSATION: float = 0.6
## auto_fill: the ambient energy with the sun at EXPOSURE_ELEVATION (shadows nearly black: an
## eighth of flat sunlit ground)
const REFERENCE_FILL: float = 0.04


## World direction (unit) at an azimuth and elevation in degrees
static func sky_direction(azimuth: float, elevation: float) -> Vector3:
	var az: float = deg_to_rad(azimuth)
	var el: float = deg_to_rad(elevation)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


func _ready() -> void:
	_update()


## World direction -> equatorial coordinates (x towards RA 0h, z the north celestial pole).
## World up is the south ecliptic pole; the horizon towards -Z is at forward_ecliptic_longitude.
func world_to_equatorial() -> Basis:
	# World (x, y, z) -> ecliptic (x, z, -y): up is the south ecliptic pole, and +X is at
	# ecliptic longitude 0; then turn about the pole so -Z is at forward_ecliptic_longitude
	var world_to_ecliptic := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	var turn := Basis(Vector3.BACK, deg_to_rad(forward_ecliptic_longitude + 90.0))
	return Basis(Vector3.RIGHT, OBLIQUITY) * turn * world_to_ecliptic


## World direction of a star (right ascension and declination in degrees)
func star_direction(right_ascension: float, declination: float) -> Vector3:
	var ra: float = deg_to_rad(right_ascension)
	var dec: float = deg_to_rad(declination)
	var equatorial := Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
	return world_to_equatorial().inverse() * equatorial


func earth_direction() -> Vector3:
	var level_direction = get_parent().get("earth_direction") if get_parent() else null
	if level_direction is Vector3 and level_direction != Vector3.ZERO:
		return (level_direction as Vector3).normalized()
	return RoverVisuals.DEFAULT_EARTH_DIRECTION


## Exposure for a sun `elevation` degrees up: 2.0 at 9 degrees, 5.9 at 1.5
static func exposure_for_elevation(elevation: float) -> float:
	var ratio: float = sin(deg_to_rad(EXPOSURE_ELEVATION)) / sin(deg_to_rad(maxf(elevation, 0.5)))
	return REFERENCE_EXPOSURE * pow(ratio, EXPOSURE_COMPENSATION)


## Ambient (fill) energy for a sun `elevation` degrees up: 0.04 at 9 degrees, in proportion to the
## sunlight on flat ground (0.0094 at 2.1)
static func fill_for_elevation(elevation: float) -> float:
	return REFERENCE_FILL * sin(deg_to_rad(maxf(elevation, 0.0))) / sin(deg_to_rad(EXPOSURE_ELEVATION))


func sun_direction() -> Vector3:
	return sky_direction(sun_azimuth, sun_elevation)


func _update() -> void:
	if not is_inside_tree():
		return
	if sun:
		sun.global_basis = Basis.looking_at(-sun_direction(), Vector3.UP)
	sun_changed.emit()
	if auto_exposure and environment:
		environment.tonemap_exposure = exposure_for_elevation(sun_elevation)
	if auto_fill and environment:
		environment.ambient_light_energy = fill_for_elevation(sun_elevation)
	var sky_material := environment.sky.sky_material as ShaderMaterial if environment and environment.sky else null
	if sky_material == null:
		return
	var to_equatorial: Basis = world_to_equatorial()
	sky_material.set_shader_parameter("world_to_equatorial", to_equatorial)
	sky_material.set_shader_parameter("star_energy", star_brightness / maxf(environment.tonemap_exposure, 0.01))
	sky_material.set_shader_parameter("earth_direction", earth_direction())
	sky_material.set_shader_parameter("earth_angular_radius", deg_to_rad(earth_angular_diameter) * 0.5)
	sky_material.set_shader_parameter("earth_north", to_equatorial.inverse() * Vector3.BACK)
	sky_material.set_shader_parameter("earth_facing_longitude", deg_to_rad(earth_facing_longitude))
