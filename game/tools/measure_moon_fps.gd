extends SceneTree
## Measures the Moon level's frame rate in a window: the rover drives a full-throttle circle
## with its headlights on, SECONDS each in the chase and the mast view, then the player walks
## on foot with the helmet light on, then stands facing the parked rover, its headlights and the
## helmet light both in view (the player's helmet light is on throughout), then stands in the
## workshop's bay facing the docked rover (the workshop's lights, WORKSHOP_KIT.md 8). Prints per phase the mean frame rate and the 99th percentile and worst frame times
## and the triangles drawn per frame; before that the load time (main menu to playing, and the
## terrain's own data / mesh times: the meshes come from user://terrain_cache after the first load)
## and the memory in use (static and video) on the menu and once the level is in.
## Vsync is off unless `vsync` is given, so the numbers show the headroom.
##
##     Godot --path game -s res://tools/measure_moon_fps.gd --resolution 1920x1080
##     (append `-- vsync`, `sun=<elevation>`, `quality=<0-5>` (directional soft shadow quality),
##     `atlas=<size>` (directional shadow atlas) or `lights=off` to compare)

const SECONDS: float = 12.0
const WARM_UP: float = 2.0
# RoverCamera.View (this script compiles before the game's autoloads exist)
const CHASE: int = 0
const MAST: int = 1

var GS: Node
var SL: Node
var args: Dictionary = {}


func _initialize() -> void:
	_watchdog(300.0)
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	for arg in OS.get_cmdline_user_args():
		args[arg.get_slice("=", 0)] = arg.get_slice("=", 1) if arg.contains("=") else ""
	# The window takes the focus (an unfocused one may be throttled): keys typed meanwhile must
	# not drive, leave the rover or pause the game. Input.action_press still works.
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if args.has("vsync") else DisplayServer.VSYNC_DISABLED)

	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	for i in 30:
		await process_frame
	var menu_static: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var menu_video: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var load_start: int = Time.get_ticks_msec()
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await process_frame
	var load_ms: int = Time.get_ticks_msec() - load_start
	var level: Node = SL.current_scene
	for i in 30:
		await process_frame
	var terrain: Node = level.get_node("Terrain")
	print("LOAD %.2f s from the menu to playing (includes the loading screen's 0.5 s fade); terrain data and collision %d ms, meshes %.2f s for %d chunks" % [
		load_ms / 1000.0, terrain.data_ms, terrain.build_seconds, terrain.chunk_count])
	var mb := func(bytes: float) -> float: return bytes / 1048576.0
	var level_static: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var level_video: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	# (RENDER_TEXTURE_MEM_USED reads as garbage on Metal in 4.7: the rest of the video memory is shown instead)
	var buffers: float = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)
	print("MEMORY static %.0f MB (menu %.0f, +%.0f for the level); video %.0f MB (menu %.0f, +%.0f): buffers %.0f MB, textures and the rest %.0f MB" % [
		mb.call(level_static), mb.call(menu_static), mb.call(level_static - menu_static), mb.call(level_video), mb.call(menu_video),
		mb.call(level_video - menu_video), mb.call(buffers), mb.call(level_video - buffers)])
	var sky: Node = level.get_node("WorldEnvironment")
	if args.has("sun"):
		sky.sun_elevation = float(args["sun"])
	if args.has("atlas"):
		RenderingServer.directional_shadow_atlas_set_size(int(args["atlas"]), true)
	if args.has("quality"):
		RenderingServer.directional_soft_shadow_filter_set_quality(int(args["quality"]))
	print("SETUP %s, %.0f Hz screen, sun %s deg, vsync %s, atlas %s, soft shadow quality %s, %s" % [
		RenderingServer.get_video_adapter_name(), DisplayServer.screen_get_refresh_rate(), sky.get("sun_elevation"), args.has("vsync"),
		args.get("atlas", "default"), args.get("quality", "default"), "lights off" if args.get("lights") == "off" else "lights on"])

	var rover: Node = level.get_node("ReadyRover")
	var workshop: Node3D = level.get_node("Workshop")
	# The rover starts docked in the workshop: out onto the apron for the drive
	rover.global_transform = Transform3D(workshop.global_basis, workshop.to_global(Vector3(-1.0, 0.4, -16.0)))
	GS.drive(rover)
	if "headlights_on" in rover:
		rover.headlights_on = args.get("lights") != "off"
	if "helmet_light_on" in GS.player:
		GS.player.helmet_light_on = args.get("lights") != "off"
	Input.action_press("move_forward")
	Input.action_press("move_left", 0.6)
	var rig: Node = rover.get_node("CameraRig")
	rig._switch(CHASE)
	await _measure("rover, chase camera")
	rig._switch(MAST)
	await _measure("rover, mast camera")
	Input.action_release("move_forward")
	Input.action_release("move_left")

	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	# On foot outdoors, where the player spawned before the workshop (the spawn is inside it now),
	# so this phase stays comparable with earlier runs
	var outdoors := Vector3(-297.5, 0.0, 253.8)
	GS.player.global_position = Vector3(outdoors.x, terrain.height_at(outdoors.x, outdoors.z) + 0.05, outdoors.z)
	GS.player.linear_velocity = Vector3.ZERO
	GS.player.controller.camera_azimuth = 0.0
	Input.action_press("move_forward")
	await _measure("player on foot")
	Input.action_release("move_forward")

	# 4 m in front of the parked rover, looking at it and the ground its headlights light
	var player: Node = GS.player
	var rover_forward: Vector3 = -rover.global_basis.z
	rover_forward = Vector3(rover_forward.x, 0.0, rover_forward.z).normalized()
	player.global_position = rover.global_position + rover_forward * 4.0 + Vector3.UP * 0.5
	player.linear_velocity = Vector3.ZERO
	player.controller.camera_azimuth = atan2(rover_forward.x, rover_forward.z)
	player.controller.camera_altitude = deg_to_rad(-15.0)
	await _measure("player facing the rover, both lights")

	# In the workshop: the rover docked, the player in the bay beside the pad looking at it
	rover.global_transform = workshop.get_dock_transform().translated(Vector3.UP * 0.05)
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	player.global_position = workshop.to_global(Vector3(1.3, 0.05, -2.6))
	player.linear_velocity = Vector3.ZERO
	var to_rover: Vector3 = rover.global_position - player.global_position
	player.controller.camera_azimuth = atan2(-to_rover.x, -to_rover.z)
	player.controller.camera_altitude = deg_to_rad(-20.0)
	await _measure("player in the workshop, facing the docked rover")
	quit()


func _measure(phase: String) -> void:
	# Back in front: another window can take the focus during a run, and the game caps an
	# unfocused window at 30 fps (frames measured unfocused are counted and reported)
	DisplayServer.window_move_to_foreground()
	var start: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < WARM_UP * 1e6:
		await process_frame
	var frame_times: Array[float] = []
	var primitives: float = 0.0
	var unfocused: int = 0
	var last: int = Time.get_ticks_usec()
	start = last
	while last - start < SECONDS * 1e6:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frame_times.append((now - last) / 1000.0)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		last = now
		if not DisplayServer.window_is_focused():
			unfocused += 1
	var sorted: Array[float] = frame_times.duplicate()
	sorted.sort()
	var mean: float = (last - start) / 1000.0 / frame_times.size()
	print("FPS %-22s mean %6.1f fps (%5.2f ms)  p99 %5.2f ms  worst %6.2f ms  %d frames  %.2f M triangles a frame%s" % [
		phase, 1000.0 / mean, mean, sorted[int(sorted.size() * 0.99)], sorted[-1],
		frame_times.size(), primitives / frame_times.size() / 1e6, "" if unfocused == 0 else "  (%d unfocused: throttled)" % unfocused])


# A hang fails the run instead of stalling it (the windowed tools wait for a level to load)
func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
