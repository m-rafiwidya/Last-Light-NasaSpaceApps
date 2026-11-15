extends SceneTree
## Headless test: the Moon level's sky, sun and Earth, the antenna target as a level setting,
## and the lights.
##   1. Sky orientation (LunarSky.world_to_equatorial): the terrain pipeline's, for the Apollo 12
##      site at the EVA 2 midpoint (JPL Horizons): the star map puts the sun's, Earth's and
##      Jupiter's catalogue directions (RA / Dec) where Horizons saw them from the site, within 0.05
##      degrees, and the north celestial pole at its computed azimuth / elevation.
##   2. The sun light shines from sun_elevation / sun_azimuth (terrain.json's), the exposure and
##      fill follow the sun's height, and the sky shader gets the level's Earth direction (Horizons'
##      azimuth / elevation), Horizons' angular diameter and facing longitude, lit to the phase its
##      angle to the sun gives (Horizons' illuminated fraction).
##   3. The assembled rover's high-gain antenna points at the level's Earth: the Moon's, 61
##      degrees up in the east; the test level keeps the old fixed direction 35 degrees up.
##   4. In both levels, L (the `lights` action, sent as real key events) toggles the player's
##      helmet light on foot (a shadowed spotlight on the head, aimed with the view) and the driven
##      rover's headlights while driving, each keeping its state while the other mode is used
##      (getting in and out of the rover); the on-foot and the rover controls hints show L.
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_moon_sky.gd

const TICKS: int = 240
const TERRAIN: String = "res://res/terrain/moon_apollo12/terrain.json"
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
	await _check_lights("Moon", moon)

	var test_level: Node = await _load("test_level")
	_check("test level: Earth direction is the old fixed one",
		test_level.earth_direction.is_equal_approx(TEST_LEVEL_EARTH), str(test_level.earth_direction))
	await _check_antenna("test level", test_level, TEST_LEVEL_EARTH.normalized())
	await _check_lights("test level", test_level)

	print("DONE %d failures" % failures)
	quit(1 if failures else 0)


func _azimuth(direction: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(direction.x, -direction.z)), 360.0)


func _check_sky(sky: Node, level: Node) -> void:
	var terrain_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TERRAIN))
	var sky_meta: Dictionary = terrain_meta["sky"]
	var sun_meta: Dictionary = terrain_meta["sun"]
	var earth_meta: Dictionary = terrain_meta["earth"]
	_check("the sky uses the pipeline's orientation", sky.use_fixed_orientation)
	var m: Array = sky_meta["world_to_equatorial"]
	var worst_matrix: float = 0.0
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var expected := Vector3(m[0][0] * axis.x + m[0][1] * axis.y + m[0][2] * axis.z, m[1][0] * axis.x + m[1][1] * axis.y + m[1][2] * axis.z,
			m[2][0] * axis.x + m[2][1] * axis.y + m[2][2] * axis.z)
		worst_matrix = maxf(worst_matrix, (sky.world_to_equatorial() * axis - expected).length())
	_check("orientation = terrain.json sky.world_to_equatorial", worst_matrix < 1e-6, "%.9f" % worst_matrix)
	var sun_star: Vector3 = sky.star_direction(sky_meta["sun_ra_dec"][0], sky_meta["sun_ra_dec"][1])
	var off: float = rad_to_deg(sun_star.angle_to(sky.sun_direction()))
	_check("the star map's sun position is the sun light's", off < 0.05, "%.4f deg apart" % off)
	var earth_star: Vector3 = sky.star_direction(sky_meta["earth_ra_dec"][0], sky_meta["earth_ra_dec"][1])
	off = rad_to_deg(earth_star.angle_to(level.earth_direction.normalized()))
	_check("the star map's Earth position is the level's Earth", off < 0.05, "%.4f deg apart" % off)
	var jupiter: Dictionary = sky_meta["checks"]["599"]
	var jupiter_star: Vector3 = sky.star_direction(jupiter["ra"], jupiter["dec"])
	off = rad_to_deg(jupiter_star.angle_to(sky.sky_direction(jupiter["azimuth"], jupiter["elevation"])))
	_check("Jupiter (not in the fit) where Horizons saw it", off < 0.05, "%.4f deg off, %.1f deg up" % [off, jupiter["elevation"]])
	var north: Vector3 = sky.world_to_equatorial().inverse() * Vector3.BACK
	var ncp: Array = sky_meta["north_celestial_pole_az_el"]
	_check("the celestial north pole at its computed place", absf(_azimuth(north) - ncp[0]) < 0.05 and absf(_elevation(north) - ncp[1]) < 0.05,
		"azimuth %.2f, %.2f deg up" % [_azimuth(north), _elevation(north)])

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
	_check("fill follows the sun's height", is_equal_approx(sky.environment.ambient_light_energy, sky.fill_for_elevation(sky.sun_elevation)),
		"%.4f" % sky.environment.ambient_light_energy)
	_check("fill 0.04 at 9 deg, in proportion to the sunlight on flat ground",
		is_equal_approx(sky.fill_for_elevation(9.0), 0.04) and absf(sky.fill_for_elevation(2.1) / 0.04 - sin(deg_to_rad(2.1)) / sin(deg_to_rad(9.0))) < 0.001,
		"%.4f / %.4f" % [sky.fill_for_elevation(9.0), sky.fill_for_elevation(2.1)])
	# Godot's soft shadows widen with the caster's distance past what the nearest cascade covers:
	# with 0.53 degrees, 70% of the sun came through the crater's rim onto parts on its floor
	_check("the sun casts hard shadows (a distant rim must shade what stands under it)", is_zero_approx(sun.light_angular_distance),
		"light_angular_distance %.2f" % sun.light_angular_distance)

	var material: ShaderMaterial = sky.environment.sky.sky_material
	var shader_earth: Vector3 = material.get_shader_parameter("earth_direction")
	_check("sky draws Earth along the level's earth_direction", shader_earth.is_equal_approx(level.earth_direction.normalized()))
	_check("Earth where Horizons puts it", absf(_azimuth(shader_earth) - earth_meta["azimuth"]) < 0.01 and absf(_elevation(shader_earth) - earth_meta["elevation"]) < 0.01,
		"azimuth %.2f, %.2f deg up" % [_azimuth(shader_earth), _elevation(shader_earth)])
	_check("Earth's facing longitude from Horizons", absf(wrapf(sky.earth_facing_longitude - earth_meta["facing_longitude_east"], -180.0, 180.0)) < 0.01,
		"%.2f deg east" % sky.earth_facing_longitude)
	_check("the sun where the terrain pipeline put it", is_equal_approx(sky.sun_azimuth, sun_meta["azimuth"]) and is_equal_approx(sky.sun_elevation, sun_meta["elevation"]),
		"azimuth %.1f, %.1f deg up" % [sky.sun_azimuth, sky.sun_elevation])
	var diameter: float = rad_to_deg(material.get_shader_parameter("earth_angular_radius")) * 2.0
	_check("Earth's angular diameter from Horizons", absf(diameter - earth_meta["angular_diameter_degrees"]) < 0.001, "%.3f deg" % diameter)
	# Earth's lit fraction as seen from here follows from its angle to the sun
	var separation: float = rad_to_deg(shader_earth.angle_to(towards_sun))
	var lit: float = (1.0 + cos(deg_to_rad(180.0 - separation))) / 2.0
	_check("Earth's phase follows the sun", absf(lit - earth_meta["lit_fraction"]) < 0.01,
		"%.0f deg from the sun: %.0f%% lit" % [separation, lit * 100.0])


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


# L (the `lights` action, real key events) in `level`, tagged `tag`: on foot the player's helmet
# light, driving the rover's headlights; each keeps its state while the other mode is in use
func _check_lights(tag: String, level: Node) -> void:
	var rover: Node = level.get_node("ReadyRover")
	var lights: Node3D = rover.headlights
	var player: Node = GS.player
	var helmet: SpotLight3D = player.helmet_light
	_check(tag + ": helmet light and headlights start off", not helmet.visible and not lights.visible)
	_check(tag + ": no permanent key-hint line on either HUD", root.get_node("Main/UIManager/HUD").find_child("Hint", true, false) == null
		and root.get_node("Main/UIManager/RobotHUD").find_child("Hint", true, false) == null)

	# On foot
	await _key(KEY_L)
	_check(tag + ": L on foot turns the helmet light on", helmet.visible and player.helmet_light_on)
	_check(tag + ": ... and leaves the headlights off", not lights.visible)
	var view: Vector3 = -player.camera.global_basis.z
	_check(tag + ": a shadowed spotlight on the head, aimed with the view",
		helmet.shadow_enabled and (-helmet.global_basis.z).angle_to(view) < deg_to_rad(2.0)
		and helmet.global_position.distance_to(player.camera.global_position) < 0.3,
		"%.1f deg off the view, %.2f m from the eyes" % [rad_to_deg((-helmet.global_basis.z).angle_to(view)), helmet.global_position.distance_to(player.camera.global_position)])

	# Driving
	GS.drive(rover)
	await _ticks(0.2)
	await _key(KEY_L)
	_check(tag + ": L while driving turns the headlights on", lights.visible and rover.headlights_on)
	_check(tag + ": ... and leaves the helmet light as it was (on)", helmet.visible)
	var spots: Array = lights.find_children("*", "SpotLight3D", true, false)
	var forward: Vector3 = -rover.global_basis.z
	var aimed: bool = spots.size() == 2
	for spot in spots:
		aimed = aimed and (-spot.global_basis.z).angle_to(forward) < deg_to_rad(15.0) and spot.shadow_enabled
	_check(tag + ": two shadowed headlights aimed ahead", aimed, "%d spots" % spots.size())
	await _key(KEY_L)
	_check(tag + ": L again turns the headlights off", not lights.visible and not rover.headlights_on and helmet.visible)

	# Out of the rover and back in: each light keeps its state
	await _key(KEY_L)
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.2)
	_check(tag + ": out of the rover, the helmet light is still on", helmet.visible and player.helmet_light_on)
	await _key(KEY_L)
	_check(tag + ": L on foot turns it off, the headlights stay on", not helmet.visible and lights.visible)
	GS.drive(rover)
	await _ticks(0.2)
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.2)
	_check(tag + ": in and out again, the helmet light is still off", not helmet.visible and not player.helmet_light_on)
	rover.headlights_on = false
