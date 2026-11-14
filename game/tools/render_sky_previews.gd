extends SceneTree
## Renders the Moon level's sky and lighting from the rover's chase and mast cameras into
## tools/previews/sky/ (repo root), once per sun elevation in SUN_ELEVATIONS. Needs a window
## (not --headless):
##
##     Godot --path game -s res://tools/render_sky_previews.gd --resolution 1920x1080
##     (append `-- elevations=1.5,9` to pick the sun elevations, `only=<shot>` for one shot,
##     `energy=<sun energy>`, `exposure=<e1>,<e2>` (one per elevation) and `tonemap=<mode>` to
##     try other lighting than the level's)
##
## Each sun elevation gets:
##   chase_shadows_lights_off / _on   the rover facing between its long shadow (ahead and to the
##                                    left: the sun is behind it) and Earth (ahead, right)
##   chase_toward_sun                 the rover facing the sun on the horizon, backlit
##   chase_far_shadows                1 m posts 10 to 400 m ahead, shadows on every cascade
##   mast_earth / mast_earth_zoom     the mast camera on Earth, unzoomed and at full zoom
##   mast_zenith                      the mast camera straight up: the south ecliptic pole,
##                                    the Large Magellanic Cloud and Canopus
## It also checks the star map's orientation: Canopus must be the brightest point near the
## direction LunarSky computes for it (prints RESULT ... PASS / FAIL).

const SUN_ELEVATIONS: Array = [1.5, 9.0]
const OUT_DIR: String = "res://../tools/previews/sky"
const ROVER_AT := Vector3(10.5, 0.35, 12.0)
# Canopus (alpha Carinae), J2000
const CANOPUS_RA: float = 95.988
const CANOPUS_DEC: float = -52.696
# RoverCamera.View and MAST_FOV_MIN / _MAX (this script compiles before the game's
# autoloads exist, so it names none of the game's classes)
const CHASE: int = 0
const MAST: int = 1
const MAST_FOV_MIN: float = 20.0
const MAST_FOV_MAX: float = 90.0

var GS: Node
var SL: Node
var failures: int = 0
var only: String = ""
var overrides: Dictionary = {}


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-50s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	# The window pops up over whatever else is open: keys and the mouse must not drive, look,
	# leave the rover or pause the game, and it shouldn't take the keyboard focus
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var elevations: Array = SUN_ELEVATIONS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("elevations="):
			elevations = Array(arg.trim_prefix("elevations=").split(",")).map(func(v: String) -> float: return v.to_float())
		elif arg.begins_with("only="):
			only = arg.trim_prefix("only=")
		elif arg.contains("="):
			overrides[arg.get_slice("=", 0)] = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await process_frame
	await _frames(30)

	var level: Node = SL.current_scene
	var sky: Node = level.get_node("WorldEnvironment")
	var rover: Node = level.get_node("ReadyRover")
	GS.drive(rover)
	await _frames(10)
	_add_posts(level, sky)

	var environment: Environment = sky.environment
	if overrides.has("energy"):
		sky.sun.light_energy = float(overrides["energy"])
	if overrides.has("atlas"):
		RenderingServer.directional_shadow_atlas_set_size(int(overrides["atlas"]), true)
	if overrides.has("tonemap"):
		environment.tonemap_mode = int(overrides["tonemap"])
	var exposures: Array = Array(overrides.get("exposure", "").split(",", false)).map(func(v: String) -> float: return v.to_float())
	for i in elevations.size():
		var elevation: float = elevations[i]
		sky.sun_elevation = elevation
		if i < exposures.size():
			sky.auto_exposure = false
			environment.tonemap_exposure = exposures[i]
		print("LIGHTING sun %.1f deg, energy %.2f, exposure %.2f, tonemap %d" % [elevation, sky.sun.light_energy, environment.tonemap_exposure, environment.tonemap_mode])
		await _shots(sky, rover, "sun%04.1f" % elevation)
	await _check_star_orientation(sky, level)
	print("DONE %d failures" % failures)
	quit(1 if failures else 0)


func _shots(sky: Node, rover: Node, tag: String) -> void:
	var rig: Node = rover.get_node("CameraRig")
	var away: float = sky.sun_azimuth + 180.0
	var earth: Vector3 = sky.earth_direction()
	var earth_azimuth: float = rad_to_deg(atan2(earth.x, -earth.z))
	var earth_elevation: float = rad_to_deg(asin(earth.y))
	# Between the shadows and Earth, so both are in the picture
	var shadows_and_earth: float = away + wrapf(earth_azimuth - away, -180.0, 180.0) / 2.0

	rover.headlights_on = false
	await _shot("chase_shadows_lights_off", tag, rover, rig, CHASE, shadows_and_earth, 0.0, 0.0)
	rover.headlights_on = true
	await _shot("chase_shadows_lights_on", tag, rover, rig, CHASE, shadows_and_earth, 0.0, 0.0)
	rover.headlights_on = false
	await _shot("chase_toward_sun", tag, rover, rig, CHASE, sky.sun_azimuth, 0.0, 0.0)
	await _shot("chase_far_shadows", tag, rover, rig, CHASE, away, 0.0, 0.0, Vector3(-40.0, 0.35, 12.0))
	await _shot("mast_earth", tag, rover, rig, MAST, earth_azimuth, 0.0, earth_elevation)
	rig.mast_fov_target = MAST_FOV_MIN
	await _shot("mast_earth_zoom", tag, rover, rig, MAST, earth_azimuth, 0.0, earth_elevation)
	rig.mast_fov_target = MAST_FOV_MAX
	await _shot("mast_zenith", tag, rover, rig, MAST, earth_azimuth, 0.0, 90.0)


## Puts the rover at `at` facing `heading` (azimuth, degrees), switches to `view` with the look
## turned by `look_azimuth` / `look_altitude` (degrees) and saves the frame.
func _shot(shot: String, tag: String, rover: Node, rig: Node, view: int,
		heading: float, look_azimuth: float, look_altitude: float, at: Vector3 = ROVER_AT) -> void:
	if not only.is_empty() and shot != only:
		return
	if GS.state != GS.State.IN_GAME_ROBOT:
		push_warning("%s: back in the rover (the state was %s)" % [shot, GS.State.keys()[GS.state]])
		GS.drive(rover)
	rover.global_transform = Transform3D(Basis(Vector3.UP, -deg_to_rad(heading)), at)
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	for wheel in rover.running_gear.wheel_states:
		rover.running_gear.wheel_states[wheel][0] = 0.0
	rig._switch(view)
	rover.controller.camera_azimuth = deg_to_rad(look_azimuth)
	rover.controller.camera_altitude = clampf(deg_to_rad(look_altitude), -rover.controller.altitude_limit, rover.controller.altitude_limit)
	# Settle on the suspension, let the chase camera swing round and the zoom ease in
	await _frames(150)
	if GS.state != GS.State.IN_GAME_ROBOT:
		push_warning("%s: left the rover while settling (state %s)" % [shot, GS.State.keys()[GS.state]])
	var tilt: float = rad_to_deg(rover.global_basis.y.angle_to(Vector3.UP))
	if tilt > 5.0 or rover.global_position.distance_to(at) > 0.5:
		push_warning("%s: the rover moved (tilt %.1f deg, %.2f m away)" % [shot, tilt, rover.global_position.distance_to(at)])
	var image: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("%s/%s_%s.jpg" % [OUT_DIR, tag, shot])
	image.save_jpg(path, 0.92)
	print("SAVED %s" % path)


## 1 m wide, 2 m tall posts straight ahead of chase_far_shadows' rover, 10 to 400 m out, so
## their shadows land in every cascade
func _add_posts(level: Node, sky: Node) -> void:
	var away: Vector3 = sky.sky_direction(sky.sun_azimuth + 180.0, 0.0)
	var side: Vector3 = away.cross(Vector3.UP)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.6, 0.6)
	for distance in [10.0, 25.0, 50.0, 100.0, 200.0, 400.0]:
		var post := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, 2.0, 1.0)
		mesh.material = material
		post.mesh = mesh
		level.add_child(post)
		post.global_position = Vector3(-40.0, 1.0, 12.0) + away * distance + side * 3.0


## Canopus must be the brightest thing in a 4 degree view centred on where LunarSky puts it
func _check_star_orientation(sky: Node, level: Node) -> void:
	var direction: Vector3 = sky.star_direction(CANOPUS_RA, CANOPUS_DEC)
	# Its own viewport on the level's world, so the HUD isn't in the picture
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.world_3d = root.world_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera := Camera3D.new()
	camera.fov = 4.0
	viewport.add_child(camera)
	level.add_child(viewport)
	camera.global_position = Vector3(0.0, 2.0, 0.0)
	camera.look_at(camera.global_position + direction, Vector3.FORWARD if absf(direction.y) > 0.99 else Vector3.UP)
	camera.make_current()
	await _frames(20)
	var image: Image = viewport.get_texture().get_image()
	var size: Vector2i = image.get_size()
	# The star is a saturated blob: take the centroid of everything near the peak
	var best: float = 0.0
	for y in size.y:
		for x in size.x:
			best = maxf(best, image.get_pixel(x, y).get_luminance())
	var sum := Vector2.ZERO
	var count: int = 0
	for y in size.y:
		for x in size.x:
			if image.get_pixel(x, y).get_luminance() >= best * 0.9:
				sum += Vector2(x, y)
				count += 1
	var brightest: Vector2 = sum / count
	var off_degrees: float = (brightest - Vector2(size) / 2.0).length() / size.y * camera.fov
	# A black or uniform view (e.g. the sky shader failed) has no star to find
	var is_star: bool = best > 0.3 and count < size.x * size.y / 100
	_check("star map orientation: Canopus at its computed direction", is_star and off_degrees < 0.3,
		"(brightest spot %.2f deg from the centre, peak %.2f over %d px, elevation %.1f deg)" % [off_degrees, best, count, rad_to_deg(asin(direction.y))])
	viewport.queue_free()
