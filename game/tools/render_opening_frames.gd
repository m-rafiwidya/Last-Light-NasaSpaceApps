extends SceneTree
## Renders review frames of the opening cutscene and of the lander in the Moon level. Needs a
## window (not --headless):
##
##     Godot --path game -s res://tools/render_opening_frames.gd --resolution 1920x1080 -- out=<dir> tag=<name>
##
## Frames: the opening, played in a window, at a few moments of each shot (<tag>_<shot>_<t>.jpg), then the lander from the
## hatch porch, the ramp foot and the workshop apron (<tag>_lander_*.jpg). `only=<prefix>` limits
## them.

const SHOTS: Array = [
	["space", 3.0], ["space", 10.0], ["space", 16.5],
	["head_crater", 2.0], ["head_crater", 8.0],
	["tracking", 2.0], ["tracking", 8.0],
	["approach", 4.0],
	["touchdown", 3.0], ["touchdown", 10.0],
	["hatch", 2.0], ["hatch", 7.0],
]

var GS: Node
var SL: Node
var out_dir: String = ""
var tag: String = "frame"
var only: String = ""


func _initialize() -> void:
	_watchdog(900.0)
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _frames(count: int) -> void:
	DisplayServer.window_move_to_foreground()
	for i in count:
		await process_frame


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("tag="):
			tag = arg.trim_prefix("tag=")
		elif arg.begins_with("only="):
			only = arg.trim_prefix("only=")
		elif arg.begins_with("lod="):
			root.mesh_lod_threshold = arg.trim_prefix("lod=").to_float()
	if out_dir.is_empty():
		printerr("out=<dir> is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	load("res://src/cutscene/cutscene_director.gd").autoplay = true
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	var save_index: GDScript = load("res://src/save/save_index.gd")
	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	root.get_node("CampaignState").reset()
	save_index.start_new_campaign("slot_3")
	while not (SL.current_level_id == "moon_level" and SL.loading_scene_id.is_empty() and GS.state == GS.State.CUTSCENE):
		await process_frame
	print("RENDER window %s, 3D scale %.2f, msaa %d" % [root.size, root.scaling_3d_scale, root.msaa_3d])
	var level: Node = SL.current_scene
	var cutscenes: Node = level.get_node("MissionDirector/Cutscenes")
	var starts: Dictionary = {}
	var start: float = 0.0
	for shot in cutscenes.cutscenes["opening"]["shots"]:
		starts[shot["name"]] = start
		start += float(shot["duration"])
	for shot in SHOTS:
		var name: String = "%s_%s_%04.1f" % [tag, shot[0], shot[1]]
		if only.is_empty() or name.begins_with(tag + "_" + only):
			await _reach(cutscenes, starts[shot[0]] + shot[1])
			_save(name)
	cutscenes.skip()
	while cutscenes.is_playing():
		await process_frame
	await _frames(30)
	await _lander_views(level)
	quit(0)


## Plays the cutscene on to `t` (jumping to 1.5 s before it across a long gap), so the lander's
## own motion keeps time with it
func _reach(cutscenes: Node, t: float) -> void:
	if t - cutscenes.time > 6.0:
		cutscenes.time = t - 1.5
	while cutscenes.time < t:
		await _frames(1)


func _lander_views(level: Node) -> void:
	var lander: Node3D = level.get_node("Lander")
	var workshop: Node3D = level.get_node("Workshop")
	var hatch: Node3D = lander.get_node("Hatch")
	var ramp_foot: Node3D = lander.get_node_or_null("RampFoot")
	var camera := Camera3D.new()
	camera.far = 50000.0
	camera.fov = 75.0
	level.add_child(camera)
	camera.make_current()
	var door: Vector3 = workshop.to_global(Vector3(-1.0, 1.6, -9.0))
	var views: Array = [
		["lander_walkout", hatch.global_position + Vector3.UP * 1.6, door],
		["lander_apron", door, lander.global_position + Vector3.UP * 3.0],
		["lander_three_quarter", lander.to_global(Vector3(9.0, 1.7, -12.0)), lander.global_position + Vector3.UP * 3.0],
	]
	if ramp_foot:
		views.insert(1, ["lander_ramp_foot", ramp_foot.global_position + Vector3.UP * 1.6 - (hatch.global_position - ramp_foot.global_position).normalized() * 1.5 * Vector3(1, 0, 1),
			hatch.global_position + Vector3.UP * 1.2])
		views.append(["lander_ramp_side", lander.to_global(Vector3(-7.0, 1.7, -5.0)), ramp_foot.global_position.lerp(hatch.global_position, 0.5)])
	for view in views:
		var name: String = "%s_%s" % [tag, view[0]]
		if not only.is_empty() and not name.begins_with(tag + "_" + only):
			continue
		camera.global_position = view[1]
		camera.look_at(view[2], Vector3.UP)
		GS.player.visible = view[0] != "lander_walkout"
		await _frames(60)
		_save(name)
	GS.player.visible = true


func _save(name: String) -> void:
	var path: String = out_dir.path_join(name + ".jpg")
	root.get_texture().get_image().save_jpg(path, 0.92)
	print("SAVED %s" % path)


func _watchdog(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	printerr("WATCHDOG: no result after %d s, quitting" % seconds)
	quit(2)
