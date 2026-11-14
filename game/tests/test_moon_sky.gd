extends SceneTree
## Headless test: the Moon level's sky, sun and Earth, the antenna target as a level setting,
## and the rover headlights.
##   1. Sky orientation (LunarSky.world_to_equatorial): the south ecliptic pole is straight up,
##      Canopus (14 degrees from it) is 75.8 degrees up, the ecliptic (where the sun and Earth
##      are) runs along the horizon, and Earth's north pole points below the horizon.
##   2. The sun light shines from sun_elevation / sun_azimuth, the exposure follows the sun's
##      height, and the sky shader gets the level's Earth direction, about 2 degrees across.
##   3. The assembled rover's high-gain antenna points at the level's Earth: the Moon's, low
##      over the horizon; the test level keeps the old fixed direction 35 degrees up.
##   4. L (the rover_lights action, sent as a real key event) toggles the driven rover's
##      headlights; on foot it does nothing.
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_moon_sky.gd

const TICKS: int = 240
# Canopus (alpha Carinae) and the south ecliptic pole (RA 6h, Dec -66.56), J2000
const CANOPUS := Vector2(95.988, -52.696)
const SOUTH_ECLIPTIC_POLE := Vector2(90.0, -66.561)
# RoverVisuals.DEFAULT_EARTH_DIRECTION (this script compiles before the game's autoloads
# exist, so it names none of the game's classes)
const TEST_LEVEL_EARTH := Vector3(0.46, 0.57, -0.68)

var GS: Node
var SL: Node
var failures: int = 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-58s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _load(level_id: String) -> Node:
	SL.load_scene(level_id)
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == level_id):
		await physics_frame
	await _ticks(0.5)
	return SL.current_scene


func _elevation(direction: Vector3) -> float:
	return rad_to_deg(asin(clampf(direction.normalized().y, -1.0, 1.0)))


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _ticks(0.05)


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await process_frame

	var moon: Node = await _load("moon_level")
	var sky: Node = moon.get_node("WorldEnvironment")
	_check_sky(sky, moon)
	await _check_antenna("Moon", moon, moon.earth_direction)
	await _check_headlights(moon)

	var test_level: Node = await _load("test_level")
	_check("test level: Earth direction is the old fixed one",
		test_level.earth_direction.is_equal_approx(TEST_LEVEL_EARTH), str(test_level.earth_direction))
	await _check_antenna("test level", test_level, TEST_LEVEL_EARTH.normalized())

	print("DONE %d failures" % failures)
	quit(1 if failures else 0)


func _check_sky(sky: Node, level: Node) -> void:
	var pole: Vector3 = sky.star_direction(SOUTH_ECLIPTIC_POLE.x, SOUTH_ECLIPTIC_POLE.y)
	_check("south ecliptic pole straight overhead", _elevation(pole) > 89.9, "%.2f deg up" % _elevation(pole))
	var canopus: float = _elevation(sky.star_direction(CANOPUS.x, CANOPUS.y))
	_check("Canopus 75.8 deg up (its ecliptic latitude)", absf(canopus - 75.8) < 0.1, "%.2f deg up" % canopus)
	var worst: float = 0.0
	for longitude in range(0, 360, 15):
		# A point on the ecliptic, in equatorial coordinates
		var l: float = deg_to_rad(longitude)
		var e: float = sky.OBLIQUITY
		var equatorial := Vector3(cos(l), sin(l) * cos(e), sin(l) * sin(e))
		worst = maxf(worst, absf(_elevation(sky.world_to_equatorial().inverse() * equatorial)))
	_check("the ecliptic runs along the horizon", worst < 0.01, "at most %.3f deg off" % worst)
	var north: Vector3 = sky.world_to_equatorial().inverse() * Vector3.BACK
	_check("the celestial north pole is below the horizon", absf(_elevation(north) + 66.56) < 0.1, "%.2f deg" % _elevation(north))

	var sun: DirectionalLight3D = sky.sun
	var towards_sun: Vector3 = sun.global_basis.z
	_check("sun light shines from sun_elevation", absf(_elevation(towards_sun) - sky.sun_elevation) < 0.01,
		"%.2f deg up, sun_elevation %.2f" % [_elevation(towards_sun), sky.sun_elevation])
	_check("sun light shines from sun_azimuth", towards_sun.is_equal_approx(sky.sun_direction()))
	_check("exposure follows the sun's height", is_equal_approx(sky.environment.tonemap_exposure, sky.exposure_for_elevation(sky.sun_elevation)),
		"%.2f" % sky.environment.tonemap_exposure)
	_check("exposure 2.0 at 9 deg, about 5.9 at 1.5 deg",
		is_equal_approx(sky.exposure_for_elevation(9.0), 2.0) and absf(sky.exposure_for_elevation(1.5) - 5.85) < 0.05,
		"%.2f / %.2f" % [sky.exposure_for_elevation(9.0), sky.exposure_for_elevation(1.5)])

	var material: ShaderMaterial = sky.environment.sky.sky_material
	var shader_earth: Vector3 = material.get_shader_parameter("earth_direction")
	_check("sky draws Earth along the level's earth_direction", shader_earth.is_equal_approx(level.earth_direction.normalized()))
	_check("Earth low over the horizon", _elevation(shader_earth) > 1.0 and _elevation(shader_earth) < 8.0, "%.1f deg up" % _elevation(shader_earth))
	var diameter: float = rad_to_deg(material.get_shader_parameter("earth_angular_radius")) * 2.0
	_check("Earth about 2 deg across", absf(diameter - 1.9) < 0.05, "%.2f deg" % diameter)
	var phase: float = rad_to_deg(shader_earth.angle_to(towards_sun))
	_check("Earth and sun far enough apart for a gibbous Earth", phase > 90.0 and phase < 150.0, "%.0f deg apart" % phase)


func _check_antenna(tag: String, level: Node, earth: Vector3) -> void:
	var rover: Node = level.get_node("ReadyRover")
	await _ticks(3.0)   # mounted at start, then the dish slews
	var antenna: Node = rover.get_node("AntennaSocket").part
	var dish: Node3D = antenna.find_child("antenna_dish", true, false) if antenna else null
	if dish == null:
		_check("%s: antenna mounted" % tag, false)
		return
	# The dish faces up (its Y) at rest
	var error: float = rad_to_deg(dish.global_basis.y.angle_to(earth))
	_check("%s: antenna points at the level's Earth" % tag, error < 1.0,
		"%.2f deg off, Earth %.1f deg up" % [error, _elevation(earth)])


func _check_headlights(level: Node) -> void:
	var rover: Node = level.get_node("ReadyRover")
	var lights: Node3D = rover.headlights
	_check("headlights start off", not lights.visible)
	await _key(KEY_L)
	_check("L on foot leaves them off", not lights.visible)
	GS.drive(rover)
	await _ticks(0.2)
	await _key(KEY_L)
	_check("L while driving turns them on", lights.visible and rover.headlights_on)
	var spots: Array = lights.find_children("*", "SpotLight3D", true, false)
	var forward: Vector3 = -rover.global_basis.z
	var aimed: bool = spots.size() == 2
	for spot in spots:
		aimed = aimed and (-spot.global_basis.z).angle_to(forward) < deg_to_rad(15.0) and spot.shadow_enabled
	_check("two shadowed spotlights aimed ahead", aimed, "%d spots" % spots.size())
	await _key(KEY_L)
	_check("L again turns them off", not lights.visible and not rover.headlights_on)
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.2)
