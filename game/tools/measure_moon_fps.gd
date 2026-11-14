extends SceneTree
## Measures the Moon level's frame rate in a window: the rover drives a full-throttle circle
## with its headlights on, SECONDS each in the chase and the mast view, then the player walks
## on foot with the helmet light on, then stands facing the parked rover, its headlights and the
## helmet light both in view (the player's helmet light is on throughout). Prints per phase the mean frame rate and the 99th percentile and worst frame times.
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
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await process_frame
	var level: Node = SL.current_scene
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
	quit()


func _measure(phase: String) -> void:
	var start: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < WARM_UP * 1e6:
		await process_frame
	var frame_times: Array[float] = []
	var last: int = Time.get_ticks_usec()
	start = last
	while last - start < SECONDS * 1e6:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frame_times.append((now - last) / 1000.0)
		last = now
	var sorted: Array[float] = frame_times.duplicate()
	sorted.sort()
	var mean: float = (last - start) / 1000.0 / frame_times.size()
	print("FPS %-22s mean %6.1f fps (%5.2f ms)  p99 %5.2f ms  worst %6.2f ms  %d frames" % [
		phase, 1000.0 / mean, mean, sorted[int(sorted.size() * 0.99)], sorted[-1],
		frame_times.size()])


# A hang fails the run instead of stalling it (the windowed tools wait for a level to load)
func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
