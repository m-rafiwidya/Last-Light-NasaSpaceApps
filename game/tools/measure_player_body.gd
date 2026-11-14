extends SceneTree
## Frame cost of the first-person spacesuit body (src/player/body/, PlayerBody) on the Moon:
## standing in the workshop bay looking at the docked rover, then walking, in alternating
## windows with the body on and off (hidden, its animation, IK and script stopped). Prints the
## mean frame time, the process (CPU) time and the draw calls / primitives of each window.
## With a window (the renderer); vsync off and no frame cap so the numbers are the frame's cost:
##   Godot --path game --resolution 1920x1080 --disable-vsync -s res://tools/measure_player_body.gd
## Headless, it measures the CPU alone (the body's script, animation tree, IK and skinning
## setup, without drawing), which is steadier:
##   Godot --headless --path game -s res://tools/measure_player_body.gd

const WINDOW: float = 8.0
const PAIRS: int = 6

var GS: Node
var SL: Node


func _initialize() -> void:
	# No focus: a real key or mouse movement on the desktop mustn't reach the game mid-measurement
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	InputMap.action_erase_events("ui_cancel")
	InputMap.action_erase_events("console")
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _set_body(body: Node3D, on: bool) -> void:
	body.visible = on
	body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _window(seconds: float) -> Array:
	var frames: int = 0
	var draw: float = 0.0
	var primitives: float = 0.0
	var process: float = 0.0
	var start: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < int(seconds * 1e6):
		await process_frame
		frames += 1
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		process += Performance.get_monitor(Performance.TIME_PROCESS)
	var ms: float = (Time.get_ticks_usec() - start) / 1000.0 / frames
	return [ms, process / frames * 1000.0, draw / frames, primitives / frames]


func _run() -> void:
	await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await process_frame
	# The game caps an unfocused window at 30 fps (main.gd); this window never takes focus
	var main: Node = root.get_node("Main")
	main.throttle_when_unfocused = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var workshop = SL.current_scene.get_node("Workshop")
	var player = GS.player
	var body = player.get_node("Body")
	player.global_position = workshop.to_global(Vector3(-3.0, 0.05, -1.2))
	var to: Vector3 = workshop.to_global(Vector3(-0.5, 0.8, 1.0)) - player.global_position
	player.controller.camera_azimuth = atan2(-to.x, -to.z) - player.global_basis.get_euler().y
	player.controller.camera_altitude = deg_to_rad(-15.0)
	for i in 240:
		await process_frame
	for walking in [false, true]:
		var sums: Dictionary = {true: [0.0, 0.0, 0.0, 0.0], false: [0.0, 0.0, 0.0, 0.0]}
		for pair in PAIRS:
			for on in [true, false]:
				_set_body(body, on)
				if walking:
					# Back and forth over the same 2 m, so both windows see the same views
					Input.action_press("move_forward" if pair % 2 == 0 else "move_backward")
				await _window(0.5)
				var r: Array = await _window(WINDOW)
				Input.action_release("move_forward")
				Input.action_release("move_backward")
				for k in 4:
					sums[on][k] += r[k] / PAIRS
				print("MEASURE %s body %-3s  frame %.3f ms  process %.3f ms  draw calls %.0f  primitives %.0f" % [
					"walking" if walking else "standing", "on" if on else "off", r[0], r[1], r[2], r[3]])
		print("MEASURE %s, mean of %d pairs: frame %.3f -> %.3f ms (%+.3f), process %.3f -> %.3f ms (%+.3f), draw calls %+.0f, primitives %+.0f" % [
			"walking" if walking else "standing", PAIRS, sums[false][0], sums[true][0], sums[true][0] - sums[false][0],
			sums[false][1], sums[true][1], sums[true][1] - sums[false][1], sums[true][2] - sums[false][2],
			sums[true][3] - sums[false][3]])
	_set_body(body, true)
	# The body's own work, timed directly while walking: its script with the animation tree, and
	# the skeleton update that runs the modifiers (legs, arm IK, hands) and skins
	Input.action_press("move_forward")
	await _window(0.5)
	var sk: Skeleton3D = body.skeleton
	var script_us: float = 0.0
	var skeleton_us: float = 0.0
	var n: int = 600
	for i in n:
		await process_frame
		var t0: int = Time.get_ticks_usec()
		body._process(1.0 / 144.0)
		var t1: int = Time.get_ticks_usec()
		sk.force_update_all_bone_transforms()
		var t2: int = Time.get_ticks_usec()
		script_us += t1 - t0
		skeleton_us += t2 - t1
		if i == n / 2:
			Input.action_release("move_forward")
			Input.action_press("move_backward")
	Input.action_release("move_backward")
	print("MEASURE the body's own CPU per frame (walking, %d frames): script and animation tree %.3f ms, skeleton update with modifiers %.3f ms" % [
		n, script_us / n / 1000.0, skeleton_us / n / 1000.0])
	quit()
