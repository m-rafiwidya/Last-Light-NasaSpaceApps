extends Node

## With vsync on, macOS (Metal) blocks for up to a second per frame waiting for a frame buffer
## while the window can't be shown: minimised, covered, on another Space, or just restored and not
## yet focused (measured: 1012-1016 ms frames, no shader compiles, normal CPU time; none with vsync
## off). While the window isn't focused, the game renders without vsync, capped at this rate;
## focus brings back the vsync mode and frame cap it had.
## Not when the game runs embedded in the editor (its Game tab): there the editor's process keeps
## the operating system's focus, so the game would be "unfocused" all the time, and the editor
## shows the frames anyway.
## Getting the focus back also re-applies the mouse mode for the game state (captured in game,
## visible in menus), so switching away and back never leaves the cursor hidden or free.
## At launch it applies the saved settings that act on the window and the engine (window mode,
## key bindings, resolution, vsync, frame cap, quality) and keeps Brightness on every
## WorldEnvironment (VideoSettings); the other settings are read where they are used.
const BACKGROUND_FPS: int = 30

## False when embedded in the editor (see above); tests may change it
var throttle_when_unfocused: bool = not Engine.is_embedded_in_editor()

var _focused_vsync: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
var _focused_max_fps: int = 0
var _in_background: bool = false


func _ready() -> void:
	# The saved window mode (fullscreen or not). Not in tests (a script runs the SceneTree): they
	# need the window as the command line opens it, whatever the player last chose
	if get_tree().get_script() == null:
		DisplaySettings.apply_saved()
	# (In a script run these are the defaults, see SettingsSection.read_saved)
	InputBindings.load_saved()
	VideoSettings.apply_saved()
	VideoSettings.track_environments(get_tree())
	SceneLoader.main_node = self
	SceneLoader.load_scene("main_menu", true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		print("Main: window focus lost (embedded in the editor: %s)" % Engine.is_embedded_in_editor())
		if throttle_when_unfocused and not _in_background:
			_in_background = true
			_focused_vsync = DisplayServer.window_get_vsync_mode()
			_focused_max_fps = Engine.max_fps
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = BACKGROUND_FPS if _focused_max_fps == 0 else mini(_focused_max_fps, BACKGROUND_FPS)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		print("Main: window focus back")
		if _in_background:
			_in_background = false
			DisplayServer.window_set_vsync_mode(_focused_vsync)
			Engine.max_fps = _focused_max_fps
		GameState.apply_mouse_mode.call_deferred()
