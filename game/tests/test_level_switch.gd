extends SceneTree
## Headless test: switches levels the way the player does and checks nothing of the old level
## is left behind.
##   1. Main menu: the test level is no longer on it, so the `testlevel` console command. Drive the ready rover and pick up a pile part with it, Esc
##      out (the rover keeps holding it), pick up a box on foot, Esc (pause), "Switch to Moon".
##   2. On the Moon: the level's contents (the workshop; no outdoor drive trigger or pile), then
##      drive its rover from the workshop console with the rack's cartridge on its cargo mount, Esc out,
##      restock the rack, pick up a rack part on foot, pause, "Switch to Test level".
##   3. Back in the test level: the same checks, then pause, "Quit To Menu".
## After every switch: one level under Main and the old one freed; no rover driven
## (GameState.robot, root.get_node("Debug").current_robot); the new player's camera is current and holds
## nothing; robot HUD hidden, player HUD shown; tree unpaused, normal time scale; only the
## new level's rovers in the tree; the pause menu offers only the other level.
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_level_switch.gd

var GS: Node
var SL: Node
var step := 0
var wait := 0.0
var failures := 0
var old_level: WeakRef = null
var old_player: WeakRef = null
var held: WeakRef = null
var elapsed := 0.0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-58s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ui(path: String) -> Node:
	return root.get_node("Main").find_child(path, true, false)


func _press_esc() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)


func _pause_button(label: String) -> Button:
	for button in _ui("PauseMenu").find_children("*", "Button", true, false):
		if button.text.to_lower() == label.to_lower() and button.is_visible_in_tree():
			return button
	return null


func _rovers() -> Array:
	return root.find_children("*", "Robot", true, false)


func _remember_old() -> void:
	old_level = weakref(SL.current_scene) if SL.current_scene else null
	old_player = weakref(GS.player) if GS.player else null


# Everything that must be true once a gameplay level has finished loading after a switch
func _check_clean(level_id: String, level_name: String, rover_count: int) -> void:
	var tag: String = "[%s] " % level_id
	_check(tag + "current level", SL.current_level_id == level_id and SL.current_scene != null
		and SL.current_scene.name == level_name, "%s %s" % [SL.current_level_id, SL.current_scene.name if SL.current_scene else "-"])
	var levels: int = 0
	for child in root.get_node("Main").get_children():
		if child is Node3D:
			levels += 1
	_check(tag + "one level under Main", levels == 1, "%d" % levels)
	_check(tag + "old level freed", old_level == null or old_level.get_ref() == null)
	_check(tag + "old player freed", old_player == null or old_player.get_ref() == null)
	_check(tag + "held prop freed", held == null or held.get_ref() == null)
	_check(tag + "no rover driven", GS.robot == null and root.get_node("Debug").current_robot == null)
	_check(tag + "state IN_GAME_PLAYER", GS.state == GS.State.IN_GAME_PLAYER, GS.State.keys()[GS.state])
	var player = GS.player
	_check(tag + "new player in the level", is_instance_valid(player) and SL.current_scene.is_ancestor_of(player))
	_check(tag + "player camera is current", is_instance_valid(player) and root.get_camera_3d() == player.camera)
	_check(tag + "player holds nothing", is_instance_valid(player) and player.holder.held_object == null)
	_check(tag + "robot HUD hidden, player HUD shown", not _ui("RobotHUD").visible and _ui("HUD").visible)
	_check(tag + "tree unpaused, time scale 1", not paused and is_equal_approx(Engine.time_scale, 1.0), "time scale %.2f" % Engine.time_scale)
	_check(tag + "only this level's rovers", _rovers().size() == rover_count and _rovers().all(func(r): return SL.current_scene.is_ancestor_of(r)), "%d rovers" % _rovers().size())


func _drive_and_hold(rover_name: String) -> void:
	var rover = SL.current_scene.get_node(rover_name)
	var part: RigidBody3D
	if SL.current_scene.has_node("PartsPile"):
		SL.current_scene._on_robot_trigger_interacted(GS.player, rover)
		part = SL.current_scene.get_node("PartsPile").get_child(0)
	else:
		# The Moon: driven from the workshop console. The rover picks nothing up there; it carries
		# what's on its cargo mount, so the rack's cartridge goes onto it
		SL.current_scene.get_node("Workshop")._on_console_interacted(GS.player)
		var cartridge = SL.current_scene.get_node("Workshop").rack_stock.get_node("Slot17")
		rover.get_node("CargoSocket").mount(cartridge)
		_check("[moon_level] the cartridge rides on the rover's cargo mount", rover.get_node("CargoSocket").part == cartridge)
		return
	rover.holder.pickup(part)


func _check_driving(rover_name: String) -> void:
	var rover = SL.current_scene.get_node(rover_name)
	_check("[%s] drive: rover takes camera and HUD" % SL.current_level_id, GS.robot == rover
		and root.get_node("Debug").current_robot == rover and root.get_camera_3d() == rover.camera and _ui("RobotHUD").visible)


# Returns how long to wait before the next step, -1 when done, or null to retry next frame
func _run_step():
	match step:
		0:   # main menu
			if GS.state != GS.State.MAIN_MENU:
				return null
			_check("main menu lists no levels (PLAY opens the save popup)",
				_ui("MainMenu").find_child("LevelChoice", true, false) == null)
			_remember_old()   # the menu backdrop
			root.get_node("Debug").parse_command("testlevel")
		1:
			if GS.state != GS.State.IN_GAME_PLAYER:
				return null
			_check_clean("test_level", "TestLevel", 3)
			_drive_and_hold("ReadyRover")
			held = weakref(GS.robot.holder.held_object)
			return 0.5
		2:
			_check_driving("ReadyRover")
			_check("[test_level] rover holds a pile part", held.get_ref() != null and GS.robot.holder.held_object == held.get_ref())
			_press_esc()   # leave the rover
			return 0.5
		3:
			var box: RigidBody3D = SL.current_scene.get_node("Box")
			GS.player.holder.pickup(box)
			_check("[test_level] player holds the box", GS.player.holder.held_object == box)
			_press_esc()   # pause
			return 0.8
		4:
			_check("[test_level] paused", GS.state == GS.State.PAUSED and paused)
			_check("[test_level] pause menu offers only Moon", _pause_button("Switch to Moon") != null and _pause_button("Switch to Test level") == null)
			_remember_old()
			_pause_button("Switch to Moon").pressed.emit()
		5:
			if GS.state != GS.State.IN_GAME_PLAYER or SL.current_level_id != "moon_level":
				return null
			return 0.6   # HUD fades, time scale eases back
		6:
			_check_clean("moon_level", "MoonLevel", 1)
			var scene: Node = SL.current_scene
			for node_name in ["SpawnPoint", "Terrain", "ReadyRover", "Workshop"]:
				_check("[moon_level] has " + node_name, scene.has_node(node_name))
			for node_name in ["ReadyRoverTrigger", "PartsPile", "RespawnPartsTrigger"]:
				_check("[moon_level] no outdoor " + node_name, not scene.has_node(node_name))
			_check("[moon_level] rover starts assembled", scene.get_node("ReadyRover").start_assembled)
			_drive_and_hold("ReadyRover")
			return 0.5
		7:
			_check_driving("ReadyRover")
			_press_esc()
			return 0.5
		8:
			var pile: Node = SL.current_scene.get_node("Workshop").rack_stock
			var count: int = pile.get_child_count()
			SL.current_scene.get_node("Workshop")._on_restock_interacted(GS.player)
			set_meta("pile_count", count)
			return 0.1
		9:
			var pile: Node = SL.current_scene.get_node("Workshop").rack_stock
			# The part the rover holds stays (it is loose, so it is cleared too and restocked)
			_check("[moon_level] restock lays out the full rack", pile.get_child_count() == _rack_slots(SL.current_scene.get_node("Workshop")), "%d parts (was %d)" % [pile.get_child_count(), get_meta("pile_count")])
			var part: RigidBody3D = pile.get_child(0)
			GS.player.holder.pickup(part)
			held = weakref(part)
			_press_esc()
			return 0.8
		10:
			_check("[moon_level] pause menu offers only Test level", _pause_button("Switch to Test level") != null and _pause_button("Switch to Moon") == null)
			_remember_old()
			_pause_button("Switch to Test level").pressed.emit()
		11:
			if GS.state != GS.State.IN_GAME_PLAYER or SL.current_level_id != "test_level":
				return null
			return 0.6
		12:
			_check_clean("test_level", "TestLevel", 3)
			_check("[test_level] intro dialog and mission console still wired", SL.current_scene.get_node("DialogTrigger").interacted.get_connections().size() > 0
				and SL.current_scene.get_node("MissionConsoleTrigger").interacted.get_connections().size() > 0
				and SL.current_scene.get_node("BareRoverTrigger").interacted.get_connections().size() > 0)
			_press_esc()
			return 0.8
		13:
			_remember_old()
			_pause_button("Quit To Menu").pressed.emit()
		14:
			if GS.state != GS.State.MAIN_MENU:
				return null
			return 0.6
		15:
			_check("[main_menu] old level and player freed", old_level.get_ref() == null and (old_player == null or old_player.get_ref() == null))
			_check("[main_menu] no player, no rover driven", GS.player == null and GS.robot == null and root.get_node("Debug").current_robot == null)
			_check("[main_menu] HUDs hidden, unpaused", not _ui("RobotHUD").visible and not _ui("HUD").visible and not paused)
			return -1.0
	return 0.1


func _physics_process(_delta: float) -> bool:
	# Unscaled: pausing eases Engine.time_scale to 0, which would stop a scaled delta
	var delta: float = 1.0 / Engine.physics_ticks_per_second
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	elapsed += delta
	if elapsed > 120.0:
		print("RESULT step %d never finished: FAIL" % step)
		return true
	if wait > 0.0:
		wait -= delta
		return false
	var result = _run_step()
	if result == null:
		return false
	if result < 0.0:
		print("RESULT %s" % ("ALL PASS" if failures == 0 else "%d CHECKS FAILED" % failures))
		return true
	step += 1
	wait = result
	return false


func _rack_slots(workshop) -> int:
	return workshop.SLOTS.keys().filter(func(n): return workshop.anchors.has("slot_%02d" % n)).size()
