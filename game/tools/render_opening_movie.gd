extends SceneTree
## Plays the opening (or, with part=iris, the IRIS cutscene) for Godot's Movie Maker, saving key
## frames at moments of each shot as JPGs. Needs a window:
##
##     Godot --path game --write-movie <out>/opening.avi --fixed-fps 30 --resolution 1920x1080 \
##         -s res://tools/render_opening_movie.gd -- frames=<dir> [part=iris]

const KEYS: Dictionary = {
	"opening": [["title", 5.0], ["space", 3.0], ["space", 10.0], ["space", 16.5], ["head_crater", 2.0], ["head_crater", 8.0],
		["tracking", 2.0], ["tracking", 8.0], ["approach", 2.0], ["approach", 7.0], ["touchdown", 2.5], ["touchdown", 5.5],
		["touchdown", 6.2], ["touchdown", 9.0], ["hatch", 2.0], ["hatch", 7.5]],
	"iris_online": [["mast", 0.5], ["mast", 3.5], ["signal", 1.0], ["signal", 5.5]],
}

var GS: Node
var SL: Node
var frames_dir: String = ""
var part: String = "opening"


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("frames="):
			frames_dir = arg.trim_prefix("frames=")
		elif arg == "part=iris":
			part = "iris_online"
	DirAccess.make_dir_recursive_absolute(frames_dir)
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	load("res://src/cutscene/cutscene_director.gd").autoplay = true
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	root.get_node("CampaignState").reset()
	load("res://src/save/save_index.gd").start_new_campaign("slot_3")
	while not (SL.current_level_id == "moon_level" and SL.loading_scene_id.is_empty() and GS.state == GS.State.CUTSCENE):
		await process_frame
	var cutscenes: Node = SL.current_scene.get_node("MissionDirector/Cutscenes")
	if part == "iris_online":
		cutscenes.skip()
		while cutscenes.is_playing():
			await process_frame
		var debug: Node = root.get_node("Debug")
		debug.parse_command("startmission m2")
		for id in ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed"]:
			debug.parse_command("objective " + id)
		GS.drive(SL.current_scene.get_node("ReadyRover"))
		for i in 30:
			await process_frame
		debug.parse_command("objective m2.iris_activated")
		debug.parse_command("flag iris_online")
		while cutscenes.playing_id != "iris_online":
			await process_frame
	var starts: Dictionary = {}
	var start: float = 0.0
	for shot in cutscenes.cutscenes[part]["shots"]:
		starts[shot["name"]] = start
		start += float(shot["duration"])
	var keys: Array = KEYS[part].duplicate()
	while cutscenes.is_playing():
		if not keys.is_empty() and cutscenes.time >= starts[keys[0][0]] + keys[0][1]:
			var key: Array = keys.pop_front()
			root.get_texture().get_image().save_jpg(frames_dir.path_join("%s_%s_%04.1f.jpg" % [part, key[0], key[1]]), 0.9)
		await process_frame
	for i in 60:
		await process_frame
	DirAccess.remove_absolute(load("res://src/save/save_index.gd").slot_path("slot_3"))
	quit(0)
