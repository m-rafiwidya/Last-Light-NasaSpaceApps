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


## Adds the message to the console and prints it to the Godot output log
func _log_and_print(message: String) -> void:
	print(message)
	add_log(message)


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
			"credits":
				# Plays the credits roll over the main menu, or over the game (it returns to it)
				var credits: Node = get_tree().root.get_node_or_null("Main/UIManager/Credits")
				if credits and (GameState.state == GameState.State.MAIN_MENU or GameState.is_in_game()):
					get_tree().root.get_node("Main/UIManager/Console").hide()
					if GameState.state == GameState.State.MAIN_MENU:
						credits.open()
					else:
						GameState.open_credits()
				else:
					add_log("The credits play on the main menu or in a level only")
			"testlevel":
				# The test sandbox, no longer on the main menu (the pause menu still offers it)
				SceneLoader.load_scene("test_level")
			"fakesaves":
				# Sample save metadata so the PLAY popup's list can be previewed
				add_log("Wrote %d fake saves to %s" % [SaveIndex.write_fake_saves(), SaveIndex.save_dir()])
			"clearsaves":
				add_log("Removed %d fake saves" % SaveIndex.clear_fake_saves())
			"saves":
				# Lists the save slots (SaveIndex.list_slots) in the console and the output log
				_log_and_print("Saves folder: %s" % ProjectSettings.globalize_path(SaveIndex.save_dir()))
				for info in SaveIndex.list_slots():
					var path: String = ProjectSettings.globalize_path(SaveIndex.slot_path(info.slot_id))
					if info.is_empty():
						_log_and_print("%s | empty" % info.slot_id)
					elif not info.is_readable():
						_log_and_print("%s | unreadable | %s" % [info.slot_id, path])
					else:
						_log_and_print("%s | %s | %s | %s | %d%% | %s | %s" % [
							info.slot_id, info.mission_title, SaveIndex.format_date(info.saved_at),
							SaveIndex.format_play_time(info.play_time_sec), roundi(info.story_progress * 100.0),
							info.current_objective, path])
			"unlockall":
				# Unlocks every planet in the planet explorer until the game quits (testing)
				PlanetData.unlock_all = true
				var explorer: PlanetExplorer = get_tree().root.find_child("PlanetExplorer", true, false)
				if explorer:
					explorer.refresh_locks()
				add_log("All planets unlocked")
			"startmission":
				if argc >= 2:
					CampaignState.start_mission(argv[1])
					add_log("Current mission: %s" % CampaignState.current_mission())
				else:
					add_log("Usage: startmission <mission id>")
			"objective":
				if argc >= 2:
					CampaignState.complete_objective(argv[1])
					add_log("%s done: %s" % [argv[1], CampaignState.is_objective_done(argv[1])])
				else:
					add_log("Usage: objective <objective id>")
			"flag":
				if argc >= 2:
					var value: bool = argc < 3 or argv[2].to_lower() not in ["false", "0", "off"]
					CampaignState.set_flag(argv[1], value)
					add_log("Flag %s: %s" % [argv[1], CampaignState.has_flag(argv[1])])
				else:
					add_log("Usage: flag <name> [true|false]")
			"guidance":
				if argc >= 2:
					GeneralSettings.section.set_value("guidance", argv[1].to_lower() not in ["false", "0", "off"])
				add_log("Guidance: %s" % ("on" if GeneralSettings.guidance() else "off"))
			"campaign":
				for line in CampaignState.debug_dump():
					_log_and_print(line)
			"fullbright":
				var viewport = get_viewport()
				if viewport.debug_draw != Viewport.DEBUG_DRAW_UNSHADED:
					viewport.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
				else:
					viewport.debug_draw = Viewport.DEBUG_DRAW_DISABLED

			_:
				add_log("Unknown command \"%s\"" % argv[0])
