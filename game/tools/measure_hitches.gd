extends SceneTree
## Counts frame hitches (over 40 ms) in 40 s of play on the Moon, standing still, in a window;
## `-- menu` measures the main menu instead; `-- off=<path>,<path>` turns those nodes' processing off first (paths from the root, e.g.
## Main/... or the level's children as Level/<name>), to find what stalls.
##
##     Godot --path game -s res://tools/measure_hitches.gd --resolution 1920x1080 -- off=Level/Terrain

var GS: Node
var SL: Node


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	var on_menu: bool = "menu" in OS.get_cmdline_user_args()
	if not on_menu:
		root.get_node("CampaignState").reset()
		load("res://src/save/save_index.gd").start_new_campaign("slot_3")
	while not on_menu and not (SL.current_level_id == "moon_level" and SL.loading_scene_id.is_empty() and GS.state == GS.State.IN_GAME_PLAYER):
		await process_frame
	var off: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("off="):
			off = Array(arg.trim_prefix("off=").split(",", false))
	for path in off:
		var node: Node = SL.current_scene.get_node_or_null(path.trim_prefix("Level/")) if path.begins_with("Level/") else root.get_node_or_null(path)
		if node == null:
			print("MISSING ", path)
			continue
		node.process_mode = Node.PROCESS_MODE_DISABLED
	DisplayServer.window_move_to_foreground()
	for i in 300:
		await process_frame
	var hitches: Array = []
	var last: int = Time.get_ticks_usec()
	var start: int = last
	while Time.get_ticks_usec() - start < 40000000:
		await process_frame
		var now: int = Time.get_ticks_usec()
		if now - last > 40000:
			hitches.append("%.1f s: %.0f ms" % [(now - start) / 1e6, (now - last) / 1000.0])
		last = now
	print("HITCHES off=%s: %d  %s" % [",".join(off), hitches.size(), str(hitches)])
	quit(0)
