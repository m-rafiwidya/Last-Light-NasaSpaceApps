extends Node

# The rover being driven, set by the Robot when it takes control (read by the robot HUD)
var current_robot: Robot

## True while the debug console popup is open (set by UIManager). Player and robot
## controllers ignore input meanwhile, so typing in the console doesn't move them.
var console_open: bool = false

var debug_console_output: PackedStringArray = [
	'Debug console for "%s"' % ProjectSettings.get_setting("application/config/name", "Unnamed Project"),
	'Game started at: %s' % Time.get_datetime_string_from_system()
]


func add_log(message: String):
	var entry: String = "[" + Time.get_time_string_from_system() + "]"
	entry += " ~ "
	entry += message
	debug_console_output.append(entry)


func parse_command(input: String):
	var argv: PackedStringArray = input.split(" ", false)
	var argc: int = argv.size()
	if argc != 0:
		match argv[0].to_lower():
			"timescale":
				if argc >= 2:
					var value: float = maxf(float(argv[1]), 0.0)
					GameState.normal_time_scale = value
					# While paused the time scale is 0; unpausing tweens to the new value
					if GameState.state != GameState.State.PAUSED:
						Engine.set_time_scale(value)
					add_log("Engine timescale set to %s" % value)
				else:
					add_log("Not enough parameters!")
			"quit":
				get_tree().quit()
			"say":
				if argc >= 2:
					var test_dialog: Dialog = Dialog.new()
					# TODO: implement audio stream to support dialogs
					#test_dialog.audio_stream = ResourceLoader.load("res://res/sounds/test_narration.wav")
					test_dialog.subtitle = " ".join(argv.slice(1))
					DialogServer.play_dialog(test_dialog)
				else:
					add_log("Not enough parameters!")
			"intro":
				# Replays the main menu's opening sequence
				var menu: Node = get_tree().root.get_node_or_null("Main/UIManager/MainMenu")
				if menu and GameState.state == GameState.State.MAIN_MENU:
					menu.replay_intro()
				else:
					add_log("The opening sequence plays on the main menu only")
			"testlevel":
				# The test sandbox, no longer on the main menu (the pause menu still offers it)
				SceneLoader.load_scene("test_level")
			"fakesaves":
				# Sample save metadata so the PLAY popup's list can be previewed
				add_log("Wrote %d fake saves to %s" % [SaveIndex.write_fake_saves(), SaveIndex.SAVE_DIR])
			"clearsaves":
				add_log("Removed %d fake saves" % SaveIndex.clear_fake_saves())
			"fullbright":
				var viewport = get_viewport()
				if viewport.debug_draw != Viewport.DEBUG_DRAW_UNSHADED:
					viewport.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
				else:
					viewport.debug_draw = Viewport.DEBUG_DRAW_DISABLED

			_:
				add_log("Unknown command \"%s\"" % argv[0])
