extends Node

## With vsync on, macOS (Metal) blocks for up to a second per frame waiting for a frame buffer
## while the window can't be shown: minimised, covered, on another Space, or just restored and not
## yet focused (measured: 1012-1016 ms frames, no shader compiles, normal CPU time; none with vsync
## off). While the window isn't focused, the game renders without vsync, capped at this rate;
## focus brings back the vsync mode and frame cap it had.
const BACKGROUND_FPS: int = 30

var _focused_vsync: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
var _focused_max_fps: int = 0
var _in_background: bool = false


func _ready() -> void:
	SceneLoader.main_node = self
	SceneLoader.load_scene("main_menu", true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _in_background:
		_in_background = true
		_focused_vsync = DisplayServer.window_get_vsync_mode()
		_focused_max_fps = Engine.max_fps
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = BACKGROUND_FPS if _focused_max_fps == 0 else mini(_focused_max_fps, BACKGROUND_FPS)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _in_background:
		_in_background = false
		DisplayServer.window_set_vsync_mode(_focused_vsync)
		Engine.max_fps = _focused_max_fps
