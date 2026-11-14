extends SceneTree
## Renders the Moon level's terrain from the player's, the chase and the mast cameras into
## tools/previews/terrain/ (repo root). Needs a window (not --headless):
##
##     Godot --path game -s res://tools/render_terrain_previews.gd --resolution 1920x1080
##     (append `-- terrain_detail=low` for the 1 m ground: the files get a `low_` prefix)
##
## Shots: the player's view from the spawn; the rover at the base towards and away from the sun;
## the permanently shadowed crater (in the terrain's shadow) from its rim and from its floor,
## headlights on; Earth over the
## skyline from the mast camera, unzoomed and zoomed; from the highest ground in the play area
## towards Shackleton.

const OUT_DIR: String = "res://../tools/previews/terrain"
const DATA: String = "res://res/terrain/moon_site01/terrain.json"
# RoverCamera.View and its zoom limit (this script compiles before the game's autoloads exist)
const CHASE: int = 0
const MAST: int = 1
const MAST_FOV_MIN: float = 20.0
const MAST_FOV_MAX: float = 90.0
# On the graded base, clear of the rover's sign, the pile and the player
const BASE := Vector2(-352.0, -283.0)
const CRATER := Vector2(192.0, 384.0)
const CRATER_RIM := Vector2(130.0, 310.0)
const SHACKLETON_AZIMUTH: float = 71.0

var GS: Node
var SL: Node
var prefix: String = ""


func _initialize() -> void:
	_watchdog(600.0)
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


# Back in front first: another window can take the focus during a run, and an unfocused
# window's frames come out stale or black
func _frames(count: int) -> void:
	DisplayServer.window_move_to_foreground()
	for i in count:
		await process_frame


func _azimuth(from: Vector2, to: Vector2) -> float:
	return rad_to_deg(atan2(to.x - from.x, -(to.y - from.y)))


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	if "terrain_detail=low" in OS.get_cmdline_user_args():
		prefix = "low_"
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))

	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await process_frame
	var level: Node = SL.current_scene
	var terrain: Node = level.get_node("Terrain")
	var rover: Node = level.get_node("ReadyRover")
	var rig: Node = rover.get_node("CameraRig")
	var sun: Dictionary = meta["sun"]
	var earth: Dictionary = meta["earth"]
	await _frames(60)
	await _save("player_spawn")

	GS.drive(rover)
	await _rover_shot("base_towards_sun", terrain, rover, rig, CHASE, BASE, sun["azimuth"], 0.0, 0.0)
	await _rover_shot("base_away_from_sun", terrain, rover, rig, CHASE, BASE, sun["azimuth"] + 180.0, 0.0, 0.0)
	await _rover_shot("base_towards_crater", terrain, rover, rig, CHASE, BASE, _azimuth(BASE, CRATER), 0.0, 0.0)
	# The crater and the ground around it are in the terrain's shadow at this sun: headlights
	rover.headlights_on = true
	await _rover_shot("crater_from_rim_headlights", terrain, rover, rig, CHASE, CRATER_RIM, _azimuth(CRATER_RIM, CRATER), 0.0, 10.0)
	await _rover_shot("crater_floor_headlights", terrain, rover, rig, CHASE, CRATER, _azimuth(CRATER, CRATER_RIM) + 150.0, 0.0, 0.0)
	await _rover_shot("crater_floor_mast_headlights", terrain, rover, rig, MAST, CRATER, _azimuth(CRATER, CRATER_RIM) + 150.0, 0.0, -10.0)
	rover.headlights_on = false
	await _rover_shot("mast_earth", terrain, rover, rig, MAST, BASE, earth["azimuth"], 0.0, earth["elevation"])
	rig.mast_fov_target = MAST_FOV_MIN
	await _rover_shot("mast_earth_zoom", terrain, rover, rig, MAST, BASE, earth["azimuth"], 0.0, earth["elevation"])
	rig.mast_fov_target = MAST_FOV_MAX
	# The highest ground inside the boundary (every 10 m, 30 m in)
	var best := Vector2.ZERO
	var best_height: float = -INF
	for x in range(-470, 471, 10):
		for z in range(-470, 471, 10):
			var h: float = terrain.height_at(x, z)
			if h > best_height:
				best_height = h
				best = Vector2(x, z)
	print("INFO highest ground at %s, %.1f m" % [best, best_height])
	await _rover_shot("high_ground_towards_shackleton", terrain, rover, rig, MAST, best, SHACKLETON_AZIMUTH, 0.0, 0.0)
	quit()


func _rover_shot(shot: String, terrain: Node, rover: Node, rig: Node, view: int, at: Vector2,
		heading: float, look_azimuth: float, look_altitude: float) -> void:
	if GS.state != GS.State.IN_GAME_ROBOT:
		GS.drive(rover)
	rover.global_transform = Transform3D(Basis(Vector3.UP, -deg_to_rad(heading)), Vector3(at.x, terrain.height_at(at.x, at.y) + 0.4, at.y))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	for wheel in rover.running_gear.wheel_states:
		rover.running_gear.wheel_states[wheel][0] = 0.0
	rig._switch(view)
	rover.controller.camera_azimuth = deg_to_rad(look_azimuth)
	rover.controller.camera_altitude = clampf(deg_to_rad(look_altitude), -rover.controller.altitude_limit, rover.controller.altitude_limit)
	await _frames(150)
	await _save(shot)


func _save(shot: String) -> void:
	var path: String = ProjectSettings.globalize_path("%s/%s%s.jpg" % [OUT_DIR, prefix, shot])
	root.get_texture().get_image().save_jpg(path, 0.9)
	print("SAVED %s" % path)


# A hang fails the run instead of stalling it
func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
